#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbServiceBrokerQueue",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: azure-sqldb N/A -- Service Broker is not supported in Azure SQL Database (Microsoft Learn, features comparison: Azure SQL Managed Instance only), and SMO's ServiceQueue enumerator declares no cloud support.

Describe "Native Service Broker queue behavior" -Tag IntegrationTests {
    BeforeAll {
        $brokerQueueDatabase = $null
        $brokerQueueSecondServer = $null
        $brokerQueueServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $splatBrokerQueueSecondConnection = @{
            SqlInstance         = $brokerQueueServer
            Database            = "tempdb"
            NonPooledConnection = $true
            EnableException     = $true
        }
        $brokerQueueSecondServer = Connect-DbaInstance @splatBrokerQueueSecondConnection
        if ([object]::ReferenceEquals($brokerQueueServer, $brokerQueueSecondServer)) {
            throw "The pipeline fixture requires distinct SMO Server objects"
        }
        $brokerQueueDatabase = $brokerQueueServer.Databases["tempdb"]
        $brokerQueueName = "native_queue_$([Guid]::NewGuid().ToString("N"))"
        $brokerQueueFixture = New-Object Microsoft.SqlServer.Management.Smo.Broker.ServiceQueue -ArgumentList $brokerQueueDatabase.ServiceBroker, $brokerQueueName, "dbo"
        $brokerQueueFixture.Create()
        $brokerQueueBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $brokerQueueListeners = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
        if (@($brokerQueueListeners | Where-Object Port -eq 1).Count) {
            throw "Queue failure fixture requires no local TCP listener on port 1"
        }
    }

    AfterAll {
        if ($brokerQueueDatabase -and $brokerQueueName) {
            $brokerQueueDatabase.ServiceBroker.Queues.Refresh()
            $brokerQueueCleanup = $brokerQueueDatabase.ServiceBroker.Queues[$brokerQueueName, "dbo"]
            if ($null -ne $brokerQueueCleanup) { $brokerQueueCleanup.Drop() }
        }
        if ($brokerQueueSecondServer) { $brokerQueueSecondServer.ConnectionContext.Disconnect() }
    }

    It "preserves typed queues and replaces stale metadata and QueueID aliases" {
        foreach ($brokerQueueProperty in @("ComputerName", "InstanceName", "SqlInstance", "Database", "QueueID")) {
            $splatBrokerQueueStaleProperty = @{
                InputObject = $brokerQueueFixture
                MemberType  = "NoteProperty"
                Name        = $brokerQueueProperty
                Value       = "stale"
                Force       = $true
            }
            Add-Member @splatBrokerQueueStaleProperty
        }
        $splatBrokerQueueMetadata = @{
            SqlInstance     = $brokerQueueServer
            Database        = "tempdb"
            EnableException = $true
        }
        $brokerQueueMetadataRows = @(Get-DbaDbServiceBrokerQueue @splatBrokerQueueMetadata | Where-Object Name -eq $brokerQueueName)
        $brokerQueueMetadataRows.Count | Should -Be 1
        $brokerQueueMetadataRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.Broker.ServiceQueue
        $brokerQueueMetadataRows[0].Database | Should -BeExactly "tempdb"
        $brokerQueueMetadataRows[0].Schema | Should -BeExactly "dbo"
        $brokerQueueMetadataRows[0].ComputerName | Should -Not -BeNullOrEmpty
        $brokerQueueMetadataRows[0].ComputerName | Should -Not -Be "stale"
        $brokerQueueMetadataRows[0].InstanceName | Should -BeExactly $brokerQueueServer.ServiceName
        $brokerQueueMetadataRows[0].SqlInstance | Should -BeExactly $brokerQueueServer.DomainInstanceName
        $brokerQueueMetadataRows[0].QueueID | Should -Be $brokerQueueMetadataRows[0].ID
        $brokerQueueMetadataRows[0].PSObject.Properties["QueueID"].MemberType | Should -Be "AliasProperty"
        ($brokerQueueMetadataRows[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
            Should -BeExactly "ComputerName,InstanceName,SqlInstance,Database,Schema,QueueID,CreateDate,DateLastModified,Name,ProcedureName,ProcedureSchema"
    }

    It "includes system queues by default and when -ExcludeSystemQueue is explicitly false" -Tag "NativeChecklist:switch-false" {
        # Pinned public/Get-DbaDbServiceBrokerQueue.ps1:123 uses Test-Bound, so an explicit false
        # switch still excluded system queues (dead parameter value). Explicit false is now absent.
        $splatBrokerQueueSystem = @{
            SqlInstance     = $brokerQueueServer
            Database        = "tempdb"
            EnableException = $true
        }
        $brokerQueueAll = @(Get-DbaDbServiceBrokerQueue @splatBrokerQueueSystem)
        @($brokerQueueAll | Where-Object IsSystemObject).Count | Should -BeGreaterThan 0
        $splatBrokerQueueSystem.ExcludeSystemQueue = $false
        $brokerQueueExplicitFalse = @(Get-DbaDbServiceBrokerQueue @splatBrokerQueueSystem)
        @($brokerQueueExplicitFalse | Where-Object IsSystemObject).Count | Should -Be @($brokerQueueAll | Where-Object IsSystemObject).Count
        @($brokerQueueExplicitFalse | Where-Object Name -eq $brokerQueueName).Count | Should -Be 1
        $splatBrokerQueueSystem.ExcludeSystemQueue = $true
        $brokerQueueFiltered = @(Get-DbaDbServiceBrokerQueue @splatBrokerQueueSystem)
        @($brokerQueueFiltered | Where-Object IsSystemObject).Count | Should -Be 0
        @($brokerQueueFiltered | Where-Object Name -eq $brokerQueueName).Count | Should -Be 1
    }

    It "preserves exact case-insensitive database inclusion and exclusion" {
        $splatBrokerQueueFilter = @{
            SqlInstance     = $brokerQueueServer
            Database        = "TEMPDB"
            EnableException = $true
        }
        @(Get-DbaDbServiceBrokerQueue @splatBrokerQueueFilter | Where-Object Name -eq $brokerQueueName).Count | Should -Be 1
        $splatBrokerQueueFilter.Database = "tempdb"
        $splatBrokerQueueFilter.ExcludeDatabase = "TEMPDB"
        @(Get-DbaDbServiceBrokerQueue @splatBrokerQueueFilter).Count | Should -Be 0
    }

    It "keeps distinct pipeline records around a failed connection with outer EnableException=<OuterException>" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" -TestCases @(
        @{ OuterException = $false }
        @{ OuterException = $true }
    ) {
        param($OuterException)
        $brokerQueueWarnings = @()
        $brokerQueuePreviousErrors = @($global:Error)
        $splatBrokerQueuePipeline = @{
            Database        = "tempdb"
            EnableException = $OuterException
            WarningAction   = "SilentlyContinue"
            WarningVariable = "brokerQueueWarnings"
        }
        $brokerQueueRows = @(
            @($brokerQueueServer, $brokerQueueBadInstance, $brokerQueueSecondServer) |
                Get-DbaDbServiceBrokerQueue @splatBrokerQueuePipeline |
                Where-Object Name -eq $brokerQueueName
        )
        $brokerQueueRows.Count | Should -Be 2
        [object]::ReferenceEquals($brokerQueueRows[0].Parent.Parent.Parent, $brokerQueueServer) | Should -BeTrue
        [object]::ReferenceEquals($brokerQueueRows[1].Parent.Parent.Parent, $brokerQueueSecondServer) | Should -BeTrue
        ($brokerQueueWarnings -join " ") | Should -BeLike "*Failure*"
        $brokerQueueHelperError = $global:Error | Where-Object {
            $brokerQueuePreviousErrors -notcontains $PSItem -and $PSItem.FullyQualifiedErrorId -like "dbatools_Get-DbaDatabase*"
        } | Select-Object -First 1
        $brokerQueueHelperError | Should -Not -BeNullOrEmpty
        $brokerQueueHelperError.CategoryInfo.Category | Should -Be "ConnectionError"
    }

    # NativeChecklist: whatif-confirm N/A -- read-only command; no SupportsShouldProcess or WhatIf/Confirm parameters.

    Context "Documented wildcard database selection" {
        BeforeAll {
            # Pinned help :20 and :24 document wildcards for -Database and -ExcludeDatabase; :109
            # delegates to the exact-match Get-DbaDatabase, so the documented form never took effect.
            # Every new database contains the system Service Broker queues.
            $brokerQueueWildcardPrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $brokerQueueWildcardNames = @(
                "${brokerQueueWildcardPrefix}_a"
                "${brokerQueueWildcardPrefix}_b"
                "${brokerQueueWildcardPrefix}_[a]"
            )
            $brokerQueueWildcardCreated = New-Object System.Collections.Generic.List[string]
            foreach ($brokerQueueWildcardName in $brokerQueueWildcardNames) {
                $brokerQueueWildcardDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $brokerQueueServer, $brokerQueueWildcardName
                $brokerQueueWildcardDatabase.Create()
                $brokerQueueWildcardCreated.Add($brokerQueueWildcardName)
            }
        }

        AfterAll {
            $brokerQueueServer.Databases.Refresh()
            foreach ($brokerQueueWildcardName in $brokerQueueWildcardCreated) {
                if ($brokerQueueServer.Databases[$brokerQueueWildcardName]) {
                    $brokerQueueServer.KillDatabase($brokerQueueWildcardName)
                }
            }
        }

        It "selects databases by a documented wildcard pattern" {
            $splatBrokerQueueWildcard = @{
                SqlInstance     = $brokerQueueServer
                Database        = "${brokerQueueWildcardPrefix}_*"
                EnableException = $true
            }
            $brokerQueueWildcardRows = @(Get-DbaDbServiceBrokerQueue @splatBrokerQueueWildcard)
            (($brokerQueueWildcardRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($brokerQueueWildcardNames | Sort-Object) -join ",")
            $splatBrokerQueueWildcard.Database = "${brokerQueueWildcardPrefix}_?"
            $brokerQueueWildcardRows = @(Get-DbaDbServiceBrokerQueue @splatBrokerQueueWildcard)
            (($brokerQueueWildcardRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($brokerQueueWildcardNames[0, 1] | Sort-Object) -join ",")
        }

        It "excludes databases by a documented wildcard pattern" {
            $splatBrokerQueueExclude = @{
                SqlInstance     = $brokerQueueServer
                Database        = $brokerQueueWildcardNames
                ExcludeDatabase = "${brokerQueueWildcardPrefix}_?"
                EnableException = $true
            }
            $brokerQueueExcludeRows = @(Get-DbaDbServiceBrokerQueue @splatBrokerQueueExclude)
            (($brokerQueueExcludeRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly $brokerQueueWildcardNames[2]
        }

        It "keeps bracket-only and invalid values literal, with exclusion taking precedence" {
            $splatBrokerQueueLiteral = @{
                SqlInstance     = $brokerQueueServer
                Database        = $brokerQueueWildcardNames[2]
                EnableException = $true
            }
            $brokerQueueLiteralRows = @(Get-DbaDbServiceBrokerQueue @splatBrokerQueueLiteral)
            (($brokerQueueLiteralRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly $brokerQueueWildcardNames[2]
            $splatBrokerQueueLiteral.Database = "${brokerQueueWildcardPrefix}_[*"
            @(Get-DbaDbServiceBrokerQueue @splatBrokerQueueLiteral).Count | Should -Be 0
            $splatBrokerQueueLiteral.Database = $brokerQueueWildcardNames
            $splatBrokerQueueLiteral.ExcludeDatabase = @("${brokerQueueWildcardPrefix}_[*", $brokerQueueWildcardNames[2])
            $brokerQueueLiteralRows = @(Get-DbaDbServiceBrokerQueue @splatBrokerQueueLiteral)
            (($brokerQueueLiteralRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($brokerQueueWildcardNames[0, 1] | Sort-Object) -join ",")
        }
    }

    Context "Real database names containing wildcard characters" {
        BeforeAll {
            # Rule E+ (pinned help :20 and :24 document -Database and -ExcludeDatabase wildcards): a value equal to a real database name stays
            # literal, so a caller passing a real name containing * or ? never reaches other databases.
            function New-NativeWildcardNameDatabase {
                param($Server, [string]$Name, [string]$FileStem)
                # Names with * or ? are not valid Windows file names, so the files get explicit names.
                $dataDirectory = $Server.DefaultFile
                if (-not $dataDirectory) { $dataDirectory = $Server.MasterDBPath }
                $logDirectory = $Server.DefaultLog
                if (-not $logDirectory) { $logDirectory = $Server.MasterDBLogPath }
                $separator = "\"
                if ($dataDirectory -match "/" -and $dataDirectory -notmatch "\\") { $separator = "/" }
                $database = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $Server, $Name
                $fileGroup = New-Object Microsoft.SqlServer.Management.Smo.FileGroup -ArgumentList $database, "PRIMARY"
                $database.FileGroups.Add($fileGroup)
                $dataPath = $dataDirectory.TrimEnd("\", "/") + $separator + $FileStem + ".mdf"
                $dataFile = New-Object Microsoft.SqlServer.Management.Smo.DataFile -ArgumentList $fileGroup, ($FileStem + "_data"), $dataPath
                $dataFile.IsPrimaryFile = $true
                $fileGroup.Files.Add($dataFile)
                $logPath = $logDirectory.TrimEnd("\", "/") + $separator + $FileStem + "_log.ldf"
                $logFile = New-Object Microsoft.SqlServer.Management.Smo.LogFile -ArgumentList $database, ($FileStem + "_log"), $logPath
                $database.LogFiles.Add($logFile)
                $database.Create()
                $database
            }
            $brokerQueueRealNamePrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $brokerQueueRealNameNames = @("${brokerQueueRealNamePrefix}_*", "${brokerQueueRealNamePrefix}_?", "${brokerQueueRealNamePrefix}_x")
            $brokerQueueRealNameCreated = New-Object System.Collections.Generic.List[string]
            foreach ($brokerQueueRealNameIndex in 0, 1, 2) {
                $brokerQueueRealNameName = $brokerQueueRealNameNames[$brokerQueueRealNameIndex]
                $brokerQueueRealNameDatabase = New-NativeWildcardNameDatabase -Server $brokerQueueServer -Name $brokerQueueRealNameName -FileStem ("${brokerQueueRealNamePrefix}_file" + $brokerQueueRealNameIndex)
                $brokerQueueRealNameCreated.Add($brokerQueueRealNameName)
            }
        }

        AfterAll {
            $brokerQueueServer.Databases.Refresh()
            foreach ($brokerQueueRealNameName in $brokerQueueRealNameCreated) {
                if ($brokerQueueServer.Databases[$brokerQueueRealNameName]) {
                    $brokerQueueServer.KillDatabase($brokerQueueRealNameName)
                }
            }
        }

        It "selects a real database whose name contains * or ? alone by its exact name" {
            $splatBrokerQueueRealNameExact = @{
                SqlInstance     = $brokerQueueServer
                Database        = $brokerQueueRealNameNames[0]
                EnableException = $true
            }
            $brokerQueueRealNameRows = @(Get-DbaDbServiceBrokerQueue @splatBrokerQueueRealNameExact)
            (($brokerQueueRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly $brokerQueueRealNameNames[0]
            $splatBrokerQueueRealNameExact.Database = $brokerQueueRealNameNames[1].ToUpperInvariant()
            $brokerQueueRealNameRows = @(Get-DbaDbServiceBrokerQueue @splatBrokerQueueRealNameExact)
            (($brokerQueueRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly $brokerQueueRealNameNames[1]
            $splatBrokerQueueRealNameExact.Database = $brokerQueueRealNameNames[0, 1]
            $brokerQueueRealNameRows = @(Get-DbaDbServiceBrokerQueue @splatBrokerQueueRealNameExact)
            (($brokerQueueRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($brokerQueueRealNameNames[0, 1] | Sort-Object) -join ",")
        }

        It "expands a non-colliding pattern beside databases whose names contain * or ?" {
            $splatBrokerQueueRealNamePattern = @{
                SqlInstance     = $brokerQueueServer
                Database        = "${brokerQueueRealNamePrefix}*"
                EnableException = $true
            }
            $brokerQueueRealNameRows = @(Get-DbaDbServiceBrokerQueue @splatBrokerQueueRealNamePattern)
            (($brokerQueueRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($brokerQueueRealNameNames | Sort-Object) -join ",")
            $splatBrokerQueueRealNamePattern.ExcludeDatabase = $brokerQueueRealNameNames[1]
            $brokerQueueRealNameRows = @(Get-DbaDbServiceBrokerQueue @splatBrokerQueueRealNamePattern)
            (($brokerQueueRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($brokerQueueRealNameNames[0, 2] | Sort-Object) -join ",")
        }

        It "excludes only a real database whose name contains * or ? when its exact name is excluded" {
            $splatBrokerQueueRealNameExclude = @{
                SqlInstance     = $brokerQueueServer
                Database        = $brokerQueueRealNameNames
                ExcludeDatabase = $brokerQueueRealNameNames[1]
                EnableException = $true
            }
            $brokerQueueRealNameRows = @(Get-DbaDbServiceBrokerQueue @splatBrokerQueueRealNameExclude)
            (($brokerQueueRealNameRows.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($brokerQueueRealNameNames[0, 2] | Sort-Object) -join ",")
        }
    }

    It "does not write the empty-queue message for a database whose system queues exist" {
        # Pinned public/Get-DbaDbServiceBrokerQueue.ps1:117-118 checks Count -eq 0 before any filter,
        # so system queues keep the message away even when -ExcludeSystemQueue removes them all.
        $brokerQueueEmptyText = "No Service Broker Queues exist in the [tempdb] database on"
        $brokerQueueEmptyBefore = @([Dataplat.Dbatools.Message.LogHost]::GetLog() | Where-Object { $PSItem.Message -and $PSItem.Message.StartsWith($brokerQueueEmptyText) }).Count
        $splatBrokerQueueSystemOnly = @{
            SqlInstance        = $brokerQueueServer
            Database           = "tempdb"
            ExcludeSystemQueue = $true
            EnableException    = $true
            Verbose            = $true
        }
        $brokerQueueSystemOnlyRecords = @(Get-DbaDbServiceBrokerQueue @splatBrokerQueueSystemOnly 4>&1)
        @($brokerQueueSystemOnlyRecords | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*No Service Broker Queues exist*" }).Count | Should -Be 0
        @($brokerQueueSystemOnlyRecords | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] -and $PSItem.IsSystemObject }).Count | Should -Be 0
        @([Dataplat.Dbatools.Message.LogHost]::GetLog() | Where-Object { $PSItem.Message -and $PSItem.Message.StartsWith($brokerQueueEmptyText) }).Count | Should -Be $brokerQueueEmptyBefore
    }

    Context "Connection callback failures" {
        BeforeAll {
            $gatherProbeMessage = "native gather callback probe " + [Guid]::NewGuid().ToString("N")
            $gatherProbeAssembly = (Get-Command -Name "Get-DbaDbServiceBrokerQueue" -CommandType Cmdlet).ImplementingType.Assembly
            $gatherProbeSelection = $gatherProbeAssembly.GetType("Dataplat.Dbatools.Commands.NativeDatabaseSelection", $true)
            $gatherProbeMethod = $gatherProbeSelection.GetMethod("Gather", [System.Reflection.BindingFlags]"Static, NonPublic")
            if ($null -eq $gatherProbeMethod) {
                throw "The callback fixture requires NativeDatabaseSelection.Gather"
            }
            if (-not ([System.Management.Automation.PSTypeName]"NativeDatabaseSelectionTests.InvokeNativeGatherCallbackProbe").Type) {
                $gatherProbeSource = @"
using System;
using System.Management.Automation;
using System.Reflection;
using System.Runtime.ExceptionServices;
using Dataplat.Dbatools.Commands;
using Dataplat.Dbatools.Parameter;
namespace NativeDatabaseSelectionTests {
    [Cmdlet(VerbsLifecycle.Invoke, "NativeGatherCallbackProbe")]
    public sealed class InvokeNativeGatherCallbackProbe : DbaBaseCmdlet {
        [Parameter(Mandatory = true)]
        public DbaInstanceParameter[] SqlInstance { get; set; }
        [Parameter(Mandatory = true)]
        public MethodInfo Gather { get; set; }
        [Parameter(Mandatory = true)]
        public string FailureMessage { get; set; }
        public void Fail(object server) { throw new InvalidOperationException(FailureMessage); }
        protected override void ProcessRecord() {
            ParameterInfo[] parameters = Gather.GetParameters();
            Delegate connected = Delegate.CreateDelegate(parameters[5].ParameterType, this, GetType().GetMethod("Fail"));
            Func<bool> interrupted = delegate { return false; };
            object result;
            try {
                result = Gather.Invoke(null, new object[] { this, SqlInstance, null, null, null, connected, interrupted });
            } catch (TargetInvocationException e) {
                ExceptionDispatchInfo.Capture(e.InnerException).Throw();
                throw;
            }
            WriteObject(result, true);
        }
    }
}
"@
                $splatGatherProbeType = @{
                    TypeDefinition       = $gatherProbeSource
                    ReferencedAssemblies = @(
                        [Dataplat.Dbatools.Commands.DbaBaseCmdlet].Assembly.Location
                        [Microsoft.Data.SqlClient.SqlCommand].Assembly.Location
                        [Microsoft.SqlServer.Management.Common.ServerConnection].Assembly.Location
                        [psobject].Assembly.Location
                    )
                    IgnoreWarnings       = $true
                }
                Add-Type @splatGatherProbeType
            }
            Import-Module -Assembly ([System.Management.Automation.PSTypeName]"NativeDatabaseSelectionTests.InvokeNativeGatherCallbackProbe").Type.Assembly
        }

        It "surfaces a failing connection callback instead of reporting a connection failure" {
            # Upstream connects inside Get-DbaDatabase and has no caller callback, so only the
            # connection attempt itself may produce the "Failure" ConnectionError warning.
            $gatherProbeWarnings = @()
            $gatherProbePreviousErrors = @($global:Error)
            $gatherProbeCaught = $null
            $splatGatherProbe = @{
                SqlInstance     = $brokerQueueServer
                Gather          = $gatherProbeMethod
                FailureMessage  = $gatherProbeMessage
                WarningAction   = "SilentlyContinue"
                WarningVariable = "gatherProbeWarnings"
            }
            try {
                $null = Invoke-NativeGatherCallbackProbe @splatGatherProbe
            } catch {
                $gatherProbeCaught = $PSItem
            }
            $gatherProbeCaught | Should -Not -BeNullOrEmpty
            $gatherProbeException = $gatherProbeCaught.Exception
            while ($null -ne $gatherProbeException -and $gatherProbeException -isnot [System.InvalidOperationException]) {
                $gatherProbeException = $gatherProbeException.InnerException
            }
            $gatherProbeException.Message | Should -BeExactly $gatherProbeMessage
            ($gatherProbeWarnings -join " ") | Should -Not -BeLike "*Failure*"
            $gatherProbeHelperErrors = @($global:Error | Where-Object {
                    $gatherProbePreviousErrors -notcontains $PSItem -and $PSItem.FullyQualifiedErrorId -like "dbatools_Get-DbaDatabase*"
                })
            $gatherProbeHelperErrors.Count | Should -Be 0
        }
    }
}

Describe "Native Get-DbaDbServiceBrokerQueue over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDbName = "native_queue_sqllogin_" + [Guid]::NewGuid().ToString("N")
            $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
            $loginDatabase.Create()
            $loginQueue = New-Object Microsoft.SqlServer.Management.Smo.Broker.ServiceQueue -ArgumentList $loginDatabase.ServiceBroker, "native_login_queue", "dbo"
            $loginQueue.Create()
        }
        AfterAll {
            if ($loginServer) {
                # KillDatabase ends the command's pooled connections before the drop.
                $loginServer.Databases.Refresh()
                if ($loginServer.Databases[$loginDbName]) {
                    $loginServer.KillDatabase($loginDbName)
                }
            }
        }

        It "works with -SqlCredential" {
            $splatLoginQueue = @{
                SqlInstance        = $loginInstance
                SqlCredential      = $loginCred
                Database           = $loginDbName
                ExcludeSystemQueue = $true
                EnableException    = $true
            }
            $loginRows = @(Get-DbaDbServiceBrokerQueue @splatLoginQueue)
            ($loginRows.Name -join ",") | Should -BeExactly "native_login_queue"
            $loginRows[0].Parent.Parent.Name | Should -BeExactly $loginDbName
        }

        It "fails cleanly without the credential: a warning and no output with either EnableException value" {
            # As upstream, the connection failure belongs to the nested database gather, which is not given
            # -EnableException, so it warns and continues in both cases.
            foreach ($loginEnableException in $false, $true) {
                $loginWarnings = @()
                $splatLoginNoCredential = @{
                    SqlInstance     = $loginInstance
                    Database        = $loginDbName
                    EnableException = $loginEnableException
                    WarningAction   = "SilentlyContinue"
                    WarningVariable = "loginWarnings"
                }
                $loginResult = @(Get-DbaDbServiceBrokerQueue @splatLoginNoCredential)
                $loginResult.Count | Should -Be 0
                ($loginWarnings -join " ") | Should -BeLike "*Failure*"
            }
        }
    }
}
