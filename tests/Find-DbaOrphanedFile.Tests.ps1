$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

$null = Get-DbaDatabase -SqlInstance $script:instance1 -NoSystemDb | Remove-DbaDatabase
$server = Connect-DbaSqlServer -SqlInstance $script:instance1
$dbname = "findme"
$server.Query("CREATE DATABASE $dbname")

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Detaches a single database and tests to ensure the alias still exists" {
		$null = Detach-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Force
		$results = Find-DbaOrphanedFile -SqlInstance $script:instance1
		It "Should find two files" {
			$results.Count | Should Be 2
		}
		
		$results.FileName | Remove-Item
		
		$results = Find-DbaOrphanedFile -SqlInstance $script:instance1 *>&1
		It "Should find zero files" {
			$results.Count | Should Be 0
		}
	}
}