
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
#Get-Module $ModuleName | Remove-Module

# Because ModuleBase includes version number, this imports the required version
# of the module
$null = Import-Module $ModuleBase\$ModuleName.psd1 -PassThru #-ErrorAction Stop


###############

## Validate functionality. 


Describe $name {
	context 'validate Select-Object AND Get-CimInstance' {
		It "gets Local Computer Info" {
			$localInfo = [pscustomobject] @{
				OSVersion              = 'Microsoft Windows 10 Enterprise(10.0.14393.0)'
				OsArchitecture         = '64-bit'
				PowerShellVersion      = '5.1.14393.693'
				PowerShellArchitecture = '64-bit PowerShell'
				DbaToolsVersion        = '0.8.941'
				ModuleBase             = 'D:\GitHub\dbatools'
				CLR                    = '4.0.30319.42000'
				SMO                    = '13.0.0.0'
				DomainUser             = 'False'
				RunAsAdmin             = 'True'
				isPowerShellISE        = 'False'
				}
			Mock Select-Object { 
				return $localInfo
				}

				#[System.Management.Automation.PSCustomObject] `
				#@{OSVersion, OsArchitecture,PowerShellVersion, PowerShellArchitecture, DbaToolsVersion, ModuleBase, CLR, SMO, DomainUser, RunAsAdmin, isPowerShellISE}
				#[System.Collections.Hashtable]


			Mock Get-CimInstance {
					[pscustomobject]@{
						Caption = 'Microsoft Windows 10 Enterprise'
						PSTypeName = 'Microsoft.Management.Infrastructure.CimInstance#root/cimv2/Win32_OperatingSystem'
					}
						[pscustomobject]@{
						OSArchitecture = '64-bit'
						PSTypeName = 'Microsoft.Management.Infrastructure.CimInstance#root/cimv2/Win32_OperatingSystem'
					}
				} -ParameterFilter {$ClassName -And $ClassName -ieq 'CIM_OperatingSystem'}



			

			Get-DbaDiagnosticInfo 

			Assert-MockCalled Select-Object -Times 2 -Exactly	
			Assert-MockCalled Get-CimInstance -Times 2 -Exactly
			
		} #end It block
	
	} -Tag "Unit Tests"
		Context "Checking Output of the function " {
					
					It 'Should not return null or Empty' {

					$localInfo = Get-DbaDiagnosticInfo

					$localInfo.OSVersion              | should Not BeNullOrEmpty
					$localInfo.OsArchitecture         | should Not BeNullOrEmpty
					$localInfo.PowerShellVersion      | should Not BeNullOrEmpty
					$localInfo.PowerShellArchitecture | should Not BeNullOrEmpty
					$localInfo.DbaToolsVersion        | should Not BeNullOrEmpty
					$localInfo.ModuleBase             | should Not BeNullOrEmpty
					$localInfo.CLR                    | should Not BeNullOrEmpty
					$localInfo.SMO                    | should Not BeNullOrEmpty
					$localInfo.DomainUser             | should Not BeNullOrEmpty
					$localInfo.RunAsAdmin             | should Not BeNullOrEmpty
					$localInfo.isPowerShellISE        | should Not BeNullOrEmpty
			} #end It block
		} -Tag "Operational Tests"
		
	
    
}
