$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
	InModuleScope dbatools {
		Context "Validate parameters" {
			$params = (Get-ChildItem function:\Get-DbaAgDatabase).Parameters	
			it "should have a parameter named SqlInstance" {
				$params.ContainsKey("SqlInstance") | Should Be $true
			}
			it "should have a parameter named Credential" {
				$params.ContainsKey("SqlCredential") | Should Be $true
			}
			it "should have a parameter named Silent" {
				$params.ContainsKey("Silent") | Should Be $true
			}
			it "should have a parameter named AvailabilityGroup" {
				$params.ContainsKey("AvailabilityGroup") | Should Be $true
			}
			it "should have a parameter named Database" {
				$params.ContainsKey("Database") | Should Be $true
			}
		}
		Context "Validate input" {
			it "Should throw message if SqlInstance is not accessible" {
				mock Resolve-DbaNetworkName {$null}
				{Get-DbaAgDatabase -SqlInstance 'DoesNotExist142' -WarningAction Stop 3> $null} | Should Throw
			}
		}
	}
}
Describe "Get-DbaAgDatabase Integration Test" -Tag "IntegrationTests" {
	Write-Host "[Get-DbaAgDatabase] - No integration test can be performed for this command"
} 
