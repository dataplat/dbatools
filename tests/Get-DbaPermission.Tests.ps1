$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
Describe "Get-DbaPermission Unit Tests" -Tag "UnitTests" {
	InModuleScope dbatools {
		Context "Validate parameters" {
			$params = (Get-ChildItem function:\Get-DbaPermission).Parameters	
			it "should have a parameter named SqlInstance" {
				$params.ContainsKey("SqlInstance") | Should Be $true
			}
			it "should have a parameter named SqlCredential" {
				$params.ContainsKey("SqlCredential") | Should Be $true
			}
			it "should have a parameter named EnableException" {
				$params.ContainsKey("EnableException") | Should Be $true
			}
		}
		Context "Validate input" {
			it "Cannot resolve hostname of computer" {
				mock Resolve-DbaNetworkName {$null}
				{Get-DbaComputerSystem -ComputerName 'DoesNotExist142' -WarningAction Stop 3> $null} | Should Throw
			}
		}
	}
}