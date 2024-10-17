param($ModuleName = 'dbatools')

Describe "Export-DbaInstance Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaInstance
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Mandatory:$false
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type String -Mandatory:$false
        }
        It "Should have NoRecovery as a parameter" {
            $CommandUnderTest | Should -HaveParameter NoRecovery -Type Switch -Mandatory:$false
        }
        It "Should have AzureCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter AzureCredential -Type String -Mandatory:$false
        }
        It "Should have IncludeDbMasterKey as a parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeDbMasterKey -Type Switch -Mandatory:$false
        }
        It "Should have Exclude as a parameter" {
            $CommandUnderTest | Should -HaveParameter Exclude -Type String[] -Mandatory:$false
        }
        It "Should have BatchSeparator as a parameter" {
            $CommandUnderTest | Should -HaveParameter BatchSeparator -Type String -Mandatory:$false
        }
        It "Should have ScriptingOption as a parameter" {
            $CommandUnderTest | Should -HaveParameter ScriptingOption -Type ScriptingOptions -Mandatory:$false
        }
        It "Should have NoPrefix as a parameter" {
            $CommandUnderTest | Should -HaveParameter NoPrefix -Type Switch -Mandatory:$false
        }
        It "Should have ExcludePassword as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludePassword -Type Switch -Mandatory:$false
        }
        It "Should have Force as a parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch -Mandatory:$false
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }
}

Describe "Export-DbaInstance Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $dbName = "dbatoolsci_$random"
        $exportDir = "C:\temp\dbatools_export_dbainstance"
        if (-not (Test-Path $exportDir -PathType Container)) {
            $null = New-Item -Path $exportDir -ItemType Container
        }

        $testServer = $global:instance2
        $server = Connect-DbaInstance -SqlInstance $testServer
        $srvName = "dbatoolsci-server1"
        $group = "dbatoolsci-group1"
        $regSrvName = "dbatoolsci-server12"
        $regSrvDesc = "dbatoolsci-server123"

        $newGroup = Add-DbaRegServerGroup -SqlInstance $testServer -Name $group
        $newServer = Add-DbaRegServer -SqlInstance $testServer -ServerName $srvName -Name $regSrvName -Description $regSrvDesc

        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_addmessage 250000, 16, N'Sample error message1'"
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_addmessage 250001, 16, N'Sample error message2'"

        New-DbaCredential -SqlInstance $testServer -Name "dbatools1$random" -Identity "dbatools1$random" -SecurePassword (ConvertTo-SecureString -String "dbatools1" -AsPlainText -Force) -Confirm:$false
        New-DbaCredential -SqlInstance $testServer -Name "dbatools2$random" -Identity "dbatools2$random" -SecurePassword (ConvertTo-SecureString -String "dbatools2" -AsPlainText -Force) -Confirm:$false

        New-DbaLogin -SqlInstance $testServer -Login "dbatools$random" -SecurePassword (ConvertTo-SecureString -String "dbatools1" -AsPlainText -Force) -Confirm:$false

        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_addumpdevice 'disk', 'backupdevice$random', 'c:\temp\backupdevice$random.bak'"

        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_addlinkedserver @server = N'server$random', @srvproduct=N'SQL Server'"

        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "CREATE TRIGGER [create_database_$random] ON ALL SERVER FOR CREATE_DATABASE AS SELECT 1"

        $backupdir = Join-Path $server.BackupDirectory $dbName
        if (-not (Test-Path $backupdir -PathType Container)) {
            $null = New-Item -Path $backupdir -ItemType Container
        }
        New-DbaDatabase -SqlInstance $testServer -Name $dbName
        Backup-DbaDatabase -SqlInstance $testServer -Database $dbName -BackupDirectory $backupdir

        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "CREATE SERVER AUDIT [Audit_$random] TO FILE (FILEPATH = N'c:\temp', MAXSIZE = 8 MB, MAX_ROLLOVER_FILES = 2, RESERVE_DISK_SPACE = OFF) WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE)"

        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "CREATE SERVER AUDIT SPECIFICATION [Audit_Specification_$random] FOR SERVER AUDIT [Audit_$random] ADD (FAILED_LOGIN_GROUP) WITH (STATE=ON)"

        $null = Invoke-DbaQuery -SqlInstance $testServer -Database $dbName -Query "CREATE DATABASE AUDIT SPECIFICATION [DatabaseAuditSpecification_$random] FOR SERVER AUDIT [Audit_$random] ADD (DELETE ON DATABASE::[$dbName] BY [public])"

        New-DbaEndpoint -SqlInstance $testServer -Type DatabaseMirroring -Name dbatoolsci_$random

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

        Install-DbaWhoIsActive -SqlInstance $testServer -Database master
    }

    AfterAll {
        Get-DbaRegServer -SqlInstance $testServer | Where-Object Name -Match dbatoolsci | Remove-DbaRegServer -Confirm:$false
        Get-DbaRegServerGroup -SqlInstance $testServer | Where-Object Name -Match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false

        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_dropmessage 250000"
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_dropmessage 250001"

        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "DROP CREDENTIAL [dbatools1$random]"
        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "DROP CREDENTIAL [dbatools2$random]"

        Remove-DbaLogin -SqlInstance $testServer -Login "dbatools$random" -Confirm:$false

        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_dropdevice 'backupdevice$random'"

        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC sp_dropserver @server = 'server$random'"

        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "DROP TRIGGER [create_database_$random] ON ALL SERVER"

        Remove-Item -Path $backupdir -Recurse -Force -ErrorAction SilentlyContinue

        $null = Invoke-DbaQuery -SqlInstance $testServer -Database $dbName -Query "ALTER DATABASE AUDIT SPECIFICATION [DatabaseAuditSpecification_$random] WITH (STATE = OFF); DROP DATABASE AUDIT SPECIFICATION [DatabaseAuditSpecification_$random]"

        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "ALTER SERVER AUDIT SPECIFICATION [Audit_Specification_$random] WITH (STATE = OFF); DROP SERVER AUDIT SPECIFICATION [Audit_Specification_$random]"

        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "ALTER SERVER AUDIT [Audit_$random] WITH (STATE = OFF); DROP SERVER AUDIT [Audit_$random];"

        Remove-DbaEndpoint -SqlInstance $testServer -EndPoint dbatoolsci_$random -Confirm:$false

        $null = Invoke-DbaQuery -SqlInstance $testServer -Database master -Query "EXEC msdb.dbo.sp_syspolicy_delete_policy @policy_id=$policyId;
                                                                                  EXEC msdb.dbo.sp_syspolicy_delete_condition @condition_id=$policyConditionId;
                                                                                  EXEC msdb.dbo.sp_syspolicy_delete_object_set @object_set_id=$objectSetId;"

        Remove-DbaDatabase -SqlInstance $testServer -Database $dbName -Confirm:$false

        Remove-Item -Path $exportDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "Export dir should have the date in the correct format" {
        It "Exports with correct date format" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'
            $results.Count | Should -BeGreaterThan 0

            $indexOfDateTimeStamp = $results[0].Directory.Name.Split("-").Count - 1
            $dateTimeStampOnFolder = [datetime]::parseexact($results[0].Directory.Name.Split("-")[$indexOfDateTimeStamp], "yyyyMMddHHmmss", $null)

            $dateTimeStampOnFolder | Should -Not -BeNullOrEmpty
        }
    }

    Context "Ensure the -Force param replaces existing files" {
        It "Replaces existing files when using -Force" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider' -Force

            $results.FullName | Should -Exist
            $results.Count | Should -BeGreaterThan 0

            $originalCount = $results.Count
            $originalLastWriteTime = $results.LastWriteTime

            $newResults = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider' -Force

            $newResults.FullName | Should -Exist
            $newResults.Count | Should -BeGreaterThan 0
            $newResults.Count | Should -Be $originalCount
            $newResults.LastWriteTime | Should -BeGreaterThan $originalLastWriteTime
        }
    }

    Context "Export various server components" {
        It "Exports sp_configure values" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

            $results.FullName | Should -Exist
            $results.Count | Should -BeGreaterThan 0
        }

        It "Exports CentralManagementServer" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

            $results.FullName | Should -Exist
            $results.Count | Should -BeGreaterThan 0
        }

        It "Exports custom errors" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

            $results.FullName | Should -Exist
            $results.Count | Should -BeGreaterThan 0
        }

        It "Exports server roles" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

            $results.FullName | Should -Exist
            $results.Count | Should -BeGreaterThan 0
        }

        It "Exports credentials" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

            $results.FullName | Should -Exist
            $results.Count | Should -BeGreaterThan 0
        }

        It "Exports logins" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

            $results.FullName | Should -Exist
            $results.Count | Should -BeGreaterThan 0
        }

        It "Exports database mail settings" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

            $results.FullName | Should -Exist
            $results.Count | Should -BeGreaterThan 0
        }

        It "Exports backup devices" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

            $results.FullName | Should -Exist
            $results.Count | Should -BeGreaterThan 0
        }

        It "Exports linked servers" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

            $results.FullName | Should -Exist
            $results.Count | Should -BeGreaterThan 0
        }

        It "Exports system triggers" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'OleDbProvider'

            $results.FullName | Should -Exist
            $results.Count | Should -BeGreaterThan 0
        }

        It "Exports database restore scripts" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

            $results.FullName | Should -Exist
            $results.Count | Should -BeGreaterThan 0
        }

        It "Exports server audits" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

            $results.FullName | Should -Exist
            $results.Count | Should -BeGreaterThan 0
        }

        It "Exports server audit specifications" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

            $results.FullName | Should -Exist
            $results.Count | Should -BeGreaterThan 0
        }

        It "Exports endpoints" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

            $results.FullName | Should -Exist
            $results.Count | Should -BeGreaterThan 0
        }

        It "Exports policies" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

            $results.FullName | Should -Exist
            $results.Count | Should -BeGreaterThan 0
        }

        It "Exports resource governor settings" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

            $results.FullName | Should -Exist
            $results.Count | Should -BeGreaterThan 0
        }

        It "Exports extended events" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

            $results.FullName | Should -Exist
            $results.Count | Should -BeGreaterThan 0
        }

        It "Exports agent server" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

            $results.FullName | Should -Exist
            $results.Count | Should -BeGreaterThan 0
        }

        It "Exports replication settings" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SysDbUserObjects', 'SystemTriggers', 'OleDbProvider'

            $results.FullName | Should -Exist
            $results.Count | Should -BeGreaterThan 0
        }

        It "Exports system db user objects" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SystemTriggers', 'OleDbProvider'

            $results.FullName | Should -Exist
            $results.Count | Should -BeGreaterThan 0
        }

        It "Exports oledb providers" {
            $results = Export-DbaInstance -SqlInstance $testServer -Path $exportDir -Exclude 'AgentServer', 'Audits', 'AvailabilityGroups', 'BackupDevices', 'CentralManagementServer', 'Credentials', 'CustomErrors', 'DatabaseMail', 'Databases', 'Endpoints', 'ExtendedEvents', 'LinkedServers', 'Logins', 'PolicyManagement', 'ReplicationSettings', 'ResourceGovernor', 'ServerAuditSpecifications', 'ServerRoles', 'SpConfigure', 'SystemTriggers', 'SysDbUserObjects'

            $results.FullName | Should -Exist
            $results.Count | Should -BeGreaterThan 0
        }
    }
}
