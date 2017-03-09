
## Thank you Warren http://ramblingcookiemonster.github.io/Testing-DSC-with-Pester-and-AppVeyor/

if(-not $PSScriptRoot) {
	$PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}

$Verbose = @{}
if($env:APPVEYOR_REPO_BRANCH -and $env:APPVEYOR_REPO_BRANCH -notlike "master") {
	$Verbose.add("Verbose", $true)
}


$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace('.Tests.', '.')
Import-Module "$PSScriptRoot\..\functions\$sut" -Force
Import-Module PSScriptAnalyzer
## Added PSAvoidUsingPlainTextForPassword as credential is an object and therefore fails. We can ignore any rules here under special circumstances agreed by admins :-)
$rules = Get-ScriptAnalyzerRule | Where-Object{$_.RuleName -notin ('PSAvoidUsingPlainTextForPassword') }
$name = $sut.Split('.')[0]

Describe 'Script Analyzer Tests' {
	Context "Testing $name for Standard Processing" {
		foreach ($rule in $rules) { 
			$index = $rules.IndexOf($rule)
			It "passes the PSScriptAnalyzer Rule number $index - $rule	" {
				(Invoke-ScriptAnalyzer -Path "$PSScriptRoot\..\functions\$sut" -IncludeRule $rule.RuleName).Count | Should Be 0 
			}
		}
	}
}

## Load the command
$ModuleBase = Split-Path -Parent $MyInvocation.MyCommand.Path

# For tests in .\Tests subdirectory
if ((Split-Path $ModuleBase -Leaf) -eq 'Tests')
{
	$ModuleBase = Split-Path $ModuleBase -Parent
}

# Handles modules in version directories
$leaf = Split-Path $ModuleBase -Leaf
$parent = Split-Path $ModuleBase -Parent
$parsedVersion = $null
if ([System.Version]::TryParse($leaf, [ref]$parsedVersion)) {
	$ModuleName = Split-Path $parent -Leaf
}
else {
	$ModuleName = $leaf
}

# Removes all versions of the module from the session before importing
Get-Module $ModuleName | Remove-Module

# Because ModuleBase includes version number, this imports the required version
# of the module
$null = Import-Module $ModuleBase\$ModuleName.psd1 -PassThru -ErrorAction Stop



###############

## Validate functionality. 
<#

Describe $name {
    It "tries to get Powershell version" {
        $true | Should Be $false
    }



    It "tries to get Windows Version" {
        $true | Should Be $false
    }

    It "tries to determine if Powershell is running in Adminstrator mode" {
        $true | Should Be $false
    }

    It "tries to get DBAtools version" {
        $true | Should Be $false
    }

    

#>