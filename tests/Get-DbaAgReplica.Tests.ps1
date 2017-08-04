$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
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