<#
.SYNOPSIS
    Reports the status and recent log lines of an async image-build step.

.DESCRIPTION
    Companion to invoke-step-async.ps1. Prints the step status marker (or "running"),
    then the transcript tail, keeping well under the run-command 4KB output cap.

        az vm run-command invoke --resource-group dbatools-ci-imagebuild --name dbat-imgbuild --command-id RunPowerShellScript --scripts "@.github/runners/image-scripts/poll-step.ps1" --parameters "Step=step1-tools"

.NOTES
    Author: the dbatools team + Claude
#>
param(
    [Parameter(Mandatory)]
    [string]$Step
)

$buildRoot = "C:\imagebuild"
$statusPath = Join-Path $buildRoot "$Step.status"
$logPath = Join-Path $buildRoot "$Step.log"

if (Test-Path -Path $statusPath) {
    "STATUS: $(Get-Content -Path $statusPath -Raw)"
} else {
    "STATUS: running"
}
if (Test-Path -Path $logPath) {
    "--- log tail ---"
    Get-Content -Path $logPath -Tail 20 | ForEach-Object { $_ }
}
