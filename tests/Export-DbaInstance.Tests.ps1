#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaInstance",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Credential",
                "Path",
                "NoRecovery",
                "AzureCredential",
                "IncludeDbMasterKey",
                "Exclude",
                "BatchSeparator",
                "ScriptingOption",
                "NoPrefix",
                "ExcludePassword",
                "Force",
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
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $exportPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $exportPath -ItemType Directory

        # Explain what needs to be set up for the test:
        # We need to set up various SQL Server objects to test the export functionality

        # Set variables. They are available in all the It blocks.
        $random                  = Get-Random
        $dbName                  = "dbatoolsci_$random"
        $testServer              = $TestConfig.instance2
        $server                  = Connect-DbaInstance -SqlInstance $testServer
        $srvName                 = "dbatoolsci-server1"
        $group                   = "dbatoolsci-group1"
        $regSrvName              = "dbatoolsci-server12"
        $regSrvDesc              = "dbatoolsci-server123"
        $policyConditionId       = $null
        $objectSetId             = $null
        $policyId                = $null
        $backupdir               = Join-Path $server.BackupDirectory $dbName
        $resultsToCleanup        = @()

        # Create the objects.

        # registered server and group
        $newGroup = Add-DbaRegServerGroup -SqlInstance $testServer -Name $group
        $newServer = Add-DbaRegServer -SqlInstance $testServer -ServerName $srvName -Name $regSrvName -Description $regSrvDesc

        # custom error message
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_addmessage 250000, 16, N'Sample error message1'"
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_addmessage 250001, 16, N'Sample error message2'"

        # credentials
        $splatCred1 = @{
            SqlInstance     = $testServer
            Name            = "dbatools1$random"
            Identity        = "dbatools1$random"
            SecurePassword  = (ConvertTo-SecureString -String "dbatools1" -AsPlainText -Force)
            Confirm         = $false
        }
        New-DbaCredential @splatCred1

        $splatCred2 = @{
            SqlInstance     = $testServer
            Name            = "dbatools2$random"
            Identity        = "dbatools2$random"
            SecurePassword  = (ConvertTo-SecureString -String "dbatools2" -AsPlainText -Force)
            Confirm         = $false
        }
        New-DbaCredential @splatCred2

        # logins
        $splatLogin = @{
            SqlInstance     = $testServer
            Login           = "dbatools$random"
            SecurePassword  = (ConvertTo-SecureString -String "dbatools1" -AsPlainText -Force)
            Confirm         = $false
        }
        New-DbaLogin @splatLogin

        # backup device
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_addumpdevice 'disk', 'backupdevice$random', 'c:\temp\backupdevice$random.bak'"

        # linked server
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_addlinkedserver @server = N'server$random', @srvproduct=N'SQL Server'"

        # system trigger
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "CREATE TRIGGER [create_database_$random] ON ALL SERVER FOR CREATE_DATABASE AS SELECT 1"

        # database restore scripts
        if (-not (Test-Path $backupdir -PathType Container)) {
            $null = New-Item -Path $backupdir -ItemType Container
        }
        New-DbaDatabase -SqlInstance $testServer -Name $dbName
        Backup-DbaDatabase -SqlInstance $testServer -Database $dbName -BackupDirectory $backupdir

        # server audit and spec
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "CREATE SERVER AUDIT [Audit_$random] TO FILE (FILEPATH = N'c:\temp', MAXSIZE = 8 MB, MAX_ROLLOVER_FILES = 2, RESERVE_DISK_SPACE = OFF) WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE)"

        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "CREATE SERVER AUDIT SPECIFICATION [Audit_Specification_$random] FOR SERVER AUDIT [Audit_$random] ADD (FAILED_LOGIN_GROUP) WITH (STATE=ON)"

        # database audit
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database $dbName -Query "CREATE DATABASE AUDIT SPECIFICATION [DatabaseAuditSpecification_$random] FOR SERVER AUDIT [Audit_$random] ADD (DELETE ON DATABASE::[$dbName] BY [public])"

        # endpoint
        New-DbaEndpoint -SqlInstance $testServer -Type DatabaseMirroring -Name "dbatoolsci_$random"

        # policies
        $output = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "Declare @condition_id int;
                                                                                    EXEC msdb.dbo.sp_syspolicy_add_condition @name=N'dbatoolsci_condition_$random', @description=N'dbatools_test', @facet=N'Database', @expression=N'<Operator>
                                                                                      <TypeClass>Bool</TypeClass>
                                                                                      <OpType>GE</OpType>
                                                                                      <Count>2</Count>
                                                                                      <Attribute>
                                                                                        <TypeClass>Numeric</TypeClass>
                                                                                        <Name>SpaceAvailable</Name>
                                                                                      </Attribute>
                                                                                      <Constant>
                                                                                        <TypeClass>Numeric</TypeClass>
                                                                                        <ObjType>System.Double</ObjType>
                                                                                        <Value>0</Value>
                                                                                      </Constant>
                                                                                    </Operator>', @is_name_condition=0, @obj_name=N'', @condition_id=@condition_id OUTPUT;
                                                                                    Select @condition_id AS ConditionId;"

        $policyConditionId = $output.ConditionId

        $output = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "Declare @object_set_id int;
                                                                                    EXEC msdb.dbo.sp_syspolicy_add_object_set @object_set_name=N'dbatoolsci_$random', @facet=N'Database', @object_set_id=@object_set_id OUTPUT;
                                                                                    Select @object_set_id AS ObjectSetId;"

        $objectSetId = $output.ObjectSetId

        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "Declare @target_set_id int;
                                                                                    EXEC msdb.dbo.sp_syspolicy_add_target_set @object_set_name=N'dbatoolsci_$random', @type_skeleton=N'Server/Database', @type=N'DATABASE', @enabled=True, @target_set_id=@target_set_id OUTPUT;
                                                                                    EXEC msdb.dbo.sp_syspolicy_add_target_set_level @target_set_id=@target_set_id, @type_skeleton=N'Server/Database', @level_name=N'Database', @condition_name=N'', @target_set_level_id=0;"

        $output = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "Declare @policy_id int;
                                                                                    EXEC msdb.dbo.sp_syspolicy_add_policy @name=N'dbatools_test_$random', @condition_name=N'dbatoolsci_condition_$random', @execution_mode=0, @policy_id=@policy_id OUTPUT, @object_set=N'dbatoolsci_$random';
                                                                                    Select @policy_id AS PolicyId;"

        $policyId = $output.PolicyId

        # add a procedure to the master db for the export of user objects in system databases
        Install-DbaWhoIsActive -SqlInstance $testServer -Database master

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup all created objects.

        # registered server and group
        Get-DbaRegServer -SqlInstance $testServer | Where-Object Name -Match dbatoolsci | Remove-DbaRegServer -Confirm:$false
        Get-DbaRegServerGroup -SqlInstance $testServer | Where-Object Name -Match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false

        # custom error message
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_dropmessage 250000"
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_dropmessage 250001"

        # credentials
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "DROP CREDENTIAL [dbatools1$random]"
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "DROP CREDENTIAL [dbatools2$random]"

        # logins
        Remove-DbaLogin -SqlInstance $testServer -Login "dbatools$random" -Confirm:$false

        # backup devices
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_dropdevice 'backupdevice$random'"

        # linked server
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_dropserver @server = 'server$random'"

        # system trigger
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "DROP TRIGGER [create_database_$random] ON ALL SERVER"

        # database restore scripts
        Remove-Item -Path $backupdir -Recurse -Force -ErrorAction SilentlyContinue

        # database audit
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database $dbName -Query "ALTER DATABASE AUDIT SPECIFICATION [DatabaseAuditSpecification_$random] WITH (STATE = OFF); DROP DATABASE AUDIT SPECIFICATION [DatabaseAuditSpecification_$random]"

        # server audit and spec
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "ALTER SERVER AUDIT SPECIFICATION [Audit_Specification_$random] WITH (STATE = OFF); DROP SERVER AUDIT SPECIFICATION [Audit_Specification_$random]"

        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "ALTER SERVER AUDIT [Audit_$random] WITH (STATE = OFF); DROP SERVER AUDIT [Audit_$random];"

        # endpoint
        Remove-DbaEndpoint -SqlInstance $testServer -EndPoint "dbatoolsci_$random" -Confirm:$false

        # policies
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC msdb.dbo.sp_syspolicy_delete_policy @policy_id=$policyId;
                                                                                  EXEC msdb.dbo.sp_syspolicy_delete_condition @condition_id=$policyConditionId;
                                                                                  EXEC msdb.dbo.sp_syspolicy_delete_object_set @object_set_id=$objectSetId;"

        # last step to remove sample db
        Remove-DbaDatabase -SqlInstance $testServer -Database $dbName -Confirm:$false

        # remove export dir
        Remove-Item -Path $exportPath -Recurse -Force -ErrorAction SilentlyContinue

        # Remove any test results directories
        foreach ($dir in $resultsToCleanup) {
            if ($dir -ne $null) {
                Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Export directory structure" {
        BeforeEach {
            $results = $null
        }

        AfterEach {
            $dirToRemove = $null

            if (($results -ne $null) -and ($results.Count -gt 1)) {
                $dirToRemove = $results[0].Directory.FullName
            } elseif ($results -ne $null) {
                $dirToRemove = $results.Directory.FullName
            }

            if ($dirToRemove -ne $null) {
                $null = Remove-Item -Path $dirToRemove -Force -Recurse -ErrorAction SilentlyContinue
            }
        }

        It "Export dir should have the date in the correct format" {
            $splatExport = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "AgentServer",
                    "Audits",
                    "AvailabilityGroups",
                    "BackupDevices",
                    "CentralManagementServer",
                    "Credentials",
                    "CustomErrors",
                    "DatabaseMail",
                    "Endpoints",
                    "ExtendedEvents",
                    "LinkedServers",
                    "Logins",
                    "PolicyManagement",
                    "ReplicationSettings",
                    "ResourceGovernor",
                    "ServerAuditSpecifications",
                    "ServerRoles",
                    "SpConfigure",
                    "SysDbUserObjects",
                    "SystemTriggers",
                    "OleDbProvider"
                )
            }
            $results = Export-DbaInstance @splatExport
            $results.Count | Should -BeGreaterThan 0

            # parse the exact format of the date
            $indexOfDateTimeStamp = $results[0].Directory.Name.Split("-").Count
            $dateTimeStampOnFolder = [datetime]::parseexact($results[0].Directory.Name.Split("-")[$indexOfDateTimeStamp - 1], "yyyyMMddHHmmss", $null)

            $dateTimeStampOnFolder | Should -Not -Be $null
        }

        It "Ensure the -Force param replaces existing files" {
            $splatExportForce = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "Audits",
                    "AvailabilityGroups",
                    "BackupDevices",
                    "CentralManagementServer",
                    "Credentials",
                    "CustomErrors",
                    "DatabaseMail",
                    "Databases",
                    "Endpoints",
                    "ExtendedEvents",
                    "LinkedServers",
                    "Logins",
                    "PolicyManagement",
                    "ReplicationSettings",
                    "ResourceGovernor",
                    "ServerAuditSpecifications",
                    "ServerRoles",
                    "SpConfigure",
                    "SysDbUserObjects",
                    "SystemTriggers",
                    "OleDbProvider"
                )
                Force       = $true
            }
            $results = Export-DbaInstance @splatExportForce

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0

            $originalLength = $results.Length
            $originalLastWriteTime = $results.LastWriteTime

            $results = Export-DbaInstance @splatExportForce

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0
            $results.Length | Should -Be $originalLength
            $results.LastWriteTime | Should -BeGreaterThan $originalLastWriteTime
        }
    }

    Context "Export specific components" {
        BeforeEach {
            $results = $null
        }

        AfterEach {
            $dirToRemove = $null

            if (($results -ne $null) -and ($results.Count -gt 1)) {
                $dirToRemove = $results[0].Directory.FullName
            } elseif ($results -ne $null) {
                $dirToRemove = $results.Directory.FullName
            }

            if ($dirToRemove -ne $null) {
                $null = Remove-Item -Path $dirToRemove -Force -Recurse -ErrorAction SilentlyContinue
            }
        }

        It "Export sp_configure values" {
            $splatExportSpConfigure = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "AgentServer",
                    "Audits",
                    "AvailabilityGroups",
                    "BackupDevices",
                    "CentralManagementServer",
                    "Credentials",
                    "CustomErrors",
                    "DatabaseMail",
                    "Databases",
                    "Endpoints",
                    "ExtendedEvents",
                    "LinkedServers",
                    "Logins",
                    "PolicyManagement",
                    "ReplicationSettings",
                    "ResourceGovernor",
                    "ServerAuditSpecifications",
                    "ServerRoles",
                    "SysDbUserObjects",
                    "SystemTriggers",
                    "OleDbProvider"
                )
            }
            $results = Export-DbaInstance @splatExportSpConfigure

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0
        }

        It "Export CentralManagementServer" {
            $splatExportCMS = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "AgentServer",
                    "Audits",
                    "AvailabilityGroups",
                    "BackupDevices",
                    "Credentials",
                    "CustomErrors",
                    "DatabaseMail",
                    "Databases",
                    "Endpoints",
                    "ExtendedEvents",
                    "LinkedServers",
                    "Logins",
                    "PolicyManagement",
                    "ReplicationSettings",
                    "ResourceGovernor",
                    "ServerAuditSpecifications",
                    "ServerRoles",
                    "SpConfigure",
                    "SysDbUserObjects",
                    "SystemTriggers",
                    "OleDbProvider"
                )
            }
            $results = Export-DbaInstance @splatExportCMS

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0
        }

        It "Export custom errors" {
            $splatExportCustomErrors = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "AgentServer",
                    "Audits",
                    "AvailabilityGroups",
                    "BackupDevices",
                    "CentralManagementServer",
                    "Credentials",
                    "DatabaseMail",
                    "Databases",
                    "Endpoints",
                    "ExtendedEvents",
                    "LinkedServers",
                    "Logins",
                    "PolicyManagement",
                    "ReplicationSettings",
                    "ResourceGovernor",
                    "ServerAuditSpecifications",
                    "ServerRoles",
                    "SpConfigure",
                    "SysDbUserObjects",
                    "SystemTriggers",
                    "OleDbProvider"
                )
            }
            $results = Export-DbaInstance @splatExportCustomErrors

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0
        }

        It "Export server roles" {
            $splatExportServerRoles = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "AgentServer",
                    "Audits",
                    "AvailabilityGroups",
                    "BackupDevices",
                    "CentralManagementServer",
                    "Credentials",
                    "CustomErrors",
                    "DatabaseMail",
                    "Databases",
                    "Endpoints",
                    "ExtendedEvents",
                    "LinkedServers",
                    "Logins",
                    "PolicyManagement",
                    "ReplicationSettings",
                    "ResourceGovernor",
                    "ServerAuditSpecifications",
                    "SpConfigure",
                    "SysDbUserObjects",
                    "SystemTriggers",
                    "OleDbProvider"
                )
            }
            $results = Export-DbaInstance @splatExportServerRoles

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0
        }

        It "Export credentials" {
            $splatExportCredentials = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "AgentServer",
                    "Audits",
                    "AvailabilityGroups",
                    "BackupDevices",
                    "CentralManagementServer",
                    "CustomErrors",
                    "DatabaseMail",
                    "Databases",
                    "Endpoints",
                    "ExtendedEvents",
                    "LinkedServers",
                    "Logins",
                    "PolicyManagement",
                    "ReplicationSettings",
                    "ResourceGovernor",
                    "ServerAuditSpecifications",
                    "ServerRoles",
                    "SpConfigure",
                    "SysDbUserObjects",
                    "SystemTriggers",
                    "OleDbProvider"
                )
            }
            $results = Export-DbaInstance @splatExportCredentials

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0
        }

        It "Export logins" {
            $splatExportLogins = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "AgentServer",
                    "Audits",
                    "AvailabilityGroups",
                    "BackupDevices",
                    "CentralManagementServer",
                    "Credentials",
                    "CustomErrors",
                    "DatabaseMail",
                    "Databases",
                    "Endpoints",
                    "ExtendedEvents",
                    "LinkedServers",
                    "PolicyManagement",
                    "ReplicationSettings",
                    "ResourceGovernor",
                    "ServerAuditSpecifications",
                    "ServerRoles",
                    "SpConfigure",
                    "SysDbUserObjects",
                    "SystemTriggers",
                    "OleDbProvider"
                )
            }
            $results = Export-DbaInstance @splatExportLogins

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0
        }

        It "Export database mail settings" {
            $splatExportDbMail = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "AgentServer",
                    "Audits",
                    "AvailabilityGroups",
                    "BackupDevices",
                    "CentralManagementServer",
                    "Credentials",
                    "CustomErrors",
                    "Databases",
                    "Endpoints",
                    "ExtendedEvents",
                    "LinkedServers",
                    "Logins",
                    "PolicyManagement",
                    "ReplicationSettings",
                    "ResourceGovernor",
                    "ServerAuditSpecifications",
                    "ServerRoles",
                    "SpConfigure",
                    "SysDbUserObjects",
                    "SystemTriggers",
                    "OleDbProvider"
                )
            }
            $results = Export-DbaInstance @splatExportDbMail

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0
        }

        It "Export backup devices" {
            $splatExportBackupDevices = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "AgentServer",
                    "Audits",
                    "AvailabilityGroups",
                    "CentralManagementServer",
                    "Credentials",
                    "CustomErrors",
                    "DatabaseMail",
                    "Databases",
                    "Endpoints",
                    "ExtendedEvents",
                    "LinkedServers",
                    "Logins",
                    "PolicyManagement",
                    "ReplicationSettings",
                    "ResourceGovernor",
                    "ServerAuditSpecifications",
                    "ServerRoles",
                    "SpConfigure",
                    "SysDbUserObjects",
                    "SystemTriggers",
                    "OleDbProvider"
                )
            }
            $results = Export-DbaInstance @splatExportBackupDevices

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0
        }

        It "Export linked servers" {
            $splatExportLinkedServers = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "AgentServer",
                    "Audits",
                    "AvailabilityGroups",
                    "BackupDevices",
                    "CentralManagementServer",
                    "Credentials",
                    "CustomErrors",
                    "DatabaseMail",
                    "Databases",
                    "Endpoints",
                    "ExtendedEvents",
                    "Logins",
                    "PolicyManagement",
                    "ReplicationSettings",
                    "ResourceGovernor",
                    "ServerAuditSpecifications",
                    "ServerRoles",
                    "SpConfigure",
                    "SysDbUserObjects",
                    "SystemTriggers",
                    "OleDbProvider"
                )
            }
            $results = Export-DbaInstance @splatExportLinkedServers

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0
        }

        It "Export system triggers" {
            $splatExportSystemTriggers = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "AgentServer",
                    "Audits",
                    "AvailabilityGroups",
                    "BackupDevices",
                    "CentralManagementServer",
                    "Credentials",
                    "CustomErrors",
                    "DatabaseMail",
                    "Databases",
                    "Endpoints",
                    "ExtendedEvents",
                    "LinkedServers",
                    "Logins",
                    "PolicyManagement",
                    "ReplicationSettings",
                    "ResourceGovernor",
                    "ServerAuditSpecifications",
                    "ServerRoles",
                    "SpConfigure",
                    "SysDbUserObjects",
                    "OleDbProvider"
                )
            }
            $results = Export-DbaInstance @splatExportSystemTriggers

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0
        }

        It "Export database restore scripts" {
            $splatExportDatabases = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "AgentServer",
                    "Audits",
                    "AvailabilityGroups",
                    "BackupDevices",
                    "CentralManagementServer",
                    "Credentials",
                    "CustomErrors",
                    "DatabaseMail",
                    "Endpoints",
                    "ExtendedEvents",
                    "LinkedServers",
                    "Logins",
                    "PolicyManagement",
                    "ReplicationSettings",
                    "ResourceGovernor",
                    "ServerAuditSpecifications",
                    "ServerRoles",
                    "SpConfigure",
                    "SysDbUserObjects",
                    "SystemTriggers",
                    "OleDbProvider"
                )
            }
            $results = Export-DbaInstance @splatExportDatabases

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0
        }

        It "Export server audits" {
            $splatExportAudits = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "AgentServer",
                    "AvailabilityGroups",
                    "BackupDevices",
                    "CentralManagementServer",
                    "Credentials",
                    "CustomErrors",
                    "DatabaseMail",
                    "Databases",
                    "Endpoints",
                    "ExtendedEvents",
                    "LinkedServers",
                    "Logins",
                    "PolicyManagement",
                    "ReplicationSettings",
                    "ResourceGovernor",
                    "ServerAuditSpecifications",
                    "ServerRoles",
                    "SpConfigure",
                    "SysDbUserObjects",
                    "SystemTriggers",
                    "OleDbProvider"
                )
            }
            $results = Export-DbaInstance @splatExportAudits

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0
        }

        It "Export server audit specifications" {
            $splatExportServerAuditSpecs = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "AgentServer",
                    "Audits",
                    "AvailabilityGroups",
                    "BackupDevices",
                    "CentralManagementServer",
                    "Credentials",
                    "CustomErrors",
                    "DatabaseMail",
                    "Databases",
                    "Endpoints",
                    "ExtendedEvents",
                    "LinkedServers",
                    "Logins",
                    "PolicyManagement",
                    "ReplicationSettings",
                    "ResourceGovernor",
                    "ServerRoles",
                    "SpConfigure",
                    "SysDbUserObjects",
                    "SystemTriggers",
                    "OleDbProvider"
                )
            }
            $results = Export-DbaInstance @splatExportServerAuditSpecs

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0
        }

        It "Export endpoints" {
            $splatExportEndpoints = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "AgentServer",
                    "Audits",
                    "AvailabilityGroups",
                    "BackupDevices",
                    "CentralManagementServer",
                    "Credentials",
                    "CustomErrors",
                    "DatabaseMail",
                    "Databases",
                    "ExtendedEvents",
                    "LinkedServers",
                    "Logins",
                    "PolicyManagement",
                    "ReplicationSettings",
                    "ResourceGovernor",
                    "ServerAuditSpecifications",
                    "ServerRoles",
                    "SpConfigure",
                    "SysDbUserObjects",
                    "SystemTriggers",
                    "OleDbProvider"
                )
            }
            $results = Export-DbaInstance @splatExportEndpoints

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0
        }

        It "Export policies" {
            $splatExportPolicies = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "AgentServer",
                    "Audits",
                    "AvailabilityGroups",
                    "BackupDevices",
                    "CentralManagementServer",
                    "Credentials",
                    "CustomErrors",
                    "DatabaseMail",
                    "Databases",
                    "Endpoints",
                    "ExtendedEvents",
                    "LinkedServers",
                    "Logins",
                    "ReplicationSettings",
                    "ResourceGovernor",
                    "ServerAuditSpecifications",
                    "ServerRoles",
                    "SpConfigure",
                    "SysDbUserObjects",
                    "SystemTriggers",
                    "OleDbProvider"
                )
            }
            $results = Export-DbaInstance @splatExportPolicies

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0
        }

        It "Export resource governor settings" {
            $splatExportResourceGovernor = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "AgentServer",
                    "Audits",
                    "AvailabilityGroups",
                    "BackupDevices",
                    "CentralManagementServer",
                    "Credentials",
                    "CustomErrors",
                    "DatabaseMail",
                    "Databases",
                    "Endpoints",
                    "ExtendedEvents",
                    "LinkedServers",
                    "Logins",
                    "PolicyManagement",
                    "ReplicationSettings",
                    "ServerAuditSpecifications",
                    "ServerRoles",
                    "SpConfigure",
                    "SysDbUserObjects",
                    "SystemTriggers",
                    "OleDbProvider"
                )
            }
            $results = Export-DbaInstance @splatExportResourceGovernor

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0
        }

        It "Export extended events" {
            $splatExportExtendedEvents = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "AgentServer",
                    "Audits",
                    "AvailabilityGroups",
                    "BackupDevices",
                    "CentralManagementServer",
                    "Credentials",
                    "CustomErrors",
                    "DatabaseMail",
                    "Databases",
                    "Endpoints",
                    "LinkedServers",
                    "Logins",
                    "PolicyManagement",
                    "ReplicationSettings",
                    "ResourceGovernor",
                    "ServerAuditSpecifications",
                    "ServerRoles",
                    "SpConfigure",
                    "SysDbUserObjects",
                    "SystemTriggers",
                    "OleDbProvider"
                )
            }
            $results = Export-DbaInstance @splatExportExtendedEvents

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0
        }

        It "Export agent server" {
            $splatExportAgentServer = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "Audits",
                    "AvailabilityGroups",
                    "BackupDevices",
                    "CentralManagementServer",
                    "Credentials",
                    "CustomErrors",
                    "DatabaseMail",
                    "Databases",
                    "Endpoints",
                    "ExtendedEvents",
                    "LinkedServers",
                    "Logins",
                    "PolicyManagement",
                    "ReplicationSettings",
                    "ResourceGovernor",
                    "ServerAuditSpecifications",
                    "ServerRoles",
                    "SpConfigure",
                    "SysDbUserObjects",
                    "SystemTriggers",
                    "OleDbProvider"
                )
            }
            $results = Export-DbaInstance @splatExportAgentServer

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0
        }

        It "Export replication settings" {
            $splatExportReplication = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "AgentServer",
                    "Audits",
                    "AvailabilityGroups",
                    "BackupDevices",
                    "CentralManagementServer",
                    "Credentials",
                    "CustomErrors",
                    "DatabaseMail",
                    "Databases",
                    "Endpoints",
                    "ExtendedEvents",
                    "LinkedServers",
                    "Logins",
                    "PolicyManagement",
                    "ResourceGovernor",
                    "ServerAuditSpecifications",
                    "ServerRoles",
                    "SpConfigure",
                    "SysDbUserObjects",
                    "SystemTriggers",
                    "OleDbProvider"
                )
            }
            $results = Export-DbaInstance @splatExportReplication

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0
        }

        It "Export system db user objects" {
            $splatExportSysDbUserObjects = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "AgentServer",
                    "Audits",
                    "AvailabilityGroups",
                    "BackupDevices",
                    "CentralManagementServer",
                    "Credentials",
                    "CustomErrors",
                    "DatabaseMail",
                    "Databases",
                    "Endpoints",
                    "ExtendedEvents",
                    "LinkedServers",
                    "Logins",
                    "PolicyManagement",
                    "ReplicationSettings",
                    "ResourceGovernor",
                    "ServerAuditSpecifications",
                    "ServerRoles",
                    "SpConfigure",
                    "SystemTriggers",
                    "OleDbProvider"
                )
            }
            $results = Export-DbaInstance @splatExportSysDbUserObjects

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0
        }

        It "Exports oledb providers" {
            $splatExportOleDbProvider = @{
                SqlInstance = $testServer
                Path        = $exportPath
                Exclude     = @(
                    "AgentServer",
                    "Audits",
                    "AvailabilityGroups",
                    "BackupDevices",
                    "CentralManagementServer",
                    "Credentials",
                    "CustomErrors",
                    "DatabaseMail",
                    "Databases",
                    "Endpoints",
                    "ExtendedEvents",
                    "LinkedServers",
                    "Logins",
                    "PolicyManagement",
                    "ReplicationSettings",
                    "ResourceGovernor",
                    "ServerAuditSpecifications",
                    "ServerRoles",
                    "SpConfigure",
                    "SystemTriggers",
                    "SysDbUserObjects"
                )
            }
            $results = Export-DbaInstance @splatExportOleDbProvider

            $results.FullName | Should -Exist
            $results.Length | Should -BeGreaterThan 0
        }
    }

    # placeholder for a future test with availability groups
    It -Skip "Export availability groups" {
    }
}