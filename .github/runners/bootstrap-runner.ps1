<#
.SYNOPSIS
    Configures a fresh VMSS instance as a single-use (ephemeral) GitHub Actions runner.

.DESCRIPTION
    Executed on new instances by the runner-scale-up / runner-reconcile workflows through
    az vm run-command (no inbound ports, no secrets at rest -- the registration token is
    single use with a one hour expiry and is only ever passed as a parameter).

    The golden image pre-stages the runner at C:\github-runner, so this only has to:
      1. set the network profile to Private (appveyor.prep.ps1 runs Set-WSManQuickConfig,
         which refuses on Public profiles)
      2. register the runner as an ephemeral service running as LocalSystem; config.cmd
         installs and starts the service immediately, so the VM takes its job on this
         boot -- no autologon, no logon task, no second boot

    BITS transfers (Copy-DbaBackupDevice among others) work in this service session
    because LocalSystem is one of the accounts BITS treats as always logged on:
    https://learn.microsoft.com/windows/win32/bits/users-and-network-connections

    The runner takes exactly one job; runner-reconcile deletes the instance afterwards,
    so every job starts on a factory-fresh VM, AppVeyor style.

.NOTES
    Author: the dbatools team + Claude
#>
param(
    [Parameter(Mandatory)]
    [string]$Token,
    [Parameter(Mandatory)]
    [string]$RunnerName,
    [string]$Labels = "dbatools-modern",
    [string]$RepoUrl = "https://github.com/dataplat/dbatools"
)

$ErrorActionPreference = "Stop"
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]3072

function Get-RunnerVmState {
    <#
    .SYNOPSIS
        Reports whether this VM is fresh, still serving its single job, or spent.

    .DESCRIPTION
        Kept as a function with no side effects so tests/bootstrap-runner.Tests.ps1 can
        lift it out of this script and exercise every outcome. It decides the fate of a
        VM, so it is the one part of the bootstrap that must not be guessed at.
    #>
    param(
        [string]$RunnerRoot = "C:\github-runner"
    )

    if (-not (Test-Path -Path (Join-Path -Path $RunnerRoot -ChildPath ".bootstrapped-once"))) {
        return "fresh"
    }

    # .bootstrapped-once is written before config.cmd runs, so reaching here means a
    # bootstrap was at least attempted. Healthy means the runner is still configured and
    # its service is running (the single job has not been served yet). Anything else --
    # the ephemeral runner served its job and unregistered itself, or a previous bootstrap
    # died mid-config -- leaves the VM dirty (SQL state, workspace); it must be deleted,
    # never reused.
    $runningService = @(Get-Service -Name "actions.runner.*" -ErrorAction SilentlyContinue | Where-Object Status -eq "Running")
    if ((Test-Path -Path (Join-Path -Path $RunnerRoot -ChildPath ".runner")) -and $runningService.Count -gt 0) {
        return "healthy"
    }
    return "spent"
}

function Get-RunnerPackageVersion {
    <#
    .SYNOPSIS
        Reports the version the runner listener under RunnerRoot answers with.

    .DESCRIPTION
        Returns nothing when bin\Runner.Listener.exe is missing, fails to run or prints no
        version. A function of its own so tests/bootstrap-runner.Tests.ps1 can stand in for
        a real listener when it exercises Install-RunnerPackage.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$RunnerRoot
    )

    $listenerPath = Join-Path -Path $RunnerRoot -ChildPath "bin\Runner.Listener.exe"
    if (-not (Test-Path -Path $listenerPath)) {
        return
    }
    try {
        $versionMatch = [regex]::Match((@(& $listenerPath --version) -join " "), "\d+\.\d+\.\d+")
    } catch {
        return
    }
    if ($versionMatch.Success) {
        $versionMatch.Value
    }
}

function Install-RunnerPackage {
    <#
    .SYNOPSIS
        Replaces the runner staged under RunnerRoot with the package at PackageUrl, unless its
        listener already reports Version.

    .DESCRIPTION
        Throws when the download fails, its SHA256 is not Sha256 or the listener does not
        report Version after the install; the caller turns that into a failed bootstrap.

        The package is downloaded and unpacked into a new staging folder under RunnerRoot,
        which SYSTEM owns, rather than the shared temp folder, and moved into place with bin
        last. A runner counts as installed when bin\Runner.Listener.exe reports Version, and
        bin only arrives once externals and the root files are in place, so an install cut
        off at any point leaves the old listener or none, and the next pass installs again.
        Staging folders such a pass left behind are removed first.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$RunnerRoot,
        [Parameter(Mandatory)]
        [string]$Version,
        [Parameter(Mandatory)]
        [string]$Sha256,
        [Parameter(Mandatory)]
        [string]$PackageUrl
    )

    # every step stops the install whatever the caller's preference: a failed move that only
    # warned would let bin arrive without externals and the runner count as installed
    $ErrorActionPreference = "Stop"

    $stagedVersion = Get-RunnerPackageVersion -RunnerRoot $RunnerRoot
    if ($stagedVersion -eq $Version) {
        "runner $Version is staged"
        return
    }
    "runner $stagedVersion is staged; installing $Version"

    foreach ($oldStage in @(Get-ChildItem -Path $RunnerRoot -Filter ".runner-package-*")) {
        $splatRemoveOldStage = @{
            Path    = $oldStage.FullName
            Recurse = $true
            Force   = $true
        }
        Remove-Item @splatRemoveOldStage
    }

    $stageRoot = Join-Path -Path $RunnerRoot -ChildPath ".runner-package-$([System.Guid]::NewGuid().ToString("N"))"
    $packagePath = Join-Path -Path $stageRoot -ChildPath "package.zip"
    $unpackedPath = Join-Path -Path $stageRoot -ChildPath "unpacked"
    $null = New-Item -Path $stageRoot -ItemType Directory
    try {
        $webClient = New-Object -TypeName System.Net.WebClient
        try {
            $webClient.DownloadFile($PackageUrl, $packagePath)
        } finally {
            $webClient.Dispose()
        }
        $actualSha256 = (Get-FileHash -Path $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualSha256 -ne $Sha256) {
            throw "runner download $PackageUrl has SHA256 $actualSha256, expected $Sha256"
        }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($packagePath, $unpackedPath)

        # bin goes first and comes back last: without it no listener answers, so an install
        # cut off anywhere in between probes as not installed. Removing externals too means
        # no file of the old version outlives the swap.
        foreach ($runnerFolder in "bin", "externals") {
            $runnerFolderPath = Join-Path -Path $RunnerRoot -ChildPath $runnerFolder
            if (Test-Path -Path $runnerFolderPath) {
                $splatRemoveRunnerFolder = @{
                    Path    = $runnerFolderPath
                    Recurse = $true
                    Force   = $true
                }
                Remove-Item @splatRemoveRunnerFolder
            }
        }
        # the root files (config.cmd, run.cmd) replace the ones the image staged
        foreach ($packageItem in @(Get-ChildItem -Path $unpackedPath)) {
            if ($packageItem.Name -in "bin", "externals") {
                continue
            }
            $splatCopyPackageItem = @{
                Path        = $packageItem.FullName
                Destination = $RunnerRoot
                Recurse     = $true
                Force       = $true
            }
            Copy-Item @splatCopyPackageItem
        }
        # a rename on the same volume, so each folder arrives whole or not at all
        Move-Item -Path (Join-Path -Path $unpackedPath -ChildPath "externals") -Destination (Join-Path -Path $RunnerRoot -ChildPath "externals")
        Move-Item -Path (Join-Path -Path $unpackedPath -ChildPath "bin") -Destination (Join-Path -Path $RunnerRoot -ChildPath "bin")
    } finally {
        $splatRemoveStage = @{
            Path        = $stageRoot
            Recurse     = $true
            Force       = $true
            ErrorAction = "SilentlyContinue"
        }
        Remove-Item @splatRemoveStage
    }

    $installedVersion = Get-RunnerPackageVersion -RunnerRoot $RunnerRoot
    if ($installedVersion -ne $Version) {
        throw "runner reports version $installedVersion after the install, expected $Version"
    }
    "runner $installedVersion installed"
}

$vmState = Get-RunnerVmState
if ($vmState -eq "healthy") {
    "runner already configured on $env:COMPUTERNAME"
    exit 0
}
if ($vmState -eq "spent") {
    "SPENT-VM: $env:COMPUTERNAME already served a job or failed its bootstrap"
    exit 1
}

Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private

# AppVeyor parity: their workers run with Windows Firewall off, and several tests
# reach the local instances over loopback SMB/WMI/WinRM by computer name. The NSG
# still default-denies everything from the internet.
Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled False

# some tests create local user accounts and reach admin shares with them over
# loopback (\\COMPUTERNAME\x$); local accounts need an unfiltered token for that.
# The runner itself is LocalSystem and does not depend on this knob.
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name LocalAccountTokenFilterPolicy -Value 1 -Type DWord

# a SQL login with CHECK_POLICY can only be locked out when the host has an account
# lockout threshold, and the base image sets none, so LOGINPROPERTY(..., 'IsLocked')
# stayed 0 whatever happened. SQL Server reads the local policy of the machine running
# the instance, and the runner is not domain joined, so this is the whole story. The
# Set-DbaLogin unlock test fails exactly five logons, so the threshold has to be five or
# lower; duration and window only decide when Windows would release the lock by itself,
# the test unlocks explicitly (#10529).
$null = net accounts /lockoutthreshold:5 /lockoutduration:10 /lockoutwindow:10
if ($LASTEXITCODE -ne 0) {
    "WARNING: net accounts failed with exit code $LASTEXITCODE; login lockout tests will fail on this runner"
}

# the smalldisk base keeps a 30GB partition; harmless no-op when already extended
$partitionMax = (Get-PartitionSupportedSize -DriveLetter C).SizeMax
$partitionNow = (Get-Partition -DriveLetter C).Size
if ($partitionMax - $partitionNow -gt 1GB) {
    Resize-Partition -DriveLetter C -Size $partitionMax
}

# LocalSystem has no Documents folder by default. The module's Path.DbatoolsExport
# default resolves from MyDocuments (private/configurations/settings/paths.ps1), and
# several Export-Dba* tests write below $env:USERPROFILE\Documents.
$null = New-Item -Path "$env:SystemRoot\System32\config\systemprofile\Documents\DbatoolsExport" -ItemType Directory -Force

Set-Location -Path "C:\github-runner"

# GitHub stops handing jobs to a runner version once its runtime support ends (the
# runtime_deprecates_at of GET /repos/{repo}/actions/runners/deprecations/{version}), and
# --disableupdate below keeps the runner from fixing that itself. The golden image staged
# 2.335.1, whose runtime support ended 2026-09-24; when GitHub enforced it on 2026-11-15
# every runner registered, exited with "Runner version v2.335.1 is deprecated and cannot
# receive messages", probed as SPENT and was replaced, so the fleet churned VMs without
# serving a job. The bootstrap therefore brings the staged runner up to $runnerVersion
# before config.cmd. Bump the version and its hash together, from the release notes of
# actions/runner, and the image (image-scripts/step1-tools.ps1) with them. This runs
# before the bootstrapped-once marker, so a VM whose download or unpack fails still probes
# as fresh and the next reconcile retries it.
$runnerVersion = "2.338.2"
$runnerSha256 = "a1f17aa987fc8158bc7521d284912267a0d01b7c2c4684b33c86783b5e8221cc"
$splatRunnerPackage = @{
    RunnerRoot = "C:\github-runner"
    Version    = $runnerVersion
    Sha256     = $runnerSha256
    PackageUrl = "https://github.com/actions/runner/releases/download/v$runnerVersion/actions-runner-win-x64-$runnerVersion.zip"
}
try {
    Install-RunnerPackage @splatRunnerPackage
} catch {
    "runner install failed: $($PSItem.Exception.Message)"
    exit 1
}

# written before config.cmd on purpose: in service mode the runner can take its job the
# moment config.cmd starts the service, so a bootstrap that dies mid-config must probe
# as SPENT (delete and replace) rather than be retried onto a half-configured VM
Set-Content -Path "C:\github-runner\.bootstrapped-once" -Value (Get-Date -Format o)

# native commands write progress to stderr, which must not become terminating errors
$ErrorActionPreference = "Continue"
$configArgs = @(
    "--unattended",
    "--url", $RepoUrl,
    "--token", $Token,
    "--name", $RunnerName,
    "--labels", $Labels,
    "--work", "_work",
    "--ephemeral",
    "--disableupdate",
    "--runasservice",
    "--windowslogonaccount", "NT AUTHORITY\SYSTEM"
)
& .\config.cmd @configArgs 2>&1 | ForEach-Object { "$_" }
"config exit: $LASTEXITCODE"
if ($LASTEXITCODE -ne 0) {
    exit 1
}
$ErrorActionPreference = "Stop"

if ((Get-RunnerVmState) -ne "healthy") {
    "runner service is missing or not running after config.cmd"
    exit 1
}
$runnerService = @(Get-Service -Name "actions.runner.*" -ErrorAction SilentlyContinue | Where-Object Status -eq "Running")[0]
"runner configured as a LocalSystem service: $($runnerService.Name) [$($runnerService.Status)]"
