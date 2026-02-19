#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaInstance",
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
                "Credential",
                "Path",
                "NoRecovery",
                "IncludeDbMasterKey",
                "Exclude",
                "BatchSeparator",
                "ScriptingOption",
                "NoPrefix",
                "ExcludePassword",
                "AzureCredential",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeEach {
        $results = $null
    }

    AfterEach {
        $dirToRemove = $null

        if (($results -ne $null) -and ($results.length -gt 1)) {
            $dirToRemove = $results[0].Directory.FullName
        } elseif ($results -ne $null) {
            $dirToRemove = $results.Directory.FullName
        }

        if ($dirToRemove -ne $null) {
            $null = Remove-Item -Path $dirToRemove -Force -Recurse
        }
    }

    BeforeAll {
        $random = Get-Random
        $dbName = "dbatoolsci_$random"
        $exportDir = "$($TestConfig.Temp)\dbatools_export_dbainstance"
        if (-not (Test-Path $exportDir -PathType Container)) {
            $null = New-Item -Path $exportDir -ItemType Container
        }

        # registered server and group
        $testServer = $TestConfig.InstanceSingle
        $srvName = "dbatoolsci-server1"
        $group = "dbatoolsci-group1"
        $regSrvName = "dbatoolsci-server12"
        $regSrvDesc = "dbatoolsci-server123"

        $newGroup = Add-DbaRegServerGroup -SqlInstance $testServer -Name $group
        $newServer = Add-DbaRegServer -SqlInstance $testServer -ServerName $srvName -Name $regSrvName -Description $regSrvDesc

        # custom error message
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_addmessage 250000, 16, N'Sample error message1'"
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_addmessage 250001, 16, N'Sample error message2'"

        # credentials
        New-DbaCredential -SqlInstance $testServer -Name "dbatools1$random" -Identity "dbatools1$random" -SecurePassword (ConvertTo-SecureString -String "dbatools1" -AsPlainText -Force)
        New-DbaCredential -SqlInstance $testServer -Name "dbatools2$random" -Identity "dbatools2$random" -SecurePassword (ConvertTo-SecureString -String "dbatools2" -AsPlainText -Force)

        # logins
        New-DbaLogin -SqlInstance $testServer -Login "dbatools$random" -SecurePassword (ConvertTo-SecureString -String "dbatools1" -AsPlainText -Force)

        # backup device
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_addumpdevice 'disk', 'backupdevice$random', '$($TestConfig.Temp)\backupdevice$random.bak'"

        # linked server
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_addlinkedserver @server = N'server$random', @srvproduct=N'SQL Server'"

        # system trigger
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "CREATE TRIGGER [create_database_$random] ON ALL SERVER FOR CREATE_DATABASE AS SELECT 1"

        # database restore scripts
        $backupdir = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupdir -ItemType Directory
        New-DbaDatabase -SqlInstance $testServer -Name $dbName
        Backup-DbaDatabase -SqlInstance $testServer -Database $dbName -BackupDirectory $backupdir

        # server audit and spec
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "CREATE SERVER AUDIT [Audit_$random] TO FILE (FILEPATH = N'$($TestConfig.Temp)', MAXSIZE = 8 MB, MAX_ROLLOVER_FILES = 2, RESERVE_DISK_SPACE = OFF) WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE)"

        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "CREATE SERVER AUDIT SPECIFICATION [Audit_Specification_$random] FOR SERVER AUDIT [Audit_$random] ADD (FAILED_LOGIN_GROUP) WITH (STATE=ON)"

        # database audit
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database $dbName -Query "CREATE DATABASE AUDIT SPECIFICATION [DatabaseAuditSpecification_$random] FOR SERVER AUDIT [Audit_$random] ADD (DELETE ON DATABASE::[$dbName] BY [public])"

        # endpoint
        New-DbaEndpoint -SqlInstance $testServer -Type DatabaseMirroring -Name dbatoolsci_$random

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
    }

    AfterAll {
        # registered server and group
        Get-DbaRegServer -SqlInstance $testServer | Where-Object Name -Match dbatoolsci | Remove-DbaRegServer
        Get-DbaRegServerGroup -SqlInstance $testServer | Where-Object Name -Match dbatoolsci | Remove-DbaRegServerGroup

        # custom error message
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_dropmessage 250000"
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_dropmessage 250001"

        # credentials
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "DROP CREDENTIAL [dbatools1$random]"
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "DROP CREDENTIAL [dbatools2$random]"

        # logins
        Remove-DbaLogin -SqlInstance $testServer -Login "dbatools$random"

        # backup devices
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_dropdevice 'backupdevice$random'"

        # linked server
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_dropserver @server = 'server$random'"

        # system trigger
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "DROP TRIGGER [create_database_$random] ON ALL SERVER"

        # database restore scripts
        Remove-Item -Path $backupdir -Recurse

        # database audit
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database $dbName -Query "ALTER DATABASE AUDIT SPECIFICATION [DatabaseAuditSpecification_$random] WITH (STATE = OFF); DROP DATABASE AUDIT SPECIFICATION [DatabaseAuditSpecification_$random]"

        # server audit and spec
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "ALTER SERVER AUDIT SPECIFICATION [Audit_Specification_$random] WITH (STATE = OFF); DROP SERVER AUDIT SPECIFICATION [Audit_Specification_$random]"

        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "ALTER SERVER AUDIT [Audit_$random] WITH (STATE = OFF); DROP SERVER AUDIT [Audit_$random];"

        # endpoint
        Remove-DbaEndpoint -SqlInstance $testServer -EndPoint dbatoolsci_$random

        # policies
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC msdb.dbo.sp_syspolicy_delete_policy @policy_id=$policyId;
                                                                                  EXEC msdb.dbo.sp_syspolicy_delete_condition @condition_id=$policyConditionId;
                                                                                  EXEC msdb.dbo.sp_syspolicy_delete_object_set @object_set_id=$objectSetId;"

        # last step to remove sample db
        Remove-DbaDatabase -SqlInstance $testServer -Database $dbName

        # remove export dir
        Remove-Item -Path $exportDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "Export dir should have the date in the correct format" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'
        $results.length | Should -BeGreaterThan 0

        # parse the exact format of the date
        $indexOfDateTimeStamp = $results[0].Directory.Name.Split("-").length
        $dateTimeStampOnFolder = [datetime]::parseexact($results[0].Directory.Name.Split("-")[$indexOfDateTimeStamp - 1], "yyyyMMddHHmmss", $null)

        $dateTimeStampOnFolder | Should -Not -BeNullOrEmpty
    }

    It "Ensure the -Force param replaces existing files" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider' -Force

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0

        $originalLength = $results.Length
        $originalLastWriteTime = $results.LastWriteTime

        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider' -Force

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
        $results.Length | Should -Be $originalLength
        $results.LastWriteTime | Should -BeGreaterThan $originalLastWriteTime
    }

    It "Export sp_configure values" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    It "Export CentralManagementServer" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    It "Export custom errors" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    It "Export server roles" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    It "Export credentials" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    It "Export credentials without passwords" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider' -ExcludePassword

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    It "Export credentials with preopend dac" {
        $dac = Connect-DbaInstance -SqlInstance $testServer -DedicatedAdminConnection
        $results = Export-DbaInstance -SqlInstance $dac -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider' -ExcludePassword
        $null = $dac | Disconnect-DbaInstance

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    It "Export logins" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    It "Export database mail settings" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    It "Export backup devices" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    It "Export linked servers" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    It "Export system triggers" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'OleDbProvider'

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    It "Export database restore scripts" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    It "Export server audits" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    It "Export server audit specifications" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    It "Export endpoints" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    It "Export policies" -Skip:($PSVersionTable.PSVersion.Major -gt 5) {
        # Skip It on pwsh because working with policies is not supported.

        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    It "Export resource governor settings" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    It "Export extended events" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    It "Export agent server" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    It "Export replication settings" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    It "Export system db user objects" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SystemTriggers', 'OleDbProvider'

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    It "Exports oledb providers" {
        $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SystemTriggers', 'SysDbUserObjects'

        $results.FullName | Should -Exist
        $results.Length | Should -BeGreaterThan 0
    }

    # placeholder for a future test with availability groups
    # It "Export availability groups" {
    # }
}