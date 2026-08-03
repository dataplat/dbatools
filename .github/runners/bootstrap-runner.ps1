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
