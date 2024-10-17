param($ModuleName = 'dbatools')

Describe "Get-DbaBackupInformation" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $DestBackupDir = 'C:\Temp\GetBackups'
        if (-Not(Test-Path $DestBackupDir)) {
            New-Item -Type Container -Path $DestBackupDir
        } else {
            Remove-Item $DestBackupDir\*
        }
        $random = Get-Random
        $dbname = "dbatoolsci_Backuphistory_$random"
        $null = Get-DbaDatabase -SqlInstance $global:instance1 -Database $dbname | Remove-DbaDatabase -Confirm:$false
        $null = Restore-DbaDatabase -SqlInstance $global:instance1 -Path $global:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $dbname -DestinationFilePrefix $dbname
        $db = Get-DbaDatabase -SqlInstance $global:instance1 -Database $dbname
        $db | Backup-DbaDatabase -Type Full -BackupDirectory $DestBackupDir
        $db | Backup-DbaDatabase -Type Differential -BackupDirectory $DestBackupDir
        $db | Backup-DbaDatabase -Type Log -BackupDirectory $DestBackupDir

        $dbname2 = "dbatoolsci_Backuphistory2_$random"
        $null = Get-DbaDatabase -SqlInstance $global:instance1 -Database $dbname2 | Remove-DbaDatabase -Confirm:$false
        $null = Restore-DbaDatabase -SqlInstance $global:instance1 -Path $global:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $dbname2 -DestinationFilePrefix $dbname2
        $db2 = Get-DbaDatabase -SqlInstance $global:instance1 -Database $dbname2
        $db2 | Backup-DbaDatabase -Type Full -BackupDirectory $DestBackupDir
        $db2 | Backup-DbaDatabase -Type Differential -BackupDirectory $DestBackupDir
        $db2 | Backup-DbaDatabase -Type Log -BackupDirectory $DestBackupDir

        $DestBackupDirOla = 'C:\Temp\GetBackupsOla'
        if (-Not(Test-Path $DestBackupDirOla)) {
            New-Item -Type Container -Path $DestBackupDirOla
            New-Item -Type Container -Path $DestBackupDirOla\FULL
            New-Item -Type Container -Path $DestBackupDirOla\DIFF
            New-Item -Type Container -Path $DestBackupDirOla\LOG
        } else {
            Remove-Item $DestBackupDirOla\FULL\*
            Remove-Item $DestBackupDirOla\DIFF\*
            Remove-Item $DestBackupDirOla\LOG\*
        }

        $dbname3 = "dbatoolsci_BackuphistoryOla_$random"
        $null = Get-DbaDatabase -SqlInstance $global:instance1 -Database $dbname3 | Remove-DbaDatabase -Confirm:$false
        $null = Restore-DbaDatabase -SqlInstance $global:instance1 -Path $global:appveyorlabrepo\singlerestore\singlerestore.bak -DatabaseName $dbname3 -DestinationFilePrefix $dbname3
        $db3 = Get-DbaDatabase -SqlInstance $global:instance1 -Database $dbname3
        $db3 | Backup-DbaDatabase -Type Full -BackupDirectory "$DestBackupDirOla\FULL"
        $db3 | Backup-DbaDatabase -Type Differential -BackupDirectory "$DestBackupDirOla\Diff"
        $db3 | Backup-DbaDatabase -Type Log -BackupDirectory "$DestBackupDirOla\LOG"
    }

    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $global:instance1 -Database $dbname, $dbname2, $dbname3 | Remove-DbaDatabase -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaBackupInformation
        }
        It "Should have Path parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type Object[] -Not -Mandatory
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have DatabaseName parameter" {
            $CommandUnderTest | Should -HaveParameter DatabaseName -Type String[] -Not -Mandatory
        }
        It "Should have SourceInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SourceInstance -Type String[] -Not -Mandatory
        }
        It "Should have NoXpDirTree parameter" {
            $CommandUnderTest | Should -HaveParameter NoXpDirTree -Type Switch -Not -Mandatory
        }
        It "Should have NoXpDirRecurse parameter" {
            $CommandUnderTest | Should -HaveParameter NoXpDirRecurse -Type Switch -Not -Mandatory
        }
        It "Should have DirectoryRecurse parameter" {
            $CommandUnderTest | Should -HaveParameter DirectoryRecurse -Type Switch -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
        It "Should have MaintenanceSolution parameter" {
            $CommandUnderTest | Should -HaveParameter MaintenanceSolution -Type Switch -Not -Mandatory
        }
        It "Should have IgnoreLogBackup parameter" {
            $CommandUnderTest | Should -HaveParameter IgnoreLogBackup -Type Switch -Not -Mandatory
        }
        It "Should have IgnoreDiffBackup parameter" {
            $CommandUnderTest | Should -HaveParameter IgnoreDiffBackup -Type Switch -Not -Mandatory
        }
        It "Should have ExportPath parameter" {
            $CommandUnderTest | Should -HaveParameter ExportPath -Type String -Not -Mandatory
        }
        It "Should have AzureCredential parameter" {
            $CommandUnderTest | Should -HaveParameter AzureCredential -Type String -Not -Mandatory
        }
        It "Should have Import parameter" {
            $CommandUnderTest | Should -HaveParameter Import -Type Switch -Not -Mandatory
        }
        It "Should have Anonymise parameter" {
            $CommandUnderTest | Should -HaveParameter Anonymise -Type Switch -Not -Mandatory
        }
        It "Should have NoClobber parameter" {
            $CommandUnderTest | Should -HaveParameter NoClobber -Type Switch -Not -Mandatory
        }
        It "Should have PassThru parameter" {
            $CommandUnderTest | Should -HaveParameter PassThru -Type Switch -Not -Mandatory
        }
    }

    Context "Get history for all database" {
        BeforeAll {
            $results = Get-DbaBackupInformation -SqlInstance $global:instance1 -Path $DestBackupDir
        }
        It "Should be 6 backups returned" {
            $results.count | Should -Be 6
        }
        It "Should return 2 full backups" {
            ($results | Where-Object {$_.Type -eq 'Database'}).count | Should -Be 2
        }
        It "Should return 2 log backups" {
            ($results | Where-Object {$_.Type -eq 'Transaction Log'}).count | Should -Be 2
        }
    }

    Context "Get history for one database" {
        BeforeAll {
            $results = Get-DbaBackupInformation -SqlInstance $global:instance1 -Path $DestBackupDir -DatabaseName $dbname2
        }
        It "Should be 3 backups returned" {
            $results.count | Should -Be 3
        }
        It "Should Be 1 full backup" {
            ($results | Where-Object {$_.Type -eq 'Database'}).count | Should -Be 1
        }
        It "Should be 1 log backups" {
            ($results | Where-Object {$_.Type -eq 'Transaction Log'}).count | Should -Be 1
        }
        It "Should only be backups of $dbname2" {
            ($results | Where-Object {$_.Database -ne $dbname2 }).count | Should -Be 0
        }
    }

    Context "Check the export/import of backup history" {
        BeforeAll {
            $results = Get-DbaBackupInformation -SqlInstance $global:instance1 -Path $DestBackupDir -DatabaseName $dbname2 -ExportPath "$DestBackupDir\history.xml"
        }
        It "Should restore cleanly" {
            ($results | Where-Object {$_.RestoreComplete -eq $false}).count | Should -Be 0
        }
    }

    Context "Test Maintenance solution options" {
        BeforeAll {
            $results = Get-DbaBackupInformation -SqlInstance $global:instance1 -Path $DestBackupDirOla -MaintenanceSolution
        }
        It "Should be 3 backups returned" {
            $results.count | Should -Be 3
        }
        It "Should Be 1 full backup" {
            ($results | Where-Object {$_.Type -eq 'Database'}).count | Should -Be 1
        }
        It "Should be 1 log backups" {
            ($results | Where-Object {$_.Type -eq 'Transaction Log'}).count | Should -Be 1
        }
        It "Should only be backups of $dbname3" {
            ($results | Where-Object {$_.Database -ne $dbname3 }).count | Should -Be 0
        }

        Context "Ignore Log Backup" {
            BeforeAll {
                $ResultsSanLog = Get-DbaBackupInformation -SqlInstance $global:instance1 -Path $DestBackupDirOla -MaintenanceSolution -IgnoreLogBackup
            }
            It "Should be 2 backups returned" {
                $ResultsSanLog.count | Should -Be 2
            }
            It "Should Be 1 full backup" {
                ($ResultsSanLog | Where-Object {$_.Type -eq 'Database'}).count | Should -Be 1
            }
            It "Should be 0 log backups" {
                ($resultsSanLog | Where-Object {$_.Type -eq 'Transaction Log'}).count | Should -Be 0
            }
        }

        Context "Ignore Log Backup without MaintenanceSolution" {
            BeforeAll {
                $ResultsSanLog = Get-DbaBackupInformation -SqlInstance $global:instance1 -Path $DestBackupDirOla -IgnoreLogBackup -WarningVariable warnvar -WarningAction SilentlyContinue
            }
            It "Should Warn if IgnoreLogBackup without MaintenanceSolution" {
                $warnVar | Should -Match "IgnoreLogBackup can only by used with MaintenanceSolution. Will not be used"
            }
            It "Should ignore IgnoreLogBackup and return 3 backups" {
                $resultsSanLog.count | Should -Be 3
            }
        }
    }
}
