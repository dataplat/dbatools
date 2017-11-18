$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "Get-DbaDbRole Unit Tests" -Tag "UnitTests" {
	InModuleScope dbatools {
		Context "Validate parameters" {
			$params = (Get-ChildItem function:\Get-DbaDbRole).Parameters
			it "should have a parameter named SqlInstance" {
				$params.ContainsKey("SqlInstance") | Should Be $true
			}
			it "should have a parameter named SqlCredential" {
				$params.ContainsKey("SqlCredential") | Should Be $true
			}
			it "should have a parameter named Database" {
				$params.ContainsKey("Database") | Should Be $true
			}
			it "should have a parameter named ExcludeDatabase" {
				$params.ContainsKey("ExcludeDatabase") | Should Be $true
			}
			it "should have a parameter named EnableException" {
				$params.ContainsKey("EnableException") | Should Be $true
			}
		}
}
Describe "Get-DbaDbRole Integration Tests" -Tag "IntegrationTests" {
		Context "parameters work" {
			it "returns no roles from excluded DB with -ExcludeDatabase" {
                $results = Get-DbaDbRole -SqlInstance $script:instance2 -ExcludeDatabase master
				$results.where({$_.Database -eq 'master'}).count | Should Be 0
			}
			it "returns only roles from selected DB with -Database" {
                $results = Get-DbaDbRole -SqlInstance $script:instance2 -Database master
				$results.where({$_.Database -ne 'master'}).count | Should Be 0
			}
			it "returns no fixed roles with -NoFixedRole" {
                $results = Get-DbaDbRole -SqlInstance $script:instance2 -NoFixedRole
				$results.where({$_.name -match 'db_datareader|db_datawriter|db_ddladmin'}).count | Should Be 0
			}
			it "returns fixed roles without -NoFixedRole" {
                $results = Get-DbaDbRole -SqlInstance $script:instance2
				$results.where({$_.name -match 'db_datareader|db_datawriter|db_ddladmin'}).count | Should BeGreaterThan 0
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