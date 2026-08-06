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

    # This Context has to run before the one that takes a source database offline. Copy-DbaDatabase
    # throws "Cannot index into a null array" building the file structure of an OFFLINE source
    # database, so a whole-instance migration - even a dry run - dies once one exists. Measured on
    # the shipping implementation, so it is upstream behaviour rather than anything this suite can
    # assert around.
    Context "When -WhatIf is supplied" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $whatIfDb = "dbatoolsci_whatif$random"
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Database $whatIfDb -ErrorAction SilentlyContinue

            $splatCreateWhatIfDb = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Query       = "CREATE DATABASE $whatIfDb; ALTER DATABASE $whatIfDb SET AUTO_CLOSE OFF WITH ROLLBACK IMMEDIATE"
            }
            Invoke-DbaQuery @splatCreateWhatIfDb

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $splatWhatIf = @{
                Source        = $TestConfig.InstanceCopy1
                Destination   = $TestConfig.InstanceCopy2
                BackupRestore = $true
                SharedPath    = $backupPath
                Force         = $true
                Exclude       = @(
                    "Logins", "AgentServer", "Credentials", "LinkedServers", "SpConfigure",
                    "CentralManagementServer", "DatabaseMail", "SysDbUserObjects", "SystemTriggers",
                    "BackupDevices", "Audits", "Endpoints", "ExtendedEvents", "PolicyManagement",
                    "ResourceGovernor", "ServerAuditSpecifications", "CustomErrors", "ServerRoles",
                    "DataCollector", "StartupProcedures", "ExtendedStoredProcedures",
                    "AgentServerProperties", "MasterCertificates", "SsisCatalog"
                )
            }
            $null = Start-DbaMigration @splatWhatIf -WhatIf -WarningAction SilentlyContinue
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Database $whatIfDb -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should leave the source database in place" {
            # Positive control: without it, the absence assertion below is satisfied by a fixture
            # that was never created.
            $sourceDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $whatIfDb
            $sourceDb.Name | Should -Be $whatIfDb
        }

        It "Should not create the database on the destination" {
            # Asserted on the side effect, never on What-if text: What-if lines are emitted by the
            # gate that was consulted, not by the copies that were skipped.
            $destDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $whatIfDb
            $destDb | Should -BeNullOrEmpty
        }
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

    Context "When every component is excluded" {
        BeforeAll {
            # Nothing to migrate, so this run reaches the end block in seconds. It is the positive
            # control for the two absence assertions in the next Context: the same verbose lines
            # that must be missing after a validation failure have to be present after a clean run,
            # or their absence proves nothing.
            $everyComponent = @(
                "Databases", "Logins", "AgentServer", "Credentials", "LinkedServers", "SpConfigure",
                "CentralManagementServer", "DatabaseMail", "SysDbUserObjects", "SystemTriggers",
                "BackupDevices", "Audits", "Endpoints", "ExtendedEvents", "PolicyManagement",
                "ResourceGovernor", "ServerAuditSpecifications", "CustomErrors", "ServerRoles",
                "DataCollector", "StartupProcedures", "ExtendedStoredProcedures",
                "AgentServerProperties", "MasterCertificates", "SsisCatalog"
            )
            $splatExcludeAll = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Exclude     = $everyComponent
                Force       = $true
                Verbose     = $true
            }
            $excludeAllVerbose = @(Start-DbaMigration @splatExcludeAll 4>&1) -match "\S"
        }

        It "Should open the normal source connection" {
            @($excludeAllVerbose | Where-Object { $PSItem -like "*Opening or reusing normal connection*" }).Count | Should -BeGreaterThan 0
        }

        It "Should report the migration as complete" {
            @($excludeAllVerbose | Where-Object { $PSItem -like "*SQL Server migration complete.*" }).Count | Should -BeGreaterThan 0
        }
    }

    Context "When a validation guard in the begin block trips" {
        BeforeAll {
            # No migration method and no -Exclude Databases, which is the first begin-block guard.
            $splatNoMethod = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Force       = $true
                Verbose     = $true
            }
            $noMethodVerbose = @(Start-DbaMigration @splatNoMethod -WarningVariable noMethodWarning -WarningAction SilentlyContinue 4>&1) -match "\S"
        }

        It "Should warn that a migration method is required" {
            @($noMethodWarning | Where-Object { $PSItem -like "*must specify a database migration method*" }).Count | Should -BeGreaterThan 0
        }

        It "Should not reach the process block" {
            # The guard latches and the process block opens with Test-FunctionInterrupt, so the
            # source never connects. The latch is set in one scope and read in another, so a port
            # that dropped the carry would connect and migrate here.
            @($noMethodVerbose | Where-Object { $PSItem -like "*Opening or reusing normal connection*" }).Count | Should -Be 0
        }

        It "Should not report the migration as complete" {
            # The end block reads the same latch, and reads it AFTER closing the admin connection.
            @($noMethodVerbose | Where-Object { $PSItem -like "*SQL Server migration complete.*" }).Count | Should -Be 0
        }
    }

    Context "When a dedicated admin connection is needed" {
        BeforeAll {
            # dacNeeded is true unless Credentials, DatabaseMail AND LinkedServers are all excluded.
            # Leaving LinkedServers in opens the admin connection while keeping the run trivial.
            $splatDac = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Exclude     = @(
                    "Databases", "Logins", "AgentServer", "Credentials", "SpConfigure",
                    "CentralManagementServer", "DatabaseMail", "SysDbUserObjects", "SystemTriggers",
                    "BackupDevices", "Audits", "Endpoints", "ExtendedEvents", "PolicyManagement",
                    "ResourceGovernor", "ServerAuditSpecifications", "CustomErrors", "ServerRoles",
                    "DataCollector", "StartupProcedures", "ExtendedStoredProcedures",
                    "AgentServerProperties", "MasterCertificates", "SsisCatalog"
                )
                Force       = $true
                Verbose     = $true
            }
            $dacVerbose = @(Start-DbaMigration @splatDac -WarningAction SilentlyContinue 4>&1) -match "\S"
        }

        It "Should open the dedicated admin connection" {
            # Without this the release assertion below would pass on a run that never opened one.
            @($dacVerbose | Where-Object { $PSItem -like "*Opening dedicated admin connection*" }).Count | Should -BeGreaterThan 0
        }

        It "Should release the dedicated admin connection when the migration ends" {
            # SQL Server allows exactly one DAC session per instance. $dacOpened and the admin
            # connection itself are process-block locals that only the end block reads, so a port
            # that dropped that carry leaves the session open and this connect fails outright.
            $splatSecondDac = @{
                SqlInstance              = $TestConfig.InstanceCopy1
                DedicatedAdminConnection = $true
                EnableException          = $true
            }
            $secondDac = Connect-DbaInstance @splatSecondDac
            $secondDac.Name | Should -BeLike "ADMIN:*"
            $null = $secondDac | Disconnect-DbaInstance -WhatIf:$false
        }
    }

    Context "When resolving the command name in a cold shell" {
        BeforeAll {
            # Every other leg runs in a session that imported dbatools long before Pester started,
            # so none of them can tell the binary cmdlet apart from the retired script function -
            # whichever got there first answers to the name. This leg starts a shell of the same
            # edition that has imported nothing, loads the module the way a consumer does, and asks
            # what the name resolves to. dbatools.psm1 is the import under test on purpose: it is
            # the loader that pulls the satellite in by path, and importing the manifest by name
            # cannot work in a dev tree because the satellites are not on PSModulePath.
            $moduleBase = @(Get-Module -Name dbatools)[0].ModuleBase
            $shellPath = (Get-Process -Id $PID).Path

            # The probe is written and then executed as a script, so it gets a directory of its
            # own rather than a guessable name in shared temp: New-Item -ItemType Directory fails
            # if the name is taken, which makes the create the exclusive step. Otherwise a peer
            # window - or anything else on this box - could win the race between the write and the
            # run and decide what this shell executes.
            $probeRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatoolsci-resolve-$([guid]::NewGuid().ToString("n"))"
            $splatProbeRoot = @{
                Path        = $probeRoot
                ItemType    = "Directory"
                ErrorAction = "Stop"
            }
            $null = New-Item @splatProbeRoot
            $probePath = Join-Path -Path $probeRoot -ChildPath "resolve.ps1"

            # Get-Command -All so a retired function shadowing the cmdlet shows up as a second
            # entry rather than silently winning; the count is what proves it is not there.
            # Start-SqlMigration is reported too: the alias is registered against the command NAME
            # in dbatools.psm1, so it has to keep resolving once the name is a cmdlet.
            $probeBody = @"
Import-Module -Name "$moduleBase\dbatools.psm1" -DisableNameChecking
`$resolved = Get-Command -Name Start-DbaMigration -ErrorAction SilentlyContinue
`$allResolved = @(Get-Command -Name Start-DbaMigration -All -ErrorAction SilentlyContinue)
`$functionCount = @(`$allResolved | Where-Object { `$PSItem.CommandType -eq "Function" }).Count
`$satelliteLoaded = [bool](Get-Module -Name dbatools.migration)
`$aliasTarget = (Get-Command -Name Start-SqlMigration -ErrorAction SilentlyContinue).ResolvedCommand.Name
"RESOLVED|`$(`$resolved.CommandType)|`$(`$resolved.ModuleName)|`$functionCount|`$satelliteLoaded|`$aliasTarget"
"@
            $splatProbeBody = @{
                Path     = $probePath
                Value    = $probeBody
                Encoding = "UTF8"
            }
            Set-Content @splatProbeBody

            # An array splat, not a hashtable one: this is a native executable, and PowerShell
            # renders a splatted hashtable as -key:value pairs, which is not the form -File takes.
            $splatProbeShell = @(
                "-NoProfile"
                "-NonInteractive"
                "-File"
                $probePath
            )
            $probeOutput = & $shellPath @splatProbeShell 2>&1
            $probeFields = @("$(@($probeOutput | Where-Object { "$PSItem" -like "RESOLVED|*" })[0])" -split "\|")
        }

        AfterAll {
            $splatProbeCleanup = @{
                Path        = $probeRoot
                Recurse     = $true
                Force       = $true
                ErrorAction = "SilentlyContinue"
            }
            Remove-Item @splatProbeCleanup
        }

        It "Should resolve to the binary cmdlet shipped by dbatools.migration" {
            $probeFields[1] | Should -Be "Cmdlet"
            $probeFields[2] | Should -Be "dbatools.migration"
        }

        It "Should load the satellite and leave no retired function shadowing the name" {
            $probeFields[4] | Should -Be "True"
            $probeFields[3] | Should -Be "0"
        }

        It "Should keep the Start-SqlMigration alias pointed at the command" {
            $probeFields[5] | Should -Be "Start-DbaMigration"
        }
    }

}