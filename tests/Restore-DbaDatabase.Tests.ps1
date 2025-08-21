#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Restore-DbaDatabase",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Path",
                "DatabaseName",
                "DestinationDataDirectory",
                "DestinationLogDirectory",
                "DestinationFileStreamDirectory",
                "RestoreTime",
                "NoRecovery",
                "WithReplace",
                "XpDirTree",
                "OutputScriptOnly",
                "VerifyOnly",
                "MaintenanceSolutionBackup",
                "FileMapping",
                "IgnoreLogBackup",
                "IgnoreDiffBackup",
                "UseDestinationDefaultDirectories",
                "ReuseSourceFolderStructure",
                "DestinationFilePrefix",
                "RestoredDatabaseNamePrefix",
                "TrustDbBackupHistory",
                "MaxTransferSize",
                "BlockSize",
                "BufferCount",
                "DirectoryRecurse",
                "EnableException",
                "StandbyDirectory",
                "Continue",
                "AzureCredential",
                "ReplaceDbNameInFile",
                "DestinationFileSuffix",
                "Recover",
                "KeepCDC",
                "GetBackupInformation",
                "StopAfterGetBackupInformation",
                "SelectBackupInformation",
                "StopAfterSelectBackupInformation",
                "FormatBackupInformation",
                "StopAfterFormatBackupInformation",
                "TestBackupInformation",
                "StopAfterTestBackupInformation",
                "PageRestore",
                "PageRestoreTailFolder",
                "StatementTimeout",
                "KeepReplication",
                "StopBefore",
                "StopMark",
                "StopAfterDate",
                "ExecuteAs",
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

        # Setup variable for multiple contexts
        $dataFolder = "c:\temp\datafiles"
        $logFolder = "C:\temp\logfiles"
        $null = New-Item -ItemType Directory $dataFolder -ErrorAction SilentlyContinue
        $null = New-Item -ItemType Directory $logFolder -ErrorAction SilentlyContinue

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up any remaining databases
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase

        # Remove temporary directories
        Remove-Item -Path "C:\temp\*" -Recurse -Force -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Properly restores a database on the local drive using Path" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
        }

        It "Should Return the proper backup file location" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak"
            $results.BackupFile | Should -Be "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak"
        }

        It "Should return successful restore" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak"
            $results.RestoreComplete | Should -Be $true
        }
    }

    Context "Ensuring warning is thrown if database already exists" {
        It "Should warn" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -WarningVariable warning -WarningAction SilentlyContinue
            $warning | Where-Object Name -like "*Test-DbaBackupInformation*Database*" | Should -Match "exists, so WithReplace must be specified"
        }

        It "Should not return object" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -WarningVariable warning -WarningAction SilentlyContinue
            $results | Should -Be $null
        }
    }

    Context "Database is properly removed again after withreplace test" {
        BeforeAll {
            $null = Get-DbaProcess $TestConfig.instance2 -Database singlerestore | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
        }

        It "Should say the status was dropped" {
            $results = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database singlerestore
            $null = Get-DbaProcess $TestConfig.instance2 -Database singlerestore | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
            $results = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database singlerestore
            $results.Status -eq "Dropped" -or $results.Status -eq $null
        }
    }

    Context "Properly restores a database on the local drive using piped Get-ChildItem results" {
        BeforeAll {
            $null = Get-DbaProcess $TestConfig.instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
        }

        It "Should Return the proper backup file location" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2
            $results.BackupFile | Should -Be "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak"
        }

        It "Should return successful restore" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2
            $results.RestoreComplete | Should -Be $true
        }
    }

    Context "Test VerifyOnly works with db in existence" {
        It "Should have verified Successfully" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -VerifyOnly
            $results[0] | Should -Be "Verify successful"
        }
    }

    Context "Database is properly removed again after gci tests" {
        BeforeAll {
            $null = Get-DbaProcess $TestConfig.instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
        }

        It "Should say the status was dropped" {
            $results = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database singlerestore
            $results.Status | Should -Be "Dropped"
        }
    }

    Context "Allows continues with Differential Backups" {
        It "Should restore the root full cleanly" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\DoubleDiffing\difftest-full.bak" -NoRecovery
            $results.RestoreComplete | Should -Be $true
        }

        It "Should restore the first diff cleanly" {
            $results1 = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\DoubleDiffing\difftest-diff1.bak" -NoRecovery -Continue
            $results1.RestoreComplete | Should -Be $true
        }

        It "Should restore the second diff cleanly" {
            $results2 = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\DoubleDiffing\difftest-diff2.bak" -Continue
            $results2.RestoreComplete | Should -Be $true
        }
    }

    Context "Database is restored with correct renamings" {
        BeforeAll {
            $null = Get-DbaProcess $TestConfig.instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
            Clear-DbaConnectionPool
            Start-Sleep -Seconds 2
        }

        It "Should return successful restore with prefix" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DestinationFilePrefix prefix
            $results.RestoreComplete | Should -Be $true
        }

        It "Should return the 2 prefixed files" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DestinationFilePrefix prefix
            (($results.RestoredFile -split ",").substring(0, 6) -eq "prefix").count | Should -Be 2
        }

        It "Should return successful restore with suffix" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DestinationFileSuffix suffix -WithReplace
            ($results.RestoreComplete -eq $true) | Should -Be $true
        }

        It "Should return the 2 suffixed files" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DestinationFileSuffix suffix -WithReplace
            (($results.RestoredFile -split ",") -match "suffix\.").count | Should -Be 2
        }

        It "Should return successful restore with suffix and prefix" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DestinationFileSuffix suffix -DestinationFilePrefix prefix -WithReplace
            ($results.RestoreComplete -eq $true) | Should -Be $true
        }

        It "Should return the 2 prefixed and suffixed files" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DestinationFileSuffix suffix -DestinationFilePrefix prefix -WithReplace
            (($results.RestoredFile -split ",") -match "^prefix.*suffix\.").count | Should -Be 2
        }
    }

    Context "Database is properly removed again post prefix and suffix tests" {
        BeforeAll {
            $null = Get-DbaProcess $TestConfig.instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
        }

        It "Should say the status was dropped" {
            $results = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database singlerestore
            $results.Status | Should -Be "Dropped"
        }
    }

    Context "Replace databasename in Restored File" {
        It "Should return the 2 files swapping singlerestore for pestering (output)" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName Pestering -replaceDbNameInFile -WithReplace
            (($results.RestoredFile -split ",") -like "*pestering*").count | Should -Be 2
        }

        It "Should exist on Filesystem" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName Pestering -replaceDbNameInFile -WithReplace
            ForEach ($file in ($results.RestoredFileFull -split ",")) {
                $file | Should -Exist
            }
        }
    }

    Context "Replace databasename in Restored File, but don't change backup history #5036" {
        It "Should not change the PhysicalName in the FileList of the backup history" {
            $bh = Get-DbaBackupInformation -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -SqlInstance $TestConfig.instance2
            $firstPhysicalName = $bh.FileList.PhysicalName[0]

            $null = $bh | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName Pestering -replaceDbNameInFile -WithReplace -OutputScriptOnly
            $bh.FileList.PhysicalName[0] | Should -Be $firstPhysicalName
        }
    }

    Context "Database is properly removed (name change)" {
        It "Should say the status was dropped" {
            $results = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database pestering
            $results.Status | Should -Be "Dropped"
        }
    }

    Context "Test restoring as other login #6992" {
        BeforeAll {
            $restoreAsUser = "RestoreAs"
        }

        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database Pestering
            $null = Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $restoreAsUser
        }

        It "Should Not be owned by SA this time" {
            #Check first that the db isn't owned by SA
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName Pestering -replaceDbNameInFile -WithReplace
            $db = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database Pestering
            $db.owner | Should -Not -Be "sa"

            Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database Pestering
        }

        It "Should throw a warning if login doesn't exist" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName Pestering -replaceDbNameInFile -WithReplace -ExecuteAs badlogin -WarningVariable warnvar
            $db = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database Pestering
            $warnvar | Should -BeLike "*You specified a Login to execute the restore, but the login 'badlogin' does not exist"
        }

        It "Should be owned by SA this time" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName Pestering -replaceDbNameInFile -WithReplace -ExecuteAs sa
            $db = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database Pestering
            $db.owner | Should -Be "sa"

            Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database Pestering
        }

        It "Should be owned by $restoreAsUser this time" {
            New-DbaLogin -SqlInstance $TestConfig.instance2 -Login $restoreAsUser -SecurePassword (ConvertTo-SecureString "P@ssw0rdl!ng" -AsPlainText -Force) -force
            Add-DbaServerRoleMember -SqlInstance $TestConfig.instance2 -ServerRole sysadmin -Login $restoreAsUser
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName Pestering -replaceDbNameInFile -WithReplace -ExecuteAs $restoreAsUser
            $db2 = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database Pestering
            $db2.owner | Should -Be "$restoreAsUser"
        }

        It "Should prefix the script with the Execute As statement" {
            $results6 = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName Pestering -replaceDbNameInFile -WithReplace -ExecuteAs $restoreAsUser -OutputScriptOnly
            $results6 | Should -BeLike "EXECUTE AS LOGIN='$restoreAsUser'*"
        }
    }

    Context "Folder restore options" {
        BeforeAll {
            $null = Get-DbaProcess $TestConfig.instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
            Clear-DbaConnectionPool
            Start-Sleep -Seconds 2
        }

        It "Should return successful restore with DestinationDataDirectory" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DestinationDataDirectory $dataFolder
            $results.RestoreComplete | Should -Be $true
        }

        It "Should have moved all files to $dataFolder" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DestinationDataDirectory $dataFolder
            (($results.RestoredFileFull -split ",") -like "$dataFolder*").count | Should -Be 2
        }

        It "Should exist on Filesystem" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DestinationDataDirectory $dataFolder
            ForEach ($file in ($results.RestoredFileFull -split ",")) {
                $file | Should -Exist
            }
        }

        It "Should have moved data file to $dataFolder" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DestinationDataDirectory $dataFolder -DestinationLogDirectory $logFolder -WithReplace
            (($results.RestoredFileFull -split ",") -like "$dataFolder*").count | Should -Be 1
        }

        It "Should have moved Log file to $logFolder" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DestinationDataDirectory $dataFolder -DestinationLogDirectory $logFolder -WithReplace
            (($results.RestoredFileFull -split ",") -like "$logFolder*").count | Should -Be 1
        }

        It "Should exist on Filesystem after moving to separate directories" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DestinationDataDirectory $dataFolder -DestinationLogDirectory $logFolder -WithReplace
            ForEach ($file in ($results.RestoredFileFull -split ",")) {
                $file | Should -Exist
            }
        }
    }

    Context "Database is properly removed again after folder options tests" {
        It "Should say the status was dropped" {
            $results = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database singlerestore
            $results.Status | Should -Be "Dropped"
        }
    }

    Context "Putting all restore file modification options together" {
        BeforeAll {
            Clear-DbaConnectionPool
            Start-Sleep -Seconds 2
        }

        It "Should return successful restore with all file mod options" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DestinationDataDirectory $dataFolder -DestinationLogDirectory $logFolder -DestinationFileSuffix Suffix -DestinationFilePrefix prefix
            $results.RestoreComplete | Should -Be $true
        }

        It "Should have moved data file to $dataFolder (output)" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DestinationDataDirectory $dataFolder -DestinationLogDirectory $logFolder -DestinationFileSuffix Suffix -DestinationFilePrefix prefix
            (($results.RestoredFileFull -split ",") -like "$dataFolder*").count | Should -Be 1
        }

        It "Should have moved Log file to $logFolder (output)" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DestinationDataDirectory $dataFolder -DestinationLogDirectory $logFolder -DestinationFileSuffix Suffix -DestinationFilePrefix prefix
            (($results.RestoredFileFull -split ",") -like "$logFolder*").count | Should -Be 1
        }

        It "Should return the 2 prefixed and suffixed files" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DestinationDataDirectory $dataFolder -DestinationLogDirectory $logFolder -DestinationFileSuffix Suffix -DestinationFilePrefix prefix
            (($results.RestoredFile -split ",") -match "^prefix.*suffix\.").count | Should -Be 2
        }

        It "Should exist on Filesystem with all modifications" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DestinationDataDirectory $dataFolder -DestinationLogDirectory $logFolder -DestinationFileSuffix Suffix -DestinationFilePrefix prefix
            ForEach ($file in ($results.RestoredFileFull -split ",")) {
                $file | Should -Exist
            }
        }
    }

    Context "Database is properly removed again after all file mods test" {
        BeforeAll {
            Clear-DbaConnectionPool
            Start-Sleep -Seconds 1
        }

        It "Should say the status was dropped" {
            $results = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database singlerestore
            $results.Status | Should -Be "Dropped"
        }
    }

    Context "Properly restores an instance using ola-style backups via pipe" {
        BeforeAll {
            $null = Get-DbaProcess $TestConfig.instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
            Clear-DbaConnectionPool
            Start-Sleep -Seconds 5
            Clear-DbaConnectionPool
        }

        It "Restored files count should be the right number" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\sql2008-backups" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2
            $results.DatabaseName.Count | Should -Be 33
        }

        It "Should return successful restore" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\sql2008-backups" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2
            ($results.RestoreComplete -contains $false) | Should -Be $false
            ($results.count -gt 0) | Should -Be $true
        }
    }

    Context "Should proceed if backups from multiple dbs passed in and databasename specified" {
        It "Should return nothing" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\sql2008-backups" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName test -WarningVariable warnvar
            $null -eq $results | Should -Be $true
        }

        It "Should have warned with the correct error" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\sql2008-backups" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName test -WarningVariable warnvar
            $warnvar -like "*Multiple Databases' backups passed in, but only 1 name to restore them under. Stopping as cannot work out how to proceed*" | Should -Be $true
        }
    }

    Context "Database is properly removed again after ola pipe test" {
        BeforeAll {
            $null = Get-DbaProcess $TestConfig.instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
        }

        It "Should say the status was dropped or null" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
            $null = Get-DbaProcess $TestConfig.instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase

            foreach ($result in $results) {
                $result.Status -eq "Dropped" -or $result.Status -eq $null
            }
        }
    }

    Context "Properly restores an instance using ola-style backups via string" {
        It "Restored files count should be the right number" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups"
            $results.DatabaseName.Count | Should -Be 33
        }

        It "Should return successful restore" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups"
            ($results.RestoreComplete -contains $false) | Should -Be $false
            ($results.count -gt 0) | Should -Be $true
        }
    }

    Context "All user databases are removed post ola-style test" {
        BeforeAll {
            $null = Get-DbaProcess $TestConfig.instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
        }

        It "Should say the status was dropped" -Skip {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
            $results | ForEach-Object { $PSItem.Status | Should -Be "Dropped" }
        }
    }

    Context "RestoreTime setup checks" {
        BeforeAll {
            $null = Get-DbaProcess $TestConfig.instance2 -ExcludeSystemSpids | Stop-DbaProcess -WarningVariable warn -WarningAction SilentlyContinue
            Clear-DbaConnectionPool
            Start-Sleep -Seconds 2
        }

        It "Should restore cleanly" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016"
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
            ($results.RestoreComplete -contains $false) | Should -Be $false
            ($results.count -gt 0) | Should -Be $true
        }

        It "Should have restored 5 files" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016"
            $results.count | Should -Be 5
        }

        It "Should have restored from 2019-05-02 21:00:55" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016"
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
            $sqlResults.mindt | Should -Be (Get-Date "2019-05-02 21:00:55")
        }

        It "Should have restored to 2019-05-02 13:28:43" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016"
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
            $sqlResults.maxdt | Should -Be (Get-Date "2019-05-02 21:30:26")
        }
    }

    Context "All user databases are removed post RestoreTime check" {
        BeforeAll {
            Clear-DbaConnectionPool
            Start-Sleep -Seconds 1
        }

        It "Should say the status was dropped" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
            Foreach ($db in $results) { $db.Status | Should -Be "Dropped" }
        }
    }

    Context "RestoreTime point in time" {
        BeforeAll {
            Clear-DbaConnectionPool
            Start-Sleep -Seconds 1
        }

        It "Should have restored 4 files" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016" -RestoreTime (Get-Date "2019-05-02 21:12:27") -WarningVariable warnvar -ErrorVariable errvar
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
            $results.count | Should -Be 4
        }

        It "Should have restored from 2019-05-02 21:00:55" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016" -RestoreTime (Get-Date "2019-05-02 21:12:27") -WarningVariable warnvar -ErrorVariable errvar
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
            $sqlResults.mindt | Should -Be (Get-Date "2019-05-02 21:00:55")
        }

        It "Should have restored to 2019-05-02 21:12:26" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016" -RestoreTime (Get-Date "2019-05-02 21:12:27") -WarningVariable warnvar -ErrorVariable errvar
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
            $sqlResults.maxdt | Should -Be (Get-Date "2019-05-02 21:12:26")
        }
    }

    Context "All user databases are removed" {
        It "Should say the status was dropped post point in time test" -Skip {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
            Foreach ($db in $results) { $db.Status | Should -Be "Dropped" }
        }
    }

    Context "RestoreTime point in time with Simple Model" {
        BeforeAll {
            Clear-DbaConnectionPool
            Start-Sleep -Seconds 1
        }

        It "Should have restored 2 files" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\sql2008-backups\SimpleRecovery\" -RestoreTime (Get-Date "2018-04-06 10:37:44")
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from SimpleBackTest.dbo.steps"
            $results.count | Should -Be 2
        }

        It "Should have restored from 2018-04-06 10:30:32" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\sql2008-backups\SimpleRecovery\" -RestoreTime (Get-Date "2018-04-06 10:37:44")
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from SimpleBackTest.dbo.steps"
            $sqlResults.mindt | Should -Be (Get-Date "2018-04-06 10:30:32")
        }

        It "Should have restored to 2018-04-06 10:35:02" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\sql2008-backups\SimpleRecovery\" -RestoreTime (Get-Date "2018-04-06 10:37:44")
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from SimpleBackTest.dbo.steps"
            $sqlResults.maxdt | Should -Be (Get-Date "2018-04-06 10:35:02")
        }
    }

    Context "All user databases are removed" {
        It "Should say the status was dropped post point in time test" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
            Foreach ($db in $results) { $db.Status | Should -Be "Dropped" }
        }
    }

    Context "RestoreTime point in time and continue" {
        BeforeAll {
            Clear-DbaConnectionPool
            Start-Sleep -Seconds 1
            $shouldRun = (Connect-DbaInstance -SqlInstance $TestConfig.instance2).Version.ToString() -like "13.*"
        }

        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
        }

        It "The test can run" {
            if (-not ($shouldRun)) {
                Set-TestInconclusive -Message "a 2016 is strictly needed"
                return
            }
        }

        It "Should not warn" {
            if (-not ($shouldRun)) {
                Set-TestInconclusive -Message "a 2016 is strictly needed"
                return
            }
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016" -RestoreTime (Get-Date "2019-05-02 21:12:27") -StandbyDirectory c:\temp -WarningVariable warnvar -ErrorVariable errvar -ErrorAction SilentlyContinue
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
            $warnvar
            $null -eq (Get-Variable | Where-Object Name -eq "warnvar") -or "" -eq $warnvar | Should -Be $true
        }

        It "Should have restored 4 files" {
            if (-not ($shouldRun)) {
                Set-TestInconclusive -Message "a 2016 is strictly needed"
                return
            }
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016" -RestoreTime (Get-Date "2019-05-02 21:12:27") -StandbyDirectory c:\temp -WarningVariable warnvar -ErrorVariable errvar -ErrorAction SilentlyContinue
            $results.count | Should -Be 4
        }

        It "Should have restored from 05/02/2019 21:00:55" {
            if (-not ($shouldRun)) {
                Set-TestInconclusive -Message "a 2016 is strictly needed"
                return
            }
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016" -RestoreTime (Get-Date "2019-05-02 21:12:27") -StandbyDirectory c:\temp -WarningVariable warnvar -ErrorVariable errvar -ErrorAction SilentlyContinue
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
            $sqlResults.mindt | Should -Be (Get-Date "02 May 2019 21:00:55")
        }

        # Note, actual time is lower than target time due to how the db was built.
        It "Should have restored to 05/02/2019 21:12:26" {
            if (-not ($shouldRun)) {
                Set-TestInconclusive -Message "a 2016 is strictly needed"
                return
            }
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016" -RestoreTime (Get-Date "2019-05-02 21:12:27") -StandbyDirectory c:\temp -WarningVariable warnvar -ErrorVariable errvar -ErrorAction SilentlyContinue
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
            $sqlResults.maxdt | Should -Be (Get-Date "02 May 2019 21:12:26")
        }

        It "Should have restored 4 files on continue" {
            if (-not ($shouldRun)) {
                Set-TestInconclusive -Message "a 2016 is strictly needed"
                return
            }
            $results2 = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016" -Continue
            $sqlResults2 = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
            $results2.count | Should -Be 4
        }

        It "Should have restored from 02 May 2019 21:00:55" {
            if (-not ($shouldRun)) {
                Set-TestInconclusive -Message "a 2016 is strictly needed"
                return
            }
            $results2 = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016" -Continue
            $sqlResults2 = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
            $sqlResults2.mindt | Should -Be (Get-Date "02 May 2019 21:00:55")
        }

        It "Should have restored to 02 May 2019 21:30:26" {
            if (-not ($shouldRun)) {
                Set-TestInconclusive -Message "a 2016 is strictly needed"
                return
            }
            $results2 = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016" -Continue
            $sqlResults2 = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
            $sqlResults2.maxdt | Should -Be (Get-Date "02 May 2019 21:30:26")
        }
    }

    Context "RestoreTime point in time and continue with rename" {
        BeforeAll {
            $shouldRun = (Connect-DbaInstance -SqlInstance $TestConfig.instance2).Version.ToString() -like "13.*"
        }

        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
        }

        It "The test can run" {
            if (-not ($shouldRun)) {
                Set-TestInconclusive -Message "a 2016 is strictly needed"
                return
            }
        }

        It "Should have restored 4 files" {
            if (-not ($shouldRun)) {
                Set-TestInconclusive -Message "a 2016 is strictly needed"
                return
            }
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Databasename contest -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016" -RestoreTime (Get-Date "2019-05-02 21:23:58") -StandbyDirectory c:\temp
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from contest.dbo.steps"
            $results.count | Should -Be 4
        }

        It "Should have restored from 05/02/2019 21:00:55" {
            if (-not ($shouldRun)) {
                Set-TestInconclusive -Message "a 2016 is strictly needed"
                return
            }
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Databasename contest -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016" -RestoreTime (Get-Date "2019-05-02 21:23:58") -StandbyDirectory c:\temp
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from contest.dbo.steps"
            $sqlResults.mindt | Should -Be (Get-Date "02 May 2019 21:00:55")
        }

        It "Should have restored to 05/02/2019 21:23:56" {
            if (-not ($shouldRun)) {
                Set-TestInconclusive -Message "a 2016 is strictly needed"
                return
            }
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Databasename contest -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016" -RestoreTime (Get-Date "2019-05-02 21:23:58") -StandbyDirectory c:\temp
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from contest.dbo.steps"
            $sqlResults.maxdt | Should -Be (Get-Date "02 May 2019 21:23:56")
        }

        It "Should have restored 2 files on continue" {
            if (-not ($shouldRun)) {
                Set-TestInconclusive -Message "a 2016 is strictly needed"
                return
            }
            $results2 = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Databasename contest -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016" -Continue
            $sqlResults2 = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from contest.dbo.steps"
            $results2.count | Should -Be 2
        }

        It "Should have restored from 02 May 2019 21:00:55" {
            if (-not ($shouldRun)) {
                Set-TestInconclusive -Message "a 2016 is strictly needed"
                return
            }
            $results2 = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Databasename contest -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016" -Continue
            $sqlResults2 = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from contest.dbo.steps"
            $sqlResults2.mindt | Should -Be (Get-Date "02 May 2019 21:00:55")
        }

        It "Should have restored to 02 May 2019 21:30:26" {
            if (-not ($shouldRun)) {
                Set-TestInconclusive -Message "a 2016 is strictly needed"
                return
            }
            $results2 = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Databasename contest -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016" -Continue
            $sqlResults2 = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from contest.dbo.steps"
            $sqlResults2.maxdt | Should -Be (Get-Date "02 May 2019 21:30:26")
        }
    }

    Context "Continue Restore with Differentials" {
        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
        }

        It "Should Have restored the database cleanly" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\ft1\FULL\" -NoRecovery
            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true
        }

        It "Should have left the db in a norecovery state" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\ft1\FULL\" -NoRecovery
            (Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database ft1).Status | Should -Be "Restoring"
        }

        It "Should Have restored the database cleanly on continue" {
            $results2 = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\ft1\" -Continue
            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true
        }

        It "Should have recovered the database" {
            $results2 = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\ft1\" -Continue
            (Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database ft1).Status | Should -Be "Normal"
        }
    }

    Context "Continue Restore with Differentials and rename " {
        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
        }

        It "Should Have restored the database cleanly" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName contest -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\ft1\FULL\" -NoRecovery
            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true
        }

        It "Should have left the db in a norecovery state" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName contest -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\ft1\FULL\" -NoRecovery
            (Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database contest).Status | Should -Be "Restoring"
        }

        It "Should Have restored the database cleanly on continue" {
            $results2 = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName contest -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\ft1\" -Continue
            ($results2.RestoreComplete -contains $false) | Should -Be $false
            (($results2 | Measure-Object).count -gt 0) | Should -Be $true
        }

        It "Should have recovered the database" {
            $results2 = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName contest -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\ft1\" -Continue
            (Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database contest).Status | Should -Be "Normal"
        }
    }

    Context "Continue Restore with multiple databases" {
        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
        }

        It "Should Have restored the database cleanly" {
            $files = @()
            $files += Get-ChildItem "$($TestConfig.appveyorlabrepo)\sql2008-backups\db1\FULL\"
            $files += Get-ChildItem "$($TestConfig.appveyorlabrepo)\sql2008-backups\dbareports\FULL"
            $results = $files | Restore-DbaDatabase -SqlInstance $TestConfig.instance2  -NoRecovery
            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true
        }

        It "Should have left the db in a norecovery state" {
            $files = @()
            $files += Get-ChildItem "$($TestConfig.appveyorlabrepo)\sql2008-backups\db1\FULL\"
            $files += Get-ChildItem "$($TestConfig.appveyorlabrepo)\sql2008-backups\dbareports\FULL"
            $results = $files | Restore-DbaDatabase -SqlInstance $TestConfig.instance2  -NoRecovery
            (Get-DbaDatabase -SqlInstance $TestConfig.instance2 | Where-Object Status -eq "Recovering").count | Should -Be 0
        }

        It "Should Have restored the database cleanly on continue" {
            $files = @()
            $files += Get-ChildItem "$($TestConfig.appveyorlabrepo)\sql2008-backups\db1\" -Recurse
            $files += Get-ChildItem "$($TestConfig.appveyorlabrepo)\sql2008-backups\dbareports\" -Recurse
            $results2 = $files | Where-Object PsIsContainer -eq $false | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Continue
            ($results2.RestoreComplete -contains $false) | Should -Be $false
            (($results2 | Measure-Object).count -gt 0) | Should -Be $true
        }

        It "Should have recovered the database" {
            $files = @()
            $files += Get-ChildItem "$($TestConfig.appveyorlabrepo)\sql2008-backups\db1\" -Recurse
            $files += Get-ChildItem "$($TestConfig.appveyorlabrepo)\sql2008-backups\dbareports\" -Recurse
            $results2 = $files | Where-Object PsIsContainer -eq $false | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Continue
            (Get-DbaDatabase -SqlInstance $TestConfig.instance2 | Where-Object Status -eq "Recovering").count | Should -Be 0
        }
    }

    Context "Backup DB For next test" {
        It "Should return successful backup" {
            $null = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016\restoretimeclean.bak"
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance2 -Database RestoreTimeClean -BackupDirectory C:\temp
            $results.BackupComplete | Should -Be $true
        }
    }

    Context "All user databases are removed post continue test" {
        It "Should say the status was dropped" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
            Foreach ($db in $results) { $db.Status | Should -Be "Dropped" }
        }
    }

    Context "Check Get-DbaDbBackupHistory pipes into Restore-DbaDatabase" {
        BeforeAll {
            Clear-DbaConnectionPool
            Start-Sleep -Seconds 1
            $null = Get-DbaProcess $TestConfig.instance2 | Where-Object Program -match "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue
        }

        It "Should have restored everything successfully" {
            $history = Get-DbaDbBackupHistory -SqlInstance $TestConfig.instance2 -Database RestoreTimeClean -Last
            $results = $history | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -WithReplace -TrustDbBackupHistory
            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true
        }
    }

    Context "All user databases are removed post history test" {
        BeforeAll {
            Clear-DbaConnectionPool
            Start-Sleep -Seconds 1
        }

        It "Should say the status was dropped" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
            Foreach ($db in $results) { $db.Status | Should -Be "Dropped" }
        }
    }

    Context "Restores a db with log and file files missing extensions" {
        It "Should Restore successfully" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\sql2008-backups\Noextension.bak" -ErrorVariable Errvar -WarningVariable WarnVar
            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true
        }
    }

    Context "All user databases are removed post history test" {
        BeforeAll {
            Clear-DbaConnectionPool
            Start-Sleep -Seconds 1
        }

        It "Should say the status was dropped" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
            Foreach ($db in $results) { $db.Status | Should -Be "Dropped" }
        }
    }

    Context "Setup for Recovery Tests" {
        BeforeAll {
            $databaseName = "rectest"
        }

        It "Should have restored everything successfully" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -NoRecovery -DatabaseName $databaseName -DestinationFilePrefix $databaseName -WithReplace
            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true
        }

        It "Should return 1 database" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -NoRecovery -DatabaseName $databaseName -DestinationFilePrefix $databaseName -WithReplace
            $check = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName
            $check.count | Should -Be 1
        }

        It "Should be a database in Restoring state" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -NoRecovery -DatabaseName $databaseName -DestinationFilePrefix $databaseName -WithReplace
            $check = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName
            $check.status | Should -Be "Restoring"
        }
    }

    Context "Test recovery via parameter" {
        BeforeAll {
            $databaseName = "rectest"
        }

        It "Should have restored everything successfully" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Recover -DatabaseName $databaseName
            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true
        }

        It "Should return 1 database" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Recover -DatabaseName $databaseName
            $check = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName
            $check.count | Should -Be 1
        }

        It "Should be a database in Restoring state" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Recover -DatabaseName $databaseName
            $check = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName
            "Normal" -in $check.status | Should -Be $true
        }
    }

    Context "Setup for Recovery Tests" {
        BeforeAll {
            $databaseName = "rectest"
        }

        It "Should have restored everything successfully" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -NoRecovery -DatabaseName $databaseName -DestinationFilePrefix $databaseName -WithReplace
            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true
        }

        It "Should return 1 database" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -NoRecovery -DatabaseName $databaseName -DestinationFilePrefix $databaseName -WithReplace
            $check = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName
            $check.count | Should -Be 1
        }

        It "Should be a database in Restoring state" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -NoRecovery -DatabaseName $databaseName -DestinationFilePrefix $databaseName -WithReplace
            $check = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName
            $check.status | Should -Be "Restoring"
        }
    }

    Context "Test recovery via pipeline" {
        BeforeAll {
            $databaseName = "rectest"
        }

        It "Should have restored everything successfully" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Recover
            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true
        }

        It "Should return 1 database" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Recover
            $check = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName
            $check.count | Should -Be 1
        }

        It "Should be a database in Restoring state" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Recover
            $check = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName
            "Normal" -in $check.status | Should -Be $true
        }
    }

    Context "Checking we cope with a port number (#244)" {
        BeforeAll {
            $databaseName = "rectest"
        }

        It "Should have restored everything successfully" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2_detailed -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName $databaseName -DestinationFilePrefix $databaseName -WithReplace
            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true
        }
    }

    Context "All user databases are removed post port test" {
        It "Should say the status was dropped" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
            Foreach ($db in $results) { $db.Status | Should -Be "Dropped" }
        }
    }

    Context "Checking OutputScriptOnly only outputs script" {
        BeforeAll {
            $databaseName = "rectestSO"
        }

        It "Should only output a script" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName $databaseName -OutputScriptOnly
            $db = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName
            $results -match "RESTORE DATABASE" | Should -Be $true
            ($null -eq $db) | Should -Be $true
        }
    }

    Context "Checking OutputScriptOnly only outputs script without changing state for existing dbs (#2940)" {
        BeforeAll {
            $databaseName = "dbatoolsci_rectestSO"
        }

        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName | Remove-DbaDatabase
        }

        It "Should only output a script" {
            Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName | Remove-DbaDatabase
            $server = Connect-DbaInstance $TestConfig.instance2
            $server.Query("CREATE DATABASE $databaseName")
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName $databaseName -OutputScriptOnly -WithReplace
            $db = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName
            $results -match "RESTORE DATABASE" | Should -Be $true
        }

        It "Doesn't change the status of the existing database" {
            Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName | Remove-DbaDatabase
            $server = Connect-DbaInstance $TestConfig.instance2
            $server.Query("CREATE DATABASE $databaseName")
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName $databaseName -OutputScriptOnly -WithReplace
            $db = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName
            $db.UserAccess | Should -Be "Multiple"
        }
    }

    Context "All user databases are removed post Output script test" {
        It "Should say the status was dropped" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
            Foreach ($db in $results) { $db.Status | Should -Be "Dropped" }
        }
    }

    Context "Checking Output vs input" {
        BeforeAll {
            $databaseName = "rectestSO"
        }

        It "Should return the destination instance" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName $databaseName -BufferCount 24 -MaxTransferSize 128kb -BlockSize 64kb
            $results.SqlInstance = $TestConfig.instance2
        }

        It "Should have a BlockSize of 65536" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName $databaseName -BufferCount 24 -MaxTransferSize 128kb -BlockSize 64kb
            $results.Script | Should -Match "BLOCKSIZE = 65536"
        }

        It "Should have a BufferCount of 24" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName $databaseName -BufferCount 24 -MaxTransferSize 128kb -BlockSize 64kb
            $results.Script | Should -Match "BUFFERCOUNT = 24"
        }

        It "Should have a MaxTransferSize of 131072" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName $databaseName -BufferCount 24 -MaxTransferSize 128kb -BlockSize 64kb
            $results.Script | Should -Match "MAXTRANSFERSIZE = 131072"
        }
    }

    Context "All user databases are removed post Output vs Input test" {
        It "Should say the status was dropped" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
            Foreach ($db in $results) { $db.Status | Should -Be "Dropped" }
        }
    }

    Context "Checking CDC parameter " {
        BeforeAll {
            $databaseName = "testCDC"
        }

        It "Should have KEEP_CDC in the SQL" {
            $output = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName $databaseName -OutputScriptOnly -KeepCDC -WithReplace
            ($output -like "*KEEP_CDC*") | Should -Be $true
        }

        It "Should not output, and warn if Norecovery and KeepCDC specified" {
            $output = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName $databaseName -OutputScriptOnly -KeepCDC -WithReplace -WarningVariable warnvar -NoRecovery -WarningAction SilentlyContinue
            ($warnvar -like "*KeepCDC cannot be specified with Norecovery or Standby as it needs recovery to work") | Should -Be $true
            $output | Should -Be $null
        }

        It "Should not output, and warn if StandbyDirectory and KeepCDC specified" {
            $output = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName $databaseName -OutputScriptOnly -KeepCDC -WithReplace -WarningVariable warnvar -StandbyDirectory c:\temp\ -WarningAction SilentlyContinue
            ($warnvar -like "*KeepCDC cannot be specified with Norecovery or Standby as it needs recovery to work") | Should -Be $true
            $output | Should -Be $null
        }
    }

    Context "Page level restores" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
            $null = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName PageRestore -DestinationFilePrefix PageRestore
            $sql = @"
alter database PageRestore set Recovery Full
Create table testpage(
    Filler char(8000)
)

insert into testpage values (REPLICATE('a','8000'))
insert into testpage values (REPLICATE('b','8000'))
insert into testpage values (REPLICATE('c','8000'))
insert into testpage values (REPLICATE('d','8000'))

Backup database PageRestore to disk='c:\temp\pagerestore.bak'
Create table #TmpIndex(
PageFiD int,
PagePid int,
IAMFID int,
IAMPid int,
ObjectID int,
IndexID int,
PartitionNumber bigint,
ParitionId bigint,
iam_chain_type varchar(50),
PageType int,
IndexLevel int,
NextPageFID int,
NextPagePID int,
prevPageFid int,
PrevPagePID int
)

insert #TmpIndex exec ('dbcc ind(PageRestore,testpage,-1)')
dbcc ind(PageRestore,testpage,-1)

declare @pageid int
select top 1 @pageid=PagePid from #TmpIndex where IAMFID is not null and IAmPID is not null

--select * from #TmpIndex
--pageid = 256
alter database pagerestore set single_user with rollback immediate

dbcc writepage(pagerestore,1,@pageid,0,1,0x41,1)
dbcc writepage(pagerestore,1,@pageid,1,1,0x41,1)
dbcc writepage(pagerestore,1,@pageid,2,1,0x41,1)

alter database pagerestore set multi_user

insert into testpage values (REPLICATE('e','8000'))

Backup log PageRestore to disk='c:\temp\PageRestore.trn'

insert into testpage values (REPLICATE('f','8000'))
use master
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query $sql -Database Pagerestore
        }

        It "Should have warned about corruption" {
            $sqlResults2 = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database Master -Query "select * from pagerestore.dbo.testpage where filler like 'a%'" -ErrorVariable errvar -ErrorAction SilentlyContinue
            ($errvar -match "SQL Server detected a logical consistency-based I/O error: incorrect checksum \(expected") | Should -Be $true
            ($null -eq $sqlResults2) | Should -Be $true
        }

        It "Should work after page restore" -Skip {
            $null = Get-DbaDbBackupHistory -SqlInstance $TestConfig.instance2 -Database pagerestore -last | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -PageRestore (Get-DbaSuspectPage -SqlInstance $TestConfig.instance2 -Database PageRestore) -TrustDbBackupHistory -DatabaseName PageRestore -PageRestoreTailFolder c:\temp -ErrorAction SilentlyContinue
            $sqlResults3 = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select * from pagerestore.dbo.testpage where filler like 'f%'" -ErrorVariable errvar3 -ErrorAction SilentlyContinue
            #($null -eq $errvar3) | Should Be $True
            ($null -eq $sqlResults3) | Should -Be $false
        }
    }

    Context "Testing Backup to Restore piping" {
        It "Should backup and restore cleanly" {
            Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
            $null = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName PipeTest -DestinationFilePrefix PipeTest
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance2 -Database Pipetest -BackupDirectory c:\temp -CopyOnly -WarningAction SilentlyContinue -WarningVariable bwarnvar -ErrorAction SilentlyContinue -ErrorVariable berrvar | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName restored -ReplaceDbNameInFile -WarningAction SilentlyContinue -WarningVariable rwarnvar -ErrorAction SilentlyContinue -ErrorVariable rerrvar
            $results.RestoreComplete | Should -Be $true
        }
    }

    Context "Check we restore striped database" {
        It "Should backup and restore cleanly" {
            Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\RestoreTimeStripe" -DatabaseName StripeTest -DestinationFilePrefix StripeTest
            ($results | Where-Object RestoreComplete -eq $true).count | Should -Be $results.count
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database StripeTest
        }
    }

    Context "Don't try to create/test folders with OutputScriptOnly (Issue 4046)" {
        It "Should not raise a warning" {
            $null = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016\RestoreTimeClean.bak" -DestinationDataDirectory g:\DoesNtExist -OutputScriptOnly -WarningVariable warnvar
            ("" -eq $warnvar) | Should -Be $true
        }
    }

    Context "Checking that WITH KEEP_REPLICATION gets properly added" {
        BeforeAll {
            $databaseName = "reptestSO"
        }

        It "Should output a script with keep replication clause" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName $databaseName -OutputScriptOnly -KeepReplication
            $results -match "RESTORE DATABASE.*WITH.*KEEP_REPLICATION" | Should -Be $true
        }
    }

    Context "Test restoring a Backup encrypted with Certificate" {
        BeforeAll {
            $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name EncRestTest
            $securePass = ConvertTo-SecureString "estBackupDir\master\script:instance1).split('\')[1])\Full\master-Full.bak" -AsPlainText -Force
            $null = New-DbaDbMasterKey -SqlInstance $TestConfig.instance2 -Database Master -SecurePassword $securePass
            $cert = New-DbaDbCertificate -SqlInstance $TestConfig.instance2 -Database Master -Name RestoreTestCert -Subject RestoreTestCert
        }

        AfterAll {
            $null = Remove-DbaDbCertificate -SqlInstance $TestConfig.instance2 -Database Master -Certificate RestoreTestCert
            $null = Remove-DbaDbMasterKey -SqlInstance $TestConfig.instance2 -Database Master
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database EncRestTest, certEncRestTest
        }

        It "Should encrypt the backup" {
            $encBackupResults = Backup-DbaDatabase -SqlInstance $TestConfig.instance2 -Database EncRestTest -EncryptionAlgorithm AES128 -EncryptionCertificate RestoreTestCert -FilePath "$($TestConfig.Temp)\EncRestTest.bak"
            $encBackupResults.EncryptorType | Should -Be "CERTIFICATE"
            $encBackupResults.KeyAlgorithm | Should -Be "aes_128"
        }

        It "Should have restored the backup" {
            $encBackupResults = Backup-DbaDatabase -SqlInstance $TestConfig.instance2 -Database EncRestTest -EncryptionAlgorithm AES128 -EncryptionCertificate RestoreTestCert -FilePath "$($TestConfig.Temp)\EncRestTest.bak"
            $results = $encBackupResults | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -TrustDbBackupHistory -RestoredDatabaseNamePrefix cert -DestinationFilePrefix cert
            $results.RestoreComplete | Should -Be $true
        }
    }

    Context "Test restoring with StopAt" {
        It "Should have stoped at mark" {
            $restoreOutput = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Name StopAt2 -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\StopAt" -StopMark dbatoolstest -WithReplace
            $null = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Name StopAt2 -Recover
            $sqlOut = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database StopAt2 -Query "select max(step) as ms from steps"
            $sqlOut.ms | Should -Be 9876
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database StopAt2
        }
    }

    Context "Test restoring with StopAtBefore" {
        It "Should have stoped at mark" {
            $restoreOutput = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Name StopAt2 -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\StopAt" -StopMark dbatoolstest -WithReplace -StopBefore
            $null = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Name StopAt2 -Recover
            $sqlOut = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database StopAt2 -Query "select max(step) as ms from steps"
            $sqlOut.ms | Should -Be 8764
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database StopAt2
        }
    }

    Context "Test restoring with StopAt and StopAfterDate" {
        It "Should have stoped at mark" {
            $restoreOutput = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Name StopAt2 -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\StopAt" -StopMark dbatoolstest -StopAfterDate (Get-Date "2020-05-12 13:33:35") -WithReplace
            $null = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Name StopAt2 -Recover
            $sqlOut = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database StopAt2 -Query "select max(step) as ms from steps"
            $sqlOut.ms | Should -Be 29876
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database StopAt2
        }
    }

    Context "Warn if OutputScriptOnly and VerifyOnly specified together #6987" {
        It "Should return a warning" {
            $restoreOutput = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Name StopAt2 -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\StopAt" -OutputScriptOnly -VerifyOnly -WarningVariable warnvar
            $warnvar | Should -BeLike "*The switches OutputScriptOnly and VerifyOnly cannot both be specified at the same time, stopping"
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database StopAt2
        }
    }

    Context "Restores From Azure using SAS" {
        BeforeAll {
            if (-not $env:azurepasswd) {
                Set-TestInconclusive -Message "Azure password not available"
                return
            }
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            if (Get-DbaCredential -SqlInstance $TestConfig.instance2 -Name "[$TestConfig.azureblob]" ) {
                $sql = "DROP CREDENTIAL [$TestConfig.azureblob]"
                $server.Query($sql)
            }
            $sql = "CREATE CREDENTIAL [$TestConfig.azureblob] WITH IDENTITY = N'SHARED ACCESS SIGNATURE', SECRET = N'$env:azurepasswd'"
            $server.Query($sql)
            $server.Query("CREATE DATABASE dbatoolsci_azure")
        }

        AfterAll {
            if (-not $env:azurepasswd) {
                return
            }
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $server.Query("DROP CREDENTIAL [$TestConfig.azureblob]")
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_azure" | Remove-DbaDatabase
        }

        It "Should restore cleanly" {
            if (-not $env:azurepasswd) {
                Set-TestInconclusive -Message "Azure password not available"
                return
            }
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -WithReplace -DatabaseName dbatoolsci_azure -Path $TestConfig.azureblob/dbatoolsci_azure.bak
            $results.BackupFile | Should -Be "$TestConfig.azureblob/dbatoolsci_azure.bak"
            $results.RestoreComplete | Should -Be $true
        }
    }

    Context "Restores Striped backup From Azure using SAS" {
        BeforeAll {
            if (-not $env:azurepasswd -or $env:appveyor) {
                Set-TestInconclusive -Message "Azure password not available or running on AppVeyor"
                return
            }
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            if (Get-DbaCredential -SqlInstance $TestConfig.instance2 -name "[$TestConfig.azureblob]" ) {
                $sql = "DROP CREDENTIAL [$TestConfig.azureblob]"
                $server.Query($sql)
            }
            $sql = "CREATE CREDENTIAL [$TestConfig.azureblob] WITH IDENTITY = N'SHARED ACCESS SIGNATURE', SECRET = N'$env:azurepasswd'"
            $server.Query($sql)
            $server.Query("CREATE DATABASE dbatoolsci_azure")
        }

        AfterAll {
            if (-not $env:azurepasswd -or $env:appveyor) {
                return
            }
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $server.Query("DROP CREDENTIAL [$TestConfig.azureblob]")
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_azure" | Remove-DbaDatabase
        }

        It "Should restore cleanly" {
            if (-not $env:azurepasswd -or $env:appveyor) {
                Set-TestInconclusive -Message "Azure password not available or running on AppVeyor"
                return
            }
            $results = @("$TestConfig.azureblob/az-1.bak", "$TestConfig.azureblob/az-2.bak", "$TestConfig.azureblob/az-3.bak") | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName azstripetest  -WithReplace -ReplaceDbNameInFile
            $results.RestoreComplete | Should -Be $true
        }
    }

    Context "Restores from Azure using Access Key" {
        BeforeAll {
            if (-not $env:azurelegacypasswd) {
                Set-TestInconclusive -Message "Azure legacy password not available"
                return
            }
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_azure" | Remove-DbaDatabase
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            if (Get-DbaCredential -SqlInstance $TestConfig.instance2 -name dbatools_ci) {
                $sql = "DROP CREDENTIAL dbatools_ci"
                $server.Query($sql)
            }
            $sql = "CREATE CREDENTIAL [dbatools_ci] WITH IDENTITY = N'$TestConfig.azureblobaccount', SECRET = N'$env:azurelegacypasswd'"
            $server.Query($sql)
            $server.Query("CREATE DATABASE dbatoolsci_azure")
        }

        AfterAll {
            if (-not $env:azurelegacypasswd) {
                return
            }
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $server.Query("DROP CREDENTIAL dbatools_ci")
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_azure" | Remove-DbaDatabase
        }

        It "supports legacy credential setups" -Skip {
            if (-not $env:azurelegacypasswd) {
                Set-TestInconclusive -Message "Azure legacy password not available"
                return
            }
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -WithReplace -DatabaseName dbatoolsci_azure -Path https://dbatools.blob.core.windows.net/legacy/dbatoolsci_azure.bak -AzureCredential dbatools_ci
            $results.BackupFile | Should -Be "https://dbatools.blob.core.windows.net/legacy/dbatoolsci_azure.bak"
            $results.Script -match "CREDENTIAL" | Should -Be $true
            $results.RestoreComplete | Should -Be $true
        }
    }
}