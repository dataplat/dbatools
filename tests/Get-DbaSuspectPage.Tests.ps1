$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Testing if suspect pages are present" {
		BeforeAll {
			$dbname = "dbatoolsci_GetSuspectPage"
			$Server = Connect-DbaInstance -SqlInstance $script:instance1
			$null = $Server.Query("Create Database [$dbname]")
			$db = Get-DbaDatabase -SqlInstance $Server -Database $dbname
		}
		
		AfterAll {
			Remove-DbaDatabase -SqlInstance $Server -Database $dbname -Confirm:$false
		}
		
		
		$null = $db.Query("
		CREATE TABLE dbo.[Example] (id int); 
		INSERT dbo.[Example] 
		SELECT top 1000 1 
		FROM sys.objects")
		
		try {
			$null = Invoke-DbaDatabaseCorruption -SqlInstance $script:instance1 -Database $dbname -Confirm:$false
			$null = $db.Query("select top 1 from example")
			$null = Start-DbccCheck -Server $Server -dbname $dbname -WarningAction SilentlyContinue
		} catch {} # should fail
		
		try { $null = $db.Query("select top 1 from example") } catch { }
		try { $null = $db.Query("select top 1 from example") } catch { }
		try { $null = $db.Query("select top 1 from example") } catch { }
		try { $null = $db.Query("select top 1 from example") } catch { }
		try { $null = Start-DbccCheck -Server $Server -dbname $dbname -Table -WarningAction SilentlyContinue } catch { }
		
		$results = Get-DbaSuspectPage -SqlInstance $server
		It "function should find at least one record in suspect_pages table" {
			$results.Database -contains $dbname | Should Be $true
		}
	}
}
