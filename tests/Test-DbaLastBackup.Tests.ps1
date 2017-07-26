$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

# prep
$null = Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeAllSystemDb | Remove-DbaDatabase
$server = Connect-DbaSqlServer -SqlInstance $script:instance2
$random = Get-Random
$testlastbackup = "testlastbackup$random"
$dbs = $testlastbackup, "lildb", "testrestore", "singlerestore"

foreach ($db in $dbs) {
	$server.Query("CREATE DATABASE $db")
	$server.Query("ALTER DATABASE $db SET RECOVERY FULL WITH NO_WAIT")
	$server.Query("CREATE TABLE [$db].[dbo].[Example] (id int identity, name nvarchar(max))")
	$server.Query("INSERT INTO [$db].[dbo].[Example] values ('sample')")
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	Context "Setup restores and backups on the local drive for Test-DbaLastBackup" {
		Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeDatabase tempdb | Backup-DbaDatabase -Type Database
		$server.Query("INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample')")
		Get-DbaDatabase -SqlInstance $script:instance2 -Database $testlastbackup | Backup-DbaDatabase -Type Differential
		$server.Query("INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample1')")
		Get-DbaDatabase -SqlInstance $script:instance2 -Database $testlastbackup | Backup-DbaDatabase -Type Differential
		$server.Query("INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample2')")
		Get-DbaDatabase -SqlInstance $script:instance2 -Database $testlastbackup | Backup-DbaDatabase -Type Log
		$server.Query("INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample3')")
		Get-DbaDatabase -SqlInstance $script:instance2 -Database $testlastbackup | Backup-DbaDatabase -Type Log
		$server.Query("INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample4')")
	}
	
	Context "Test a single database" {
		$results = Test-DbaLastBackup -SqlInstance $script:instance2 -Database $testlastbackup
		
		It "Should return success" {
			$results.RestoreResult | Should Be "Success"
			$results.DbccResult | Should Be "Success"
		}
	}
	
	Context "Testing the whole instance" {
		$results = Test-DbaLastBackup -SqlInstance $script:instance2 -ExcludeDatabase tempdb
		It "Should be more than 3 databases" {
			$results.count | Should BeGreaterThan 3
		}
	}
	
	Context "Testing that it restores to a specific path" {
		$null = Get-DbaDatabase -SqlInstance $script:instance2 -Database singlerestore | Backup-DbaDatabase
		$null = Test-DbaLastBackup -SqlInstance $script:instance2 -Database singlerestore -DataDirectory C:\temp -LogDirectory C:\temp -NoDrop
		$results = Get-DbaDatabaseFile -SqlInstance $script:instance2 -Database dbatools-testrestore-singlerestore
		It "Should match C:\temp" {
			('C:\temp\dbatools-testrestore-singlerestore.mdf' -in $results.PhysicalName) | Should Be $true
			('C:\temp\dbatools-testrestore-singlerestore_log.ldf' -in $results.PhysicalName) | Should Be $true
		}
		
		$null = Get-DbaProcess -SqlInstance $script:instance2 -Database dbatools-testrestore-singlerestore | Stop-DbaProcess
		$null = Get-DbaDatabase -SqlInstance $script:instance2 -ExcludeAllSystemDb | Remove-DbaDatabase
	}
}