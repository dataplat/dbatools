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
    
    [switch]
    $SkipHelpTest
)
$ModuleBase = Split-Path -Path $PSScriptRoot -Parent
Write-Host "Importing: $ModuleBase\dbatools.psm1"
Import-Module "$ModuleBase\dbatools.psm1" -DisableNameChecking
$ScriptAnalyzerRules = Get-ScriptAnalyzerRule

if ($Path)
{
    foreach ($item in $Path)
    {
        Invoke-Pester $item
    }
}

else
{
    Invoke-Pester
}