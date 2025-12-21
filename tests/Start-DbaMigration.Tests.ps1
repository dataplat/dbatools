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

        # Always use SQL Server's default backup directory to ensure the service account has access
        # This works for both Linux (Docker) and Windows environments
        $backupPath = (Get-DbaDefaultPath -SqlInstance $TestConfig.instance2).Backup

        # Explain what needs to be set up for the test:
        # To test migration functionality, we need databases on the source instance that can be migrated to the destination.
        # We'll create test databases with unique names to avoid conflicts.

        # Set variables. They are available in all the It blocks.
        $random = Get-Random
        $startmigrationrestoredb = "dbatoolsci_startmigrationrestore$random"
        $startmigrationrestoredb2 = "dbatoolsci_startmigrationrestoreother$random"
        $detachattachdb = "dbatoolsci_detachattach$random"
        $offlineTestDb = "dbatoolsci_offlinetest$random"

        # Clean up any existing databases with these names first
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $startmigrationrestoredb, $detachattachdb, $startmigrationrestoredb2, $offlineTestDb -ErrorAction SilentlyContinue

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

        $splatInstance2OfflineDb = @{
            SqlInstance = $TestConfig.instance2
            Query       = "CREATE DATABASE $offlineTestDb; ALTER DATABASE $offlineTestDb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE"
        }
        Invoke-DbaQuery @splatInstance2OfflineDb

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
        # First bring offline databases back online so they can be dropped
        Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $offlineTestDb -Online -Force -ErrorAction SilentlyContinue
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $startmigrationrestoredb, $detachattachdb, $startmigrationrestoredb2, $offlineTestDb -ErrorAction SilentlyContinue

        # Note: We don't delete the backup path since we use SQL Server's default backup directory

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When using SetSourceOffline parameter" {
        BeforeAll {
            $splatOfflineMigration = @{
                Force            = $true
                Source           = $TestConfig.instance2
                Destination      = $TestConfig.instance3
                BackupRestore    = $true
                SharedPath       = $backupPath
                SetSourceOffline = $true
                Exclude          = "Logins", "SpConfigure", "SysDbUserObjects", "AgentServer", "CentralManagementServer", "ExtendedEvents", "PolicyManagement", "ResourceGovernor", "Endpoints", "ServerAuditSpecifications", "Audits", "LinkedServers", "SystemTriggers", "DataCollector", "DatabaseMail", "BackupDevices", "Credentials", "StartupProcedures", "MasterCertificates"
            }
            $results = Start-DbaMigration @splatOfflineMigration
        }

        AfterAll {
            # Bring databases back online for subsequent tests
            $databasesToRestore = @($startmigrationrestoredb, $startmigrationrestoredb2, $detachattachdb, $offlineTestDb)
            Set-DbaDbState -SqlInstance $TestConfig.instance2 -Database $databasesToRestore -Online -Force -ErrorAction SilentlyContinue
        }

        It "Should return at least one result" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should copy databases successfully" {
            $databaseResults = $results | Where-Object Type -eq "Database"
            $databaseResults | Should -Not -BeNullOrEmpty
            $successfulResults = $databaseResults | Where-Object Status -eq "Successful"
            $successfulResults | Should -Not -BeNullOrEmpty
        }

        It "Should set source databases offline after migration" {
            $sourceDb = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $offlineTestDb
            $sourceDb.Status | Should -Match "Offline"
        }

        It "Should have databases online on destination" {
            $destDb = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $offlineTestDb
            $destDb | Should -Not -BeNullOrEmpty
            $destDb.Status | Should -Be "Normal"
        }
    }

    Context "When using backup restore method" {
        BeforeAll {
            $splatMigration = @{
                Force         = $true
                Source        = $TestConfig.instance2
                Destination   = $TestConfig.instance3
                BackupRestore = $true
                SharedPath    = $backupPath
                Exclude       = "Logins", "SpConfigure", "SysDbUserObjects", "AgentServer", "CentralManagementServer", "ExtendedEvents", "PolicyManagement", "ResourceGovernor", "Endpoints", "ServerAuditSpecifications", "Audits", "LinkedServers", "SystemTriggers", "DataCollector", "DatabaseMail", "BackupDevices", "Credentials", "StartupProcedures", "MasterCertificates"
            }
            $results = Start-DbaMigration @splatMigration
        }

        It "Should return at least one result" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should copy databases successfully" {
            $databaseResults = $results | Where-Object Type -eq "Database"
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
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -ExcludeSystem | Backup-DbaDatabase -BackupDirectory $backupPath

            $splatLastBackup = @{
                Force         = $true
                Source        = $TestConfig.instance2
                Destination   = $TestConfig.instance3
                UseLastBackup = $true
                # Excluding MasterCertificates to avoid this warning: [Copy-DbaDbCertificate] The SQL Server service account (NT Service\MSSQL$SQLINSTANCE2) for CLIENT\SQLInstance2 does not have access to
                Exclude       = "Logins", "SpConfigure", "SysDbUserObjects", "AgentServer", "CentralManagementServer", "ExtendedEvents", "PolicyManagement", "ResourceGovernor", "Endpoints", "ServerAuditSpecifications", "Audits", "LinkedServers", "SystemTriggers", "DataCollector", "DatabaseMail", "BackupDevices", "Credentials", "StartupProcedures", "MasterCertificates"
            }
            $results = Start-DbaMigration @splatLastBackup
        }

        It "Should return at least one result" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should copy databases successfully" {
            $databaseResults = $results | Where-Object Type -eq "Database"
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
}
