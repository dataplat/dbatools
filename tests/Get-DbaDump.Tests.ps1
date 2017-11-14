$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Testing if memory dump is present" {
		BeforeAll {
			$Server = Connect-DbaInstance -SqlInstance $script:instance1
			$Server.Query("DBCC STACKDUMP;")
		}
		
		$results = Get-DbaDump -SqlInstance $server
		It "finds least one dump" {
			($results).Count -ge 1 | Should Be $true
		}
	}
}