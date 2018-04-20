Clear-Host 

$ScriptDirectory = Split-Path (Split-Path -Path $MyInvocation.MyCommand.Definition -Parent) -Parent
. ("$ScriptDirectory\internal\functions\Connect-SqlInstance.ps1")
. ("$ScriptDirectory\internal\functions\Stop-Function.ps1")
. ("$ScriptDirectory\internal\functions\Test-FunctionInterrupt.ps1")
. ("$ScriptDirectory\internal\functions\Test-DbaDeprecation.ps1")
. ("$ScriptDirectory\internal\functions\Write-Message.ps1")
. ("$ScriptDirectory\internal\functions\Select-DefaultView.ps1")
. ("$ScriptDirectory\functions\Copy-DbaResourceGovernor.ps1")
. ("$ScriptDirectory\functions\Get-DbaResourceGovernorClassiferFunction.ps1")

Copy-DbaResourceGovernor -Source "localhost\MSSQL2012" -Destination "localhost\MSSQL2016" -Force
#Get-DbaResourceGovernorClassiferFunction -SqlInstance localhost\MSSQL2012
#Write-Host $f

##