#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaPbmCondition",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only condition retrieval; the pin has no ShouldProcess.

Describe "Native Get-DbaPbmCondition" -Tag IntegrationTests {
    BeforeAll {
        & (Get-Module -Name dbatools) { Add-PbmLibrary }
        if (-not ("NativePbmCallerEnumerable" -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Collections;
public sealed class NativePbmCallerEnumerable : IEnumerable
{
    private readonly string stage;
    private readonly object first;
    public NativePbmCallerEnumerable(string stage, object first) { this.stage = stage; this.first = first; }
    public IEnumerator GetEnumerator()
    {
        if (stage == "GetEnumerator") throw new InvalidOperationException("native PBM GetEnumerator fixture");
        return new Iterator(first);
    }
    private sealed class Iterator : IEnumerator
    {
        private readonly object first;
        private bool moved;
        internal Iterator(object first) { this.first = first; }
        public object Current { get { return first; } }
        public bool MoveNext()
        {
            if (moved) throw new InvalidOperationException("native PBM MoveNext fixture");
            moved = true;
            return true;
        }
        public void Reset() { throw new NotSupportedException(); }
    }
}
'@
        }
        $nativeConditionServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -ErrorAction Stop
        $nativeConditionPrefix = "dbatoolsci_pbm_" + [guid]::NewGuid().ToString("N")
        $nativeConditionNames = @("${nativeConditionPrefix}_one", "${nativeConditionPrefix}_two", "${nativeConditionPrefix}_literal*", "${nativeConditionPrefix}_literalOther")
        $nativeConditionDisplay = "ComputerName,InstanceName,SqlInstance,Id,Name,CreateDate,CreatedBy,DateModified,Description,ExpressionNode,Facet,HasScript,IsSystemObject,ModifiedBy"
        function Add-NativeConditionFixture($Server, $Name) {
            $escapedName = $Name.Replace("'", "''")
            $conditionSql = "DECLARE @condition_id int; EXEC msdb.dbo.sp_syspolicy_add_condition @name = N'$escapedName', @description = N'native condition fixture', @facet = N'Database', @expression = N'<Operator><TypeClass>Bool</TypeClass><OpType>GE</OpType><Count>2</Count><Attribute><TypeClass>Numeric</TypeClass><Name>SpaceAvailable</Name></Attribute><Constant><TypeClass>Numeric</TypeClass><ObjType>System.Double</ObjType><Value>0</Value></Constant></Operator>', @is_name_condition = 0, @obj_name = N'', @condition_id = @condition_id OUTPUT"
            $null = $Server.ConnectionContext.ExecuteNonQuery($conditionSql)
        }
        function Remove-NativeConditionFixture($Server, $Names) {
            foreach ($fixtureName in $Names) {
                $escapedName = $fixtureName.Replace("'", "''")
                $null = $Server.ConnectionContext.ExecuteNonQuery("IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_conditions WHERE name = N'$escapedName') EXEC msdb.dbo.sp_syspolicy_delete_condition @name = N'$escapedName'")
            }
        }
        foreach ($fixtureName in $nativeConditionNames) { Add-NativeConditionFixture $nativeConditionServer $fixtureName }
        $nativeConditionStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection -ArgumentList $nativeConditionServer.ConnectionContext.SqlConnectionObject
        $nativeConditionStore = New-Object Microsoft.SqlServer.Management.Dmf.PolicyStore -ArgumentList $nativeConditionStoreConnection
        $nativeConditionStore | Add-Member -MemberType NoteProperty -Name ComputerName -Value $nativeConditionServer.ComputerName -Force
        $nativeConditionStore | Add-Member -MemberType NoteProperty -Name InstanceName -Value $nativeConditionServer.ServiceName -Force
        $nativeConditionStore | Add-Member -MemberType NoteProperty -Name SqlInstance -Value $nativeConditionServer.DomainInstanceName -Force
        $nativeConditionOtherStore = New-Object Microsoft.SqlServer.Management.Dmf.PolicyStore -ArgumentList $nativeConditionStoreConnection
        $nativeConditionOtherComputer = if ($nativeConditionServer.ComputerName -ceq $nativeConditionServer.ComputerName.ToUpperInvariant()) { $nativeConditionServer.ComputerName.ToLowerInvariant() } else { $nativeConditionServer.ComputerName.ToUpperInvariant() }
        $nativeConditionOtherStore | Add-Member -MemberType NoteProperty -Name ComputerName -Value $nativeConditionOtherComputer -Force
        $nativeConditionOtherStore | Add-Member -MemberType NoteProperty -Name InstanceName -Value $nativeConditionServer.ServiceName -Force
        $nativeConditionOtherStore | Add-Member -MemberType NoteProperty -Name SqlInstance -Value $nativeConditionServer.DomainInstanceName -Force
        $nativeConditionBefore = $nativeConditionServer.ConnectionContext.ExecuteWithResults("SELECT condition_id, name, date_created, date_modified, description, facet, expression FROM msdb.dbo.syspolicy_conditions ORDER BY condition_id").Tables[0] | ConvertTo-Csv -NoTypeInformation
        function Invoke-NativeConditionOutsideTry($Arguments, $Body) {
            $state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $commandType = (Get-Command Get-DbaPbmCondition -CommandType Cmdlet).ImplementingType
            $entry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaPbmCondition", $commandType, $null
            $state.Commands.Add($entry)
            $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($state)
            $shell = [System.Management.Automation.PowerShell]::Create()
            $output = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $stop = $null
            try {
                $runspace.Open()
                $shell.Runspace = $runspace
                $null = $shell.AddScript($Body).AddArgument($Arguments)
                try { $null = $shell.Invoke($null, $output) } catch { $stop = $PSItem.Exception.InnerException }
                [pscustomobject]@{ Output = @($output); Errors = @($shell.Streams.Error); Warnings = @($shell.Streams.Warning); Stop = $stop }
            } finally {
                $shell.Dispose()
                $runspace.Dispose()
            }
        }
    }

    AfterAll {
        Remove-NativeConditionFixture $nativeConditionServer $nativeConditionNames
        $escapedPrefix = $nativeConditionPrefix.Replace("'", "''")
        $remaining = $nativeConditionServer.ConnectionContext.ExecuteWithResults("SELECT COUNT(*) AS total FROM msdb.dbo.syspolicy_conditions WHERE LEFT(name, LEN(N'$escapedPrefix')) = N'$escapedPrefix'").Tables[0].Rows[0].total
        if ($remaining -ne 0) { throw "Native condition cleanup left $remaining conditions" }
    }

    It "returns real condition objects with the pinned metadata and default display" {
        $rows = @(Get-DbaPbmCondition -SqlInstance $TestConfig.InstanceSingle -Condition $nativeConditionNames[0] -EnableException)
        $rows.Count | Should -Be 1
        $rows[0] | Should -BeOfType Microsoft.SqlServer.Management.Dmf.Condition
        $rows[0].Name | Should -BeExactly $nativeConditionNames[0]
        $rows[0].ComputerName | Should -BeExactly $nativeConditionServer.ComputerName
        $rows[0].InstanceName | Should -BeExactly $nativeConditionServer.ServiceName
        $rows[0].SqlInstance | Should -BeExactly $nativeConditionServer.DomainInstanceName
        $rows[0].Facet | Should -BeExactly "Database"
        ($rows[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $nativeConditionDisplay
    }

    It "keeps InputObject order across arrays and pipeline records" -Tag NativeChecklist:pipeline-multiple {
        $rows = @(Get-DbaPbmCondition -InputObject @($nativeConditionStore, $nativeConditionOtherStore) -Condition $nativeConditionNames[0])
        ($rows.ComputerName -join ",") | Should -BeExactly (@($nativeConditionServer.ComputerName, $nativeConditionOtherComputer) -join ",")
        $rows = @(@($nativeConditionStore, $nativeConditionOtherStore) | Get-DbaPbmCondition -Condition $nativeConditionNames[0])
        $rows.Count | Should -Be 2
        ($rows.Name -join ",") | Should -BeExactly ($nativeConditionNames[0] + "," + $nativeConditionNames[0])
        ($rows.ComputerName -join ",") | Should -BeExactly (@($nativeConditionServer.ComputerName, $nativeConditionOtherComputer) -join ",")
    }

    It "reads named instances once beside multiple piped stores" {
        $rows = @(@($nativeConditionStore, $nativeConditionOtherStore) | Get-DbaPbmCondition -SqlInstance $TestConfig.InstanceSingle -Condition $nativeConditionNames[0])
        $rows.Count | Should -Be 3
        @($rows | Where-Object Name -ne $nativeConditionNames[0]).Count | Should -Be 0
        ($rows.ComputerName -join ",") | Should -BeExactly (@($nativeConditionServer.ComputerName, $nativeConditionServer.ComputerName, $nativeConditionOtherComputer) -join ",")
    }

    It "accepts documented instance pipeline input and continues after an unreachable instance" {
        $warnings = @()
        $instanceValue = [Dataplat.Dbatools.Parameter.DbaInstanceParameter]$TestConfig.InstanceSingle
        $rows = @(@("TCP:127.0.0.1,1", [string]$TestConfig.InstanceSingle, $instanceValue, $nativeConditionServer) | Get-DbaPbmCondition -Condition $nativeConditionNames[0] -WarningAction SilentlyContinue -WarningVariable warnings)
        $rows.Count | Should -Be 3
        @($rows | Where-Object Name -ne $nativeConditionNames[0]).Count | Should -Be 0
        ($warnings -join " ") | Should -BeLike "*Get-DbaPbmStore*Failure*"
    }

    It "honors documented condition wildcards while keeping existing wildcard-bearing names literal" {
        $rows = @(Get-DbaPbmCondition -SqlInstance $TestConfig.InstanceSingle -Condition "${nativeConditionPrefix}_*")
        $rows.Count | Should -Be $nativeConditionNames.Count
        ($rows.Name | Sort-Object) -join "|" | Should -BeExactly (($nativeConditionNames | Sort-Object) -join "|")
        $rows = @(Get-DbaPbmCondition -InputObject $nativeConditionStore -Condition "${nativeConditionPrefix}_o?e")
        $rows.Count | Should -Be 1
        $rows[0].Name | Should -BeExactly $nativeConditionNames[0]
        $rows = @(Get-DbaPbmCondition -SqlInstance $TestConfig.InstanceSingle -Condition $nativeConditionNames[2])
        $rows.Count | Should -Be 1
        $rows[0].Name | Should -BeExactly $nativeConditionNames[2]
    }

    It "matches the real system-object filter and explicit false switches without changing stored conditions" -Tag NativeChecklist:switch-false {
        $nativeConditionStore.Conditions.Refresh()
        $allNames = @($nativeConditionStore.Conditions | ForEach-Object Name)
        $userNames = @($nativeConditionStore.Conditions | Where-Object IsSystemObject -eq $false | ForEach-Object Name)
        $all = @(Get-DbaPbmCondition -InputObject $nativeConditionStore -IncludeSystemObject)
        $default = @(Get-DbaPbmCondition -InputObject $nativeConditionStore)
        $explicitFalse = @(Get-DbaPbmCondition -InputObject $nativeConditionStore -IncludeSystemObject:$false -EnableException:$false -Condition "")
        ($all.Name -join "|") | Should -BeExactly ($allNames -join "|")
        ($default.Name -join "|") | Should -BeExactly ($userNames -join "|")
        ($explicitFalse.Name -join "|") | Should -BeExactly ($userNames -join "|")
        $after = $nativeConditionServer.ConnectionContext.ExecuteWithResults("SELECT condition_id, name, date_created, date_modified, description, facet, expression FROM msdb.dbo.syspolicy_conditions ORDER BY condition_id").Tables[0] | ConvertTo-Csv -NoTypeInformation
        ($after -join "`n") | Should -BeExactly ($nativeConditionBefore -join "`n")
    }

    It "continues after a nested connection failure in ordinary caller try and EnableException modes" -Tag NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception {
        foreach ($enabled in $false, $true) {
            $warnings = @()
            $caught = $null
            $rows = @()
            $splatConditions = @{
                SqlInstance = @("TCP:127.0.0.1,1", $TestConfig.InstanceSingle)
                Condition = $nativeConditionNames[0]
                EnableException = $enabled
                WarningAction = "SilentlyContinue"
                WarningVariable = "warnings"
            }
            try { $rows = @(Get-DbaPbmCondition @splatConditions) } catch { $caught = $PSItem }
            $caught | Should -BeNullOrEmpty
            $rows.Count | Should -Be 1
            $rows[0].Name | Should -BeExactly $nativeConditionNames[0]
            ($warnings -join " ") | Should -BeLike "*Get-DbaPbmStore*Failure*"
        }
    }

    It "preserves enumerator-creation records at each filter and the caller stop boundaries" {
        foreach ($filter in "Default", "IncludeSystem", "Exact") {
            foreach ($mode in "Plain", "CallerTry", "EnableException", "ErrorAction") {
                $first = $nativeConditionStore.Conditions[$nativeConditionNames[0]]
                $later = $nativeConditionStore.Conditions[$nativeConditionNames[1]]
                $broken = [pscustomobject]@{ Conditions = (New-Object NativePbmCallerEnumerable -ArgumentList "GetEnumerator", $first); ComputerName = "first"; InstanceName = "first"; SqlInstance = "first" }
                $healthy = [pscustomobject]@{ Conditions = @($later); ComputerName = "later"; InstanceName = "later"; SqlInstance = "later" }
                $arguments = @{ InputObject = @($broken, $healthy) }
                if ($filter -eq "IncludeSystem") { $arguments.IncludeSystemObject = $true }
                if ($filter -eq "Exact") { $arguments.Condition = @($nativeConditionNames[0], $nativeConditionNames[1]) }
                if ($mode -eq "EnableException") { $arguments.EnableException = $true }
                if ($mode -eq "ErrorAction") { $arguments.ErrorAction = "Stop" }
                $body = if ($mode -eq "CallerTry") {
                    'param($Arguments) try { Get-DbaPbmCondition @Arguments; "after call" } catch { $PSItem }; "next statement"'
                } else { 'param($Arguments) Get-DbaPbmCondition @Arguments; "next statement"' }
                $outcome = Invoke-NativeConditionOutsideTry $arguments $body
                $rows = @($outcome.Output | Where-Object { $PSItem -is [Microsoft.SqlServer.Management.Dmf.Condition] })
                $rows.Count | Should -Be $(if ($mode -eq "Plain") { 1 } else { 0 }) -Because "$filter/$mode"
                if ($mode -eq "Plain") { $rows[0].Name | Should -BeExactly $nativeConditionNames[1] }
                if ($mode -eq "ErrorAction") {
                    $outcome.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
                    $outcome.Output.Count | Should -Be 0
                    $faults = @($outcome.Stop.ErrorRecord)
                } else {
                    $outcome.Stop | Should -BeNullOrEmpty
                    $outcome.Output[-1] | Should -BeExactly "next statement"
                    if ($mode -eq "CallerTry") {
                        $outcome.Output.Count | Should -Be 2
                        $outcome.Errors.Count | Should -Be 0
                        $faults = @($outcome.Output[0])
                    } else {
                        $expectedCount = if ($mode -eq "EnableException" -or $filter -eq "IncludeSystem") { 1 } elseif ($filter -eq "Default") { 2 } else { 3 }
                        $outcome.Errors.Count | Should -Be $expectedCount -Because "$filter/$mode"
                        $faults = @($outcome.Errors)
                    }
                }
                foreach ($fault in $faults) {
                    $fault | Should -BeOfType System.Management.Automation.ErrorRecord
                    $fault.FullyQualifiedErrorId | Should -BeExactly "ExceptionInGetEnumerator,Dataplat.Dbatools.Commands.GetDbaPbmConditionCommand"
                    $fault.Exception | Should -BeOfType System.Management.Automation.ExtendedTypeSystemException
                    $fault.Exception.Message | Should -BeExactly 'The following exception occurred while trying to enumerate the collection: "native PBM GetEnumerator fixture".'
                    $fault.Exception.InnerException | Should -BeOfType System.InvalidOperationException
                    $fault.Exception.InnerException.Message | Should -BeExactly "native PBM GetEnumerator fixture"
                    $fault.CategoryInfo.Category | Should -Be "NotSpecified"
                    $fault.CategoryInfo.Reason | Should -BeExactly "ExtendedTypeSystemException"
                    $fault.TargetObject | Should -BeNullOrEmpty
                }
                $outcome.Warnings.Count | Should -Be 0
            }
        }
    }

    It "preserves partial rows and distinct filter and foreach errors when MoveNext fails" {
        foreach ($filter in "Default", "IncludeSystem", "Exact") {
            foreach ($mode in "Plain", "CallerTry", "EnableException", "ErrorAction") {
                $first = $nativeConditionStore.Conditions[$nativeConditionNames[0]]
                $later = $nativeConditionStore.Conditions[$nativeConditionNames[1]]
                $broken = [pscustomobject]@{ Conditions = (New-Object NativePbmCallerEnumerable -ArgumentList "MoveNext", $first); ComputerName = "first"; InstanceName = "first"; SqlInstance = "first" }
                $healthy = [pscustomobject]@{ Conditions = @($later); ComputerName = "later"; InstanceName = "later"; SqlInstance = "later" }
                $arguments = @{ InputObject = @($broken, $healthy) }
                if ($filter -eq "IncludeSystem") { $arguments.IncludeSystemObject = $true }
                if ($filter -eq "Exact") { $arguments.Condition = @($nativeConditionNames[0], $nativeConditionNames[1]) }
                if ($mode -eq "EnableException") { $arguments.EnableException = $true }
                if ($mode -eq "ErrorAction") { $arguments.ErrorAction = "Stop" }
                $body = if ($mode -eq "CallerTry") {
                    'param($Arguments) try { Get-DbaPbmCondition @Arguments; "after call" } catch { $PSItem }; "next statement"'
                } else { 'param($Arguments) Get-DbaPbmCondition @Arguments; "next statement"' }
                $outcome = Invoke-NativeConditionOutsideTry $arguments $body
                $rows = @($outcome.Output | Where-Object { $PSItem -is [Microsoft.SqlServer.Management.Dmf.Condition] })
                $expectedRows = if ($mode -eq "Plain") { 2 } elseif ($filter -eq "IncludeSystem") { 1 } else { 0 }
                $rows.Count | Should -Be $expectedRows -Because "$filter/$mode"
                if ($expectedRows -gt 0) {
                    $rows[0].Name | Should -BeExactly $nativeConditionNames[0]
                    $rows[0].ComputerName | Should -BeExactly "first"
                }
                if ($expectedRows -eq 2) {
                    $rows[1].Name | Should -BeExactly $nativeConditionNames[1]
                    $rows[1].ComputerName | Should -BeExactly "later"
                }
                if ($mode -eq "ErrorAction") {
                    $outcome.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
                    $outcome.Output.Count | Should -Be $expectedRows
                    $faults = @($outcome.Stop.ErrorRecord)
                } else {
                    $outcome.Stop | Should -BeNullOrEmpty
                    $outcome.Output[-1] | Should -BeExactly "next statement"
                    if ($mode -eq "CallerTry") {
                        $outcome.Output.Count | Should -Be ($expectedRows + 2)
                        $outcome.Errors.Count | Should -Be 0
                        $faults = @($outcome.Output[$expectedRows])
                    } else {
                        $expectedErrors = if ($mode -eq "EnableException" -or $filter -eq "IncludeSystem") { 1 } elseif ($filter -eq "Default") { 2 } else { 3 }
                        $outcome.Errors.Count | Should -Be $expectedErrors -Because "$filter/$mode"
                        $faults = @($outcome.Errors)
                    }
                }
                for ($faultIndex = 0; $faultIndex -lt $faults.Count; $faultIndex++) {
                    $fault = $faults[$faultIndex]
                    $isFilterFault = $filter -ne "IncludeSystem" -and ($mode -ne "Plain" -or $faultIndex -lt $faults.Count - 1)
                    $fault | Should -BeOfType System.Management.Automation.ErrorRecord
                    if ($isFilterFault) {
                        $fault.FullyQualifiedErrorId | Should -BeExactly "BadEnumeration,Dataplat.Dbatools.Commands.GetDbaPbmConditionCommand"
                        $fault.Exception | Should -BeOfType System.Management.Automation.RuntimeException
                        $fault.Exception.Message | Should -BeExactly "An error occurred while enumerating through a collection: native PBM MoveNext fixture."
                        $fault.Exception.InnerException | Should -BeOfType System.InvalidOperationException
                        $fault.Exception.InnerException.Message | Should -BeExactly "native PBM MoveNext fixture"
                        $fault.CategoryInfo.Category | Should -Be "InvalidOperation"
                        $fault.CategoryInfo.Reason | Should -BeExactly "RuntimeException"
                        $fault.TargetObject.GetType().FullName | Should -BeExactly "NativePbmCallerEnumerable+Iterator"
                    } else {
                        $fault.FullyQualifiedErrorId | Should -BeExactly "System.InvalidOperationException,Dataplat.Dbatools.Commands.GetDbaPbmConditionCommand"
                        $fault.Exception | Should -BeOfType System.InvalidOperationException
                        $fault.Exception.Message | Should -BeExactly "native PBM MoveNext fixture"
                        $fault.Exception.InnerException | Should -BeNullOrEmpty
                        $fault.CategoryInfo.Category | Should -Be "OperationStopped"
                        $fault.CategoryInfo.Reason | Should -BeExactly "InvalidOperationException"
                        $fault.TargetObject | Should -BeNullOrEmpty
                    }
                }
                $outcome.Warnings.Count | Should -Be 0
            }
        }
    }

    It "preserves the nested null-instance binder record and caller stop boundaries" {
        foreach ($enabled in $false, $true) {
            $arguments = @{ SqlInstance = @($null, $TestConfig.InstanceSingle); Condition = $nativeConditionNames[0]; EnableException = $enabled }
            $outcome = Invoke-NativeConditionOutsideTry $arguments 'param($Arguments) Get-DbaPbmCondition @Arguments; "next statement"'
            $outcome.Stop | Should -BeNullOrEmpty
            @($outcome.Output | Where-Object { $PSItem -is [Microsoft.SqlServer.Management.Dmf.Condition] }).Count | Should -Be $(if ($enabled) { 0 } else { 1 })
            @($outcome.Output | Where-Object { $PSItem -is [string] }) | Should -Be @("next statement")
            $outcome.Errors.Count | Should -Be 1
            $outcome.Errors[0].Exception | Should -BeOfType System.Management.Automation.ParameterBindingException
            $outcome.Errors[0].Exception.Message | Should -BeExactly "Cannot bind argument to parameter 'SqlInstance' because it is null."
            $outcome.Errors[0].FullyQualifiedErrorId | Should -Match "^ParameterArgumentValidationErrorNullNotAllowed(,|$)"
            $outcome.Errors[0].CategoryInfo.Category | Should -Be "InvalidData"
            $outcome.Errors[0].CategoryInfo.Reason | Should -BeExactly "ParameterBindingValidationException"
            $outcome.Warnings.Count | Should -Be 0
        }
        # Keep-going point 3 keeps WriteError's native -ErrorAction Stop effect: the caller script ends.
        $arguments = @{ SqlInstance = @($null, $TestConfig.InstanceSingle); Condition = $nativeConditionNames[0]; ErrorAction = "Stop" }
        $outcome = Invoke-NativeConditionOutsideTry $arguments 'param($Arguments) Get-DbaPbmCondition @Arguments; "next statement"'
        $outcome.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
        $outcome.Output.Count | Should -Be 0
        $fault = $outcome.Stop.ErrorRecord
        $fault.FullyQualifiedErrorId | Should -BeExactly "ParameterArgumentValidationErrorNullNotAllowed,Dataplat.Dbatools.Commands.GetDbaPbmConditionCommand"
        $fault.Exception | Should -BeOfType System.Management.Automation.ParameterBindingException
        $fault.Exception.Message | Should -BeExactly "Cannot bind argument to parameter 'SqlInstance' because it is null."
        $fault.CategoryInfo.Category | Should -Be "InvalidData"
        $fault.CategoryInfo.Reason | Should -BeExactly "ParameterBindingValidationException"
        $fault.CategoryInfo.Activity | Should -BeExactly "Get-DbaPbmCondition"
        $fault.TargetObject | Should -BeNullOrEmpty
        $outcome.Warnings.Count | Should -Be 0
        foreach ($extra in @{}, @{ EnableException = $true }, @{ ErrorAction = "Stop" }) {
            $arguments = @{ SqlInstance = @($null, $TestConfig.InstanceSingle); Condition = $nativeConditionNames[0] } + $extra
            $outcome = Invoke-NativeConditionOutsideTry $arguments 'param($Arguments) try { Get-DbaPbmCondition @Arguments; "after call" } catch { $PSItem }; "next statement"'
            $outcome.Stop | Should -BeNullOrEmpty
            $outcome.Output.Count | Should -Be 2
            $outcome.Output[0] | Should -BeOfType System.Management.Automation.ErrorRecord
            $outcome.Output[0].FullyQualifiedErrorId | Should -Match "^ParameterArgumentValidationErrorNullNotAllowed(,|$)"
            $outcome.Output[1] | Should -BeExactly "next statement"
            $outcome.Errors.Count | Should -Be 0
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $nativeConditionLoginServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -ErrorAction Stop
            $nativeConditionLoginName = $nativeConditionPrefix + "_login"
            Add-NativeConditionFixture $nativeConditionLoginServer $nativeConditionLoginName
        }
        AfterAll { Remove-NativeConditionFixture $nativeConditionLoginServer @($nativeConditionLoginName) }
        It "uses SqlCredential and preserves nested warnings without that credential even with EnableException" {
            $rows = @(Get-DbaPbmCondition -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -Condition $nativeConditionLoginName -EnableException)
            $rows.Count | Should -Be 1
            $rows[0].Name | Should -BeExactly $nativeConditionLoginName
            foreach ($enabled in $false, $true) {
                $warnings = @()
                $caught = $null
                $rows = @()
                try {
                    $rows = @(Get-DbaPbmCondition -SqlInstance $TestConfig.InstanceSqlLogin -Condition $nativeConditionLoginName -EnableException:$enabled -WarningAction SilentlyContinue -WarningVariable warnings)
                } catch { $caught = $PSItem }
                $caught | Should -BeNullOrEmpty
                $rows.Count | Should -Be 0
                ($warnings -join " ") | Should -BeLike "*Get-DbaPbmStore*Failure*"
            }
        }
    }
}

Describe "Native Get-DbaPbmCondition Azure refusal" -Tag IntegrationTests {
    BeforeAll {
        $splatConditionAzureConnect = @{
            SqlInstance = $TestConfig.AzureSqlDbServer
            Database = $TestConfig.AzureSqlDbName
            SqlCredential = $TestConfig.AzureSqlDbCred
            ConnectTimeout = 60
            ErrorAction = "Stop"
        }
        $nativeConditionAzure = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $nativeConditionAzure = Connect-DbaInstance @splatConditionAzureConnect
                if (-not $nativeConditionAzure) { throw "Azure setup returned no server" }
                break
            } catch {
                $failure = $PSItem.Exception
                $resuming = $false
                while ($failure) {
                    if ($failure.Number -eq 40613 -or $failure.Number -eq -2 -or $failure.Message -like "*timed out*") { $resuming = $true }
                    $failure = $failure.InnerException
                }
                if (-not $resuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }
    AfterAll { if ($nativeConditionAzure) { $nativeConditionAzure.ConnectionContext.Disconnect() } }

    # PBM is unavailable in Azure SQL Database: https://learn.microsoft.com/azure/azure-sql/database/features-comparison#platform-capabilities
    It "refuses Azure SQL Database through the nested store warning with and without EnableException" -Tag NativeChecklist:azure-sqldb {
        $nativeConditionAzure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        foreach ($enabled in $false, $true) {
            $warnings = @()
            $errors = @()
            $caught = $null
            $rows = @()
            try {
                $rows = @(Get-DbaPbmCondition -SqlInstance $nativeConditionAzure -EnableException:$enabled -WarningAction SilentlyContinue -WarningVariable warnings -ErrorVariable errors)
            } catch { $caught = $PSItem }
            $caught | Should -BeNullOrEmpty
            $rows.Count | Should -Be 0
            ($warnings -join " ") | Should -BeLike "*Get-DbaPbmStore*Failure*Azure SQL Database not supported*"
            $errors.Count | Should -Be 1
            $errors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaPbmStore(,|$)"
            $errors[0].CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}
