#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Start-DbaMigration",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "Destination",
                "DetachAttach",
                "Reattach",
                "BackupRestore",
                "SharedPath",
                "WithReplace",
                "NoRecovery",
                "SetSourceReadOnly",
                "SetSourceOffline",
                "ReuseSourceFolderStructure",
                "IncludeSupportDbs",
                "SourceSqlCredential",
                "DestinationSqlCredential",
                "Exclude",
                "DisableJobsOnDestination",
                "DisableJobsOnSource",
                "ExcludeSaRename",
                "UseLastBackup",
                "KeepCDC",
                "KeepReplication",
                "Continue",
                "Force",
                "AzureCredential",
                "MasterKeyPassword",
                "EnableException"
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
        # To test migration functionality, we need databases on the source instance that can be migrated to the destination.
        # We'll create test databases with unique names to avoid conflicts.

        # Set variables. They are available in all the It blocks.
        $random = Get-Random
        $startmigrationrestoredb = "dbatoolsci_startmigrationrestore$random"
        $startmigrationrestoredb2 = "dbatoolsci_startmigrationrestoreother$random"
        $detachattachdb = "dbatoolsci_detachattach$random"

        # Clean up any existing databases with these names first
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $startmigrationrestoredb, $detachattachdb, $startmigrationrestoredb2 -ErrorAction SilentlyContinue

        # Create the test databases on instance3 first
        $splatInstance3 = @{
            SqlInstance = $TestConfig.instance3
            Query       = "CREATE DATABASE $startmigrationrestoredb2; ALTER DATABASE $startmigrationrestoredb2 SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE"
        }
        Invoke-DbaQuery @splatInstance3

        # Create the test databases on instance2
        $splatInstance2Db1 = @{
            SqlInstance = $TestConfig.instance2
            Query       = "CREATE DATABASE $startmigrationrestoredb; ALTER DATABASE $startmigrationrestoredb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE"
        }
        Invoke-DbaQuery @splatInstance2Db1

        $splatInstance2Db2 = @{
            SqlInstance = $TestConfig.instance2
            Query       = "CREATE DATABASE $detachattachdb; ALTER DATABASE $detachattachdb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE"
        }
        Invoke-DbaQuery @splatInstance2Db2

        $splatInstance2Db3 = @{
            SqlInstance = $TestConfig.instance2
            Query       = "CREATE DATABASE $startmigrationrestoredb2; ALTER DATABASE $startmigrationrestoredb2 SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE"
        }
        Invoke-DbaQuery @splatInstance2Db3

        # Set database owners
        $splatDbOwner = @{
            SqlInstance = $TestConfig.instance2
            Database    = $startmigrationrestoredb, $detachattachdb
            TargetLogin = "sa"
        }
        $null = Set-DbaDbOwner @splatDbOwner

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $startmigrationrestoredb, $detachattachdb, $startmigrationrestoredb2 -ErrorAction SilentlyContinue

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context  "When using backup restore method" {
        BeforeAll {
            $splatMigration = @{
                Force         = $true
                Source        = $TestConfig.instance2
                Destination   = $TestConfig.instance3
                BackupRestore = $true
                SharedPath    = $backupPath
                Exclude       = "Logins", "SpConfigure", "SysDbUserObjects", "AgentServer", "CentralManagementServer", "ExtendedEvents", "PolicyManagement", "ResourceGovernor", "Endpoints", "ServerAuditSpecifications", "Audits", "LinkedServers", "SystemTriggers", "DataCollector", "DatabaseMail", "BackupDevices", "Credentials"
            }
            $migrationResults = Start-DbaMigration @splatMigration
        }

        It "Should return at least one result" {
            $migrationResults | Should -Not -BeNullOrEmpty
        }

        It "Should copy databases successfully" {
            $databaseResults = $migrationResults | Where-Object Type -eq "Database"
            $databaseResults | Should -Not -BeNullOrEmpty
            $successfulResults = $databaseResults | Where-Object Status -eq "Successful"
            $successfulResults | Should -Not -BeNullOrEmpty
        }

        It "Should retain database properties after migration" {
            $sourceDbs = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $startmigrationrestoredb2
            $destDbs = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $startmigrationrestoredb2

            $sourceDbs.Name | Should -Not -BeNullOrEmpty
            $destDbs.Name | Should -Not -BeNullOrEmpty
            # Compare database properties
            $sourceDbs.Name | Should -Be $destDbs.Name
            $sourceDbs.RecoveryModel | Should -Be $destDbs.RecoveryModel
            $sourceDbs.Status | Should -Be $destDbs.Status
            $sourceDbs.Owner | Should -Be $destDbs.Owner
        }
    }

    Context "When using last backup method" {
        BeforeAll {
            # Create backups first
            $backupResults = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Backup-DbaDatabase -BackupDirectory $backupPath

            $splatLastBackup = @{
                Force         = $true
                Source        = $TestConfig.instance2
                Destination   = $TestConfig.instance3
                UseLastBackup = $true
                # Excluding MasterCertificates to avoid this warning: [Copy-DbaDbCertificate] The SQL Server service account (NT Service\MSSQL$SQLINSTANCE2) for CLIENT\SQLInstance2 does not have access to
                Exclude       = "Logins", "SpConfigure", "SysDbUserObjects", "AgentServer", "CentralManagementServer", "ExtendedEvents", "PolicyManagement", "ResourceGovernor", "Endpoints", "ServerAuditSpecifications", "Audits", "LinkedServers", "SystemTriggers", "DataCollector", "DatabaseMail", "BackupDevices", "Credentials", "StartupProcedures", "MasterCertificates"
            }
            $lastBackupResults = Start-DbaMigration @splatLastBackup
        }

        It "Should return at least one result" {
            $lastBackupResults | Should -Not -BeNullOrEmpty
        }

        It "Should copy databases successfully" {
            $databaseResults = $lastBackupResults | Where-Object Type -eq "Database"
            $databaseResults | Should -Not -BeNullOrEmpty
            $successfulResults = $databaseResults | Where-Object Status -eq "Successful"
            $successfulResults | Should -Not -BeNullOrEmpty
        }

        It "Should retain database properties after migration" {
            $sourceDbs = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $startmigrationrestoredb2
            $destDbs = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $startmigrationrestoredb2

            $sourceDbs.Name | Should -Not -BeNullOrEmpty
            $destDbs.Name | Should -Not -BeNullOrEmpty
            # Compare database properties
            $sourceDbs.Name | Should -Be $destDbs.Name
            $sourceDbs.RecoveryModel | Should -Be $destDbs.RecoveryModel
            $sourceDbs.Status | Should -Be $destDbs.Status
            $sourceDbs.Owner | Should -Be $destDbs.Owner
        }
    }

    Context "When using SetSourceOffline parameter" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Create a unique test database for this context
            $random = Get-Random
            $offlineTestDb = "dbatoolsci_offlinetest$random"

            # Clean up any existing database with this name first
            Remove-DbaDatabase -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $offlineTestDb -ErrorAction SilentlyContinue

            # Create the test database on instance2
            $splatOfflineDb = @{
                SqlInstance = $TestConfig.instance2
                Query       = "CREATE DATABASE $offlineTestDb; ALTER DATABASE $offlineTestDb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE"
            }
            Invoke-DbaQuery @splatOfflineDb

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaDatabase -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $offlineTestDb -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should set source database offline before migration and bring destination online" {
            $splatOfflineMigration = @{
                Force            = $true
                Source           = $TestConfig.instance2
                Destination      = $TestConfig.instance3
                BackupRestore    = $true
                SharedPath       = $backupPath
                SetSourceOffline = $true
                Exclude          = "Logins", "SpConfigure", "SysDbUserObjects", "AgentServer", "CentralManagementServer", "ExtendedEvents", "PolicyManagement", "ResourceGovernor", "Endpoints", "ServerAuditSpecifications", "Audits", "LinkedServers", "SystemTriggers", "DataCollector", "DatabaseMail", "BackupDevices", "Credentials"
            }
            $offlineResults = Start-DbaMigration @splatOfflineMigration

            # Verify migration was successful
            $databaseResults = $offlineResults | Where-Object Type -eq "Database"
            $databaseResults | Should -Not -BeNullOrEmpty
            $successfulResults = $databaseResults | Where-Object Status -eq "Successful"
            $successfulResults | Should -Not -BeNullOrEmpty

            # Verify the test database was migrated
            $testDbResult = $databaseResults | Where-Object Name -eq $offlineTestDb
            $testDbResult | Should -Not -BeNullOrEmpty

            # Verify source database is offline
            $sourceDb = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $offlineTestDb
            $sourceDb.Status | Should -BeLike "*Offline*"

            # Verify destination database is online
            $destDb = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $offlineTestDb
            $destDb.Status | Should -Be "Normal"
        }
    }
}