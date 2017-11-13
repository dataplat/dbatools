$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Testing if memory dump is present" {
		BeforeAll {
			$Server = Connect-DbaInstance -SqlInstance $script:instance2
			$null = $Server.Query("DBCC STACKDUMP;")
		}
		
		$results = Get-DbaSqlDump -SqlInstance $server
		It "function should return a count of 1 dump found" {
			$results.Count -eq 1 | Should Be $true
		}
	}
}
