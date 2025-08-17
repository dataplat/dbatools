#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaLastBackup",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $TestConfig = Get-TestConfig
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
                "AzureCredential",
                "InputObject",
                "EnableException",
                "DeviceType",
                "MaxTransferSize",
                "BufferCount",
                "IgnoreDiffBackup",
                "ReuseSourceFolderStructure"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $TestConfig = Get-TestConfig

        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $global:backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $global:backupPath -ItemType Directory

        # Explain what needs to be set up for the test:
        # To test backup restoration and validation, we need test databases with various backup types.
        # For comprehensive testing, we need databases with full, differential, and log backups.

        # Set variables. They are available in all the It blocks.
        $random = Get-Random
        $global:testlastbackup = "dbatoolsci_testlastbackup$random"
        $global:dbs = $global:testlastbackup, "dbatoolsci_lildb", "dbatoolsci_testrestore", "dbatoolsci_singlerestore"

        # Create the objects.
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        foreach ($db in $global:dbs) {
            $server.Query("CREATE DATABASE $db")
            $server.Query("ALTER DATABASE $db SET RECOVERY FULL WITH NO_WAIT")
            $server.Query("CREATE TABLE [$db].[dbo].[Example] (id int identity, name nvarchar(max))")
            $server.Query("INSERT INTO [$db].[dbo].[Example] values ('sample')")
        }

        # Setup restores and backups on the local drive for Test-DbaLastBackup
        Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $global:dbs | Backup-DbaDatabase -Type Database -Path $global:backupPath
        Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query "INSERT INTO [$global:testlastbackup].[dbo].[Example] values ('sample')"
        Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $global:testlastbackup | Backup-DbaDatabase -Type Differential -Path $global:backupPath
        Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query "INSERT INTO [$global:testlastbackup].[dbo].[Example] values ('sample1')"
        Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $global:testlastbackup | Backup-DbaDatabase -Type Differential -Path $global:backupPath
        Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query "INSERT INTO [$global:testlastbackup].[dbo].[Example] values ('sample2')"
        Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $global:testlastbackup | Backup-DbaDatabase -Type Log -Path $global:backupPath
        Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query "INSERT INTO [$global:testlastbackup].[dbo].[Example] values ('sample3')"
        Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $global:testlastbackup | Backup-DbaDatabase -Type Log -Path $global:backupPath
        Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query "INSERT INTO [$global:testlastbackup].[dbo].[Example] values ('sample4')"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created object.
        # these for sure
        $global:dbs += "bigtestrest", "smalltestrest"
        Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $global:dbs | Remove-DbaDatabase -Confirm:$false
        # those just in case test-dbalastbackup didn't cooperate
        Get-DbaDatabase -SqlInstance $TestConfig.instance1 | Where-Object Name -like "dbatools-testrestore-dbatoolsci_*" | Remove-DbaDatabase -Confirm:$false
        # see "Restores using a specific path"
        Get-ChildItem -Path C:\Temp\dbatools-testrestore-dbatoolsci_singlerestore* | Remove-Item -ErrorAction SilentlyContinue

        # Remove the backup directory.
        Remove-Item -Path $global:backupPath -Recurse -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Test a single database" {
        BeforeAll {
            $singleDbResults = Test-DbaLastBackup -SqlInstance $TestConfig.instance1 -Database $global:testlastbackup
        }

        It "Should return success" {
            $singleDbResults.RestoreResult | Should -Be "Success"
            $singleDbResults.DbccResult | Should -Be "Success"
            $singleDbResults.BackupDates | ForEach-Object { $PSItem | Should -BeOfType DbaDateTime }
        }
    }

    Context "Testing the whole instance" {
        BeforeAll {
            $instanceResults = Test-DbaLastBackup -SqlInstance $TestConfig.instance1 -ExcludeDatabase tempdb
        }

        It "Should be more than 3 databases" {
            $instanceResults.Status.Count | Should -BeGreaterThan 3
        }
    }

    Context "Restores using a specific path" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database "dbatoolsci_singlerestore" | Backup-DbaDatabase -Path $global:backupPath
            $null = Test-DbaLastBackup -SqlInstance $TestConfig.instance1 -Database "dbatoolsci_singlerestore" -DataDirectory C:\Temp -LogDirectory C:\Temp -NoDrop
            $pathResults = Get-DbaDbFile -SqlInstance $TestConfig.instance1 -Database "dbatools-testrestore-dbatoolsci_singlerestore"
        }

        It "Should match C:\Temp" {
            ("C:\Temp\dbatools-testrestore-dbatoolsci_singlerestore.mdf" -in $pathResults.PhysicalName) | Should -Be $true
            ("C:\Temp\dbatools-testrestore-dbatoolsci_singlerestore_log.ldf" -in $pathResults.PhysicalName) | Should -Be $true
        }
    }

    Context "Test Ignoring Diff Backups" {
        BeforeAll {
            $ignoreDiffResults = Test-DbaLastBackup -SqlInstance $TestConfig.instance1 -Database $global:testlastbackup -IgnoreDiffBackup
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
            $results1 = Restore-DbaDatabase -SqlInstance $TestConfig.instance1 -Database bigtestrest -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\db1\FULL" -ReplaceDbNameInFile
            Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database bigtestrest -Path $global:backupPath
            $results1 = Restore-DbaDatabase -SqlInstance $TestConfig.instance1 -Database smalltestrest -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\db2\FULL\SQL2008_db2_FULL_20170518_041738.bak" -ReplaceDbNameInFile
            Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database smalltestrest -Path $global:backupPath

            $sizeResults = Test-DbaLastBackup -SqlInstance $TestConfig.instance1 -Database bigtestrest, smalltestrest -CopyFile -CopyPath c:\temp -MaxSize 5 -Prefix testlast
            $fileresult = Get-ChildItem c:\temp | Where-Object Name -like "*bigtestrest"
        }

        AfterAll {
            Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database bigtestrest, smalltestrest | Remove-DbaDatabase -Confirm:$false
        }

        It "Should have skipped bigtestrest and tested smalltestrest" {
            $sizeResults[0].RestoreResult | Should -BeLike "*exceeds the specified maximum*"
            $sizeResults[0].DbccResult | Should -Be "Skipped"
            $sizeResults[1].RestoreResult | Should -Be "Success"
            $sizeResults[1].DbccResult | Should -Be "Success"
        }

        It "Should have removed the temp backup copy even if skipped" {
            ($null -eq $fileresult) | Should -Be $true
        }
    }
}