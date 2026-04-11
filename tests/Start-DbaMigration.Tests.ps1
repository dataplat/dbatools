#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
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
                "Credential",
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
                "ExcludePassword",
                "Force",
                "AzureCredential",
                "MasterKeyPassword",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Dedicated admin connection handling" {
        It "Stops before copying credentials when the dedicated admin connection cannot be opened" {
            InModuleScope dbatools {
                $functionNames = @(
                    "Connect-DbaInstance",
                    "Copy-DbaCredential",
                    "Disconnect-DbaInstance",
                    "Stop-Function",
                    "Test-FunctionInterrupt",
                    "Write-Message",
                    "Write-ProgressHelper"
                )
                $originalFunctions = @{ }
                foreach ($functionName in $functionNames) {
                    if (Test-Path "Function:\$functionName") {
                        $originalFunctions[$functionName] = (Get-Item -Path "Function:\$functionName").ScriptBlock
                    }
                }

                try {
                    function Test-FunctionInterrupt { $false }
                    function Write-Message { }
                    function Write-ProgressHelper { }
                    function Disconnect-DbaInstance { }
                    function Stop-Function {
                        param(
                            $Message
                        )
                        $script:stopMessages += $Message
                    }
                    function Copy-DbaCredential { $script:credentialCopied = $true }
                    function Connect-DbaInstance {
                        param(
                            $SqlInstance,
                            $SqlCredential,
                            [switch]$DedicatedAdminConnection
                        )

                        if ($DedicatedAdminConnection) {
                            $script:connectCalls += "Dac"
                            return $null
                        }

                        $script:connectCalls += "Normal"
                        [PSCustomObject]@{
                            DomainInstanceName = "sql1"
                        }
                    }

                    $script:connectCalls = @()
                    $script:stopMessages = @()
                    $script:credentialCopied = $false
                    $excludeForCredentialOnly = @(
                        "Databases",
                        "Logins",
                        "AgentServer",
                        "LinkedServers",
                        "SpConfigure",
                        "CentralManagementServer",
                        "DatabaseMail",
                        "SysDbUserObjects",
                        "SystemTriggers",
                        "BackupDevices",
                        "Audits",
                        "Endpoints",
                        "ExtendedEvents",
                        "PolicyManagement",
                        "ResourceGovernor",
                        "ServerAuditSpecifications",
                        "CustomErrors",
                        "ServerRoles",
                        "DataCollector",
                        "StartupProcedures",
                        "ExtendedStoredProcedures",
                        "AgentServerProperties",
                        "MasterCertificates",
                        "SsisCatalog"
                    )

                    $null = Start-DbaMigration -Source "sql1" -Destination "sql2" -Exclude $excludeForCredentialOnly
                    ($script:stopMessages -join ",") | Should -Be "Could not establish dedicated admin connection to sql1. Use -ExcludePassword to skip password migration."
                    ($script:connectCalls -join ",") | Should -Be "Dac"
                    $script:credentialCopied | Should -BeFalse
                } finally {
                    foreach ($functionName in $functionNames) {
                        if ($originalFunctions.ContainsKey($functionName)) {
                            Set-Item -Path "Function:\$functionName" -Value $originalFunctions[$functionName]
                        } else {
                            Remove-Item -Path "Function:\$functionName" -ErrorAction Ignore
                        }
                    }
                }
            }
        }

        It "Stops before copying credentials when the normal source connection cannot be opened" {
            InModuleScope dbatools {
                $functionNames = @(
                    "Connect-DbaInstance",
                    "Copy-DbaCredential",
                    "Disconnect-DbaInstance",
                    "Stop-Function",
                    "Test-FunctionInterrupt",
                    "Write-Message",
                    "Write-ProgressHelper"
                )
                $originalFunctions = @{ }
                foreach ($functionName in $functionNames) {
                    if (Test-Path "Function:\$functionName") {
                        $originalFunctions[$functionName] = (Get-Item -Path "Function:\$functionName").ScriptBlock
                    }
                }

                try {
                    function Test-FunctionInterrupt { $false }
                    function Write-Message { }
                    function Write-ProgressHelper { }
                    function Disconnect-DbaInstance { }
                    function Stop-Function {
                        param(
                            $Message
                        )
                        $script:stopMessages += $Message
                    }
                    function Copy-DbaCredential { $script:credentialCopied = $true }
                    function Connect-DbaInstance {
                        param(
                            $SqlInstance,
                            $SqlCredential,
                            [switch]$DedicatedAdminConnection
                        )

                        if ($DedicatedAdminConnection) {
                            $script:connectCalls += "Dac"
                        } else {
                            $script:connectCalls += "Normal"
                        }

                        return $null
                    }

                    $script:connectCalls = @()
                    $script:stopMessages = @()
                    $script:credentialCopied = $false
                    $excludeForCredentialOnly = @(
                        "Databases",
                        "Logins",
                        "AgentServer",
                        "LinkedServers",
                        "SpConfigure",
                        "CentralManagementServer",
                        "DatabaseMail",
                        "SysDbUserObjects",
                        "SystemTriggers",
                        "BackupDevices",
                        "Audits",
                        "Endpoints",
                        "ExtendedEvents",
                        "PolicyManagement",
                        "ResourceGovernor",
                        "ServerAuditSpecifications",
                        "CustomErrors",
                        "ServerRoles",
                        "DataCollector",
                        "StartupProcedures",
                        "ExtendedStoredProcedures",
                        "AgentServerProperties",
                        "MasterCertificates",
                        "SsisCatalog"
                    )

                    $null = Start-DbaMigration -Source "sql1" -Destination "sql2" -Exclude $excludeForCredentialOnly -ExcludePassword
                    ($script:stopMessages -join ",") | Should -Be "Could not connect to source instance sql1."
                    ($script:connectCalls -join ",") | Should -Be "Normal"
                    $script:credentialCopied | Should -BeFalse
                } finally {
                    foreach ($functionName in $functionNames) {
                        if ($originalFunctions.ContainsKey($functionName)) {
                            Set-Item -Path "Function:\$functionName" -Value $originalFunctions[$functionName]
                        } else {
                            Remove-Item -Path "Function:\$functionName" -ErrorAction Ignore
                        }
                    }
                }
            }
        }
    }

    Context "SSIS catalog integration" {
        It "Skips SSIS catalog migration when the source instance has no SSISDB catalog" {
            InModuleScope dbatools {
                $functionNames = @(
                    "Connect-DbaInstance",
                    "Copy-DbaSsisCatalog",
                    "Stop-Function",
                    "Test-FunctionInterrupt",
                    "Write-Message",
                    "Write-ProgressHelper"
                )
                $originalFunctions = @{ }
                foreach ($functionName in $functionNames) {
                    if (Test-Path "Function:\$functionName") {
                        $originalFunctions[$functionName] = (Get-Item -Path "Function:\$functionName").ScriptBlock
                    }
                }

                try {
                    function Test-FunctionInterrupt { $false }
                    function Write-ProgressHelper { }
                    function Stop-Function {
                        param(
                            $Message
                        )
                        $script:stopMessages += $Message
                    }
                    function Write-Message {
                        param(
                            $Level,
                            $Message
                        )
                        $script:messages += "${Level}:$Message"
                    }
                    function Copy-DbaSsisCatalog { $script:ssisCopied = $true }
                    function Connect-DbaInstance {
                        param(
                            $SqlInstance,
                            $SqlCredential,
                            [switch]$DedicatedAdminConnection
                        )

                        if ($DedicatedAdminConnection) {
                            throw "Dedicated admin connection should not be requested."
                        }

                        [PSCustomObject]@{
                            DomainInstanceName = "sql1"
                            VersionMajor       = 10
                            Databases          = @{ }
                        }
                    }

                    $script:messages = @()
                    $script:ssisCopied = $false
                    $script:stopMessages = @()
                    $excludeForSsisOnly = @(
                        "Databases",
                        "Logins",
                        "AgentServer",
                        "Credentials",
                        "LinkedServers",
                        "SpConfigure",
                        "CentralManagementServer",
                        "DatabaseMail",
                        "SysDbUserObjects",
                        "SystemTriggers",
                        "BackupDevices",
                        "Audits",
                        "Endpoints",
                        "ExtendedEvents",
                        "PolicyManagement",
                        "ResourceGovernor",
                        "ServerAuditSpecifications",
                        "CustomErrors",
                        "ServerRoles",
                        "DataCollector",
                        "StartupProcedures",
                        "ExtendedStoredProcedures",
                        "AgentServerProperties",
                        "MasterCertificates"
                    )

                    $null = Start-DbaMigration -Source "sql1" -Destination "sql2" -Exclude $excludeForSsisOnly
                    $script:ssisCopied | Should -BeFalse
                    $script:stopMessages | Should -BeNullOrEmpty
                    @($script:messages | Where-Object { $PSItem -like "*Skipping SSIS catalog migration*" }).Count | Should -Be 1
                } finally {
                    foreach ($functionName in $functionNames) {
                        if ($originalFunctions.ContainsKey($functionName)) {
                            Set-Item -Path "Function:\$functionName" -Value $originalFunctions[$functionName]
                        } else {
                            Remove-Item -Path "Function:\$functionName" -ErrorAction Ignore
                        }
                    }
                }
            }
        }

        It "Calls Copy-DbaSsisCatalog when the source instance has an SSISDB catalog" {
            InModuleScope dbatools {
                $functionNames = @(
                    "Connect-DbaInstance",
                    "Copy-DbaSsisCatalog",
                    "Stop-Function",
                    "Test-FunctionInterrupt",
                    "Write-Message",
                    "Write-ProgressHelper"
                )
                $originalFunctions = @{ }
                foreach ($functionName in $functionNames) {
                    if (Test-Path "Function:\$functionName") {
                        $originalFunctions[$functionName] = (Get-Item -Path "Function:\$functionName").ScriptBlock
                    }
                }

                try {
                    function Test-FunctionInterrupt { $false }
                    function Write-ProgressHelper { }
                    function Stop-Function {
                        param(
                            $Message
                        )
                        $script:stopMessages += $Message
                    }
                    function Write-Message {
                        param(
                            $Level,
                            $Message
                        )
                        $script:messages += "${Level}:$Message"
                    }
                    function Copy-DbaSsisCatalog {
                        param(
                            $Source,
                            $Destination,
                            $DestinationSqlCredential,
                            [switch]$Force
                        )

                        $script:ssisCalls += [PSCustomObject]@{
                            Source                   = $Source
                            Destination              = $Destination
                            DestinationSqlCredential = $DestinationSqlCredential
                            Force                    = $Force.IsPresent
                        }
                    }
                    function Connect-DbaInstance {
                        param(
                            $SqlInstance,
                            $SqlCredential,
                            [switch]$DedicatedAdminConnection
                        )

                        if ($DedicatedAdminConnection) {
                            throw "Dedicated admin connection should not be requested."
                        }

                        [PSCustomObject]@{
                            DomainInstanceName = "sql1"
                            VersionMajor       = 15
                            Databases          = @{
                                SSISDB = [PSCustomObject]@{
                                    Name = "SSISDB"
                                }
                            }
                        }
                    }

                    $script:messages = @()
                    $script:ssisCalls = @()
                    $script:stopMessages = @()
                    $excludeForSsisOnly = @(
                        "Databases",
                        "Logins",
                        "AgentServer",
                        "Credentials",
                        "LinkedServers",
                        "SpConfigure",
                        "CentralManagementServer",
                        "DatabaseMail",
                        "SysDbUserObjects",
                        "SystemTriggers",
                        "BackupDevices",
                        "Audits",
                        "Endpoints",
                        "ExtendedEvents",
                        "PolicyManagement",
                        "ResourceGovernor",
                        "ServerAuditSpecifications",
                        "CustomErrors",
                        "ServerRoles",
                        "DataCollector",
                        "StartupProcedures",
                        "ExtendedStoredProcedures",
                        "AgentServerProperties",
                        "MasterCertificates"
                    )

                    $null = Start-DbaMigration -Source "sql1" -Destination "sql2" -Exclude $excludeForSsisOnly
                    $script:stopMessages | Should -BeNullOrEmpty
                    @($script:ssisCalls).Count | Should -Be 1
                    $script:ssisCalls[0].Source.VersionMajor | Should -Be 15
                    $script:ssisCalls[0].Destination | Should -Be "sql2"
                    @($script:messages | Where-Object { $PSItem -like "*Migrating SSIS catalog" }).Count | Should -Be 1
                } finally {
                    foreach ($functionName in $functionNames) {
                        if ($originalFunctions.ContainsKey($functionName)) {
                            Set-Item -Path "Function:\$functionName" -Value $originalFunctions[$functionName]
                        } else {
                            Remove-Item -Path "Function:\$functionName" -ErrorAction Ignore
                        }
                    }
                }
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
}