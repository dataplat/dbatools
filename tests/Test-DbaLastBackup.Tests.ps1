#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaLastBackup",
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
                "DeviceType",
                "IncludeCopyOnly",
                "IgnoreLogBackup",
                "AzureCredential",
                "InputObject",
                "MaxTransferSize",
                "BufferCount",
                "IgnoreDiffBackup",
                "MaxDop",
                "ReuseSourceFolderStructure",
                "EnableException"
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
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $testlastbackup = "dbatoolsci_testlastbackup$random"
        $dbs = $testlastbackup, "dbatoolsci_lildb", "dbatoolsci_testrestore", "dbatoolsci_singlerestore"

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        foreach ($db in $dbs) {
            $server.Query("CREATE DATABASE $db")
            $server.Query("ALTER DATABASE $db SET RECOVERY FULL WITH NO_WAIT")
            $server.Query("CREATE TABLE [$db].[dbo].[Example] (id int identity, name nvarchar(max))")
            $server.Query("INSERT INTO [$db].[dbo].[Example] values ('sample')")
        }

        $backupPath = "$($TestConfig.Temp)\$CommandName"
        $null = New-Item -Path $backupPath -ItemType Directory

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # these for sure
        $dbs += "bigtestrest", "smalltestrest"
        Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbs | Remove-DbaDatabase -Confirm:$false -ErrorAction SilentlyContinue
        # those just in case test-dbalastbackup didn't cooperate
        Get-DbaDatabase -SqlInstance $TestConfig.instance1 | Where-Object Name -like "dbatools-testrestore-dbatoolsci_*" | Remove-DbaDatabase -Confirm:$false -ErrorAction SilentlyContinue
        # see "Restores using a specific path"
        Get-ChildItem -Path C:\Temp\dbatools-testrestore-dbatoolsci_singlerestore* -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue

        Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue
    }
    Context "Setup restores and backups on the local drive for Test-DbaLastBackup" {
        BeforeAll {
            Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbs | Backup-DbaDatabase -Type Database -Path $backupPath
            Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query "INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample')"
            Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $testlastbackup | Backup-DbaDatabase -Type Differential -Path $backupPath
            Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query "INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample1')"
            Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $testlastbackup | Backup-DbaDatabase -Type Differential -Path $backupPath
            Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query "INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample2')"
            Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $testlastbackup | Backup-DbaDatabase -Type Log -Path $backupPath
            Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query "INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample3')"
            Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $testlastbackup | Backup-DbaDatabase -Type Log -Path $backupPath
            Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Query "INSERT INTO [$testlastbackup].[dbo].[Example] values ('sample4')"
        }
    }

    Context "Test a single database" {
        BeforeAll {
            $singleDbResults = Test-DbaLastBackup -SqlInstance $TestConfig.instance1 -Database $testlastbackup
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
            $instanceResults.Count | Should -BeGreaterThan 3
        }
    }

    Context "Restores using a specific path" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database "dbatoolsci_singlerestore" | Backup-DbaDatabase -Path $backupPath
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
            $noDiffResults = Test-DbaLastBackup -SqlInstance $TestConfig.instance1 -Database $testlastbackup -IgnoreDiffBackup
        }

        It "Should return success" {
            $noDiffResults.RestoreResult | Should -Be "Success"
        }

        It "Should not contain a diff backup" {
            ($noDiffResults.BackupFiles | Where-Object { $PSItem -like "*diff*" }).Count | Should -Be 0
        }
    }

    Context "Test dbsize skip and cleanup (Issue 3968)" {
        BeforeAll {
            $restoreResults1 = Restore-DbaDatabase -SqlInstance $TestConfig.instance1 -Database bigtestrest -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\db1\FULL" -ReplaceDbNameInFile
            Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database bigtestrest -Path $backupPath
            $restoreResults2 = Restore-DbaDatabase -SqlInstance $TestConfig.instance1 -Database smalltestrest -Path "$($TestConfig.appveyorlabrepo)\sql2008-backups\db2\FULL\SQL2008_db2_FULL_20170518_041738.bak" -ReplaceDbNameInFile
            Backup-DbaDatabase -SqlInstance $TestConfig.instance1 -Database smalltestrest -Path $backupPath

            $maxSizeResults = Test-DbaLastBackup -SqlInstance $TestConfig.instance1 -Database bigtestrest, smalltestrest -CopyFile -CopyPath c:\temp -MaxSize 5 -Prefix testlast
            $fileResult = Get-ChildItem c:\temp | Where-Object Name -like "*bigtestrest"
        }

        It "Should have skipped bigtestrest and tested smalltestrest" {
            $maxSizeResults[0].RestoreResult | Should -BeLike "*exceeds the specified maximum*"
            $maxSizeResults[0].DbccResult | Should -Be "Skipped"
            $maxSizeResults[1].RestoreResult | Should -Be "Success"
            $maxSizeResults[1].DbccResult | Should -Be "Success"
        }

        It "Should have removed the temp backup copy even if skipped" {
            ($null -eq $fileResult) | Should -Be $true
        }

        AfterAll {
            Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database bigtestrest, smalltestrest | Remove-DbaDatabase -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}