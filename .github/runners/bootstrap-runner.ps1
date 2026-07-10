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
      2. register the runner as an ephemeral service running as SYSTEM

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

if (Test-Path -Path "C:\github-runner\.runner") {
    "runner already configured on $env:COMPUTERNAME"
    exit 0
}
if (Test-Path -Path "C:\github-runner\.bootstrapped-once") {
    # the ephemeral runner already served its single job and unregistered itself;
    # this VM is dirty (SQL state, workspace) and must be deleted, never reused
    "SPENT-VM: $env:COMPUTERNAME already served a job"
    exit 1
}

Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private

# AppVeyor parity: their workers run with Windows Firewall off, and several tests
# reach the local instances over loopback SMB/WMI/WinRM by computer name. The NSG
# still default-denies everything from the internet.
Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled False

# local accounts (the appveyor runner user) need an unfiltered token over loopback
# admin shares (Copy-DbaBackupDevice and friends copy via \\COMPUTERNAME\x$)
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name LocalAccountTokenFilterPolicy -Value 1 -Type DWord

# ephemeral-OS VMs come up with no pagefile; the setting object alone satisfies
# Get-DbaPageFileSetting (activation would need a reboot these VMs never get)
if (-not (Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue)) {
    $splatPageFile = @{
        ClassName = "Win32_PageFileSetting"
        Property  = @{ Name = "D:\pagefile.sys"; InitialSize = [uint32]4096; MaximumSize = [uint32]8192 }
    }
    $null = New-CimInstance @splatPageFile
}

# the smalldisk base keeps a 30GB partition; harmless no-op when already extended
$partitionMax = (Get-PartitionSupportedSize -DriveLetter C).SizeMax
$partitionNow = (Get-Partition -DriveLetter C).Size
if ($partitionMax - $partitionNow -gt 1GB) {
    Resize-Partition -DriveLetter C -Size $partitionMax
}

Set-Location -Path "C:\github-runner"

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
    "--windowslogonaccount", ".\appveyor",
    "--windowslogonpassword", "Password12!"
)
& .\config.cmd @configArgs 2>&1 | ForEach-Object { "$_" }
"config exit: $LASTEXITCODE"
if ($LASTEXITCODE -ne 0) {
    exit 1
}
Set-Content -Path "C:\github-runner\.bootstrapped-once" -Value (Get-Date -Format o)

Get-Service -Name "actions.runner.*" -ErrorAction SilentlyContinue | ForEach-Object {
    "service: $($_.Name) [$($_.Status)]"
}
