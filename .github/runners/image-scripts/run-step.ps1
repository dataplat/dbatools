<#
.SYNOPSIS
    On-VM wrapper that runs one image-build step with logging and status markers.

.DESCRIPTION
    Executed by a scheduled task (SYSTEM) that invoke-step-async.ps1 registers. Runs
    C:\imagebuild\<Step>.ps1 with a transcript to C:\imagebuild\<Step>.log and writes
    C:\imagebuild\<Step>.status ("done" or "fail: <reason>") so the orchestrator can
    poll cheaply via short run-command calls.

.NOTES
    Author: the dbatools team + Claude
#>
param(
    [Parameter(Mandatory)]
    [string]$Step
)

$buildRoot = "C:\imagebuild"
$stepScript = Join-Path $buildRoot "$Step.ps1"
$argsPath = Join-Path $buildRoot "$Step.args.json"
$statusPath = Join-Path $buildRoot "$Step.status"
$logPath = Join-Path $buildRoot "$Step.log"

Start-Transcript -Path $logPath -Force
try {
    if (Test-Path -Path $argsPath) {
        & $stepScript -ArgsPath $argsPath
    } else {
        & $stepScript
    }
    Set-Content -Path $statusPath -Value "done"
} catch {
    $_ | Out-String | Write-Output
    Set-Content -Path $statusPath -Value "fail: $($_.Exception.Message)"
} finally {
    Stop-Transcript
}
