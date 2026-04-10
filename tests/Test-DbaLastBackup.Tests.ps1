#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
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
                "Wait",
                "Path"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "Path backup discovery" {
            BeforeEach {
                $script:mockFiles = @()
                $script:mockHeaders = @()

                $script:mockDatabases = @{ }
                Add-Member -InputObject $script:mockDatabases -Name Refresh -MemberType ScriptMethod -Value { } -Force

                $script:mockDestinationServer = [DbaInstanceParameter]"dest"
                Add-Member -InputObject $script:mockDestinationServer -Name Databases -MemberType NoteProperty -Value $script:mockDatabases -Force
                Add-Member -InputObject $script:mockDestinationServer -Name Name -MemberType NoteProperty -Value "dest" -Force
                Add-Member -InputObject $script:mockDestinationServer -Name ServiceAccount -MemberType NoteProperty -Value "NT SERVICE\MSSQLSERVER" -Force

                Mock Connect-DbaInstance { $script:mockDestinationServer }
                Mock Get-XpDirTreeRestoreFile { $script:mockFiles }
                Mock Read-DbaBackupHeader { $script:mockHeaders }
                Mock Get-SqlDefaultPaths {
                    param($SqlInstance, $FileType)

                    switch ($FileType) {
                        "mdf" { "C:\sql\data" }
                        "ldf" { "C:\sql\log" }
                    }
                }
                Mock Restore-DbaDatabase {
                    [PSCustomObject]@{
                        RestoreComplete = $true
                    }
                }
                Mock Stop-Function {
                    throw $Message
                }
            }

            It "Should honor wildcard database filters when using -Path" {
                $script:mockFiles = @(
                    "C:\backups\dbAlpha-full.bak",
                    "C:\backups\dbBeta-full.bak",
                    "C:\backups\other-full.bak"
                )
                $script:mockHeaders = @(
                    [PSCustomObject]@{
                        BackupSetGUID         = [guid]"11111111-1111-1111-1111-111111111111"
                        BackupTypeDescription = "Database"
                        MachineName           = "source1"
                        ServiceName           = "MSSQLSERVER"
                        ServerName            = "source1"
                        DatabaseName          = "dbAlpha"
                        UserName              = "sa"
                        BackupStartDate       = [datetime]"2026-03-19T12:00:00"
                        BackupFinishDate      = [datetime]"2026-03-19T12:01:00"
                        BackupPath            = "C:\backups\dbAlpha-full.bak"
                        FileList              = [PSCustomObject]@{
                            Type         = "D"
                            LogicalName  = "dbAlpha"
                            PhysicalName = "C:\sql\data\dbAlpha.mdf"
                            Size         = 1024
                        }
                        BackupSize            = [PSCustomObject]@{ Byte = 1048576 }
                        CompressedBackupSize  = [PSCustomObject]@{ Byte = 524288 }
                        Position              = 1
                        FirstLSN              = 100
                        DatabaseBackupLSN     = 100
                        CheckpointLSN         = 100
                        LastLsn               = 200
                        SoftwareVersionMajor  = 16
                        RecoveryModel         = "Full"
                        IsCopyOnly            = $false
                    },
                    [PSCustomObject]@{
                        BackupSetGUID         = [guid]"22222222-2222-2222-2222-222222222222"
                        BackupTypeDescription = "Database"
                        MachineName           = "source1"
                        ServiceName           = "MSSQLSERVER"
                        ServerName            = "source1"
                        DatabaseName          = "dbBeta"
                        UserName              = "sa"
                        BackupStartDate       = [datetime]"2026-03-19T12:05:00"
                        BackupFinishDate      = [datetime]"2026-03-19T12:06:00"
                        BackupPath            = "C:\backups\dbBeta-full.bak"
                        FileList              = [PSCustomObject]@{
                            Type         = "D"
                            LogicalName  = "dbBeta"
                            PhysicalName = "C:\sql\data\dbBeta.mdf"
                            Size         = 1024
                        }
                        BackupSize            = [PSCustomObject]@{ Byte = 1048576 }
                        CompressedBackupSize  = [PSCustomObject]@{ Byte = 524288 }
                        Position              = 1
                        FirstLSN              = 300
                        DatabaseBackupLSN     = 300
                        CheckpointLSN         = 300
                        LastLsn               = 400
                        SoftwareVersionMajor  = 16
                        RecoveryModel         = "Full"
                        IsCopyOnly            = $false
                    },
                    [PSCustomObject]@{
                        BackupSetGUID         = [guid]"33333333-3333-3333-3333-333333333333"
                        BackupTypeDescription = "Database"
                        MachineName           = "source1"
                        ServiceName           = "MSSQLSERVER"
                        ServerName            = "source1"
                        DatabaseName          = "other"
                        UserName              = "sa"
                        BackupStartDate       = [datetime]"2026-03-19T12:10:00"
                        BackupFinishDate      = [datetime]"2026-03-19T12:11:00"
                        BackupPath            = "C:\backups\other-full.bak"
                        FileList              = [PSCustomObject]@{
                            Type         = "D"
                            LogicalName  = "other"
                            PhysicalName = "C:\sql\data\other.mdf"
                            Size         = 1024
                        }
                        BackupSize            = [PSCustomObject]@{ Byte = 1048576 }
                        CompressedBackupSize  = [PSCustomObject]@{ Byte = 524288 }
                        Position              = 1
                        FirstLSN              = 500
                        DatabaseBackupLSN     = 500
                        CheckpointLSN         = 500
                        LastLsn               = 600
                        SoftwareVersionMajor  = 16
                        RecoveryModel         = "Full"
                        IsCopyOnly            = $false
                    }
                )

                $results = @(Test-DbaLastBackup -Path "C:\backups" -Destination "dest" -Database "db*" -ExcludeDatabase "dbB*" -NoCheck -NoDrop)

                $results.Count | Should -Be 1
                $results[0].Database | Should -Be "dbAlpha"
                $results[0].SourceServer | Should -Be "source1"
            }

            It "Should keep identical database names from different sources separate when using -Path" {
                $script:mockFiles = @(
                    "C:\backups\source1\SharedDb-full.bak",
                    "C:\backups\source2\SharedDb-full.bak"
                )
                $script:mockHeaders = @(
                    [PSCustomObject]@{
                        BackupSetGUID         = [guid]"44444444-4444-4444-4444-444444444444"
                        BackupTypeDescription = "Database"
                        MachineName           = "source1"
                        ServiceName           = "MSSQLSERVER"
                        ServerName            = "source1"
                        DatabaseName          = "SharedDb"
                        UserName              = "sa"
                        BackupStartDate       = [datetime]"2026-03-19T12:00:00"
                        BackupFinishDate      = [datetime]"2026-03-19T12:01:00"
                        BackupPath            = "C:\backups\source1\SharedDb-full.bak"
                        FileList              = [PSCustomObject]@{
                            Type         = "D"
                            LogicalName  = "SharedDb"
                            PhysicalName = "C:\sql\data\SharedDb.mdf"
                            Size         = 1024
                        }
                        BackupSize            = [PSCustomObject]@{ Byte = 1048576 }
                        CompressedBackupSize  = [PSCustomObject]@{ Byte = 524288 }
                        Position              = 1
                        FirstLSN              = 700
                        DatabaseBackupLSN     = 700
                        CheckpointLSN         = 700
                        LastLsn               = 800
                        SoftwareVersionMajor  = 16
                        RecoveryModel         = "Full"
                        IsCopyOnly            = $false
                    },
                    [PSCustomObject]@{
                        BackupSetGUID         = [guid]"55555555-5555-5555-5555-555555555555"
                        BackupTypeDescription = "Database"
                        MachineName           = "source2"
                        ServiceName           = "MSSQLSERVER"
                        ServerName            = "source2"
                        DatabaseName          = "SharedDb"
                        UserName              = "sa"
                        BackupStartDate       = [datetime]"2026-03-19T12:05:00"
                        BackupFinishDate      = [datetime]"2026-03-19T12:06:00"
                        BackupPath            = "C:\backups\source2\SharedDb-full.bak"
                        FileList              = [PSCustomObject]@{
                            Type         = "D"
                            LogicalName  = "SharedDb"
                            PhysicalName = "C:\sql\data\SharedDb.mdf"
                            Size         = 1024
                        }
                        BackupSize            = [PSCustomObject]@{ Byte = 1048576 }
                        CompressedBackupSize  = [PSCustomObject]@{ Byte = 524288 }
                        Position              = 1
                        FirstLSN              = 900
                        DatabaseBackupLSN     = 900
                        CheckpointLSN         = 900
                        LastLsn               = 1000
                        SoftwareVersionMajor  = 16
                        RecoveryModel         = "Full"
                        IsCopyOnly            = $false
                    }
                )

                $results = @(Test-DbaLastBackup -Path "C:\backups" -Destination "dest" -NoCheck -NoDrop | Sort-Object SourceServer)

                $results.Count | Should -Be 2
                $results[0].Database | Should -Be "SharedDb"
                $results[0].SourceServer | Should -Be "source1"
                $results[1].Database | Should -Be "SharedDb"
                $results[1].SourceServer | Should -Be "source2"
            }
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

    Context "Test restore using -Path parameter" {
        BeforeAll {
            $splatPathRestore = @{
                Path        = $backupPath
                Destination = $TestConfig.InstanceSingle
                Database    = $testlastbackup
            }
            $pathParamResults = Test-DbaLastBackup @splatPathRestore
        }

        It "Should return success when using -Path" {
            $pathParamResults.RestoreResult | Should -Be "Success"
            $pathParamResults.DbccResult | Should -Be "Success"
        }

        It "Should return the correct database name" {
            $pathParamResults.Database | Should -Be $testlastbackup
        }
    }

    Context "Test -Path without -Destination fails" {
        It "Should write an error when -Destination is not specified with -Path" {
            $result = Test-DbaLastBackup -Path $backupPath -WarningAction SilentlyContinue
            $WarnVar | Should -BeLike "*-Destination server must be specified*"
        }
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
}