<#
.SYNOPSIS
    Image-build step 3: final cleanup and sysprep generalize + shutdown.

.DESCRIPTION
    Removes build leftovers, then runs sysprep with /generalize /oobe /shutdown.
    The VM powers off when sysprep completes -- the orchestrator polls the Azure
    power state rather than a status marker for this step.

.NOTES
    Author: the dbatools team + Claude
    Runs as SYSTEM via run-step.ps1 on the image-build VM.
#>
param(
    [string]$ArgsPath
)

$ErrorActionPreference = "Stop"

Write-Output "== stopping any running SQL services"
Get-Service -Name "MSSQL`$*", "SQLAgent`$*" -ErrorAction SilentlyContinue | Where-Object Status -eq "Running" | Stop-Service -Force

Write-Output "== cleanup"
Remove-Item -Path "C:\media" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:windir\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

Write-Output "== sysprep generalize + shutdown"
$sysprepArgs = "/generalize", "/oobe", "/shutdown", "/mode:vm", "/quiet"
Start-Process -FilePath "$env:windir\System32\Sysprep\sysprep.exe" -ArgumentList $sysprepArgs
Write-Output "sysprep launched; VM will power off when generalization completes"
