#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbUserDefinedTableType",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native user-defined table type behavior" -Tag IntegrationTests {
    BeforeAll {
        $tableTypeServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $tableTypeDatabase = $tableTypeServer.Databases["tempdb"]
        $tableTypeName = "native_udtt_$([Guid]::NewGuid().ToString("N"))"
        $tableTypeFixture = New-Object Microsoft.SqlServer.Management.Smo.UserDefinedTableType($tableTypeDatabase, $tableTypeName, "dbo")
        $tableTypeColumn = New-Object Microsoft.SqlServer.Management.Smo.Column($tableTypeFixture, "value", [Microsoft.SqlServer.Management.Smo.DataType]::Int)
        $tableTypeFixture.Columns.Add($tableTypeColumn)
        $tableTypeFixture.Create()
        $tableTypeBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $tableTypeListeners = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
        if (@($tableTypeListeners | Where-Object Port -eq 1).Count) {
            throw "Table type failure fixture requires no local TCP listener on port 1"
        }
    }

    AfterAll {
        if ($tableTypeDatabase -and $tableTypeName) {
            $tableTypeDatabase.UserDefinedTableTypes.Refresh()
            $tableTypeCleanup = $tableTypeDatabase.UserDefinedTableTypes[$tableTypeName, "dbo"]
            if ($null -ne $tableTypeCleanup) { $tableTypeCleanup.Drop() }
        }
    }

    It "preserves typed objects, metadata and the documented default display" {
        $splatTableTypeMetadata = @{
            SqlInstance = $tableTypeServer
            Database = "tempdb"
            Type = $tableTypeName
            EnableException = $true
        }
        $tableTypeRows = @(Get-DbaDbUserDefinedTableType @splatTableTypeMetadata)
        $tableTypeRows.Count | Should -Be 1
        $tableTypeRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.UserDefinedTableType
        $tableTypeRows[0].Name | Should -BeExactly $tableTypeName
        $tableTypeRows[0].Database | Should -BeExactly "tempdb"
        $tableTypeRows[0].ComputerName | Should -Not -BeNullOrEmpty
        $tableTypeRows[0].InstanceName | Should -BeExactly $tableTypeServer.ServiceName
        $tableTypeRows[0].SqlInstance | Should -BeExactly $tableTypeServer.DomainInstanceName
        ($tableTypeRows[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
            Should -BeExactly "ComputerName,InstanceName,SqlInstance,Database,ID,Name,Columns,Owner,CreateDate,IsSystemObject,Version"
    }

    It "uses exact case-insensitive type and database filters" {
        $splatTableTypeFilter = @{
            SqlInstance = $tableTypeServer
            Database = "TEMPDB"
            Type = $tableTypeName.ToUpperInvariant()
            EnableException = $true
        }
        @(Get-DbaDbUserDefinedTableType @splatTableTypeFilter).Count | Should -Be 1
        $splatTableTypeFilter.Type = "$tableTypeName*"
        @(Get-DbaDbUserDefinedTableType @splatTableTypeFilter).Count | Should -Be 0
        $splatTableTypeFilter.Type = $tableTypeName
        $splatTableTypeFilter.ExcludeDatabase = "TEMPDB"
        @(Get-DbaDbUserDefinedTableType @splatTableTypeFilter).Count | Should -Be 0
    }

    It "emits results for each successful pipeline record" -Tag "NativeChecklist:pipeline-multiple" {
        $splatTableTypePipeline = @{
            Database = "tempdb"
            Type = $tableTypeName
            EnableException = $true
        }
        $tableTypeRows = @(@($tableTypeServer, $tableTypeServer) | Get-DbaDbUserDefinedTableType @splatTableTypePipeline)
        $tableTypeRows.Count | Should -Be 2
        foreach ($tableTypeRow in $tableTypeRows) {
            $tableTypeRow.Name | Should -BeExactly $tableTypeName
        }
    }

    It "warns for a failed middle connection and retains both successful records" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $tableTypeWarnings = @()
        $splatTableTypeContinue = @{
            Database = "tempdb"
            Type = $tableTypeName
            EnableException = $false
            WarningAction = "SilentlyContinue"
            WarningVariable = "tableTypeWarnings"
        }
        $tableTypeRows = @(@($tableTypeServer, $tableTypeBadInstance, $tableTypeServer) | Get-DbaDbUserDefinedTableType @splatTableTypeContinue)
        $tableTypeRows.Count | Should -Be 2
        ($tableTypeWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "preserves the database helper warning when outer EnableException is true" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
        $tableTypeOuterWarnings = @()
        $tableTypePreviousErrors = @($global:Error)
        $splatTableTypeOuterException = @{
            Database = "tempdb"
            Type = $tableTypeName
            EnableException = $true
            WarningAction = "SilentlyContinue"
            WarningVariable = "tableTypeOuterWarnings"
        }
        $tableTypeRows = @(@($tableTypeServer, $tableTypeBadInstance, $tableTypeServer) | Get-DbaDbUserDefinedTableType @splatTableTypeOuterException)
        $tableTypeRows.Count | Should -Be 2
        ($tableTypeOuterWarnings -join " ") | Should -BeLike "*Failure*"
        $tableTypeHelperError = $global:Error | Where-Object {
            $tableTypePreviousErrors -notcontains $PSItem -and $PSItem.FullyQualifiedErrorId -like "dbatools_Get-DbaDatabase*"
        } | Select-Object -First 1
        $tableTypeHelperError | Should -Not -BeNullOrEmpty
        $tableTypeHelperError.CategoryInfo.Category | Should -Be "ConnectionError"
    }

    # NativeChecklist: whatif-confirm N/A -- read-only command; no SupportsShouldProcess or WhatIf/Confirm parameters.

    Context "Documented wildcard database selection" {
        BeforeAll {
            # Pinned help :20 and :24 document wildcards for -Database and -ExcludeDatabase; :102
            # delegates to the exact-match Get-DbaDatabase, so the documented form never took effect.
            # Help :28 documents no wildcards for -Type, which stays exact.
            $tableTypeWildcardPrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $tableTypeWildcardNames = @(
                "${tableTypeWildcardPrefix}_a"
                "${tableTypeWildcardPrefix}_b"
                "${tableTypeWildcardPrefix}_[a]"
            )
            $tableTypeWildcardCreated = New-Object System.Collections.Generic.List[string]
            foreach ($tableTypeWildcardName in $tableTypeWildcardNames) {
                $tableTypeWildcardDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $tableTypeServer, $tableTypeWildcardName
                $tableTypeWildcardDatabase.Create()
                $tableTypeWildcardCreated.Add($tableTypeWildcardName)
                $tableTypeWildcardDatabase.ExecuteNonQuery("CREATE TYPE [dbo].[native_wc_tt] AS TABLE ([value] int);")
            }
        }

        AfterAll {
            $tableTypeServer.Databases.Refresh()
            foreach ($tableTypeWildcardName in $tableTypeWildcardCreated) {
                if ($tableTypeServer.Databases[$tableTypeWildcardName]) {
                    $tableTypeServer.KillDatabase($tableTypeWildcardName)
                }
            }
        }

        It "selects databases by a documented wildcard pattern" {
            $splatTableTypeWildcard = @{
                SqlInstance     = $tableTypeServer
                Database        = "${tableTypeWildcardPrefix}_*"
                Type            = "native_wc_tt"
                EnableException = $true
            }
            $tableTypeWildcardRows = @(Get-DbaDbUserDefinedTableType @splatTableTypeWildcard)
            (($tableTypeWildcardRows.Database | Sort-Object) -join ",") | Should -BeExactly (($tableTypeWildcardNames | Sort-Object) -join ",")
            $splatTableTypeWildcard.Database = "${tableTypeWildcardPrefix}_?"
            $tableTypeWildcardRows = @(Get-DbaDbUserDefinedTableType @splatTableTypeWildcard)
            (($tableTypeWildcardRows.Database | Sort-Object) -join ",") | Should -BeExactly (($tableTypeWildcardNames[0, 1] | Sort-Object) -join ",")
        }

        It "excludes databases by a documented wildcard pattern" {
            $splatTableTypeExclude = @{
                SqlInstance     = $tableTypeServer
                Database        = $tableTypeWildcardNames
                ExcludeDatabase = "${tableTypeWildcardPrefix}_?"
                Type            = "native_wc_tt"
                EnableException = $true
            }
            $tableTypeExcludeRows = @(Get-DbaDbUserDefinedTableType @splatTableTypeExclude)
            ($tableTypeExcludeRows.Database -join ",") | Should -BeExactly $tableTypeWildcardNames[2]
        }

        It "keeps bracket-only, invalid and type wildcard values literal, with exclusion taking precedence" {
            $splatTableTypeLiteral = @{
                SqlInstance     = $tableTypeServer
                Database        = $tableTypeWildcardNames[2]
                Type            = "native_wc_tt"
                EnableException = $true
            }
            $tableTypeLiteralRows = @(Get-DbaDbUserDefinedTableType @splatTableTypeLiteral)
            ($tableTypeLiteralRows.Database -join ",") | Should -BeExactly $tableTypeWildcardNames[2]
            $splatTableTypeLiteral.Database = "${tableTypeWildcardPrefix}_[*"
            @(Get-DbaDbUserDefinedTableType @splatTableTypeLiteral).Count | Should -Be 0
            $splatTableTypeLiteral.Database = $tableTypeWildcardNames
            $splatTableTypeLiteral.ExcludeDatabase = @("${tableTypeWildcardPrefix}_[*", $tableTypeWildcardNames[2])
            $tableTypeLiteralRows = @(Get-DbaDbUserDefinedTableType @splatTableTypeLiteral)
            (($tableTypeLiteralRows.Database | Sort-Object) -join ",") | Should -BeExactly (($tableTypeWildcardNames[0, 1] | Sort-Object) -join ",")
            $splatTableTypeLiteral.Remove("ExcludeDatabase")
            $splatTableTypeLiteral.Type = "native_wc_*"
            @(Get-DbaDbUserDefinedTableType @splatTableTypeLiteral).Count | Should -Be 0
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
            $tableTypeRealNamePrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $tableTypeRealNameNames = @("${tableTypeRealNamePrefix}_*", "${tableTypeRealNamePrefix}_?", "${tableTypeRealNamePrefix}_x")
            $tableTypeRealNameCreated = New-Object System.Collections.Generic.List[string]
            foreach ($tableTypeRealNameIndex in 0, 1, 2) {
                $tableTypeRealNameName = $tableTypeRealNameNames[$tableTypeRealNameIndex]
                $tableTypeRealNameDatabase = New-NativeWildcardNameDatabase -Server $tableTypeServer -Name $tableTypeRealNameName -FileStem ("${tableTypeRealNamePrefix}_file" + $tableTypeRealNameIndex)
                $tableTypeRealNameCreated.Add($tableTypeRealNameName)
                $tableTypeRealNameDatabase.ExecuteNonQuery("CREATE TYPE [dbo].[native_wc_tt] AS TABLE ([value] int);")
            }
        }

        AfterAll {
            $tableTypeServer.Databases.Refresh()
            foreach ($tableTypeRealNameName in $tableTypeRealNameCreated) {
                if ($tableTypeServer.Databases[$tableTypeRealNameName]) {
                    $tableTypeServer.KillDatabase($tableTypeRealNameName)
                }
            }
        }

        It "selects a real database whose name contains * or ? alone by its exact name" {
            $splatTableTypeRealNameExact = @{
                SqlInstance     = $tableTypeServer
                Database        = $tableTypeRealNameNames[0]
                Type            = "native_wc_tt"
                EnableException = $true
            }
            $tableTypeRealNameRows = @(Get-DbaDbUserDefinedTableType @splatTableTypeRealNameExact)
            (($tableTypeRealNameRows.Database | Sort-Object) -join ",") | Should -BeExactly $tableTypeRealNameNames[0]
            $splatTableTypeRealNameExact.Database = $tableTypeRealNameNames[1].ToUpperInvariant()
            $tableTypeRealNameRows = @(Get-DbaDbUserDefinedTableType @splatTableTypeRealNameExact)
            (($tableTypeRealNameRows.Database | Sort-Object) -join ",") | Should -BeExactly $tableTypeRealNameNames[1]
            $splatTableTypeRealNameExact.Database = $tableTypeRealNameNames[0, 1]
            $tableTypeRealNameRows = @(Get-DbaDbUserDefinedTableType @splatTableTypeRealNameExact)
            (($tableTypeRealNameRows.Database | Sort-Object) -join ",") | Should -BeExactly (($tableTypeRealNameNames[0, 1] | Sort-Object) -join ",")
        }

        It "expands a non-colliding pattern beside databases whose names contain * or ?" {
            $splatTableTypeRealNamePattern = @{
                SqlInstance     = $tableTypeServer
                Database        = "${tableTypeRealNamePrefix}*"
                Type            = "native_wc_tt"
                EnableException = $true
            }
            $tableTypeRealNameRows = @(Get-DbaDbUserDefinedTableType @splatTableTypeRealNamePattern)
            (($tableTypeRealNameRows.Database | Sort-Object) -join ",") | Should -BeExactly (($tableTypeRealNameNames | Sort-Object) -join ",")
            $splatTableTypeRealNamePattern.ExcludeDatabase = $tableTypeRealNameNames[1]
            $tableTypeRealNameRows = @(Get-DbaDbUserDefinedTableType @splatTableTypeRealNamePattern)
            (($tableTypeRealNameRows.Database | Sort-Object) -join ",") | Should -BeExactly (($tableTypeRealNameNames[0, 2] | Sort-Object) -join ",")
        }

        It "excludes only a real database whose name contains * or ? when its exact name is excluded" {
            $splatTableTypeRealNameExclude = @{
                SqlInstance     = $tableTypeServer
                Database        = $tableTypeRealNameNames
                ExcludeDatabase = $tableTypeRealNameNames[1]
                Type            = "native_wc_tt"
                EnableException = $true
            }
            $tableTypeRealNameRows = @(Get-DbaDbUserDefinedTableType @splatTableTypeRealNameExclude)
            (($tableTypeRealNameRows.Database | Sort-Object) -join ",") | Should -BeExactly (($tableTypeRealNameNames[0, 2] | Sort-Object) -join ",")
        }
    }

    Context "Empty user-defined table type results" {
        BeforeAll {
            $tableTypeEmptyCreated = $false
            $tableTypeEmptyName = "native_udtt_empty_" + [Guid]::NewGuid().ToString("N")
            $tableTypeEmptyDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $tableTypeServer, $tableTypeEmptyName
            $tableTypeEmptyDatabase.Create()
            $tableTypeEmptyCreated = $true
            $tableTypeEmptyMessage = "No User Defined Table Types exist in the [$tableTypeEmptyName] database on"
        }

        AfterAll {
            if ($tableTypeEmptyCreated) {
                $splatRemoveTableTypeEmpty = @{
                    SqlInstance     = $tableTypeServer
                    Database        = $tableTypeEmptyName
                    Confirm         = $false
                    EnableException = $true
                }
                Remove-DbaDatabase @splatRemoveTableTypeEmpty
            }
        }

        It "writes the Output-level message for a database without table types, outside the verbose stream" {
            # Pinned public/Get-DbaDbUserDefinedTableType.ps1:110-111 checks Count -eq 0 and writes at Level Output.
            $tableTypeEmptyBefore = @([Dataplat.Dbatools.Message.LogHost]::GetLog() | Where-Object { $PSItem.Message -and $PSItem.Message.StartsWith($tableTypeEmptyMessage) }).Count
            $splatTableTypeEmpty = @{
                SqlInstance     = $tableTypeServer
                Database        = $tableTypeEmptyName
                EnableException = $true
                Verbose         = $true
            }
            $tableTypeEmptyRecords = @(Get-DbaDbUserDefinedTableType @splatTableTypeEmpty 4>&1)
            @($tableTypeEmptyRecords | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] }).Count | Should -Be 0
            @($tableTypeEmptyRecords | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*No User Defined Table Types exist*" }).Count | Should -Be 0
            $tableTypeEmptyEntries = @([Dataplat.Dbatools.Message.LogHost]::GetLog() | Where-Object { $PSItem.Message -and $PSItem.Message.StartsWith($tableTypeEmptyMessage) })
            ($tableTypeEmptyEntries.Count - $tableTypeEmptyBefore) | Should -Be 1
            $tableTypeEmptyEntry = $tableTypeEmptyEntries[-1]
            $tableTypeEmptyEntry.FunctionName | Should -BeExactly "Get-DbaDbUserDefinedTableType"
            $tableTypeEmptyEntry.Level | Should -Be ([Dataplat.Dbatools.Message.MessageLevel]::Output)
            $tableTypeEmptyEntry.Type.HasFlag([Dataplat.Dbatools.Message.LogEntryType]::Verbose) | Should -BeFalse
        }

        It "does not write the message for a database that has a table type" {
            $splatTableTypePopulated = @{
                SqlInstance     = $tableTypeServer
                Database        = "tempdb"
                Type            = $tableTypeName
                EnableException = $true
            }
            $tableTypePopulatedBefore = @([Dataplat.Dbatools.Message.LogHost]::GetLog() | Where-Object { $PSItem.Message -and $PSItem.Message.StartsWith("No User Defined Table Types exist in the [tempdb] database on") }).Count
            @(Get-DbaDbUserDefinedTableType @splatTableTypePopulated).Count | Should -Be 1
            @([Dataplat.Dbatools.Message.LogHost]::GetLog() | Where-Object { $PSItem.Message -and $PSItem.Message.StartsWith("No User Defined Table Types exist in the [tempdb] database on") }).Count | Should -Be $tableTypePopulatedBefore
        }
    }

    Context "Connection callback failures" {
        BeforeAll {
            $gatherProbeMessage = "native gather callback probe " + [Guid]::NewGuid().ToString("N")
            $gatherProbeAssembly = (Get-Command -Name "Get-DbaDbUserDefinedTableType" -CommandType Cmdlet).ImplementingType.Assembly
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
                SqlInstance     = $tableTypeServer
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

Describe "Native Get-DbaDbUserDefinedTableType on Azure SQL Database" -Tag IntegrationTests {
    It "reads a user-defined table type in Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            EnableException = $true
        }
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613 while it resumes.
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -eq 40613) { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        # Six legs share the database: a unique type and cleanup.
        $azureTypeName = "native_udtt_azure_" + [Guid]::NewGuid().ToString("N")
        try {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE TYPE [dbo].[$azureTypeName] AS TABLE ([value] int);")
            $splatAzureTableType = @{
                SqlInstance     = $azureServer
                Database        = $TestConfig.AzureSqlDbName
                Type            = $azureTypeName
                EnableException = $true
            }
            $azureRows = @(Get-DbaDbUserDefinedTableType @splatAzureTableType)
            $azureRows.Count | Should -Be 1
            $azureRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.UserDefinedTableType
            $azureRows[0].Name | Should -BeExactly $azureTypeName
            $azureRows[0].Database | Should -BeExactly $TestConfig.AzureSqlDbName
        } finally {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF TYPE_ID(N'[dbo].[$azureTypeName]') IS NOT NULL DROP TYPE [dbo].[$azureTypeName];")
        }
    }
}

Describe "Native Get-DbaDbUserDefinedTableType over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDbName = "native_udtt_sqllogin_" + [Guid]::NewGuid().ToString("N")
            $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
            $loginDatabase.Create()
            $loginDatabase.ExecuteNonQuery("CREATE TYPE [dbo].[native_login_udtt] AS TABLE ([value] int);")
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
            $splatLoginTableType = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Database        = $loginDbName
                EnableException = $true
            }
            $loginRows = @(Get-DbaDbUserDefinedTableType @splatLoginTableType)
            ($loginRows.Name -join ",") | Should -BeExactly "native_login_udtt"
            $loginRows[0].Database | Should -BeExactly $loginDbName
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
                $loginResult = @(Get-DbaDbUserDefinedTableType @splatLoginNoCredential)
                $loginResult.Count | Should -Be 0
                ($loginWarnings -join " ") | Should -BeLike "*Failure*"
            }
        }
    }
}
