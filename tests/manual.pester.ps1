Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
<#
    .SYNOPSIS
        Runs dbatools tests.

    .DESCRIPTION
        This file will either run all tests for dbatools or merely run the specified tests.

    .PARAMETER Path
        The Path to the test files to run
#>
[CmdletBinding()]
Param (
    [string[]]
    $Path,
	
	[ValidateSet('None', 'Default', 'Passed', 'Failed', 'Pending', 'Skipped', 'Inconclusive', 'Describe', 'Context', 'Summary', 'Header', 'All', 'Fails')]
	[string]
	$Show = "All",
	
	[switch]
	$TestIntegration,
    
    [switch]
    $SkipHelpTest
)
$ModuleBase = Split-Path -Path $PSScriptRoot -Parent
if (Get-Module dbatools) { Remove-Module dbatools }

Write-Host "Importing: $ModuleBase\dbatools.psm1"
Import-Module "$ModuleBase\dbatools.psm1" -DisableNameChecking
$ScriptAnalyzerRules = Get-ScriptAnalyzerRule

. $PSScriptRoot\..\internal\Write-Message.ps1
. $PSScriptRoot\..\internal\Stop-Function.ps1

$testInt = $false
if ($config_TestIntegration) { $testInt = $true }
if ($TestIntegration) { $testInt = $true }

if ($Path)
{
    foreach ($item in $Path)
    {
		if ($testInt) { Invoke-Pester $item }
        else { Invoke-Pester $item -ExcludeTag "Integrationtests" -Show $Show }
    }
}

else
{
    if ($testInt) { Invoke-Pester }
	else { Invoke-Pester -ExcludeTag "Integrationtests" -Show $Show }
}