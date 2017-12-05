$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	BeforeAll {
		$dbname = "dbatoolsci_publishdacpac"
		$server = Connect-DbaInstance -SqlInstance $script:instance1
		# Need a clean empty database
		$null = $server.Query("Create Database [$dbname]")
		$db = Get-DbaDatabase -SqlInstance $server -Database $dbname
		$null = $db.Query("CREATE TABLE dbo.example (id int); 
			INSERT dbo.example
			SELECT top 100 1 
			FROM sys.objects")
		$publishprofile = New-DbaPublishProfile -SqlInstance $script:instance1 -Database $dbname -Path C:\temp
		$server = Connect-DbaInstance -SqlInstance $script:instance2
		$null = $server.Query("Create Database [$dbname]")
		$dacpac = Export-DbaDacpac -SqlInstance $script:instance1 -Database $dbname
	}
	AfterAll {
		Remove-DbaDatabase -SqlInstance $script:instance1, $script:instance2 -Database $dbname -Confirm:$false
		Remove-Item -Confirm:$false -Path $publishprofile.FileName -ErrorAction SilentlyContinue
	}
	
	Context "Testing pipability and that the command works" {
		It "shows that the upate is complete" {
			$results = $dacpac | Publish-DbaDacpac -PublishXml $publishprofile.FileName -Database $dbname -SqlInstance $script:instance2
			$results.Result -match 'Update complete.' | Should Be $true
			Remove-Item -Confirm:$false -Path ($dacpac).Path -ErrorAction SilentlyContinue
		}
	}
}