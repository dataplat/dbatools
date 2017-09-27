$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "limited operation testing of Maintenance Solution installer" {
		BeforeAll {
			$server = Connect-DbaSqlServer -SqlInstance $script:instance2
			$server.Databases['tempdb'].Query("CREATE TABLE CommandLog (id int)")
			}
		AfterAll {
			$server.Databases['tempdb'].Query("DROP TABLE CommandLog")
		}
		It "does not overwrite existing " {
			$results = Install-DbaMaintenanceSolution -SqlInstance $script:instance2 -Database tempdb -WarningVariable warn -WarningAction SilentlyContinue
			$warn -match "already exists" | Should Be $true
		}
	}
}