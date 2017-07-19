Describe "Get-DbaAgReplica Unit Tests" -Tag "UnitTests" {
	InModuleScope dbatools {
		Context "Validate parameters" {
			$params = (Get-ChildItem function:\Get-DbaAgReplica).Parameters	
			it "should have a parameter named SqlInstance" {
				$params.ContainsKey("SqlInstance") | Should Be $true
			}
			it "should have a parameter named Credential" {
				$params.ContainsKey("SqlCredential") | Should Be $true
			}
			it "should have a parameter named Silent" {
				$params.ContainsKey("Silent") | Should Be $true
			}
		}
		Context "Validate input" {
			it "Should throw message if SqlInstance is not accessible" {
				mock Resolve-DbaNetworkName {$null}
				{Get-DbaAgReplica -SqlInstance 'DoesNotExist142' -WarningAction Stop 3> $null} | Should Throw
			}
		}
	}
}
Describe "Get-DbaAgReplica Integration Test" -Tag "Integrationtests" {
	Write-Host "No integration test can be performed for this command"
}