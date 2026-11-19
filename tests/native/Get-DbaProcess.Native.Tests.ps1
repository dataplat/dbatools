#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaProcess",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command is read-only and has no SupportsShouldProcess.

Describe "Get-DbaProcess native statement faults" -Tag IntegrationTests {
    BeforeAll {
        $faultFixtures = @{}
        $faultAdmin = $null
        $faultName = 'native_process_fault_' + [guid]::NewGuid().ToString('N')
        $faultAdmin = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -ClientName ($faultName + '_admin') -NonPooledConnection
        $faultAdmin | Should -Not -BeNullOrEmpty
        $faultAdmin.ConnectionContext.Connect()
        $faultSql = [Dataplat.Dbatools.Commands.GetDbaProcessCommand].GetField('DetailSql', [System.Reflection.BindingFlags]'Static, NonPublic').GetRawConstantValue()
        $faultSql | Should -BeLike '*FROM sys.dm_exec_connections*'
        foreach ($site in 'Query', 'EnumProcesses') {
            $name = $faultName + '_' + $site
            $password = ConvertTo-SecureString ('Npf!' + [guid]::NewGuid().ToString('N')) -AsPlainText -Force
            $fixture = [pscustomobject]@{ Name = $name; Password = $password; Created = $false; Server = $null; WindowsConnection = $null; Impersonating = $false; OriginalLogin = $null; Reference = $null }
            $faultFixtures[$site] = $fixture
            $login = New-Object Microsoft.SqlServer.Management.Smo.Login -ArgumentList $faultAdmin, $name
            $login.LoginType = [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin
            $login.DefaultDatabase = 'master'
            $login.PasswordPolicyEnforced = $false
            $login.Create($password) # teardown-ok: unique login tracked before creation; AfterAll drops only its user/login and sessions.
            $fixture.Created = $true
            $null = $faultAdmin.ConnectionContext.ExecuteNonQuery("USE [master]; CREATE USER [$name] FOR LOGIN [$name];") # teardown-ok: unique user dropped by AfterAll even when later setup fails.
            if ($site -eq 'EnumProcesses') {
                $null = $faultAdmin.ConnectionContext.ExecuteNonQuery("GRANT VIEW SERVER STATE TO [$name]; USE [master]; DENY SELECT ON OBJECT::sys.sysprocesses TO [$name];") # teardown-ok: only the unique fixture principal; AfterAll drops it.
            }
            # Pool hosts need not allow SQL authentication. Keep the Windows connection
            # open and impersonate only this fixture principal, as the permission tests do.
            $fixture.WindowsConnection = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -ClientName $name -NonPooledConnection -EnableException
            $fixture.WindowsConnection | Should -Not -BeNullOrEmpty
            $fixture.Server = New-Object Microsoft.SqlServer.Management.Smo.Server -ArgumentList ($fixture.WindowsConnection.ConnectionContext.Copy())
            $fixture.Server.ConnectionContext.Connect()
            $fixture.OriginalLogin = $fixture.Server.ConnectionContext.ExecuteScalar('SELECT SUSER_SNAME()')
            $null = $fixture.Server.ConnectionContext.ExecuteNonQuery("EXECUTE AS LOGIN = N'$name'")
            $fixture.Impersonating = $true
            $fixture.Server.ConnectionContext.ExecuteScalar('SELECT SUSER_SNAME()') | Should -BeExactly $name
            # These are the pin's two expressions, measured separately by the manager on both editions.
            try {
                if ($site -eq 'Query') { $null = $fixture.Server.Query($faultSql) }
                else { $null = $fixture.Server.EnumProcesses() }
            } catch { $fixture.Reference = $PSItem }
            $fixture.Reference | Should -Not -BeNullOrEmpty
            if ($site -eq 'Query') {
                $fixture.Reference.FullyQualifiedErrorId | Should -BeExactly 'ScriptMethodRuntimeException'
                $fixture.Server.EnumProcesses().Rows.Count | Should -BeGreaterThan 0
            } else {
                $fixture.Reference.FullyQualifiedErrorId | Should -BeExactly 'FailedOperationException'
                @($fixture.Server.Query($faultSql)).Count | Should -BeGreaterThan 0
            }
        }

        function Invoke-NativeProcessFault {
            param($Restricted, $Healthy, [string]$Mode)
            $state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $entry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList 'Get-DbaProcess', ([Dataplat.Dbatools.Commands.GetDbaProcessCommand]), $null
            $state.Commands.Add($entry)
            $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($state)
            $shell = [System.Management.Automation.PowerShell]::Create()
            $captured = New-Object 'System.Management.Automation.PSDataCollection[psobject]'
            try {
                $runspace.Open()
                $shell.Runspace = $runspace
                $null = $shell.AddScript(@'
param($restricted, $healthy, $mode)
$ErrorActionPreference = 'Continue'
$Error.Clear()
$global:NativeProcessErrors = @()
$arguments = @{ SqlInstance = @($restricted, $healthy); ErrorVariable = '+global:NativeProcessErrors'; EnableException = $false }
if ($mode -in @('EnableException', 'EnableExceptionCallerTry')) { $arguments.EnableException = $true }
if ($mode -in @('ErrorActionStop', 'ErrorActionStopCallerTry')) { $arguments.ErrorAction = 'Stop' }
if ($mode -eq 'SilentlyContinue') { $arguments.ErrorAction = 'SilentlyContinue' }
if ($mode -in @('CallerTry', 'EnableExceptionCallerTry', 'ErrorActionStopCallerTry')) {
    try { Get-DbaProcess @arguments; [pscustomobject]@{ Marker = 'Next' } }
    catch { [pscustomobject]@{ Marker = 'Caught'; Record = $PSItem } }
} else {
    Get-DbaProcess @arguments
    [pscustomobject]@{ Marker = 'Next' }
}
'@).AddArgument($Restricted).AddArgument($Healthy).AddArgument($Mode)
                $stopped = $null
                try { $null = $shell.Invoke($null, $captured) } catch { $stopped = $PSItem.Exception.InnerException }
                [pscustomobject]@{
                    Rows = @($captured | Where-Object { -not $_.PSObject.Properties['Marker'] })
                    Next = @($captured | Where-Object Marker -eq Next).Count
                    Caught = @($captured | Where-Object Marker -eq Caught | ForEach-Object Record)
                    Errors = @($shell.Streams.Error); Warnings = @($shell.Streams.Warning)
                    History = @($runspace.SessionStateProxy.GetVariable('Error'))
                    ErrorVariable = @($runspace.SessionStateProxy.GetVariable('NativeProcessErrors'))
                    Stop = $stopped
                }
            } finally { $captured.Dispose(); $shell.Dispose(); $runspace.Dispose() }
        }

        function Assert-NativeProcessFaultRecord {
            param($Actual, $Reference, [string]$Activity)
            $Actual | Should -BeOfType System.Management.Automation.ErrorRecord
            $Actual.FullyQualifiedErrorId | Should -BeExactly ($Reference.FullyQualifiedErrorId + ',Dataplat.Dbatools.Commands.GetDbaProcessCommand')
            $Actual.CategoryInfo.Category | Should -Be $Reference.CategoryInfo.Category
            $Actual.CategoryInfo.Reason | Should -BeExactly $Reference.CategoryInfo.Reason
            $Actual.CategoryInfo.Activity | Should -BeExactly $Activity
            $Actual.CategoryInfo.TargetName | Should -BeExactly $Reference.CategoryInfo.TargetName
            $Actual.CategoryInfo.TargetType | Should -BeExactly $Reference.CategoryInfo.TargetType
            $Actual.TargetObject | Should -Be $Reference.TargetObject
            $Actual.ErrorDetails | Should -Be $Reference.ErrorDetails
            $actualCause = $Actual.Exception
            $expectedCause = $Reference.Exception
            while ($null -ne $expectedCause) {
                $actualCause | Should -Not -BeNullOrEmpty
                $actualCause.GetType().FullName | Should -BeExactly $expectedCause.GetType().FullName
                $actualCause.Message | Should -BeExactly $expectedCause.Message
                $actualCause.HResult | Should -Be $expectedCause.HResult
                $actualCause = $actualCause.InnerException
                $expectedCause = $expectedCause.InnerException
            }
            $actualCause | Should -BeNullOrEmpty
        }
    }

    AfterAll {
        $cleanupErrors = @()
        try {
            foreach ($fixture in $faultFixtures.Values) {
                try {
                    if ($null -ne $fixture.Server) {
                        try {
                            if ($fixture.Impersonating) {
                                $null = $fixture.Server.ConnectionContext.ExecuteNonQuery('REVERT')
                                $fixture.Server.ConnectionContext.ExecuteScalar('SELECT SUSER_SNAME()') | Should -BeExactly $fixture.OriginalLogin
                            }
                        } finally { $fixture.Server.ConnectionContext.Disconnect() }
                    }
                } catch { $cleanupErrors += $PSItem }
                finally { if ($null -ne $fixture.WindowsConnection) { $fixture.WindowsConnection.ConnectionContext.Disconnect() } }
                try {
                    if ($fixture.Created) {
                        $name = $fixture.Name
                        foreach ($row in $faultAdmin.ConnectionContext.ExecuteWithResults("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$name';").Tables[0].Rows) {
                            $sessionId = [int]$row.session_id
                            $null = $faultAdmin.ConnectionContext.ExecuteNonQuery("KILL $sessionId;")
                        }
                        $null = $faultAdmin.ConnectionContext.ExecuteNonQuery("USE [master]; IF USER_ID(N'$name') IS NOT NULL DROP USER [$name]; IF SUSER_ID(N'$name') IS NOT NULL DROP LOGIN [$name];")
                        $remaining = $faultAdmin.ConnectionContext.ExecuteWithResults("SELECT SUSER_ID(N'$name') AS LoginId, USER_ID(N'$name') AS UserId;").Tables[0].Rows[0]
                        $remaining.LoginId | Should -BeOfType System.DBNull
                        $remaining.UserId | Should -BeOfType System.DBNull
                    }
                } catch { $cleanupErrors += $PSItem }
                finally { $fixture.Password.Dispose() }
            }
        } finally { if ($null -ne $faultAdmin) { $faultAdmin.ConnectionContext.Disconnect() } }
        if ($cleanupErrors.Count -gt 0) { throw ($cleanupErrors | Out-String) }
    }

    It "surfaces the real <Site> fault and preserves caller flow with <Mode>" -TestCases @(
        foreach ($site in 'Query', 'EnumProcesses') {
            foreach ($mode in 'Plain', 'EnableException', 'ErrorActionStop', 'CallerTry', 'EnableExceptionCallerTry', 'ErrorActionStopCallerTry', 'SilentlyContinue') {
                @{ Site = $site; Mode = $mode }
            }
        }
    ) {
        param($Site, $Mode)
        $fixture = $faultFixtures[$Site]
        $outcome = Invoke-NativeProcessFault $fixture.Server $faultAdmin $Mode
        $fixture.Server.ConnectionContext.ExecuteScalar('SELECT SUSER_SNAME()') | Should -BeExactly $fixture.Name
        $outcome.Warnings.Count | Should -Be 0
        # Full ordered sequences measured on both editions; the native engine owns wrappers and Activity.
        $bareType = 'System.Management.Automation.ErrorRecord'
        $historyTypes = @($bareType)
        $variableTypes = @('System.Management.Automation.CmdletInvocationException')
        if ($Mode -in @('Plain', 'SilentlyContinue')) {
            $variableTypes = @($bareType)
        } elseif ($Mode -eq 'ErrorActionStop') {
            $historyTypes = @('System.Management.Automation.ActionPreferenceStopException', $bareType)
            $variableTypes = @('System.Management.Automation.ActionPreferenceStopException')
        }
        foreach ($channel in 'History', 'ErrorVariable') {
            $entries = @($outcome.$channel)
            $expectedTypes = if ($channel -eq 'History') { $historyTypes } else { $variableTypes }
            $entries.Count | Should -Be @($expectedTypes).Count
            for ($entryIndex = 0; $entryIndex -lt $entries.Count; $entryIndex++) {
                $entry = $entries[$entryIndex]
                $entry.GetType().FullName | Should -BeExactly @($expectedTypes)[$entryIndex]
                $record = if ($entry -is [System.Management.Automation.ErrorRecord]) { $entry } else { $entry.ErrorRecord }
                Assert-NativeProcessFaultRecord $record $fixture.Reference 'Get-DbaProcess'
            }
        }
        if ($Mode -in @('Plain', 'SilentlyContinue')) {
            $outcome.Stop | Should -BeNullOrEmpty
            $outcome.Caught.Count | Should -Be 0
            $outcome.Next | Should -Be 1
            $outcome.Errors.Count | Should -Be $(if ($Mode -eq 'Plain') { 1 } else { 0 })
            $restrictedRows = @($outcome.Rows | Where-Object { [object]::ReferenceEquals($PSItem.Parent, $fixture.Server) })
            $healthyRows = @($outcome.Rows | Where-Object { [object]::ReferenceEquals($PSItem.Parent, $faultAdmin) })
            ($restrictedRows.Count + $healthyRows.Count) | Should -Be $outcome.Rows.Count
            $healthyRows.Count | Should -BeGreaterThan 0
            if ($Site -eq 'Query') { $restrictedRows.Count | Should -BeGreaterThan 0 }
            else { $restrictedRows.Count | Should -Be 0 }
            if ($Mode -eq 'Plain') { Assert-NativeProcessFaultRecord $outcome.Errors[0] $fixture.Reference 'Get-DbaProcess' }
            $outcome.ErrorVariable.Count | Should -Be 1
            Assert-NativeProcessFaultRecord $outcome.ErrorVariable[0] $fixture.Reference 'Get-DbaProcess'
        } elseif ($Mode -eq 'EnableException') {
            $outcome.Stop | Should -BeNullOrEmpty
            $outcome.Caught.Count | Should -Be 0
            $outcome.Rows.Count | Should -Be 0
            $outcome.Next | Should -Be 1
            $outcome.Errors.Count | Should -Be 1
            Assert-NativeProcessFaultRecord $outcome.Errors[0] $fixture.Reference 'Get-DbaProcess'
            $outcome.ErrorVariable.Count | Should -Be 1
            $outcome.ErrorVariable[0].GetType().FullName | Should -BeExactly 'System.Management.Automation.CmdletInvocationException'
            Assert-NativeProcessFaultRecord $outcome.ErrorVariable[0].ErrorRecord $fixture.Reference 'Get-DbaProcess'
            $outcome.History.Count | Should -Be 1
            Assert-NativeProcessFaultRecord $outcome.History[0] $fixture.Reference 'Get-DbaProcess'
        } elseif ($Mode -eq 'ErrorActionStop') {
            $outcome.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outcome.Errors.Count | Should -Be 0
            $outcome.Rows.Count | Should -Be 0
            $outcome.Next | Should -Be 0
            $outcome.Caught.Count | Should -Be 0
            Assert-NativeProcessFaultRecord $outcome.Stop.ErrorRecord $fixture.Reference 'Get-DbaProcess'
        } else {
            $outcome.Stop | Should -BeNullOrEmpty
            $outcome.Rows.Count | Should -Be 0
            $outcome.Next | Should -Be 0
            $outcome.Errors.Count | Should -Be 0
            $outcome.Caught.Count | Should -Be 1
            Assert-NativeProcessFaultRecord $outcome.Caught[0] $fixture.Reference 'Get-DbaProcess'
        }
    }
}

Describe "Get-DbaProcess native contract" -Tag IntegrationTests {
    BeforeAll {
        $processPrefix = "native_process_" + [guid]::NewGuid().ToString("N")
        $processAppA = $processPrefix + "_a"
        $processAppB = $processPrefix + "_b"
        $processAdmin = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $splatProcessA = @{
            SqlInstance         = $TestConfig.InstanceSingle
            ClientName          = $processAppA
            Database            = "master"
            NonPooledConnection = $true
            EnableException     = $true
        }
        $splatProcessB = @{
            SqlInstance         = $TestConfig.InstanceSingle
            ClientName          = $processAppB
            Database            = "tempdb"
            NonPooledConnection = $true
            EnableException     = $true
        }
        $processA = Connect-DbaInstance @splatProcessA
        $processB = Connect-DbaInstance @splatProcessB
        $processA.ConnectionContext.Connect()
        $processB.ConnectionContext.Connect()
        $processSpidA = [int]$processA.ConnectionContext.ExecuteScalar("SELECT @@SPID /* $processAppA */")
        $processSpidB = [int]$processB.ConnectionContext.ExecuteScalar("SELECT @@SPID /* $processAppB */")
        $processDisplay = "ComputerName,InstanceName,SqlInstance,Spid,Login,LoginTime,Host,Database,BlockingSpid,Program,Status,Command,Cpu,MemUsage,LastRequestStartTime,LastRequestEndTime,MinutesAsleep,ClientNetAddress,NetTransport,EncryptOption,AuthScheme,NetPacketSize,ClientVersion,HostProcessId,IsSystem,EndpointName,IsDac,LastQuery"
    }

    AfterAll {
        if ($processB) { $processB.ConnectionContext.Disconnect() }
        if ($processA) { $processA.ConnectionContext.Disconnect() }
    }

    It "returns the live session and connection values with the pinned row type and display" {
        $splatProcessRead = @{
            SqlInstance     = $processAdmin
            Program         = $processAppA
            EnableException = $true
        }
        $processRows = @(Get-DbaProcess @splatProcessRead)
        $processRows.Count | Should -Be 1
        $processRow = $processRows[0]
        $processRow | Should -BeOfType System.Data.DataRow
        $processRow.Spid | Should -Be $processSpidA
        $processRow.Program | Should -BeExactly $processAppA
        $processRow.Database | Should -BeExactly "master"
        $processRow.Status | Should -Be "sleeping"
        $processRow.Command | Should -Be "AWAITING COMMAND"
        $processRow.LastQuery | Should -BeLike "*$processAppA*"
        $processRow.Parent | Should -BeOfType Microsoft.SqlServer.Management.Smo.Server
        $processRow.ComputerName | Should -BeExactly $processAdmin.ComputerName
        $processRow.InstanceName | Should -BeExactly $processAdmin.ServiceName
        $processRow.SqlInstance | Should -BeExactly $processAdmin.DomainInstanceName
        ($processRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $processDisplay
        $processReference = $processAdmin.ConnectionContext.ExecuteWithResults(@"
SELECT s.login_name AS Login, s.host_name AS Host, s.host_process_id AS HostProcessId,
    s.login_time AS LoginTime, s.client_version AS ClientVersion, c.net_transport AS NetTransport,
    c.encrypt_option AS EncryptOption, c.auth_scheme AS AuthScheme, c.net_packet_size AS NetPacketSize,
    c.client_net_address AS ClientNetAddress, e.name AS EndpointName, e.is_admin_endpoint AS IsDac
FROM sys.dm_exec_sessions s JOIN sys.dm_exec_connections c ON s.session_id = c.session_id
JOIN sys.endpoints e ON c.endpoint_id = e.endpoint_id WHERE s.session_id = $processSpidA
"@).Tables[0].Rows[0]
        foreach ($processProperty in @("Login", "Host", "HostProcessId", "LoginTime", "ClientVersion", "NetTransport", "EncryptOption", "AuthScheme", "NetPacketSize", "ClientNetAddress", "EndpointName", "IsDac")) {
            $processRow.$processProperty | Should -Be $processReference.$processProperty
        }
    }

    It "keeps union filter order and deduplicates earlier filter matches" {
        $splatProcessUnion = @{
            SqlInstance     = $processAdmin
            Spid            = $processSpidB
            Program         = @($processAppA, $processAppB)
            EnableException = $true
        }
        $processUnion = @(Get-DbaProcess @splatProcessUnion)
        ($processUnion.Spid -join ",") | Should -BeExactly "$processSpidB,$processSpidA"
    }

    It "intersects active filters and compares names without case sensitivity" {
        $splatProcessIntersection = @{
            SqlInstance     = $processAdmin
            Spid            = @($processSpidA, $processSpidB)
            Program         = $processAppA.ToUpperInvariant()
            Database        = "MASTER"
            Intersect       = $true
            EnableException = $true
        }
        $processIntersection = @(Get-DbaProcess @splatProcessIntersection)
        $processIntersection.Count | Should -Be 1
        $processIntersection[0].Spid | Should -Be $processSpidA
    }

    It "preserves explicit false switches and the bound empty inclusion form" -Tag NativeChecklist:switch-false {
        $splatProcessFalse = @{
            SqlInstance        = $processAdmin
            Program            = @($processAppA, $processAppB)
            ExcludeSystemSpids = $false
            Intersect          = $false
            EnableException    = $false
        }
        $processFalse = @(Get-DbaProcess @splatProcessFalse)
        ($processFalse.Spid | Sort-Object) -join "," | Should -BeExactly ((@($processSpidA, $processSpidB) | Sort-Object) -join ",")
        @(Get-DbaProcess -SqlInstance $processAdmin -Spid @()).Count | Should -Be 0
        $processSystem = @(Get-DbaProcess -SqlInstance $processAdmin -ExcludeSystemSpids)
        $processSystem.Count | Should -BeGreaterThan 0
        @($processSystem | Where-Object Spid -LE 50).Count | Should -Be 0
    }

    It "streams both array instances and both pipeline instances" -Tag NativeChecklist:pipeline-multiple {
        $splatProcessMultiple = @{
            Program         = $processAppA
            EnableException = $true
        }
        $processArray = @(Get-DbaProcess -SqlInstance $processAdmin, $processAdmin @splatProcessMultiple)
        $processPipeline = @(@($processAdmin, $processAdmin) | Get-DbaProcess @splatProcessMultiple)
        $processArray.Count | Should -Be 2
        $processPipeline.Count | Should -Be 2
        ($processArray.Spid -join ",") | Should -BeExactly "$processSpidA,$processSpidA"
        ($processPipeline.Spid -join ",") | Should -BeExactly "$processSpidA,$processSpidA"
    }

    It "continues after a connection warning and stops when EnableException is requested" -Tag NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception {
        $processMissing = "np" + [guid]::NewGuid().ToString("N").Substring(0, 12)
        $processWarnings = @()
        $splatProcessFailure = @{
            SqlInstance     = @($processMissing, $processAdmin)
            Program         = $processAppA
            EnableException = $false
            WarningVariable = "processWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $processSurvivors = @(Get-DbaProcess @splatProcessFailure)
        $processSurvivors.Count | Should -Be 1
        $processSurvivors[0].Spid | Should -Be $processSpidA
        ($processWarnings -join " ") | Should -BeLike "*Failure*"
        $splatProcessFailure.EnableException = $true
        { Get-DbaProcess @splatProcessFailure } | Should -Throw
    }

    It "applies ExcludeSpid after inclusion filters" {
        $splatProcessExclude = @{
            SqlInstance     = $processAdmin
            Spid            = @($processSpidA, $processSpidB)
            ExcludeSpid     = $processSpidA
            EnableException = $true
        }
        $processExcluded = @(Get-DbaProcess @splatProcessExclude)
        $processExcluded.Count | Should -Be 1
        $processExcluded[0].Spid | Should -Be $processSpidB
        $splatProcessExclude.Intersect = $true
        $processExcludedIntersection = @(Get-DbaProcess @splatProcessExclude)
        $processExcludedIntersection.Count | Should -Be 1
        $processExcludedIntersection[0].Spid | Should -Be $processSpidB
    }

    It "allows ExcludeSpid by itself without dropping unrelated sessions" {
        $splatProcessExcludeOnly = @{
            SqlInstance     = $processAdmin
            ExcludeSpid     = $processSpidA
            EnableException = $true
        }
        $processExcludeOnly = @(Get-DbaProcess @splatProcessExcludeOnly)
        @($processExcludeOnly | Where-Object Spid -EQ $processSpidA).Count | Should -Be 0
        @($processExcludeOnly | Where-Object Spid -EQ $processSpidB).Count | Should -Be 1
    }
}

Describe "Get-DbaProcess SQL login" -Tag IntegrationTests, NativeChecklist:sql-login {
    It "reads sessions using the supplied SQL credential" {
        $splatProcessLogin = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            SqlCredential   = $TestConfig.SqlLoginCred
            EnableException = $true
        }
        @(Get-DbaProcess @splatProcessLogin).Count | Should -BeGreaterThan 0
    }

    It "warns without the required SQL credential and stops with EnableException" {
        $processLoginWarnings = @()
        $splatProcessNoLogin = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            SqlCredential   = $null
            WarningVariable = "processLoginWarnings"
            WarningAction   = "SilentlyContinue"
            EnableException = $false
        }
        @(Get-DbaProcess @splatProcessNoLogin).Count | Should -Be 0
        ($processLoginWarnings -join " ") | Should -BeLike "*Failure*Login failed*"
        $splatProcessNoLogin.EnableException = $true
        { Get-DbaProcess @splatProcessNoLogin } | Should -Throw
    }
}

Describe "Get-DbaProcess Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $processAzureApp = "native_process_" + [guid]::NewGuid().ToString("N")
        $splatProcessAzureConnect = @{
            SqlInstance         = $TestConfig.AzureSqlDbServer
            Database            = $TestConfig.AzureSqlDbName
            SqlCredential       = $TestConfig.AzureSqlDbCred
            ClientName          = $processAzureApp
            NonPooledConnection = $true
            ConnectTimeout      = 60
            EnableException     = $true
        }
        for ($processAzureAttempt = 0; $processAzureAttempt -le 6; $processAzureAttempt++) {
            try {
                $processAzureServer = Connect-DbaInstance @splatProcessAzureConnect
                break
            } catch {
                $processAzureFailure = $PSItem.Exception
                $processAzureResuming = $false
                while ($processAzureFailure) {
                    if ($processAzureFailure.Number -in 40613, -2 -or $processAzureFailure.NativeErrorCode -eq 258 -or $processAzureFailure.Message -match "timeout|timed out") { $processAzureResuming = $true }
                    $processAzureFailure = $processAzureFailure.InnerException
                }
                if (-not $processAzureResuming -or $processAzureAttempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $processAzureServer.ConnectionContext.Connect()
        $processAzureSpid = [int]$processAzureServer.ConnectionContext.ExecuteScalar("SELECT @@SPID")
    }

    AfterAll {
        if ($processAzureServer) { $processAzureServer.ConnectionContext.Disconnect() }
    }

    It "returns database-scoped Azure sessions and identifies unavailable endpoint metadata" -Tag NativeChecklist:azure-sqldb {
        $processAzureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $processAzureWarnings = @()
        $splatProcessAzureRead = @{
            SqlInstance     = $processAzureServer
            Program         = $processAzureApp
            EnableException = $true
            WarningVariable = "processAzureWarnings"
            WarningAction   = "SilentlyContinue"
        }
        $processAzureRows = @(Get-DbaProcess @splatProcessAzureRead)
        $processAzureRows.Count | Should -BeGreaterThan 0
        $processAzureRow = @($processAzureRows | Where-Object Spid -EQ $processAzureSpid)
        $processAzureRow.Count | Should -Be 1
        $processAzureRow[0] | Should -BeOfType System.Data.DataRow
        $processAzureRow[0].Database | Should -BeExactly $TestConfig.AzureSqlDbName
        $processAzureRow[0].Program | Should -BeExactly $processAzureApp
        $processAzureRow[0].NetTransport | Should -Not -BeNullOrEmpty
        $processAzureRow[0].LoginTime | Should -BeOfType datetime
        $processAzureRow[0].PSObject.Properties["Query"] | Should -BeNullOrEmpty
        $processAzureRow[0].PSObject.Properties["LastQuery"].MemberType.ToString() | Should -BeExactly "NoteProperty"
        $processAzureRow[0].EndpointName | Should -BeNullOrEmpty
        $processAzureRow[0].IsDac | Should -BeNullOrEmpty
        ($processAzureWarnings -join " ") | Should -BeLike "*Azure SQL Database*EndpointName*IsDac*"
    }
}
