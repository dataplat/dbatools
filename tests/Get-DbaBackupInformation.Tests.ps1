$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
	
	BeforeAll {
		$DestBackupDir = 'C:\Temp\GetTackups'
		if (-Not(Test-Path $DestBackupDir)) {
			New-Item -Type Container -Path $DestBackupDir
        }
        $random = Get-Random
		$dbname = "dbatoolsci_Backuphistory_$random"
		$null = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname | Remove-DbaDatabase -Confirm:$false
		$null = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appeyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $dbname -DestinationFilePrefix $dbname
		$db = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname
		$db | Backup-DbaDatabase -Type Full -BackupDirectory $DestBackupDir
		$db | Backup-DbaDatabase -Type Differential -BackupDirectory $DestBackupDir
		$db | Backup-DbaDatabase -Type Log -BackupDirectory $DestBackupDir
		$db | Backup-DbaDatabase -Type Log -BackupDirectory $DestBackupDir
		$null = Get-DbaDatabase -SqlInstance $script:instance1 -Database master | Backup-DbaDatabase -Type Full
        $dbname2 = "dbatoolsci_Backuphistory2_$random"
		$null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname2 | Remove-DbaDatabase -Confirm:$false
		$null = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appeyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $dbname2 -DestinationFilePrefix $dbname2
		$db = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname2
		$db | Backup-DbaDatabase -Type Full -BackupDirectory $DestBackupDir
		$db | Backup-DbaDatabase -Type Differential -BackupDirectory $DestBackupDir
		$db | Backup-DbaDatabase -Type Log -BackupDirectory $DestBackupDir
		$db | Backup-DbaDatabase -Type Log -BackupDirectory $DestBackupDir
		$null = Get-DbaDatabase -SqlInstance $script:instance1 -Database master | Backup-DbaDatabase -Type Full
    
    }
    
    AfterAll {
		$null = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname | Remove-DbaDatabase -Confirm:$false
    	$null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
    }
    
    Context "Get last history for all database" {
		$results = Get-DbaBackupInformation -SqlInstance $script:instance1 -Path $DestBackupDir
		It "Should be 4 backups returned" {
			$results.count | Should Be 8
		}
		It "2 backups should be Full Backup" {
			($results | Where-Object {$_.Type -eq 'Database'}).count | Should be 2
		}
		It "4 Backups Should be log backups" {
			($results | Where-Object {$_.Type -eq 'Transaction Log'}).count | Should be 4
        }
    }

    Context "Get last history for one database" {
		$results = Get-DbaBackupInformation -SqlInstance $script:instance1 -Path $DestBackupDir -DatabaseName $dbname2
		It "Should be 4 backups returned" {
			$results.count | Should Be 4
		}
		It "Should Be 1 full backup" {
			($results | Where-Object {$_.Type -eq 'Database'}).count | Should be 1
		}
		It "Should be 2 log backups" {
			($results | Where-Object {$_.Type -eq 'Transaction Log'}).count | Should be 2
        }
        It "Should only be backups of $dbname2"{
            ($results | Where-Object {$_.Database -ne $dbname2 }).count | Should Be 0
        }
    }

    Context "Get last history for one instance" {
		$results = Get-DbaBackupInformation -SqlInstance $script:instance1 -Path $DestBackupDir -SourceInstance $dbname2
		It "Should be 4 backups returned" {
			$results.count | Should Be 4
		}
		It "Should Be 1 full backup" {
			($results | Where-Object {$_.Type -eq 'Database'}).count | Should be 1
		}
		It "Should be 2 log backups" {
			($results | Where-Object {$_.Type -eq 'Transaction Log'}).count | Should be 2
        }
        It "Should only be backups of $dbname2"{
            ($results | Where-Object {$_.SqlInsance -ne $dbname2 }).count | Should Be 0
        }
    }
}