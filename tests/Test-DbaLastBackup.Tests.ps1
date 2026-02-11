#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaLastBackup",
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
                "Database",
                "ExcludeDatabase",
                "Destination",
                "DestinationSqlCredential",
                "DataDirectory",
                "LogDirectory",
                "FileStreamDirectory",
                "Prefix",
                "VerifyOnly",
                "NoCheck",
                "NoDrop",
                "CopyFile",
                "CopyPath",
                "MaxSize",
                "MaxDop",
                "IncludeCopyOnly",
                "IgnoreLogBackup",
                "StorageCredential",
                "InputObject",
                "EnableException",
                "DeviceType",
                "MaxTransferSize",
                "BufferCount",
                "IgnoreDiffBackup",
                "ReuseSourceFolderStructure",
                "Checksum",
                "Wait"
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

        # Explain what needs to be set up for the test:
        # To test backup restoration and validation, we need test databases with various backup types.
        # For comprehensive testing, we need databases with full, differential, and log backups.

        # Set variables. They are available in all the It blocks.
        $random = Get-Random
        $testlastbackup = "dbatoolsci_testlastbackup$random"
        $dbs = $testlastbackup, "dbatoolsci_lildb", "dbatoolsci_testrestore", "dbatoolsci_singlerestore"

        # Create the objects.
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        foreach ($db in $dbs) {
            $server.Query("CREATE DATABASE $db")
            $server.Query("ALTER DATABASE $db SET RECOVERY FULL WITH NO_WAIT")
            $server.Query("CREATE TABLE [$db].[dbo].[Example] (id int identity, name nvarchar(max))")
            $server.Query("INSERT INTO [$db].[dbo].[Example] values ('sample')")
        }

        # Setup restores and backups on the local drive for Test-DbaLastBackup
        Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbs | Backup-DbaDatabase -Type Database -Path $backupPath
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample')"
        Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $testlastbackup | Backup-DbaDatabase -Type Differential -Path $backupPath
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample1')"
        Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $testlastbackup | Backup-DbaDatabase -Type Differential -Path $backupPath
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample2')"
        Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $testlastbackup | Backup-DbaDatabase -Type Log -Path $backupPath
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample3')"
        Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $testlastbackup | Backup-DbaDatabase -Type Log -Path $backupPath
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample4')"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created object.
        # these for sure
        $dbs += "bigtestrest", "smalltestrest"
        Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbs | Remove-DbaDatabase
        # those just in case test-dbalastbackup didn't cooperate
        Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -like "dbatools-testrestore-dbatoolsci_*" | Remove-DbaDatabase

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Test a single database" {
        BeforeAll {
            $singleDbResults = Test-DbaLastBackup -SqlInstance $TestConfig.InstanceSingle -Database $testlastbackup
        }

        It "Should return success" {
            $singleDbResults.RestoreResult | Should -Be "Success"
            $singleDbResults.DbccResult | Should -Be "Success"
            $singleDbResults.BackupDates | ForEach-Object { $PSItem | Should -BeOfType DbaDateTime }
        }
    }

    Context "Testing the whole instance" {
        BeforeAll {
            $instanceResults = Test-DbaLastBackup -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase tempdb
        }

        It "Should be more than 3 databases" {
            $instanceResults.Status.Count | Should -BeGreaterThan 3
        }
    }

    Context "Restores using a specific path" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_singlerestore" | Backup-DbaDatabase -Path $backupPath
            $null = Test-DbaLastBackup -SqlInstance $TestConfig.InstanceSingle -Database "dbatoolsci_singlerestore" -DataDirectory $backupPath -LogDirectory $backupPath -NoDrop
            $pathResults = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database "dbatools-testrestore-dbatoolsci_singlerestore"
        }

        It "Should match path" {
            $pathResults.PhysicalName | Should -Contain "$backupPath\dbatools-testrestore-dbatoolsci_singlerestore.mdf"
            $pathResults.PhysicalName | Should -Contain "$backupPath\dbatools-testrestore-dbatoolsci_singlerestore_log.ldf"
        }
    }

    Context "Test Ignoring Diff Backups" {
        BeforeAll {
            $ignoreDiffResults = Test-DbaLastBackup -SqlInstance $TestConfig.InstanceSingle -Database $testlastbackup -IgnoreDiffBackup
        }

        It "Should return success" {
            $ignoreDiffResults.RestoreResult | Should -Be "Success"
        }

        It "Should not contain a diff backup" {
            ($ignoreDiffResults.BackupFiles | Where-Object { $PSItem -like "*diff*" }).Status.Count | Should -Be 0
        }
    }

    Context "Test dbsize skip and cleanup (Issue 3968)" {
        BeforeAll {
            $results1 = Restore-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database bigtestrest -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\db1\FULL" -ReplaceDbNameInFile
            Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database bigtestrest -Path $backupPath
            $results1 = Restore-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database smalltestrest -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\db2\FULL\SQL2008_db2_FULL_20170518_041738.bak" -ReplaceDbNameInFile
            Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database smalltestrest -Path $backupPath

            $sizeResults = Test-DbaLastBackup -SqlInstance $TestConfig.InstanceSingle -Database bigtestrest, smalltestrest -CopyFile -CopyPath $backupPath -MaxSize 5 -Prefix testlast
            $fileresult = Get-ChildItem $backupPath | Where-Object Name -like "*bigtestrest"
        }

        AfterAll {
            Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database bigtestrest, smalltestrest | Remove-DbaDatabase
        }

        It "Should have skipped bigtestrest" {
            $sizeResults[0].RestoreResult | Should -BeLike "*exceeds the specified maximum*"
            $sizeResults[0].DbccResult | Should -Be "Skipped"
        }

        It "Should have tested smalltestrest" -Skip:$env:AppVeyor {
            # I don't know why this fails on AppVeyor, but it does.
            $sizeResults[1].RestoreResult | Should -Be "Success"
            $sizeResults[1].DbccResult | Should -Be "Success"
        }

        It "Should have removed the temp backup copy even if skipped" {
            ($null -eq $fileresult) | Should -Be $true
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outputResult = Test-DbaLastBackup -SqlInstance $TestConfig.InstanceSingle -Database $testlastbackup
        }

        It "Returns output of the documented type" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProperties = @(
                "SourceServer",
                "TestServer",
                "Database",
                "FileExists",
                "Size",
                "RestoreResult",
                "DbccResult",
                "RestoreStart",
                "RestoreEnd",
                "RestoreElapsed",
                "DbccMaxDop",
                "DbccStart",
                "DbccEnd",
                "DbccElapsed",
                "BackupDates",
                "BackupFiles"
            )
            foreach ($prop in $expectedProperties) {
                $outputResult.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }

        It "Has correct source and test server values" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $outputResult.SourceServer | Should -Not -BeNullOrEmpty
            $outputResult.TestServer | Should -Not -BeNullOrEmpty
            $outputResult.Database | Should -Be $testlastbackup
        }

        It "Has backup dates as DbaDateTime" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $outputResult.BackupDates | Should -Not -BeNullOrEmpty
            $outputResult.BackupDates | ForEach-Object { $PSItem | Should -BeOfType DbaDateTime }
        }
    }
}