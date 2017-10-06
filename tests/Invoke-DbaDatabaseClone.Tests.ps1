$CommandName = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
	$dbname = "dbatoolsci_clonetest"
	$clonedb = "dbatoolsci_clonetest_CLONE"
	$clonedb2 = "dbatoolsci_clonetest_CLONE2"
	Context "Command functions as expected" {
		BeforeAll {
			$server = Connect-DbaInstance -SqlInstance $script:instance2
			$server.Query("CREATE DATABASE $dbname")
		}
		
		AfterAll {
			Get-DbaDatabase -SqlInstance $server -Database $dbname, $clonedb, $clonedb2 | Remove-DbaDatabase -Confirm:$false
		}
		
		It "warns if SQL instance version is not supported" {
			$results = Invoke-DbaDatabaseClone -SqlInstance $script:instance1 -Database $dbname -CloneDatabase $clonedb -WarningAction SilentlyContinue -WarningVariable versionwarn
			$versionwarn -match "required" | Should Be $true
		}
		
		It -Skip "warns if destination database already exists" {
			$results = Invoke-DbaDatabaseClone -SqlInstance $script:instance2 -Database $dbname -CloneDatabase tempdb -WarningAction SilentlyContinue -WarningVariable dbwarn
			$dbwarn -match "exists" | Should Be $true
		}
		
		It -Skip "warns if a system db is specified to clone" {
			$results = Invoke-DbaDatabaseClone -SqlInstance $script:instance2 -Database master -CloneDatabase $clonedb -WarningAction SilentlyContinue -WarningVariable systemwarn
			$systemwarn -match "user database" | Should Be $true
		}
		
		$results = Invoke-DbaDatabaseClone -SqlInstance $script:instance2 -Database $dbname -CloneDatabase $clonedb -WarningAction SilentlyContinue
		
		It -Skip "returns 2 results" {
			$results.Count -eq 2 | Should Be $true
		}
		
		foreach ($result in $results) {
			It "returns a rich database object with the correct name" {
				$result.Name -in $clonedb, $clonedb2 | Should Be $true
			}
		}
	}
}