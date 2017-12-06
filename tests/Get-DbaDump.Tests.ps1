$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Testing if memory dump is present" {
		BeforeAll {
			$server = Connect-DbaInstance -SqlInstance $script:instance1
			$server.Query("DBCC STACKDUMP")
		}
		
		$results = Get-DbaDump -SqlInstance $script:instance1
		It "finds least one dump" {
			($results).Count -ge 1 | Should Be $true
		}
	}
}