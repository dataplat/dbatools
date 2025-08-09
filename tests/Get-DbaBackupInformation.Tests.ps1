#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaBackupInformation",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "SqlInstance", 
                "SqlCredential",
                "DatabaseName",
                "SourceInstance",
                "NoXpDirTree",
                "NoXpDirRecurse",
                "DirectoryRecurse",
                "EnableException",
                "MaintenanceSolution",
                "IgnoreLogBackup",
                "IgnoreDiffBackup",
                "ExportPath",
                "AzureCredential",
                "Import",
                "Anonymise",
                "NoClobber",
                "PassThru"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $DestBackupDir = "C:\Temp\GetBackups"
        if (-Not(Test-Path $DestBackupDir)) {
            $null = New-Item -Type Container -Path $DestBackupDir
        } else {
            Remove-Item $DestBackupDir\*
        }
        
        $random = Get-Random
        $dbname = "dbatoolsci_Backuphistory_$random"
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname | Remove-DbaDatabase -Confirm:$false
        $splatRestore1 = @{
            SqlInstance            = $TestConfig.instance1
            Path                   = "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak"
            DatabaseName           = $dbname
            DestinationFilePrefix  = $dbname
        }
        $null = Restore-DbaDatabase @splatRestore1
        $db = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname
        $db | Backup-DbaDatabase -Type Full -BackupDirectory $DestBackupDir
        $db | Backup-DbaDatabase -Type Differential -BackupDirectory $DestBackupDir
        $db | Backup-DbaDatabase -Type Log -BackupDirectory $DestBackupDir

        $dbname2 = "dbatoolsci_Backuphistory2_$random"
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname2 | Remove-DbaDatabase -Confirm:$false
        $splatRestore2 = @{
            SqlInstance            = $TestConfig.instance1
            Path                   = "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak"
            DatabaseName           = $dbname2
            DestinationFilePrefix  = $dbname2
        }
        $null = Restore-DbaDatabase @splatRestore2
        $db2 = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname2
        $db2 | Backup-DbaDatabase -Type Full -BackupDirectory $DestBackupDir
        $db2 | Backup-DbaDatabase -Type Differential -BackupDirectory $DestBackupDir
        $db2 | Backup-DbaDatabase -Type Log -BackupDirectory $DestBackupDir

        $DestBackupDirOla = "C:\Temp\GetBackupsOla"
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
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname3 | Remove-DbaDatabase -Confirm:$false
        $splatRestore3 = @{
            SqlInstance            = $TestConfig.instance1
            Path                   = "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak"
            DatabaseName           = $dbname3
            DestinationFilePrefix  = $dbname3
        }
        $null = Restore-DbaDatabase @splatRestore3
        $db3 = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname3
        $db3 | Backup-DbaDatabase -Type Full -BackupDirectory "$DestBackupDirOla\FULL"
        $db3 | Backup-DbaDatabase -Type Differential -BackupDirectory "$DestBackupDirOla\Diff"
        $db3 | Backup-DbaDatabase -Type Log -BackupDirectory "$DestBackupDirOla\LOG"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup all created object.
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname, $dbname2, $dbname3 | Remove-DbaDatabase -Confirm:$false
        Remove-Item -Path $DestBackupDir, $DestBackupDirOla -Recurse -Confirm:$false -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Get history for all database" {
        BeforeAll {
            $allDbResults = Get-DbaBackupInformation -SqlInstance $TestConfig.instance1 -Path $DestBackupDir
        }

        It "Should be 6 backups returned" {
            $allDbResults.Status.Count | Should -BeExactly 6
        }

        It "Should return 2 full backups" {
            ($allDbResults | Where-Object Type -eq "Database").Status.Count | Should -BeExactly 2
        }

        It "Should return 2 log backups" {
            ($allDbResults | Where-Object Type -eq "Transaction Log").Status.Count | Should -BeExactly 2
        }
    }

    Context "Get history for one database" {
        BeforeAll {
            $singleDbResults = Get-DbaBackupInformation -SqlInstance $TestConfig.instance1 -Path $DestBackupDir -DatabaseName $dbname2
        }

        It "Should be 3 backups returned" {
            $singleDbResults.Status.Count | Should -BeExactly 3
        }

        It "Should Be 1 full backup" {
            ($singleDbResults | Where-Object Type -eq "Database").Status.Count | Should -BeExactly 1
        }

        It "Should be 1 log backups" {
            ($singleDbResults | Where-Object Type -eq "Transaction Log").Status.Count | Should -BeExactly 1
        }

        It "Should only be backups of $dbname2" {
            ($singleDbResults | Where-Object Database -ne $dbname2).Status.Count | Should -BeExactly 0
        }
    }

    Context "Check the export/import of backup history" {
        BeforeAll {
            # This one used to cause all sorts of red
            $exportResults = Get-DbaBackupInformation -SqlInstance $TestConfig.instance1 -Path $DestBackupDir -DatabaseName $dbname2 -ExportPath "$DestBackupDir\history.xml"

            # the command below returns just a warning
            # Get-DbaBackupInformation -Import -Path "$DestBackupDir\history.xml" | Restore-DbaDatabase -SqlInstance $TestConfig.instance1 -DestinationFilePrefix hist -RestoredDatabaseNamePrefix hist -TrustDbBackupHistory
        }

        It "Should restore cleanly" {
            ($exportResults | Where-Object RestoreComplete -eq $false).Status.Count | Should -BeExactly 0
        }
    }

    Context "Test Maintenance solution options" {
        BeforeAll {
            $olaResults = Get-DbaBackupInformation -SqlInstance $TestConfig.instance1 -Path $DestBackupDirOla -MaintenanceSolution
            $olaResultsSanLog = Get-DbaBackupInformation -SqlInstance $TestConfig.instance1 -Path $DestBackupDirOla -MaintenanceSolution -IgnoreLogBackup
            $olaResultsWarnTest = Get-DbaBackupInformation -SqlInstance $TestConfig.instance1 -Path $DestBackupDirOla -IgnoreLogBackup -WarningVariable warnvar -WarningAction SilentlyContinue 3> $null
        }

        It "Should be 3 backups returned" {
            $olaResults.Status.Count | Should -BeExactly 3
        }

        It "Should Be 1 full backup" {
            ($olaResults | Where-Object Type -eq "Database").Status.Count | Should -BeExactly 1
        }

        It "Should be 1 log backups" {
            ($olaResults | Where-Object Type -eq "Transaction Log").Status.Count | Should -BeExactly 1
        }

        It "Should only be backups of $dbname3" {
            ($olaResults | Where-Object Database -ne $dbname3).Status.Count | Should -BeExactly 0
        }

        It "Should be 2 backups returned" {
            $olaResultsSanLog.Status.Count | Should -BeExactly 2
        }

        It "Should Be 1 full backup" {
            ($olaResultsSanLog | Where-Object Type -eq "Database").Status.Count | Should -BeExactly 1
        }

        It "Should be 0 log backups" {
            ($olaResultsSanLog | Where-Object Type -eq "Transaction Log").Status.Count | Should -BeExactly 0
        }

        It "Should Warn if IgnoreLogBackup without MaintenanceSolution" {
            $warnVar | Should -Match "IgnoreLogBackup can only by used with MaintenanceSolution. Will not be used"
        }

        It "Should ignore IgnoreLogBackup and return 3 backups" {
            $olaResultsWarnTest.Status.Count | Should -BeExactly 3
        }
    }
}