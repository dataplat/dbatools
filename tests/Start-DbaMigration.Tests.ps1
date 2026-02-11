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
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Database $startmigrationrestoredb, $detachattachdb, $startmigrationrestoredb2 -ErrorAction SilentlyContinue

        # Create the test databases on InstanceCopy2 first
        $splatInstanceCopy2 = @{
            SqlInstance = $TestConfig.InstanceCopy2
            Query       = "CREATE DATABASE $startmigrationrestoredb2; ALTER DATABASE $startmigrationrestoredb2 SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE"
        }
        Invoke-DbaQuery @splatInstanceCopy2

        # Create the test databases on InstanceCopy1
        $splatInstanceCopy1Db1 = @{
            SqlInstance = $TestConfig.InstanceCopy1
            Query       = "CREATE DATABASE $startmigrationrestoredb; ALTER DATABASE $startmigrationrestoredb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE"
        }
        Invoke-DbaQuery @splatInstanceCopy1Db1

        $splatInstanceCopy1Db2 = @{
            SqlInstance = $TestConfig.InstanceCopy1
            Query       = "CREATE DATABASE $detachattachdb; ALTER DATABASE $detachattachdb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE"
        }
        Invoke-DbaQuery @splatInstanceCopy1Db2

        $splatInstanceCopy1Db3 = @{
            SqlInstance = $TestConfig.InstanceCopy1
            Query       = "CREATE DATABASE $startmigrationrestoredb2; ALTER DATABASE $startmigrationrestoredb2 SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE"
        }
        Invoke-DbaQuery @splatInstanceCopy1Db3

        # Set database owners
        $splatDbOwner = @{
            SqlInstance = $TestConfig.InstanceCopy1
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
        Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -ExcludeSystem | Remove-DbaDatabase

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context  "When using backup restore method" {
        BeforeAll {
            $splatMigration = @{
                Force         = $true
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
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
            $sourceDbs = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $startmigrationrestoredb2
            $destDbs = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $startmigrationrestoredb2

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
            $backupResults = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -ExcludeSystem | Backup-DbaDatabase -BackupDirectory $backupPath

            $splatLastBackup = @{
                Force         = $true
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                UseLastBackup = $true
                # Excluding MasterCertificates to avoid this warning: [Copy-DbaDbCertificate] The SQL Server service account (NT Service\MSSQL$SQLInstanceCopy1) for CLIENT\SQLInstanceCopy1 does not have access to
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
            $sourceDbs = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $startmigrationrestoredb2
            $destDbs = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $startmigrationrestoredb2

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

            # Create a dedicated database for offline testing
            $offlineTestDb = "dbatoolsci_offline$random"

            # Clean up any existing test database
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Database $offlineTestDb -ErrorAction SilentlyContinue

            # Create test database on source
            $splatCreateOfflineDb = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Query       = "CREATE DATABASE $offlineTestDb; ALTER DATABASE $offlineTestDb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE"
            }
            Invoke-DbaQuery @splatCreateOfflineDb

            # Create a backup so UseLastBackup can find it
            $null = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $offlineTestDb -BackupDirectory $backupPath

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # Run migration with SetSourceOffline
            $splatOfflineMigration = @{
                Source           = $TestConfig.InstanceCopy1
                Destination      = $TestConfig.InstanceCopy2
                BackupRestore    = $true
                UseLastBackup    = $true
                SetSourceOffline = $true
                Force            = $true
                Exclude          = "Logins", "SpConfigure", "SysDbUserObjects", "AgentServer", "CentralManagementServer", "ExtendedEvents", "PolicyManagement", "ResourceGovernor", "Endpoints", "ServerAuditSpecifications", "Audits", "LinkedServers", "SystemTriggers", "DataCollector", "DatabaseMail", "BackupDevices", "Credentials", "StartupProcedures", "MasterCertificates"
            }
            $offlineResults = Start-DbaMigration @splatOfflineMigration
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Bring database back online before cleanup
            Set-DbaDbState -SqlInstance $TestConfig.InstanceCopy1 -Database $offlineTestDb -Online -Force -ErrorAction SilentlyContinue

            # Clean up
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Database $offlineTestDb -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should set source database offline after successful migration" {
            $sourceDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $offlineTestDb
            $sourceDb.Status | Should -BeLike "*Offline*"
        }

        It "Should have destination database online" {
            $destDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $offlineTestDb
            $destDb | Should -Not -BeNullOrEmpty
            $destDb.Status | Should -Be "Normal"
        }
    }

    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputTestDb = "dbatoolsci_outputmigration$(Get-Random)"
            $outputBackupPath = "$($TestConfig.Temp)\$CommandName-output-$(Get-Random)"
            $null = New-Item -Path $outputBackupPath -ItemType Directory

            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Database $outputTestDb -ErrorAction SilentlyContinue

            $splatCreateOutputDb = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Query       = "CREATE DATABASE $outputTestDb; ALTER DATABASE $outputTestDb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE"
            }
            Invoke-DbaQuery @splatCreateOutputDb

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $splatOutputMigration = @{
                Force         = $true
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                BackupRestore = $true
                SharedPath    = $outputBackupPath
                Exclude       = "Logins", "SpConfigure", "SysDbUserObjects", "AgentServer", "CentralManagementServer", "ExtendedEvents", "PolicyManagement", "ResourceGovernor", "Endpoints", "ServerAuditSpecifications", "Audits", "LinkedServers", "SystemTriggers", "DataCollector", "DatabaseMail", "BackupDevices", "Credentials", "StartupProcedures", "MasterCertificates"
            }
            $outputResult = Start-DbaMigration @splatOutputMigration
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Database $outputTestDb -ErrorAction SilentlyContinue
            Remove-Item -Path $outputBackupPath -Recurse -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns output of the expected type" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $outputResult[0].psobject.TypeNames | Should -Contain "dbatools.MigrationObject"
        }

        It "Has the expected default display properties" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}