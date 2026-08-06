#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
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
                "EncryptionPassword",
                "DecryptionPassword",
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

    Context "DAC cleanup behavior" {
        It "Should disconnect an opened DAC connection when credential export fails" {
            InModuleScope dbatools {
                $functionNames = @(
                    "Connect-DbaInstance",
                    "Disconnect-DbaInstance",
                    "Export-DbaCredential",
                    "Stop-Function",
                    "Test-ExportDirectory",
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
                    function Test-ExportDirectory { }
                    function Test-FunctionInterrupt { $false }
                    function Write-Message { }
                    function Write-ProgressHelper { }
                    function Test-Path { $true }
                    function Stop-Function {
                        param(
                            $Message,
                            $ErrorRecord
                        )
                        throw "$Message | inner: $($ErrorRecord.Exception.Message)"
                    }
                    function Connect-DbaInstance {
                        $server = [PSCustomObject]@{
                            DomainInstanceName = "sql1"
                        }
                        $server.PSObject.TypeNames.Clear()
                        $server.PSObject.TypeNames.Add("Microsoft.SqlServer.Management.Smo.Server")
                        $server
                    }
                    function Export-DbaCredential { throw "credential export failed" }
                    function Disconnect-DbaInstance { $script:dacDisconnected = $true }

                    $script:dacDisconnected = $false
                    $excludedObjects = @(
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

                    { Export-DbaInstance -SqlInstance "sql1" -Path "C:\temp" -Exclude $excludedObjects -Force } | Should -Throw "*credential export failed*"

                    $script:dacDisconnected | Should -BeTrue
                } finally {
                    foreach ($functionName in $functionNames) {
                        if ($originalFunctions.ContainsKey($functionName)) {
                            Set-Item -Path "Function:\$functionName" -Value $originalFunctions[$functionName]
                        } else {
                            Remove-Item -Path "Function:\$functionName" -ErrorAction Ignore
                        }
                    }
                    Remove-Item -Path Function:\Test-Path -ErrorAction Ignore
                }
            }
        }

        It "Should complete progress when credential export failure continues" {
            InModuleScope dbatools {
                $functionNames = @(
                    "Connect-DbaInstance",
                    "Disconnect-DbaInstance",
                    "Export-DbaCredential",
                    "Stop-Function",
                    "Test-ExportDirectory",
                    "Test-FunctionInterrupt",
                    "Write-Message",
                    "Write-Progress",
                    "Write-ProgressHelper"
                )
                $originalFunctions = @{ }
                foreach ($functionName in $functionNames) {
                    if (Test-Path "Function:\$functionName") {
                        $originalFunctions[$functionName] = (Get-Item -Path "Function:\$functionName").ScriptBlock
                    }
                }

                try {
                    function Test-ExportDirectory { }
                    function Test-FunctionInterrupt { $false }
                    function Write-Message { }
                    function Write-ProgressHelper { }
                    function Write-Progress {
                        param(
                            $Activity,
                            [switch]$Completed
                        )
                        if ($Completed) {
                            $script:progressCompleted = $true
                        }
                    }
                    function Test-Path { $true }
                    function Stop-Function {
                        param(
                            $Message,
                            $ErrorRecord,
                            [switch]$Continue
                        )
                        if ($Continue) {
                            continue
                        }
                        throw "$Message | inner: $($ErrorRecord.Exception.Message)"
                    }
                    function Connect-DbaInstance {
                        $server = [PSCustomObject]@{
                            DomainInstanceName = "sql1"
                        }
                        $server.PSObject.TypeNames.Clear()
                        $server.PSObject.TypeNames.Add("Microsoft.SqlServer.Management.Smo.Server")
                        $server
                    }
                    function Export-DbaCredential { throw "credential export failed" }
                    function Disconnect-DbaInstance { $script:dacDisconnected = $true }

                    $script:dacDisconnected = $false
                    $script:progressCompleted = $false
                    $excludedObjects = @(
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

                    $null = Export-DbaInstance -SqlInstance "sql1" -Path "C:\temp" -Exclude $excludedObjects -Force

                    $script:dacDisconnected | Should -BeTrue
                    $script:progressCompleted | Should -BeTrue
                } finally {
                    foreach ($functionName in $functionNames) {
                        if ($originalFunctions.ContainsKey($functionName)) {
                            Set-Item -Path "Function:\$functionName" -Value $originalFunctions[$functionName]
                        } else {
                            Remove-Item -Path "Function:\$functionName" -ErrorAction Ignore
                        }
                    }
                    Remove-Item -Path Function:\Test-Path -ErrorAction Ignore
                }
            }
        }
    }

    Context "Database key export behavior" {
        It "Should stage certificate and master key exports and still return FileInfo objects" {
            InModuleScope dbatools {
                $functionNames = @(
                    "Backup-DbaDbCertificate",
                    "Backup-DbaDbMasterKey",
                    "Connect-DbaInstance",
                    "Copy-Item",
                    "Get-ChildItem",
                    "Join-AdminUnc",
                    "Remove-Item",
                    "Stop-Function",
                    "Test-DbaPath",
                    "Test-ExportDirectory",
                    "Test-FunctionInterrupt",
                    "Test-Path",
                    "Write-Message",
                    "Write-Progress",
                    "Write-ProgressHelper"
                )
                $originalFunctions = @{ }
                foreach ($functionName in $functionNames) {
                    if (Test-Path "Function:\$functionName") {
                        $originalFunctions[$functionName] = (Get-Item -Path "Function:\$functionName").ScriptBlock
                    }
                }

                try {
                    function Test-ExportDirectory { }
                    function Test-FunctionInterrupt { $false }
                    function Write-Message { }
                    function Write-Progress { }
                    function Write-ProgressHelper { }
                    function Test-Path { $true }
                    function Stop-Function {
                        param(
                            $Message,
                            $ErrorRecord
                        )
                        if ($ErrorRecord) {
                            throw "$Message | inner: $($ErrorRecord.Exception.Message)"
                        }
                        throw $Message
                    }
                    function Connect-DbaInstance {
                        $server = [PSCustomObject]@{
                            ComputerName       = "sql1"
                            DomainInstanceName = "sql1"
                        }
                        $server.PSObject.TypeNames.Clear()
                        $server.PSObject.TypeNames.Add("Microsoft.SqlServer.Management.Smo.Server")
                        $server
                    }
                    function Test-DbaPath {
                        param(
                            $SqlInstance,
                            $Path
                        )
                        $Path -ne "C:\temp\sql1"
                    }
                    function Join-AdminUnc {
                        param(
                            $Servername,
                            $Filepath
                        )
                        $adminSharePath = $Filepath.Substring(0, 1) + [char]36 + $Filepath.Substring(2)
                        "\\$Servername\$adminSharePath"
                    }
                    function Copy-Item {
                        param(
                            $Path,
                            $Destination,
                            [switch]$Force,
                            $ErrorAction
                        )
                        $script:copiedFiles += [PSCustomObject]@{
                            Path        = $Path
                            Destination = $Destination
                        }
                    }
                    function Remove-Item {
                        param(
                            $Path,
                            [switch]$Force,
                            $ErrorAction
                        )
                        if ("$Path" -like "\\sql1\*") {
                            $script:removedFiles += $Path
                        }
                    }
                    function Get-ChildItem {
                        param(
                            $Path,
                            $ErrorAction
                        )
                        New-Object -TypeName System.IO.FileInfo -ArgumentList $Path
                    }
                    function Backup-DbaDbCertificate {
                        $script:certificateBackupParams = $PSBoundParameters
                        [PSCustomObject]@{
                            Path = "D:\sqlbackup\cert1.cer"
                            Key  = "D:\sqlbackup\cert1.pvk"
                        }
                    }
                    function Backup-DbaDbMasterKey {
                        $script:masterKeyBackupParams = $PSBoundParameters
                        [PSCustomObject]@{
                            Filename = "D:\sqlbackup\db1-masterkey.key"
                        }
                    }

                    $script:certificateBackupParams = $null
                    $script:masterKeyBackupParams = $null
                    $script:copiedFiles = @()
                    $script:removedFiles = @()
                    $excludedObjects = @(
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
                        "SystemTriggers",
                        "OleDbProvider"
                    )
                    $encryptionPassword = ConvertTo-SecureString -String "P@ssw0rd!" -AsPlainText -Force

                    $results = Export-DbaInstance -SqlInstance "sql1" -Path "C:\temp" -IncludeDbMasterKey -EncryptionPassword $encryptionPassword -Exclude $excludedObjects -Force

                    $script:certificateBackupParams.ContainsKey("Path") | Should -BeFalse
                    $script:masterKeyBackupParams.ContainsKey("Path") | Should -BeFalse
                    @($results).Count | Should -Be 3
                    $results.FullName | Should -Be @(
                        "C:\temp\sql1\cert1.cer",
                        "C:\temp\sql1\cert1.pvk",
                        "C:\temp\sql1\db1-masterkey.key"
                    )
                    foreach ($result in $results) {
                        $result.GetType().FullName | Should -Be "System.IO.FileInfo"
                    }
                    $script:copiedFiles.Destination | Should -Be $results.FullName
                    $script:removedFiles | Should -Be @(
                        "\\sql1\D$\sqlbackup\cert1.cer",
                        "\\sql1\D$\sqlbackup\cert1.pvk",
                        "\\sql1\D$\sqlbackup\db1-masterkey.key"
                    )
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

    It "Runs begin and end once across a two-record pipe" {
        # The per-instance work is function-scoped in the source, but the elapsed-time report lives
        # in end and the scripting options object is built in begin. Counting the verbose lines is
        # the only external evidence of how many times each block ran: the elapsed-time line has to
        # appear once no matter how many instances are piped, and the per-instance line once per
        # record - a record silently skipped or an end block folded into the record loop moves one
        # of these counts.
        $splatTwoRecord = @{
            Path    = $exportDir
            Exclude = @("AgentServer", "Audits", "AvailabilityGroups", "BackupDevices", "CentralManagementServer", "Credentials", "CustomErrors", "DatabaseMail", "Databases", "DbCertificates", "Endpoints", "ExtendedEvents", "LinkedServers", "Logins", "PolicyManagement", "ReplicationSettings", "ResourceGovernor", "ServerAuditSpecifications", "ServerRoles", "SysDbUserObjects", "SystemTriggers", "OleDbProvider")
            Force   = $true
            Verbose = $true
        }
        $twoRecordOutput = @(@($testServer, $testServer) | Export-DbaInstance @splatTwoRecord 4>&1)

        $twoRecordVerbose = @($twoRecordOutput | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })
        $results = @($twoRecordOutput | Where-Object { $_ -is [System.IO.FileInfo] })

        # Not anchored at the start: Write-Message prepends "[HH:mm:ss][Export-DbaInstance] " to the
        # verbose record whenever the message.* display config asks for it, and that config is a
        # per-session setting no assertion here should depend on. The tail is still exact.
        @($twoRecordVerbose -match "Total Elapsed time: \d").Count | Should -Be 1
        @($twoRecordVerbose -match "Exporting SQL Server Configuration$").Count | Should -Be 2
        $results.Count | Should -BeGreaterThan 0
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

    It "Export policies" {
        # The command gates its Policy Management branch on $PSVersionTable.PSEdition -ne "Core",
        # because the PBM classes are not usable under pwsh. That guard is behaviour in its own
        # right, so this runs on both editions and asserts the edition-appropriate outcome rather
        # than skipping on pwsh - a leg that never executes on an edition proves nothing about it.
        $splatPolicies = @{
            SqlInstance = $testServer
            Path        = $exportDir
            Exclude     = @("AgentServer", "Audits", "AvailabilityGroups", "BackupDevices", "CentralManagementServer", "Credentials", "CustomErrors", "DatabaseMail", "Databases", "Endpoints", "ExtendedEvents", "LinkedServers", "Logins", "ReplicationSettings", "ResourceGovernor", "ServerAuditSpecifications", "ServerRoles", "SpConfigure", "SysDbUserObjects", "SystemTriggers", "OleDbProvider")
        }
        $results = @(Export-DbaInstance @splatPolicies)
        $policyFile = @($results | Where-Object { $PSItem.Name -eq "policymanagement.sql" })

        if ($PSVersionTable.PSEdition -eq "Core") {
            # PolicyManagement is the only object type this call leaves un-excluded, so the guarded
            # branch not running means the whole call produces nothing.
            $policyFile.Count | Should -Be 0
            $results.Count | Should -Be 0
        } else {
            $policyFile.Count | Should -Be 1
            $policyFile[0].FullName | Should -Exist
            $policyFile[0].Length | Should -BeGreaterThan 0
        }
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
            $probeBody = @"
Import-Module -Name "$moduleBase\dbatools.psm1" -DisableNameChecking
`$resolved = Get-Command -Name Export-DbaInstance -ErrorAction SilentlyContinue
`$allResolved = @(Get-Command -Name Export-DbaInstance -All -ErrorAction SilentlyContinue)
`$functionCount = @(`$allResolved | Where-Object { `$PSItem.CommandType -eq "Function" }).Count
`$satelliteLoaded = [bool](Get-Module -Name dbatools.migration)
"RESOLVED|`$(`$resolved.CommandType)|`$(`$resolved.ModuleName)|`$functionCount|`$satelliteLoaded"
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
    }
}