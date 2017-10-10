$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

	BeforeAll {
	}

	AfterAll {
		$null = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname | Remove-DbaDatabase -Confirm:$false
	}

	Context "Corrupt a single database" {}
  Context "Fail if more than one database is specified" {}
  Context "Require at least a single table in the database"
  Context "Fail if the specified table does not exist"{}
}