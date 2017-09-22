$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Testing if suspect pages are present" {
		BeforeAll {
			$db = Get-DbaDatabase -SqlInstance $script:instance1 -Database msdb
			$db.Query("INSERT INTO msdb.dbo.suspect_pages VALUES(1,1,33,2,6,GETDATE())")
		}
		AfterAll {
			$db.Query("DELETE FROM msdb.dbo.suspect_pages")
		}
		
		$results = Get-DbaSuspectPage -SqlInstance $script:instance1
		
		It "function should find one record in suspect_pages table" {
			$results.file_id.Count -eq 1 | Should Be $true
		}
	}
}
