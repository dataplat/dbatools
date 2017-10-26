$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	BeforeAll {
		$server = Connect-DbaInstance -SqlInstance $script:instance2
		$sql = "EXEC msdb.dbo.sp_add_operator @name=N'dbatoolsci_operator', @enabled=1, @pager_days=0"
		$server.Query($sql)
	}
	AfterAll {
		$sql = "EXEC msdb.dbo.sp_delete_operator @name=N'dbatoolsci_operator'"
		$server.Query($sql)
	}
	Context "Count Number of Database Maintenance Agent Jobs on localhost" {
		$results = Get-DbaAgentOperator -SqlInstance $script:instance2 -Operator dbatoolsci_operator
		It "return one result" {
			$results.Count | Should Be 1
		}
	}
	
}
