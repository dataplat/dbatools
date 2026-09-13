#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaBackupInformation",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "SqlInstance",
                "SqlCredential",
                "DatabaseName",
                "SourceInstance",
                "NoXpDirTree",
                "DirectoryRecurse",
                "EnableException",
                "MaintenanceSolution",
                "IgnoreLogBackup",
                "IgnoreDiffBackup",
                "ExportPath",
                "StorageCredential",
                "Import",
                "Anonymise",
                "NoClobber",
                "PassThru",
                "NoXpDirRecurse"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $DestBackupDir = "$($TestConfig.Temp)\GetBackups"
        if (-Not(Test-Path $DestBackupDir)) {
            $null = New-Item -Type Container -Path $DestBackupDir
        } else {
            Remove-Item $DestBackupDir\*
        }
        $random = Get-Random
        $dbname = "dbatoolsci_Backuphistory_$random"
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Remove-DbaDatabase
        $splatRestore1 = @{
            SqlInstance           = $TestConfig.InstanceSingle
            Path                  = "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak"
            DatabaseName          = $dbname
            DestinationFilePrefix = $dbname
        }
        $null = Restore-DbaDatabase @splatRestore1
        $db = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname
        $db | Backup-DbaDatabase -Type Full -BackupDirectory $DestBackupDir
        $db | Backup-DbaDatabase -Type Differential -BackupDirectory $DestBackupDir
        $db | Backup-DbaDatabase -Type Log -BackupDirectory $DestBackupDir

        $dbname2 = "dbatoolsci_Backuphistory2_$random"
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname2 | Remove-DbaDatabase
        $splatRestore2 = @{
            SqlInstance           = $TestConfig.InstanceSingle
            Path                  = "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak"
            DatabaseName          = $dbname2
            DestinationFilePrefix = $dbname2
        }
        $null = Restore-DbaDatabase @splatRestore2
        $db2 = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname2
        $db2 | Backup-DbaDatabase -Type Full -BackupDirectory $DestBackupDir
        $db2 | Backup-DbaDatabase -Type Differential -BackupDirectory $DestBackupDir
        $db2 | Backup-DbaDatabase -Type Log -BackupDirectory $DestBackupDir

        $DestBackupDirOla = "$($TestConfig.Temp)\GetBackupsOla"
        if (-Not(Test-Path $DestBackupDirOla)) {
            $null = New-Item -Type Container -Path $DestBackupDirOla
            $null = New-Item -Type Container -Path $DestBackupDirOla\FULL
            $null = New-Item -Type Container -Path $DestBackupDirOla\DIFF
            $null = New-Item -Type Container -Path $DestBackupDirOla\LOG
        } else {
            Remove-Item $DestBackupDirOla\FULL\*
            Remove-Item $DestBackupDirOla\DIFF\*
            Remove-Item $DestBackupDirOla\LOG\*
        }

        $dbname3 = "dbatoolsci_BackuphistoryOla_$random"
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname3 | Remove-DbaDatabase
        $splatRestore3 = @{
            SqlInstance           = $TestConfig.InstanceSingle
            Path                  = "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak"
            DatabaseName          = $dbname3
            DestinationFilePrefix = $dbname3
        }
        $null = Restore-DbaDatabase @splatRestore3
        $db3 = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname3
        $db3 | Backup-DbaDatabase -Type Full -BackupDirectory "$DestBackupDirOla\FULL"
        $db3 | Backup-DbaDatabase -Type Differential -BackupDirectory "$DestBackupDirOla\Diff"
        $db3 | Backup-DbaDatabase -Type Log -BackupDirectory "$DestBackupDirOla\LOG"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname, $dbname2, $dbname3 | Remove-DbaDatabase
        Remove-Item -Path $DestBackupDir, $DestBackupDirOla -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Get history for all database" {
        BeforeAll {
            $splatAllBackups = @{
                SqlInstance = $TestConfig.InstanceSingle
                Path        = $DestBackupDir
            }
            $results = Get-DbaBackupInformation @splatAllBackups
        }

        It "Should be 6 backups returned" {
            $results.Count | Should -BeExactly 6
        }

        It "Should return 2 full backups" {
            ($results | Where-Object Type -eq "Full").Count | Should -BeExactly 2
        }

        It "Should return 2 log backups" {
            ($results | Where-Object Type -eq "Log").Count | Should -BeExactly 2
        }
    }

    Context "Get history for one database" {
        BeforeAll {
            $splatOneDatabase = @{
                SqlInstance  = $TestConfig.InstanceSingle
                Path         = $DestBackupDir
                DatabaseName = $dbname2
            }
            $results = Get-DbaBackupInformation @splatOneDatabase
        }

        It "Should be 3 backups returned" {
            $results.Count | Should -BeExactly 3
        }

        It "Should Be 1 full backup" {
            ($results | Where-Object Type -eq "Full").Count | Should -BeExactly 1
        }

        It "Should be 1 log backups" {
            ($results | Where-Object Type -eq "Log").Count | Should -BeExactly 1
        }

        It "Should only be backups of $dbname2" {
            ($results | Where-Object Database -ne $dbname2).Count | Should -BeExactly 0
        }
    }

    Context "Check the export/import of backup history" {
        BeforeAll {
            # This one used to cause all sorts of red
            $splatExport = @{
                SqlInstance  = $TestConfig.InstanceSingle
                Path         = $DestBackupDir
                DatabaseName = $dbname2
                ExportPath   = "$DestBackupDir\history.xml"
            }
            $results = Get-DbaBackupInformation @splatExport

            # the command below returns just a warning
            # Get-DbaBackupInformation -Import -Path "$DestBackupDir\history.xml" | Restore-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -DestinationFilePrefix hist -RestoredDatabaseNamePrefix hist -TrustDbBackupHistory
        }

        It "Should restore cleanly" {
            ($results | Where-Object RestoreComplete -eq $false).Count | Should -BeExactly 0
        }
    }

    Context "Test Maintenance solution options" {
        BeforeAll {
            $splatMaintenance = @{
                SqlInstance         = $TestConfig.InstanceSingle
                Path                = $DestBackupDirOla
                MaintenanceSolution = $true
            }
            $results = Get-DbaBackupInformation @splatMaintenance
        }

        It "Should be 3 backups returned" {
            $results.Count | Should -BeExactly 3
        }

        It "Should Be 1 full backup" {
            ($results | Where-Object Type -eq "Full").Count | Should -BeExactly 1
        }

        It "Should be 1 log backups" {
            ($results | Where-Object Type -eq "Log").Count | Should -BeExactly 1
        }

        It "Should only be backups of $dbname3" {
            ($results | Where-Object Database -ne $dbname3).Count | Should -BeExactly 0
        }

        It "Should be 2 backups returned when ignoring log backups" {
            $splatMaintenanceNoLog = @{
                SqlInstance         = $TestConfig.InstanceSingle
                Path                = $DestBackupDirOla
                MaintenanceSolution = $true
                IgnoreLogBackup     = $true
            }
            $ResultsSanLog = Get-DbaBackupInformation @splatMaintenanceNoLog
            $ResultsSanLog.Count | Should -BeExactly 2
        }

        It "Should Be 1 full backup when ignoring log backups" {
            $splatMaintenanceNoLog = @{
                SqlInstance         = $TestConfig.InstanceSingle
                Path                = $DestBackupDirOla
                MaintenanceSolution = $true
                IgnoreLogBackup     = $true
            }
            $ResultsSanLog = Get-DbaBackupInformation @splatMaintenanceNoLog
            ($ResultsSanLog | Where-Object Type -eq "Full").Count | Should -BeExactly 1
        }

        It "Should be 0 log backups when ignoring log backups" {
            $splatMaintenanceNoLog = @{
                SqlInstance         = $TestConfig.InstanceSingle
                Path                = $DestBackupDirOla
                MaintenanceSolution = $true
                IgnoreLogBackup     = $true
            }
            $resultsSanLog = Get-DbaBackupInformation @splatMaintenanceNoLog
            ($resultsSanLog | Where-Object Type -eq "Log").Count | Should -BeExactly 0
        }

        It "Should Warn if IgnoreLogBackup without MaintenanceSolution" {
            $splatNoMaintenanceWithIgnore = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Path            = $DestBackupDirOla
                IgnoreLogBackup = $true
                WarningVariable = "warnvar"
                WarningAction   = "SilentlyContinue"
            }
            $ResultsSanLog = Get-DbaBackupInformation @splatNoMaintenanceWithIgnore 3> $null
            $warnVar | Should -Match "IgnoreLogBackup can only by used with MaintenanceSolution. Will not be used"
        }

        It "Should ignore IgnoreLogBackup and return 3 backups" {
            $splatNoMaintenanceWithIgnore = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Path            = $DestBackupDirOla
                IgnoreLogBackup = $true
                WarningVariable = "warnvar"
                WarningAction   = "SilentlyContinue"
            }
            $resultsSanLog = Get-DbaBackupInformation @splatNoMaintenanceWithIgnore 3> $null
            $resultsSanLog.Count | Should -BeExactly 3
        }
    }

    Context "When a file is not a backup" {
        BeforeAll {
            # A text file where the instance can read it, so the header read fails on the content, not on access.
            $notABackup = Join-Path -Path $TestConfig.Temp -ChildPath "dbatoolsci_notabackup_$(Get-Random).txt"
            Set-Content -Path $notABackup -Value "dbatoolsci"
        }

        AfterAll {
            Remove-Item -Path $notABackup -Force -ErrorAction SilentlyContinue
        }

        It "Warns without eating an iteration of the caller's loop" {
            # The header-read catch used to run Stop-Function -Continue in the process block, where no loop
            # encloses it - the continue escaped the command and consumed an iteration of this very loop, so
            # the counter stayed at zero (#10638).
            $loopCount = 0
            foreach ($i in 1..3) {
                $null = Get-DbaBackupInformation -SqlInstance $TestConfig.InstanceSingle -Path $notABackup -WarningAction SilentlyContinue
                $loopCount++
            }
            $loopCount | Should -Be 3
            ($WarnVar -join " ") | Should -BeLike "*Failure on*"
        }

        It "Still reads the backup piped in after the file that is not one" {
            # A plain Stop-Function used to set the command-wide interrupt flag for the unreadable file, and
            # Test-FunctionInterrupt then dropped every path piped in after it.
            $validBackup = (Get-ChildItem -Path $DestBackupDir -Filter "$dbname*.bak" | Select-Object -First 1).FullName
            $results = $notABackup, $validBackup | Get-DbaBackupInformation -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue
            ($results | Measure-Object).Count | Should -Be 1
            $results.Database | Should -Be $dbname
            ($WarnVar -join " ") | Should -BeLike "*Failure on*"
        }

        It "Throws for the file that is not a backup under -EnableException" {
            { Get-DbaBackupInformation -SqlInstance $TestConfig.InstanceSingle -Path $notABackup -EnableException } | Should -Throw "*Failure on*"
        }
    }

    Context "When Path is an S3 folder" {
        It "Warns that S3 folders cannot be enumerated and returns nothing" {
            # An S3 URL skips xp_dirtree, and a folder then went to Read-DbaBackupHeader as if it were a file, which
            # rejected it with a message about files and folders instead of the one about S3 enumeration. On top of
            # that the escaping continue ended the CI test before its assertions, so nobody noticed.
            $splatS3Folder = @{
                SqlInstance   = $TestConfig.InstanceSingle
                Path          = "s3://dbatoolsci.invalid/bucket/folder/"
                WarningAction = "SilentlyContinue"
            }
            $results = Get-DbaBackupInformation @splatS3Folder
            $results | Should -BeNullOrEmpty
            ($WarnVar -join " ") | Should -BeLike "*S3 paths cannot be enumerated using T-SQL*"
        }
    }
}
