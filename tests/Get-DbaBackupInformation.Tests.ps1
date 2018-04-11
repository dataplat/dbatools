$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    BeforeAll {
        $DestBackupDir = 'C:\Temp\GetBackups'
        if (-Not(Test-Path $DestBackupDir)) {
            New-Item -Type Container -Path $DestBackupDir
        }
        else {
            Remove-Item $DestBackupDir\*
        }
        $random = Get-Random
        $dbname = "dbatoolsci_Backuphistory_$random"
        $null = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname | Remove-DbaDatabase -Confirm:$false
        $null = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $dbname -DestinationFilePrefix $dbname
        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname
        $db | Backup-DbaDatabase -Type Full -BackupDirectory $DestBackupDir
        $db | Backup-DbaDatabase -Type Differential -BackupDirectory $DestBackupDir
        $db | Backup-DbaDatabase -Type Log -BackupDirectory $DestBackupDir

        $dbname2 = "dbatoolsci_Backuphistory2_$random"
        $null = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname2 | Remove-DbaDatabase -Confirm:$false
        $null = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $dbname2 -DestinationFilePrefix $dbname2
        $db2 = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname2
        $db2 | Backup-DbaDatabase -Type Full -BackupDirectory $DestBackupDir
        $db2 | Backup-DbaDatabase -Type Differential -BackupDirectory $DestBackupDir
        $db2 | Backup-DbaDatabase -Type Log -BackupDirectory $DestBackupDir

        $DestBackupDirOla = 'C:\Temp\GetBackupsOla'
        if (-Not(Test-Path $DestBackupDirOla)) {
            New-Item -Type Container -Path $DestBackupDirOla
            New-Item -Type Container -Path $DestBackupDirOla\FULL
            New-Item -Type Container -Path $DestBackupDirOla\DIFF
            New-Item -Type Container -Path $DestBackupDirOla\LOG
        }
        else {
            Remove-Item $DestBackupDirOla\FULL\*
            Remove-Item $DestBackupDirOla\DIFF\*
            Remove-Item $DestBackupDirOla\LOG\*
        }

        $dbname3 = "dbatoolsci_BackuphistoryOla_$random"
        $null = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname3 | Remove-DbaDatabase -Confirm:$false
        $null = Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $dbname3 -DestinationFilePrefix $dbname3
        $db3 = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname3
        $db3 | Backup-DbaDatabase -Type Full -BackupDirectory "$DestBackupDirOla\FULL"
        $db3 | Backup-DbaDatabase -Type Differential -BackupDirectory "$DestBackupDirOla\Diff"
        $db3 | Backup-DbaDatabase -Type Log -BackupDirectory "$DestBackupDirOla\LOG"
    }

    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname | Remove-DbaDatabase -Confirm:$false
        $null = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname2 | Remove-DbaDatabase -Confirm:$false
    }

    Context "Get history for all database" {
        $results = Get-DbaBackupInformation -SqlInstance $script:instance1 -Path $DestBackupDir
        It "Should be 6 backups returned" {
            $results.count | Should Be 6
        }
        It "Should return 2 full backups" {
            ($results | Where-Object {$_.Type -eq 'Database'}).count | Should be 2
        }
        It "Should return 2 log backups" {
            ($results | Where-Object {$_.Type -eq 'Transaction Log'}).count | Should be 2
        }
    }

    Context "Get history for one database" {
        $results = Get-DbaBackupInformation -SqlInstance $script:instance1 -Path $DestBackupDir -DatabaseName $dbname2
        It "Should be 3 backups returned" {
            $results.count | Should Be 3
        }
        It "Should Be 1 full backup" {
            ($results | Where-Object {$_.Type -eq 'Database'}).count | Should be 1
        }
        It "Should be 1 log backups" {
            ($results | Where-Object {$_.Type -eq 'Transaction Log'}).count | Should be 1
        }
        It "Should only be backups of $dbname2" {
            ($results | Where-Object {$_.Database -ne $dbname2 }).count | Should Be 0
        }
    }

    Context "Check the export/import of backup history" {
        # This one used to cause all sorts of red
        $results = Get-DbaBackupInformation -SqlInstance $script:instance1 -Path $DestBackupDir -DatabaseName $dbname2 -ExportPath "$DestBackupDir\history.xml"

        # the command below returns just a warning
        # Get-DbaBackupInformation -Import -Path "$DestBackupDir\history.xml" | Restore-DbaDatabase -SqlInstance $script:instance1 -DestinationFilePrefix hist -RestoredDatabaseNamePrefix hist -TrustDbBackupHistory

        It "Should restore cleanly" {
            ($results | Where-Object {$_.RestoreComplete -eq $false}).count | Should be 0
        }
    }

    Context "Test Maintenance solution options" {
        $results = Get-DbaBackupInformation -SqlInstance $script:instance1 -Path $DestBackupDirOla -MaintenanceSolution
        It "Should be 3 backups returned" {
            $results.count | Should Be 3
        }
        It "Should Be 1 full backup" {
            ($results | Where-Object {$_.Type -eq 'Database'}).count | Should be 1
        }
        It "Should be 1 log backups" {
            ($results | Where-Object {$_.Type -eq 'Transaction Log'}).count | Should be 1
        }
        It "Should only be backups of $dbname3" {
            ($results | Where-Object {$_.Database -ne $dbname3 }).count | Should Be 0
        }
        $ResultsSanLog = Get-DbaBackupInformation -SqlInstance $script:instance1 -Path $DestBackupDirOla -MaintenanceSolution -IgnoreLogBackup
        It "Should be 2 backups returned" {
            $ResultsSanLog.count | Should Be 2
        }
        It "Should Be 1 full backup" {
            ($ResultsSanLog | Where-Object {$_.Type -eq 'Database'}).count | Should be 1
        }
        It "Should be 0 log backups" {
            ($resultsSanLog | Where-Object {$_.Type -eq 'Transaction Log'}).count | Should be 0
        }
        $ResultsSanLog = Get-DbaBackupInformation -SqlInstance $script:instance1 -Path $DestBackupDirOla -IgnoreLogBackup -WarningVariable warnvar -WarningAction SilentlyContinue
        It "Should Warn if IgnoreLogBackup without MaintenanceSolution" {
            ($WarnVar -match "IgnoreLogBackup can only by used with MaintenanceSolution. Will not be used") | Should Be $True
        }
        It "Should ignore IgnoreLogBackup and return 3 backups" {
            $resultsSanLog.count | Should Be 3
        }

    }

}