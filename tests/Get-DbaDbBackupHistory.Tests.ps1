#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbBackupHistory",
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
                "IncludeCopyOnly",
                "Force",
                "Since",
                "RecoveryFork",
                "Last",
                "LastFull",
                "LastDiff",
                "LastLog",
                "DeviceType",
                "Raw",
                "LastLsn",
                "Type",
                "EnableException",
                "IncludeMirror",
                "AgCheck",
                "IgnoreDiffBackup",
                "LsnSort"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $DestBackupDir = "$($TestConfig.Temp)\backups"
        if (-Not (Test-Path $DestBackupDir)) {
            New-Item -ItemType Container -Path $DestBackupDir
        }
        $random = Get-Random
        $dbname = "dbatoolsci_history_$random"
        $dbnameForked = "dbatoolsci_history_forked_$random"
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname, $dbnameForked | Remove-DbaDatabase
        $null = Restore-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -DatabaseName $dbname -DestinationFilePrefix $dbname
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $server.Databases["master"].ExecuteNonQuery("CREATE DATABASE $dbnameForked; ALTER DATABASE $dbnameForked SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE")
        $db = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname
        $db | Backup-DbaDatabase -Type Full -BackupDirectory $DestBackupDir
        $db | Backup-DbaDatabase -Type Differential -BackupDirectory $DestBackupDir
        $db | Backup-DbaDatabase -Type Log -BackupDirectory $DestBackupDir
        $db | Backup-DbaDatabase -Type Log -BackupDirectory $DestBackupDir
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database master | Backup-DbaDatabase -Type Full -BackupDirectory $DestBackupDir
        $db | Backup-DbaDatabase -Type Full -BackupDirectory $DestBackupDir -BackupFileName CopyOnly.bak -CopyOnly

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname, $dbnameForked | Remove-DbaDatabase
        Remove-Item -Path $DestBackupDir -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Get last history for single database" {
        BeforeAll {
            $results = Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Last
        }

        It "Should be 4 backups returned" {
            $results.count | Should -Be 4
        }

        It "First backup should be a Full Backup" {
            $results[0].Type | Should -Be "Full"
        }

        It "Duration should be meaningful" {
            ($results[0].end - $results[0].start).TotalSeconds | Should -Be $results[0].Duration.TotalSeconds
        }

        It "Last Backup Should be a log backup" {
            $results[-1].Type | Should -Be "Log"
        }

        It "DatabaseId is returned" {
            $results[0].Database | Should -Be $dbname
            $results[0].DatabaseId | Should -Be $db.Id
        }
    }

    Context "Get last history for all databases" {
        BeforeAll {
            $results = Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle
        }

        It "Should be more than one database" {
            ($results | Where-Object Database -match "master").Count | Should -BeGreaterThan 0
        }
    }

    Context "ExcludeDatabase is honored" {
        It "Should not report about excluded database master" {
            $results = Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase "master"
            ($results | Where-Object Database -match "master").Count | Should -Be 0
        }

        It "Should not report about excluded database master with Type Full" {
            $results = Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase "master" -Type Full
            ($results | Where-Object Database -match "master").Count | Should -Be 0
        }

        It "Should not report about excluded database master with LastFull" {
            $results = Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase "master" -LastFull
            ($results | Where-Object Database -match "master").Count | Should -Be 0
        }
    }

    Context "LastFull should work with multiple databases" {
        BeforeAll {
            $results = Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -Database $dbname, master -lastfull
        }

        It "Should return 2 records" {
            $results.count | Should -Be 2
        }
    }

    Context "Testing IncludeCopyOnly with LastFull" {
        BeforeAll {
            $results = Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -LastFull -Database $dbname
            $resultsCo = Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -LastFull -IncludeCopyOnly -Database $dbname
        }

        It "Should return the CopyOnly Backup" {
            ($resultsCo.BackupSetID -ne $Results.BackupSetID) | Should -Be $True
        }
    }

    Context "Testing IncludeCopyOnly with Last" {
        BeforeAll {
            $resultsCo = Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -Last -IncludeCopyOnly -Database $dbname
        }

        It "Should return just the CopyOnly Full Backup" {
            ($resultsCo | Measure-Object).count | Should -Be 1
        }
    }

    Context "Testing TotalSize regression test for #3517" {
        It "supports large numbers" {
            $historyObject = New-Object Dataplat.Dbatools.Database.BackupHistory
            $server = Connect-DbaInstance $TestConfig.InstanceSingle
            $cast = $server.Query("select cast(1000000000000000 as numeric(20,0)) AS TotalSize")
            $historyObject.TotalSize = $cast.TotalSize
            ($historyObject.TotalSize.Byte) | Should -Be 1000000000000000
        }
    }

    Context "Testing LastFull regression test for #6730" {
        It "gathers the last full even in a forked scenario" {
            $dbname = $dbnameForked
            $database = $server.Databases[$dbname]

            $database.ExecuteNonQuery("CREATE TABLE dbo.test (x char(1000) default 'x')")
            $null = Backup-DbaDatabase -SqlInstance $server -Database $dbname -Type Full -BackupDirectory $DestBackupDir
            1 .. 100 | ForEach-Object -Process { $database.ExecuteNonQuery("INSERT INTO dbo.test DEFAULT VALUES") }
            $null = Backup-DbaDatabase -SqlInstance $server -Database $dbname -Type Full -BackupDirectory $DestBackupDir
            1 .. 1000 | ForEach-Object -Process { $database.ExecuteNonQuery("INSERT INTO dbo.test DEFAULT VALUES") }
            $null = Backup-DbaDatabase -SqlInstance $server -Database $dbname -Type Full -BackupDirectory $DestBackupDir
            1 .. 1000 | ForEach-Object -Process { $database.ExecuteNonQuery("INSERT INTO dbo.test DEFAULT VALUES") }
            $null = Backup-DbaDatabase -SqlInstance $server -Database $dbname -Type Full -BackupDirectory $DestBackupDir
            1 .. 1000 | ForEach-Object -Process { $database.ExecuteNonQuery("INSERT INTO dbo.test DEFAULT VALUES") }
            $null = Backup-DbaDatabase -SqlInstance $server -Database $dbname -Type Full -BackupDirectory $DestBackupDir

            $interResults = Get-DbaDbBackupHistory -SqlInstance $server -Database $dbname | Sort-Object -Property End
            # create a fork restoring from the second backup sorted by date
            $null = $interResults[1] | Restore-DbaDatabase -SqlInstance $server -WithReplace

            #Sleep here because "End" has only second resolution (no ms there).
            #If we're too fast Sort-Object -Property End doesn't always work, as we want $allHistory[0] to be the last backup indeed
            Start-Sleep -Seconds 1

            $null = Backup-DbaDatabase -SqlInstance $server -Database $dbname -Type Full -BackupDirectory $DestBackupDir

            $allHistory = Get-DbaDbBackupHistory -SqlInstance $server -Database $dbname | Sort-Object -Property End -Descending
            $lastFull = Get-DbaDbBackupHistory -SqlInstance $server -Database $dbname -LastFull

            $allHistory[0].End | Should -Be $lastFull.End
            $allHistory[0].LastRecoveryForkGUID | Should -Be $lastFull.LastRecoveryForkGUID
            $allHistory[0].FirstLsn | Should -Be $lastFull.FirstLsn

        }
    }

    Context "Testing IgnoreDiff parameter for #6914" {
        BeforeAll {
            $noIgnore = Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -Database $dbname
            $Ignore = Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -Database $dbname -IgnoreDiffBackup
        }

        It "Should return one less backup" {
            $noIgnore.count - $Ignore.count | Should -Be 1
        }

        It "Should return no Diff backups" {
            ($Ignore | Where-Object Type -like "*diff*").count | Should -Be 0
        }
    }

    Context "Testing the Since parameter" {
        It "DateTime for -Since" {
            $results = Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Since (Get-Date).AddMinutes(-5)
            $results.count | Should -BeGreaterThan 0
        }

        It "TimeSpan for -Since" {
            $results = Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Since (New-TimeSpan -Minutes -5)
            $results.count | Should -BeGreaterThan 0
        }

        It "Invalid type for -Since" {
            $results = Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Since "-" -WarningVariable warning 3> $null
            $results | Should -BeNullOrEmpty
            $warning | Should -BeLike "*-Since must be either a DateTime or TimeSpan object*"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -Database $dbname -EnableException
        }

        It "Returns the documented output type" {
            $result[0] | Should -BeOfType Dataplat.Dbatools.Database.BackupHistory
        }

        It "Has the expected properties added by dbatools" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Database',
                'DatabaseId',
                'UserName',
                'Start',
                'End',
                'Duration',
                'Path',
                'TotalSize',
                'CompressedBackupSize',
                'CompressionRatio',
                'Type',
                'BackupSetId',
                'DeviceType',
                'Software',
                'FullName',
                'FileList',
                'Position',
                'FirstLsn',
                'DatabaseBackupLsn',
                'CheckpointLsn',
                'LastLsn',
                'SoftwareVersionMajor',
                'IsCopyOnly',
                'LastRecoveryForkGuid',
                'RecoveryModel',
                'EncryptorType',
                'EncryptorThumbprint',
                'KeyAlgorithm'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available"
            }
        }
    }

    Context "Output with -Raw" {
        BeforeAll {
            $result = Get-DbaDbBackupHistory -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Raw -EnableException
        }

        It "Returns DataRow when -Raw specified" {
            $result[0] | Should -BeOfType System.Data.DataRow
        }

        It "Includes FullName property" {
            $result[0].PSObject.Properties.Name | Should -Contain 'FullName'
        }
    }
}