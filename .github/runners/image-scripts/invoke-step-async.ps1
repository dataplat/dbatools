<#
.SYNOPSIS
    Launches one image-build step asynchronously on the build VM (via az vm run-command).

.DESCRIPTION
    SQL Server installs run far longer than a comfortable run-command round trip, so this
    script returns immediately: it downloads run-step.ps1 and the requested step script
    from the repo branch, writes optional step arguments, then fires a one-shot scheduled
    task running as SYSTEM. Progress is observed with poll-step.ps1.

        az vm run-command invoke --resource-group dbatools-ci-imagebuild --name dbat-imgbuild --command-id RunPowerShellScript --scripts "@.github/runners/image-scripts/invoke-step-async.ps1" --parameters "RawBase=https://raw.githubusercontent.com/dataplat/dbatools/vmssredux" "Step=step1-tools"

.NOTES
    Author: the dbatools team + Claude
#>
param(
    [Parameter(Mandatory)]
    [string]$RawBase,
    [Parameter(Mandatory)]
    [string]$Step,
    [string]$ArgsJson
)

$ErrorActionPreference = "Stop"
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]3072

$buildRoot = "C:\imagebuild"
if (-not (Test-Path -Path $buildRoot)) {
    $null = New-Item -Path $buildRoot -ItemType Directory -Force
}

$webClient = New-Object -TypeName System.Net.WebClient
$webClient.DownloadFile("$RawBase/.github/runners/image-scripts/run-step.ps1", "$buildRoot\run-step.ps1")
$webClient.DownloadFile("$RawBase/.github/runners/image-scripts/$Step.ps1", "$buildRoot\$Step.ps1")

if ($ArgsJson) {
    Set-Content -Path "$buildRoot\$Step.args.json" -Value $ArgsJson
}
Remove-Item -Path "$buildRoot\$Step.status", "$buildRoot\$Step.log" -Force -ErrorAction SilentlyContinue

$taskName = "imagebuild-$Step"
$splatAction = @{
    Execute  = "powershell.exe"
    Argument = "-NoProfile -ExecutionPolicy Bypass -File $buildRoot\run-step.ps1 -Step $Step"
}
$action = New-ScheduledTaskAction @splatAction
$splatTask = @{
    TaskName = $taskName
    Action   = $action
    User     = "NT AUTHORITY\SYSTEM"
    RunLevel = "Highest"
    Force    = $true
}
$null = Register-ScheduledTask @splatTask
Start-ScheduledTask -TaskName $taskName
"launched $Step (poll with poll-step.ps1)"
