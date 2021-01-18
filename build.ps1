[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "It is a build script, com'on")]
[cmdletbinding()]
param()
Import-Module ".\src\dbatools.psd1"
Write-Host "Module imported" -ForegroundColor Cyan

Write-Host "Rebuilding command index" -ForegroundColor Cyan
Find-DbaCommand -Rebuild -Verbose

Write-Host "Building maml file"
Import-Module HelpOut
if (Test-Path .\src\en-us\dbatools-help.xml) {
    Remove-Item .\src\en-us\dbatools-help.xml -Force -Confirm:$false
}
Install-Maml -FunctionRoot functions -Module dbatools -Compact -NoVersion

Write-Host "Updating Glenn's files"
Save-DbaDiagnosticQueryScript -Path ".\src\bin\diagnosticquery"


Write-Host "All Done" -ForegroundColor DarkCyan