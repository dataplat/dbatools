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
                "Checksum",
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

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Setup variable for multiple contexts
        $dataFolder = "$backupPath\datafiles"
        $logFolder = "$backupPath\logfiles"
        $null = New-Item -ItemType Directory $dataFolder
        $null = New-Item -ItemType Directory $logFolder

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up any remaining databases
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }


    Context "Properly restores a database" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException
        }

        It "Properly restores a database on the local drive using Path" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak"
            $results.RestoreComplete | Should -BeTrue
            $results.BackupFile | Should -Be "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak"
        }

        It "Ensuring warning is thrown if database already exists" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -WarningAction SilentlyContinue
            $WarnVar[0] | Should -BeLike "*Database singlerestore exists, so WithReplace must be specified*"
            $results | Should -BeNullOrEmpty
        }

        It "Database is properly removed again after withreplace test" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -WithReplace
            $results.RestoreComplete | Should -BeTrue
            $results.WithReplace | Should -BeTrue
            $results.BackupFile | Should -Be "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak"
        }
    }


    Context "Properly restores a database on the local drive using piped Get-ChildItem results" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException
        }

        It "Should return correct results" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -WithReplace
            $results.RestoreComplete | Should -BeTrue
            $results.BackupFile | Should -Be "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak"
        }

        It "Test VerifyOnly works with db in existence" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -VerifyOnly
            $results[0] | Should -Be "Verify successful"
        }
    }


    Context "Allows continues with Differential Backups" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException
        }

        It "Should restore the root full cleanly" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\DoubleDiffing\difftest-full.bak" -NoRecovery
            $results.RestoreComplete | Should -BeTrue
        }

        It "Should restore the first diff cleanly" {
            $results1 = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\DoubleDiffing\difftest-diff1.bak" -NoRecovery -Continue
            $results1.RestoreComplete | Should -BeTrue
        }

        It "Should restore the second diff cleanly" {
            $results2 = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\DoubleDiffing\difftest-diff2.bak" -Continue
            $results2.RestoreComplete | Should -BeTrue
        }
    }


    Context "Database is restored with correct renamings" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException
        }

        It "Should return successful restore with prefix" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DestinationFilePrefix prefix -WithReplace
            $results.RestoreComplete | Should -BeTrue
            (($results.RestoredFile -split ",").substring(0, 6) -eq "prefix").count | Should -Be 2
        }

        It "Should return successful restore with suffix" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DestinationFileSuffix suffix -WithReplace
            $results.RestoreComplete | Should -BeTrue
            (($results.RestoredFile -split ",") -match "suffix\.").count | Should -Be 2
        }

        It "Should return successful restore with suffix and prefix" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DestinationFileSuffix suffix -DestinationFilePrefix prefix -WithReplace
            $results.RestoreComplete | Should -BeTrue
            (($results.RestoredFile -split ",") -match "^prefix.*suffix\.").count | Should -Be 2
        }
    }


    Context "Replace databasename in Restored File" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException
        }

        It "Should return the 2 files swapping singlerestore for pestering (output)" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName Pestering -replaceDbNameInFile -WithReplace
            (($results.RestoredFile -split ",") -like "*pestering*").count | Should -Be 2
        }
    }


    Context "Replace databasename in Restored File, but don't change backup history #5036" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException
        }

        It "Should not change the PhysicalName in the FileList of the backup history" {
            $bh = Get-DbaBackupInformation -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -SqlInstance $TestConfig.instance2
            $firstPhysicalName = $bh.FileList.PhysicalName[0]

            $null = $bh | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName Pestering -replaceDbNameInFile -WithReplace -OutputScriptOnly
            $bh.FileList.PhysicalName[0] | Should -Be $firstPhysicalName
        }
    }


    Context "ReplaceDbNameInFile regression test for #9656" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException
        }

        It "Should replace database name in file basename only, not in directory path" {
            $scriptOutput = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName "NewDatabaseName" -ReplaceDbNameInFile -WithReplace -OutputScriptOnly
            $scriptOutput | Should -BeLike "*NewDatabaseName*"
            $scriptOutput | Should -Not -BeLike "*singlerestore\NewDatabaseName\*"
        }

        It "Should generate valid MOVE statements with replaced database name" {
            $scriptOutput = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName "ReplacedDbName" -ReplaceDbNameInFile -WithReplace -OutputScriptOnly
            $scriptOutput | Should -Match "MOVE.*ReplacedDbName"
        }
    }


    Context "Test restoring as other login #6992" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException

            $restoreAsUser = "RestoreAs"
            $restoreAsUserInvalid = "RestoreAsInvalid"
            $null = New-DbaLogin -SqlInstance $TestConfig.instance2 -Login $restoreAsUser -SecurePassword (ConvertTo-SecureString 'P@ssw0rdl!ng' -AsPlainText -Force) -EnableException
            $null = Add-DbaServerRoleMember -SqlInstance $TestConfig.instance2 -ServerRole sysadmin -Login $restoreAsUser -EnableException
        }

        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException
            $null = Remove-DbaLogin -SqlInstance $TestConfig.instance2 -Login $restoreAsUser -EnableException
        }

        It "Should throw a warning if login doesn't exist" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName Pestering -replaceDbNameInFile -WithReplace -ExecuteAs $restoreAsUserInvalid -WarningAction SilentlyContinue
            $WarnVar | Should -BeLike "*You specified a Login to execute the restore, but the login '$restoreAsUserInvalid' does not exist"
        }

        It "Should be owned by correct user" {
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database Pestering
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName Pestering -replaceDbNameInFile -ExecuteAs $restoreAsUser
            $db = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database Pestering
            $db.Owner | Should -Be $restoreAsUser
        }

        It "Should prefix the script with the Execute As statement" {
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database Pestering
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName Pestering -replaceDbNameInFile -ExecuteAs $restoreAsUser -OutputScriptOnly
            $results | Should -BeLike "EXECUTE AS LOGIN='$restoreAsUser'*"
        }
    }


    Context "Folder restore options" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException
        }

        It "Should return successful restore with DestinationDataDirectory" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -WithReplace -DestinationDataDirectory $dataFolder
            $results.RestoreComplete | Should -Be $true
        }

        It "Should have moved all files to $dataFolder" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -WithReplace -DestinationDataDirectory $dataFolder
            (($results.RestoredFileFull -split ",") -like "$dataFolder*").count | Should -Be 2
        }

        It "Should exist on Filesystem" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -WithReplace -DestinationDataDirectory $dataFolder
            ForEach ($file in ($results.RestoredFileFull -split ",")) {
                $file | Should -Exist
            }
        }

        It "Should have moved data file to $dataFolder" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -WithReplace -DestinationDataDirectory $dataFolder -DestinationLogDirectory $logFolder
            (($results.RestoredFileFull -split ",") -like "$dataFolder*").count | Should -Be 1
        }

        It "Should have moved Log file to $logFolder" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -WithReplace -DestinationDataDirectory $dataFolder -DestinationLogDirectory $logFolder
            (($results.RestoredFileFull -split ",") -like "$logFolder*").count | Should -Be 1
        }
    }


    Context "Putting all restore file modification options together" {
        BeforeEach {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException
        }

        It "Should return successful restore with all file mod options" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DestinationDataDirectory $dataFolder -DestinationLogDirectory $logFolder -DestinationFileSuffix Suffix -DestinationFilePrefix prefix
            $results.RestoreComplete | Should -Be $true
        }

        It "Should have moved data file to dataFolder (output)" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DestinationDataDirectory $dataFolder -DestinationLogDirectory $logFolder -DestinationFileSuffix Suffix -DestinationFilePrefix prefix
            (($results.RestoredFileFull -split ",") -like "$dataFolder*").count | Should -Be 1
        }

        It "Should have moved Log file to logFolder (output)" {
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


    Context "Properly restores an instance using ola-style backups via pipe" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException
        }

        It "Properly restores an instance using ola-style backups via pipe" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\sql2008-backups" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2
            $results.DatabaseName.Count | Should -Be 33
            ($results.RestoreComplete -contains $false) | Should -Be $false
        }
    }


    Context "Properly restores an instance using ola-style backups via string" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException
        }

        It "Properly restores an instance using ola-style backups via string" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups"
            $results.DatabaseName.Count | Should -Be 33
            ($results.RestoreComplete -contains $false) | Should -Be $false
        }
    }


    Context "Should proceed if backups from multiple dbs passed in and databasename specified" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException
        }

        It "Should proceed if backups from multiple dbs passed in and databasename specified" {
            $results = Get-ChildItem "$($TestConfig.appveyorlabrepo)\sql2008-backups" | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName test -WarningAction SilentlyContinue
            $WarnVar | Should -BeLike "*Multiple Databases' backups passed in, but only 1 name to restore them under. Stopping as cannot work out how to proceed*"
            $results | Should -BeNullOrEmpty
        }
    }


    Context "RestoreTime setup checks" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException

            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016"
        }

        It "Should restore cleanly" {
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
            ($results.RestoreComplete -contains $false) | Should -Be $false
            ($results.count -gt 0) | Should -Be $true
        }

        It "Should have restored 5 files" {
            $results.count | Should -Be 5
        }

        It "Should have restored from 2019-05-02 21:00:55" {
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
            $sqlResults.mindt | Should -Be (Get-Date "2019-05-02 21:00:55")
        }

        It "Should have restored to 2019-05-02 13:28:43" {
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
            $sqlResults.maxdt | Should -Be (Get-Date "2019-05-02 21:30:26")
        }
    }


    Context "RestoreTime point in time" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException

            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016" -RestoreTime (Get-Date "2019-05-02 21:12:27")
        }

        It "Should have restored 4 files" {
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
            $results.count | Should -Be 4
        }

        It "Should have restored from 2019-05-02 21:00:55" {
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
            $sqlResults.mindt | Should -Be (Get-Date "2019-05-02 21:00:55")
        }

        It "Should have restored to 2019-05-02 21:12:26" {
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from RestoreTimeClean.dbo.steps"
            $sqlResults.maxdt | Should -Be (Get-Date "2019-05-02 21:12:26")
        }
    }


    Context "RestoreTime point in time with Simple Model" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException

            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\sql2008-backups\SimpleRecovery\" -RestoreTime (Get-Date "2018-04-06 10:37:44")
        }

        It "Should have restored 2 files" {
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from SimpleBackTest.dbo.steps"
            $results.count | Should -Be 2
        }

        It "Should have restored from 2018-04-06 10:30:32" {
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from SimpleBackTest.dbo.steps"
            $sqlResults.mindt | Should -Be (Get-Date "2018-04-06 10:30:32")
        }

        It "Should have restored to 2018-04-06 10:35:02" {
            $sqlResults = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select convert(datetime,convert(varchar(20),max(dt),120)) as maxdt, convert(datetime,convert(varchar(20),min(dt),120)) as mindt from SimpleBackTest.dbo.steps"
            $sqlResults.maxdt | Should -Be (Get-Date "2018-04-06 10:35:02")
        }
    }


    Context "Continue Restore with Differentials" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException
        }

        It "Should Have restored the database cleanly in a norecovery state" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\ft1\FULL\" -NoRecovery
            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true
            (Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database ft1).Status | Should -Be "Restoring"
        }

        It "Should Have restored the database cleanly on continue" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\ft1\" -Continue
            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true
            (Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database ft1).Status | Should -Be "Normal"
        }
    }


    Context "Continue Restore with Differentials and rename " {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException
        }

        It "Should Have restored the database cleanly in a norecovery state" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName contest -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\ft1\FULL\" -NoRecovery
            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true
            (Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database contest).Status | Should -Be "Restoring"
        }

        It "Should Have restored the database cleanly on continue" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName contest -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\ft1\" -Continue
            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true
            (Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database contest).Status | Should -Be "Normal"
        }
    }


    Context "Continue Restore with multiple databases" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException
        }

        It "Should Have restored the database cleanly in a norecovery state" {
            $files = @()
            $files += Get-ChildItem "$($TestConfig.appveyorlabrepo)\sql2008-backups\db1\FULL\"
            $files += Get-ChildItem "$($TestConfig.appveyorlabrepo)\sql2008-backups\dbareports\FULL"
            $results = $files | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -NoRecovery
            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true
            (Get-DbaDatabase -SqlInstance $TestConfig.instance2 | Where-Object Status -eq "Recovering").count | Should -Be 0
        }

        It "Should Have restored the database cleanly on continue" {
            $files = @()
            $files += Get-ChildItem "$($TestConfig.appveyorlabrepo)\sql2008-backups\db1\" -Recurse
            $files += Get-ChildItem "$($TestConfig.appveyorlabrepo)\sql2008-backups\dbareports\" -Recurse
            $results2 = $files | Where-Object PsIsContainer -eq $false | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Continue
            ($results2.RestoreComplete -contains $false) | Should -Be $false
            (($results2 | Measure-Object).count -gt 0) | Should -Be $true
            (Get-DbaDatabase -SqlInstance $TestConfig.instance2 | Where-Object Status -eq "Recovering").count | Should -Be 0
        }
    }


    Context "Check Get-DbaDbBackupHistory pipes into Restore-DbaDatabase" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException

            $null = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\RestoreTimeClean2016\restoretimeclean.bak" -WarningAction SilentlyContinue
            $null = Backup-DbaDatabase -SqlInstance $TestConfig.instance2 -Database RestoreTimeClean -BackupDirectory $backupPath
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database RestoreTimeClean
        }

        It "Should have restored everything successfully" {
            $history = Get-DbaDbBackupHistory -SqlInstance $TestConfig.instance2 -Database RestoreTimeClean -Last -WarningAction SilentlyContinue
            $results = $history | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -WithReplace -TrustDbBackupHistory -WarningAction SilentlyContinue
            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true
        }
    }


    Context "Restores a db with log and file files missing extensions" {
        It "Should Restore successfully" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -path "$($TestConfig.appveyorlabrepo)\sql2008-backups\Noextension.bak"
            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true
        }
    }


    Context "Setup for Recovery Tests" {
        It "Should have restored everything successfully" {
            $databaseName = "rectest"

            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -NoRecovery -DatabaseName $databaseName -DestinationFilePrefix $databaseName -WithReplace
            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true

            $check = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName
            $check.count | Should -Be 1

            $check = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName
            $check.status | Should -Be "Restoring"
        }
    }


    Context "Test recovery via parameter" {
        It "Should have restored everything successfully" {
            $databaseName = "rectest"

            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Recover -DatabaseName $databaseName

            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true

            $check = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName
            $check.count | Should -Be 1

            $check = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName
            "Normal" -in $check.status | Should -Be $true
        }
    }


    Context "Setup for Recovery Tests" {
        It "Should have restored everything successfully" {
            $databaseName = "rectest"

            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -NoRecovery -DatabaseName $databaseName -DestinationFilePrefix $databaseName -WithReplace
            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true

            $check = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName
            $check.count | Should -Be 1

            $check = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName
            $check.status | Should -Be "Restoring"
        }
    }


    Context "Test recovery via pipeline" {
        It "Should have restored everything successfully" {
            $databaseName = "rectest"

            $results = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Recover

            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true

            $check = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName
            $check.count | Should -Be 1

            $check = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName
            "Normal" -in $check.status | Should -Be $true
        }
    }


    Context "Checking we cope with a port number (#244)" {
        It "Should have restored everything successfully" {
            $databaseName = "rectest"

            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2_detailed -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName $databaseName -DestinationFilePrefix $databaseName -WithReplace
            ($results.RestoreComplete -contains $false) | Should -Be $false
            (($results | Measure-Object).count -gt 0) | Should -Be $true
        }
    }


    Context "Checking OutputScriptOnly only outputs script" {
        It "Should only output a script" {
            $databaseName = "rectestSO"

            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName $databaseName -OutputScriptOnly
            $db = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName
            $results -match "RESTORE DATABASE" | Should -Be $true
            ($null -eq $db) | Should -Be $true
        }
    }


    Context "Checking OutputScriptOnly only outputs script without changing state for existing dbs (#2940)" {
        It "Checking OutputScriptOnly only outputs script without changing state for existing dbs (#2940)" {
            $databaseName = "dbatoolsci_rectestSO"

            Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName | Remove-DbaDatabase

            $server = Connect-DbaInstance $TestConfig.instance2
            $server.Query("CREATE DATABASE $databaseName")
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName $databaseName -OutputScriptOnly -WithReplace

            $db = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName
            $results -match "RESTORE DATABASE" | Should -Be $true
            $db.UserAccess | Should -Be "Multiple"
        }
    }


    Context "Checking Output vs input" {
        BeforeAll {
            $databaseName = "rectestSO"

            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName $databaseName -BufferCount 24 -MaxTransferSize 128kb -BlockSize 64kb
        }

        It "Should return the destination instance" {
            $results.SqlInstance = $TestConfig.instance2
        }

        It "Should have a BlockSize of 65536" {
            $results.Script | Should -Match "BLOCKSIZE = 65536"
        }

        It "Should have a BufferCount of 24" {
            $results.Script | Should -Match "BUFFERCOUNT = 24"
        }

        It "Should have a MaxTransferSize of 131072" {
            $results.Script | Should -Match "MAXTRANSFERSIZE = 131072"
        }
    }


    Context "Checking CDC parameter " {
        BeforeAll {
            Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $databaseName | Remove-DbaDatabase

            $databaseName = "testCDC"
        }

        It "Should have KEEP_CDC in the SQL" {
            $output = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName $databaseName -OutputScriptOnly -KeepCDC -WithReplace
            $output | Should -BeLike '*KEEP_CDC*'
        }

        It "Should not output, and warn if Norecovery and KeepCDC specified" {
            $output = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName $databaseName -OutputScriptOnly -KeepCDC -WithReplace -NoRecovery -WarningAction SilentlyContinue
            $WarnVar | Should -BeLike "*KeepCDC cannot be specified with Norecovery or Standby as it needs recovery to work"
            $output | Should -Be $null
        }

        It "Should not output, and warn if StandbyDirectory and KeepCDC specified" {
            $output = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName $databaseName -OutputScriptOnly -KeepCDC -WithReplace -StandbyDirectory $backupPath -WarningAction SilentlyContinue
            $WarnVar | Should -BeLike "*KeepCDC cannot be specified with Norecovery or Standby as it needs recovery to work"
            $output | Should -Be $null
        }
    }


    Context "Page level restores" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
            $null = Remove-DbaDbBackupRestoreHistory -SqlInstance $TestConfig.instance2 -KeepDays -1

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

Backup database PageRestore to disk='$backupPath\pagerestore.bak'
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

Backup log PageRestore to disk='$backupPath\PageRestore.trn'

insert into testpage values (REPLICATE('f','8000'))
use master
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query $sql -Database Pagerestore
        }

        It "Should have warned about corruption" {
            $sqlResults2 = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database Master -Query "select * from pagerestore.dbo.testpage where filler like 'a%'" -WarningAction SilentlyContinue
            $WarnVar | Should -Match ([regex]::Escape("SQL Server detected a logical consistency-based I/O error: incorrect checksum (expected"))
            $sqlResults2 | Should -BeNullOrEmpty
        }

        It "Should work after page restore" {
            $null = Get-DbaDbBackupHistory -SqlInstance $TestConfig.instance2 -Database pagerestore -last | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -PageRestore (Get-DbaSuspectPage -SqlInstance $TestConfig.instance2 -Database PageRestore) -TrustDbBackupHistory -DatabaseName PageRestore -PageRestoreTailFolder $backupPath
            $sqlResults3 = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Query "select * from pagerestore.dbo.testpage where filler like 'f%'"
            ($null -eq $sqlResults3) | Should -Be $false
        }
    }


    Context "Testing Backup to Restore piping" {
        It "Should backup and restore cleanly" {
            Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Remove-DbaDatabase
            $null = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName PipeTest -DestinationFilePrefix PipeTest
            $results = Backup-DbaDatabase -SqlInstance $TestConfig.instance2 -Database Pipetest -BackupDirectory $backupPath -CopyOnly | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName restored -ReplaceDbNameInFile
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
            $cert = New-DbaDbCertificate -SqlInstance $TestConfig.instance2 -Database master -Name RestoreTestCert -Subject RestoreTestCert

            $encBackupResults = Backup-DbaDatabase -SqlInstance $TestConfig.instance2 -Database EncRestTest -EncryptionAlgorithm AES128 -EncryptionCertificate RestoreTestCert -FilePath "$backupPath\EncRestTest.bak"
        }

        AfterAll {
            $null = Remove-DbaDbCertificate -SqlInstance $TestConfig.instance2 -Database master -Certificate RestoreTestCert
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database EncRestTest, certEncRestTest
        }

        It "Should encrypt the backup" {
            $encBackupResults.EncryptorType | Should -Be "CERTIFICATE"
            $encBackupResults.KeyAlgorithm | Should -Be "aes_128"
        }

        It "Should have restored the backup" {
            $results = $encBackupResults | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -TrustDbBackupHistory -RestoredDatabaseNamePrefix cert -DestinationFilePrefix cert
            $results.RestoreComplete | Should -Be $true
        }
    }


    <#
    TODO:
    The next tests are skipped because they don't work as expected.
    In "$($TestConfig.appveyorlabrepo)\sql2008-backups\StopAt" the backup chain is maybe broken (is file StopAt_22.trn missing?)
    Restore-DbaDatabase writes a warning: Microsoft.Data.SqlClient.SqlError: The log in this backup set begins at LSN 19000000021500001, which is too recent to apply to the database. An earlier log backup that includes LSN 19000000020400004 can be restored.
    Pester does not like this warning, reason currently unknown. But the context and the complete test fail with "System.Management.Automation.ParameterBindingValidationException: Cannot bind argument to parameter 'ErrorRecord' because it is null".
    Maybe it's because the warning is written to $error but has no ErrorRecord.
    #>

    Context -Skip "Test restoring with StopAt" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException
        }

        It "Should have stoped at mark" {
            $restoreOutput = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Name StopAt2 -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\StopAt" -StopMark dbatoolstest -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable x
            $null = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Name StopAt2 -Recover
            $sqlOut = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database StopAt2 -Query "select max(step) as ms from steps"
            $sqlOut.ms | Should -Be 9876
        }
    }


    Context -Skip "Test restoring with StopAtBefore" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException
        }

        It "Should have stoped at mark" {
            $restoreOutput = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Name StopAt2 -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\StopAt" -StopMark dbatoolstest -StopBefore -WarningAction SilentlyContinue
            $null = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Name StopAt2 -Recover
            $sqlOut = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database StopAt2 -Query "select max(step) as ms from steps"
            $sqlOut.ms | Should -Be 8764
        }
    }


    Context -Skip "Test restoring with StopAt and StopAfterDate" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem -EnableException | Remove-DbaDatabase -EnableException
        }

        It "Should have stoped at mark" {
            $restoreOutput = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Name StopAt2 -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\StopAt" -StopMark dbatoolstest -StopAfterDate (Get-Date "2020-05-12 13:33:35") -WarningAction SilentlyContinue
            $null = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Name StopAt2 -Recover
            $sqlOut = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database StopAt2 -Query "select max(step) as ms from steps"
            $sqlOut.ms | Should -Be 29876
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database StopAt2
        }
    }


    Context "Warn if OutputScriptOnly and VerifyOnly specified together #6987" {
        It "Should return a warning" {
            $restoreOutput = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -Name StopAt2 -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\StopAt" -OutputScriptOnly -VerifyOnly -WarningAction SilentlyContinue
            $WarnVar | Should -BeLike "*The switches OutputScriptOnly and VerifyOnly cannot both be specified at the same time, stopping"
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database StopAt2
        }
    }


    Context -Skip:(-not $env:azurepasswd) "Restores From Azure using SAS" {
        BeforeAll {
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
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $server.Query("DROP CREDENTIAL [$TestConfig.azureblob]")
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_azure" | Remove-DbaDatabase
        }

        It "Should restore cleanly" {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -WithReplace -DatabaseName dbatoolsci_azure -Path $TestConfig.azureblob/dbatoolsci_azure.bak
            $results.BackupFile | Should -Be "$TestConfig.azureblob/dbatoolsci_azure.bak"
            $results.RestoreComplete | Should -Be $true
        }
    }


    Context -Skip:(-not $env:azurepasswd -or $env:appveyor) "Restores Striped backup From Azure using SAS" {
        BeforeAll {
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
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $server.Query("DROP CREDENTIAL [$TestConfig.azureblob]")
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_azure" | Remove-DbaDatabase
        }

        It "Should restore cleanly" {
            $results = @("$TestConfig.azureblob/az-1.bak", "$TestConfig.azureblob/az-2.bak", "$TestConfig.azureblob/az-3.bak") | Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -DatabaseName azstripetest  -WithReplace -ReplaceDbNameInFile
            $results.RestoreComplete | Should -Be $true
        }
    }


    Context -Skip:(-not $env:azurelegacypasswd) "Restores from Azure using Access Key" {
        BeforeAll {
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
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $server.Query("DROP CREDENTIAL dbatools_ci")
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_azure" | Remove-DbaDatabase
        }

        It "supports legacy credential setups" -Skip {
            $results = Restore-DbaDatabase -SqlInstance $TestConfig.instance2 -WithReplace -DatabaseName dbatoolsci_azure -Path https://dbatools.blob.core.windows.net/legacy/dbatoolsci_azure.bak -AzureCredential dbatools_ci
            $results.BackupFile | Should -Be "https://dbatools.blob.core.windows.net/legacy/dbatoolsci_azure.bak"
            $results.Script -match "CREDENTIAL" | Should -Be $true
            $results.RestoreComplete | Should -Be $true
        }
    }
}