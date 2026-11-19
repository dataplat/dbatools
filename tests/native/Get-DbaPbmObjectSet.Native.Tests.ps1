#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaPbmObjectSet",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads object sets.
# NativeChecklist: platform windows-only -- windows-smo: the DMF PolicyStore that Add-PbmLibrary loads; off Windows the nested Get-DbaPbmStore refuses, as the pin does.

Describe "Native Get-DbaPbmObjectSet" -Tag IntegrationTests {
    BeforeAll {
        # The legs of one SQL version share the instances; every name carries this run's number, and the catalog
        # comparisons leave out other runs' fixtures.
        $instance = $TestConfig.InstanceSingle
        $server = Connect-DbaInstance -SqlInstance $instance -EnableException
        $copyServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        $stamp = Get-Random
        $prefix = "dbatoolsci_pbmos_${stamp}_"
        $objectSetA = "${prefix}a"
        $objectSetB = "${prefix}b"
        $objectSetSystem = "${prefix}sys"
        $objectSetShared = "${prefix}shared"
        $missingObjectSet = "${prefix}none"
        $badInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $bindingMessage = "Cannot bind argument to parameter 'SqlInstance' because it is null."

        # Fixture writes only. The legs that share an instance write msdb's policy tables at the same time, and one may be
        # chosen as a deadlock victim (native 0958bdb9, sqlwhale22): the victim's batch is rolled back and runs again, a
        # fixed number of times. The command under test never retries.
        function Invoke-NativeFixtureSql ($Server, [string]$Sql) {
            for ($attempt = 1; $attempt -le 5; $attempt++) {
                try {
                    $null = $Server.Query($Sql)
                    return
                } catch {
                    $fault = $PSItem.Exception
                    $isDeadlock = $false
                    while ($fault) {
                        if ($fault.Number -eq 1205 -or $fault.Message -like "*deadlocked on lock resources*") { $isDeadlock = $true }
                        $fault = $fault.InnerException
                    }
                    if (-not $isDeadlock -or $attempt -eq 5) { throw }
                    Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 2000)
                }
            }
        }

        function Add-NativeObjectSet ($Server, [string]$Name) {
            # As SQL Server Management Studio scripts a Database object set (tests/Export-DbaInstance.Tests.ps1 does the same),
            # in one transaction, so a deadlock victim leaves nothing behind.
            Invoke-NativeFixtureSql -Server $Server -Sql "SET XACT_ABORT ON; BEGIN TRANSACTION; IF NOT EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_object_sets WHERE object_set_name = N'$Name') BEGIN DECLARE @object_set_id int; EXEC msdb.dbo.sp_syspolicy_add_object_set @object_set_name = N'$Name', @facet = N'Database', @object_set_id = @object_set_id OUTPUT; DECLARE @target_set_id int; EXEC msdb.dbo.sp_syspolicy_add_target_set @object_set_name = N'$Name', @type_skeleton = N'Server/Database', @type = N'DATABASE', @enabled = True, @target_set_id = @target_set_id OUTPUT; EXEC msdb.dbo.sp_syspolicy_add_target_set_level @target_set_id = @target_set_id, @type_skeleton = N'Server/Database', @level_name = N'Database', @condition_name = N'', @target_set_level_id = 0; END; COMMIT TRANSACTION;"
        }

        function Set-NativeSystemMark ($Server, [string]$Name, [int]$Marker) {
            # msdb's own marker procedure, or the column it sets when the procedure refuses the call.
            Invoke-NativeFixtureSql -Server $Server -Sql "BEGIN TRY EXEC msdb.dbo.sp_syspolicy_mark_system @type = N'OBJECTSET', @name = N'$Name', @marker = $Marker; END TRY BEGIN CATCH UPDATE msdb.dbo.syspolicy_object_sets_internal SET is_system = $Marker WHERE object_set_name = N'$Name'; END CATCH"
        }

        function Remove-NativeObjectSet ($Server, [string]$Name) {
            Set-NativeSystemMark -Server $Server -Name $Name -Marker 0
            Invoke-NativeFixtureSql -Server $Server -Sql "IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_object_sets WHERE object_set_name = N'$Name') EXEC msdb.dbo.sp_syspolicy_delete_object_set @object_set_name = N'$Name';"
        }

        # Id|Name|IsSystemObject of every object set of the instance, without other runs' fixtures.
        function Get-NativeCatalogObjectSet ($Server, [switch]$IncludeSystem) {
            $Server.Query("SELECT object_set_id, object_set_name, is_system FROM msdb.dbo.syspolicy_object_sets;") |
                Where-Object { $IncludeSystem -or -not $PSItem.is_system } |
                Where-Object { $PSItem.object_set_name -notlike "dbatoolsci_pbmos_*" -or $PSItem.object_set_name -like "$prefix*" } |
                ForEach-Object { "{0}|{1}|{2}" -f $PSItem.object_set_id, $PSItem.object_set_name, [bool]$PSItem.is_system } |
                Sort-Object
        }

        function Format-NativeObjectSet ($Rows) {
            $Rows |
                Where-Object { $PSItem.Name -notlike "dbatoolsci_pbmos_*" -or $PSItem.Name -like "$prefix*" } |
                ForEach-Object { "{0}|{1}|{2}" -f $PSItem.Id, $PSItem.Name, $PSItem.IsSystemObject } |
                Sort-Object
        }

        Add-NativeObjectSet -Server $server -Name $objectSetA
        Add-NativeObjectSet -Server $server -Name $objectSetB
        Add-NativeObjectSet -Server $server -Name $objectSetSystem
        Set-NativeSystemMark -Server $server -Name $objectSetSystem -Marker 1
        $systemMark = $server.Query("SELECT is_system FROM msdb.dbo.syspolicy_object_sets WHERE object_set_name = N'$objectSetSystem';").is_system
        if (-not $systemMark) { throw "The system mark of $objectSetSystem did not take" }
        # On both instances, so each store has it once whether or not the lab's copy instance is this instance.
        Add-NativeObjectSet -Server $server -Name $objectSetShared
        Add-NativeObjectSet -Server $copyServer -Name $objectSetShared

        # The first call loads the DMF assemblies, which New-NativePbmStore needs.
        $null = Get-DbaPbmObjectSet -SqlInstance $instance -ObjectSet $missingObjectSet -EnableException

        # A store as the pinned Get-DbaPbmStore builds it (public/Get-DbaPbmStore.ps1:85-94). The converted Get-DbaPbmStore is
        # not used here: on PowerShell 7 it refuses every host.
        function New-NativePbmStore ([string]$SqlInstance) {
            $storeServer = Connect-DbaInstance -SqlInstance $SqlInstance -EnableException
            $storeConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $storeServer.ConnectionContext.SqlConnectionObject
            $store = New-Object Microsoft.SqlServer.Management.Dmf.PolicyStore $storeConnection
            Add-Member -Force -InputObject $store -MemberType NoteProperty ComputerName -Value $storeServer.ComputerName
            Add-Member -Force -InputObject $store -MemberType NoteProperty InstanceName -Value $storeServer.ServiceName
            Add-Member -Force -InputObject $store -MemberType NoteProperty SqlInstance -Value $storeServer.DomainInstanceName
            $store
        }

        # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
        function Invoke-NativeOutsideTry {
            param([hashtable]$Arguments, [string]$Script = 'param($Arguments) Get-DbaPbmObjectSet @Arguments; "next statement"')
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaPbmObjectSet -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaPbmObjectSet", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $outsideStop = $null
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                $null = $outsideShell.AddScript($Script).AddArgument($Arguments)
                try {
                    $null = $outsideShell.Invoke($null, $outsideOutput)
                } catch {
                    # The stop leaves the runspace's script through Invoke, as a method call's exception.
                    $outsideStop = $PSItem.Exception.InnerException
                }
                [pscustomobject]@{
                    Rows     = @($outsideOutput | Where-Object { $PSItem -isnot [string] })
                    Strings  = @($outsideOutput | Where-Object { $PSItem -is [string] } | ForEach-Object { [string]$PSItem })
                    Errors   = @($outsideShell.Streams.Error)
                    Warnings = @($outsideShell.Streams.Warning)
                    Stop     = $outsideStop
                }
            } finally {
                $outsideShell.Dispose()
                $outsideRunspace.Dispose()
            }
        }

        function Assert-NativeBindingRecord ($Record, [string]$Activity) {
            $Record.Exception | Should -BeOfType System.Management.Automation.ParameterBindingException
            $Record.Exception.Message | Should -BeExactly $bindingMessage
            $Record.FullyQualifiedErrorId | Should -Match "^ParameterArgumentValidationErrorNullNotAllowed(,|$)"
            $Record.CategoryInfo.Category | Should -Be "InvalidData"
            $Record.CategoryInfo.Reason | Should -BeExactly "ParameterBindingValidationException"
            $Record.CategoryInfo.Activity | Should -BeExactly $Activity
            $Record.TargetObject | Should -BeNullOrEmpty
        }
    }

    AfterAll {
        foreach ($name in $objectSetA, $objectSetB, $objectSetSystem, $objectSetShared) {
            Remove-NativeObjectSet -Server $server -Name $name
        }
        Remove-NativeObjectSet -Server $copyServer -Name $objectSetShared
    }

    Context "Output" {
        It "returns every user object set of the instance with its id, leaving out system object sets" {
            $results = @(Get-DbaPbmObjectSet -SqlInstance $instance -EnableException)
            @(Format-NativeObjectSet -Rows $results) | Should -Be @(Get-NativeCatalogObjectSet -Server $server)
            $results.Name | Should -Contain $objectSetA
            $results.Name | Should -Not -Contain $objectSetSystem
        }

        It "returns the system object sets too with -IncludeSystemObject" {
            $results = @(Get-DbaPbmObjectSet -SqlInstance $instance -IncludeSystemObject -EnableException)
            @(Format-NativeObjectSet -Rows $results) | Should -Be @(Get-NativeCatalogObjectSet -Server $server -IncludeSystem)
            ($results | Where-Object Name -eq $objectSetSystem).IsSystemObject | Should -BeTrue
            ($results | Where-Object Name -eq $objectSetA).IsSystemObject | Should -BeFalse
        }

        It "keeps the DMF type, the facet, the target sets, the instance columns and the pinned default view" {
            $row = Get-DbaPbmObjectSet -SqlInstance $instance -ObjectSet $objectSetA -EnableException
            $row.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Dmf.ObjectSet"
            $row.Facet | Should -BeExactly "Database"
            @($row.TargetSets | ForEach-Object TargetTypeSkeleton) | Should -Contain "Server/Database"
            $row.ComputerName | Should -Be $server.ComputerName
            $row.InstanceName | Should -Be $server.ServiceName
            $row.SqlInstance | Should -Be $server.DomainInstanceName
            $row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Be @("ComputerName", "InstanceName", "SqlInstance", "Id", "Name", "Facet", "TargetSets", "IsSystemObject")
        }
    }

    Context "-ObjectSet" {
        It "returns only the named object sets, without regard to case" {
            $results = @(Get-DbaPbmObjectSet -SqlInstance $instance -ObjectSet $objectSetA.ToUpperInvariant(), $missingObjectSet -EnableException)
            $results.Count | Should -Be 1
            $results[0].Name | Should -BeExactly $objectSetA
        }

        It "gives nothing and no warning for a name no object set has" {
            $results = @(Get-DbaPbmObjectSet -SqlInstance $instance -ObjectSet $missingObjectSet -WarningVariable missingWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            $missingWarnings | Should -BeNullOrEmpty
        }

        It "reads -ObjectSet by its truth, so a lone empty value filters nothing" {
            @(Format-NativeObjectSet -Rows @(Get-DbaPbmObjectSet -SqlInstance $instance -ObjectSet "" -EnableException)) | Should -Be @(Get-NativeCatalogObjectSet -Server $server)
        }

        It "names a system object set only with -IncludeSystemObject" {
            @(Get-DbaPbmObjectSet -SqlInstance $instance -ObjectSet $objectSetSystem -EnableException).Count | Should -Be 0
            $results = @(Get-DbaPbmObjectSet -SqlInstance $instance -ObjectSet $objectSetSystem -IncludeSystemObject -EnableException)
            $results.Count | Should -Be 1
            $results[0].Name | Should -BeExactly $objectSetSystem
        }
    }

    Context "Stores" {
        It "reads several piped stores, each with its own instance columns" -Tag "NativeChecklist:pipeline-multiple" {
            $stores = @(New-NativePbmStore -SqlInstance $instance; New-NativePbmStore -SqlInstance $TestConfig.InstanceCopy1)
            $stores.Count | Should -Be 2
            $results = @($stores | Get-DbaPbmObjectSet -ObjectSet $objectSetShared -EnableException)
            $results.Count | Should -Be 2
            $results[0].SqlInstance | Should -Be $stores[0].SqlInstance
            $results[1].SqlInstance | Should -Be $stores[1].SqlInstance
        }

        It "takes stores by -InputObject and puts the named instances after them" {
            $store = New-NativePbmStore -SqlInstance $TestConfig.InstanceCopy1
            $results = @(Get-DbaPbmObjectSet -InputObject $store -SqlInstance $instance -ObjectSet $objectSetShared -EnableException)
            $results.Count | Should -Be 2
            $results[0].SqlInstance | Should -Be $store.SqlInstance
            $results[1].SqlInstance | Should -Be $server.DomainInstanceName
        }

        It "gives nothing and no error for an object that is no store" {
            $results = @(Get-DbaPbmObjectSet -InputObject "dbatoolsci_notastore" -IncludeSystemObject -ErrorVariable junkErrors -WarningVariable junkWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            $junkErrors | Should -BeNullOrEmpty
            $junkWarnings | Should -BeNullOrEmpty
        }
    }

    Context "Failed instances" {
        It "warns as Get-DbaPbmStore of a failed instance and reads the others, -EnableException or not" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
            foreach ($enable in $false, $true) {
                $failedWarnings = @()
                $splatFailed = @{
                    SqlInstance     = $badInstance, $instance
                    ObjectSet       = $objectSetA
                    EnableException = $enable
                    WarningVariable = "failedWarnings"
                    WarningAction   = "SilentlyContinue"
                    ErrorVariable   = "failedErrors"
                }
                $results = @(Get-DbaPbmObjectSet @splatFailed)
                $results.Count | Should -Be 1
                $results[0].Name | Should -BeExactly $objectSetA
                ($failedWarnings -join " ") | Should -BeLike "*Failure*"
                $failedErrors.Count | Should -Be 1
                $failedErrors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaPbmStore(,|$)"
                $failedErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
            }
        }

        It "only warns under -EnableException:`$false too" -Tag "NativeChecklist:switch-false" {
            $results = @(Get-DbaPbmObjectSet -SqlInstance $badInstance -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            ($falseWarnings -join " ") | Should -BeLike "*Failure*"
        }
    }

    Context "Null elements" {
        It "outside any try, a plain call writes the binding fault of the nested Get-DbaPbmStore and reads the other instances" {
            foreach ($instances in @(@($null, $instance), @($instance, $null))) {
                $outcome = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = $instances; ObjectSet = $objectSetA }
                $outcome.Stop | Should -BeNullOrEmpty
                $outcome.Rows.Count | Should -Be 1
                $outcome.Rows[0].Name | Should -BeExactly $objectSetA
                $outcome.Errors.Count | Should -Be 1
                Assert-NativeBindingRecord -Record $outcome.Errors[0] -Activity "Get-DbaPbmStore"
                $outcome.Strings | Should -Be @("next statement")
            }
        }

        It "outside any try, a null -SqlInstance reads nothing and writes nothing" {
            $outcome = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = $null }
            $outcome.Stop | Should -BeNullOrEmpty
            $outcome.Rows.Count | Should -Be 0
            $outcome.Errors.Count | Should -Be 0
            $outcome.Warnings.Count | Should -Be 0
            $outcome.Strings | Should -Be @("next statement")
        }

        It "inside a caller's try, the fault stops the command and the catch receives it" {
            $script = 'param($Arguments) try { Get-DbaPbmObjectSet @Arguments; "after call" } catch { $PSItem }; "next statement"'
            foreach ($extra in @{}, @{ EnableException = $true }, @{ ErrorAction = "Stop" }) {
                $arguments = @{ SqlInstance = @($null, $instance); ObjectSet = $objectSetA } + $extra
                $outcome = Invoke-NativeOutsideTry -Arguments $arguments -Script $script
                $outcome.Rows.Count | Should -Be 1
                $caught = $outcome.Rows[0]
                $caught | Should -BeOfType System.Management.Automation.ErrorRecord
                $caught.Exception.Message | Should -BeExactly $bindingMessage
                $caught.FullyQualifiedErrorId | Should -Match "^ParameterArgumentValidationErrorNullNotAllowed(,|$)"
                $outcome.Strings | Should -Be @("next statement")
            }
        }

        It "outside any try, -EnableException ends the command at the fault and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outcome = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = @($null, $instance); ObjectSet = $objectSetA; EnableException = $true }
            $outcome.Stop | Should -BeNullOrEmpty
            $outcome.Rows.Count | Should -Be 0
            $outcome.Errors.Count | Should -Be 1
            $outcome.Errors[0].Exception.Message | Should -BeExactly $bindingMessage
            $outcome.Strings | Should -Be @("next statement")
        }

        It "outside any try, -ErrorAction Stop turns the fault into the stop PowerShell gives WriteError" {
            $outcome = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = @($null, $instance); ObjectSet = $objectSetA; ErrorAction = "Stop" }
            $outcome.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outcome.Stop.ErrorRecord.Exception.Message | Should -BeExactly $bindingMessage
            $outcome.Stop.ErrorRecord.FullyQualifiedErrorId | Should -Match "^ParameterArgumentValidationErrorNullNotAllowed(,|$)"
            $outcome.Stop.ErrorRecord.CategoryInfo.Activity | Should -BeExactly "Get-DbaPbmObjectSet"
            $outcome.Rows.Count | Should -Be 0
            $outcome.Strings.Count | Should -Be 0
        }
    }

    Context "Enumeration faults" {
        BeforeAll {
            # A store whose object sets cannot be read: getting their enumerator throws, as an SFC collection does when
            # it cannot load its members. The same code path takes a real store whose connection is gone.
            if (-not ("NativePbmObjectSetTests.FailingCollection" -as [type])) {
                Add-Type -TypeDefinition @"
using System;
using System.Collections;
namespace NativePbmObjectSetTests {
    public sealed class FailingCollection : IEnumerable {
        public IEnumerator GetEnumerator() { throw new InvalidOperationException("dbatoolsci enumeration fault"); }
    }
}
"@
            }
            $faultMessage = "*dbatoolsci enumeration fault*"
            $failingStore = [pscustomobject]@{
                ObjectSets   = New-Object NativePbmObjectSetTests.FailingCollection
                ComputerName = "dbatoolsci"
                InstanceName = "MSSQLSERVER"
                SqlInstance  = "dbatoolsci"
            }
            $healthyStore = New-NativePbmStore -SqlInstance $instance
        }

        It "outside any try, a plain call writes one record per pinned statement and reads the next store" {
            $outcome = Invoke-NativeOutsideTry -Arguments @{ InputObject = @($failingStore, $healthyStore); ObjectSet = $objectSetA }
            $outcome.Stop | Should -BeNullOrEmpty
            # The IsSystemObject filter, the -ObjectSet filter and the foreach each enumerate the collection again.
            $outcome.Errors.Count | Should -Be 3
            foreach ($record in $outcome.Errors) {
                $record.Exception.Message | Should -BeLike $faultMessage
            }
            $outcome.Rows.Count | Should -Be 1
            $outcome.Rows[0].Name | Should -BeExactly $objectSetA
            $outcome.Strings | Should -Be @("next statement")
        }

        It "outside any try, -EnableException ends the command at the first fault and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outcome = Invoke-NativeOutsideTry -Arguments @{ InputObject = @($failingStore, $healthyStore); ObjectSet = $objectSetA; EnableException = $true }
            $outcome.Stop | Should -BeNullOrEmpty
            $outcome.Errors.Count | Should -Be 1
            $outcome.Errors[0].Exception.Message | Should -BeLike $faultMessage
            $outcome.Rows.Count | Should -Be 0
            $outcome.Strings | Should -Be @("next statement")
        }

        It "outside any try, -ErrorAction Stop turns the fault into the stop PowerShell gives WriteError" {
            $outcome = Invoke-NativeOutsideTry -Arguments @{ InputObject = @($failingStore, $healthyStore); ObjectSet = $objectSetA; ErrorAction = "Stop" }
            $outcome.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outcome.Stop.ErrorRecord.Exception.Message | Should -BeLike $faultMessage
            $outcome.Rows.Count | Should -Be 0
            $outcome.Strings.Count | Should -Be 0
        }

        It "inside a caller's try, the fault stops the command and the catch receives it" {
            $script = 'param($Arguments) try { Get-DbaPbmObjectSet @Arguments; "after call" } catch { $PSItem }; "next statement"'
            foreach ($extra in @{}, @{ EnableException = $true }, @{ ErrorAction = "Stop" }) {
                $arguments = @{ InputObject = @($failingStore, $healthyStore); ObjectSet = $objectSetA } + $extra
                $outcome = Invoke-NativeOutsideTry -Arguments $arguments -Script $script
                $outcome.Rows.Count | Should -Be 1
                $outcome.Rows[0] | Should -BeOfType System.Management.Automation.ErrorRecord
                $outcome.Rows[0].Exception.Message | Should -BeLike $faultMessage
                $outcome.Strings | Should -Be @("next statement")
            }
        }

        It "with -IncludeSystemObject and no -ObjectSet, only the foreach faults, once" {
            $outcome = Invoke-NativeOutsideTry -Arguments @{ InputObject = @($failingStore); IncludeSystemObject = $true }
            $outcome.Stop | Should -BeNullOrEmpty
            $outcome.Errors.Count | Should -Be 1
            $outcome.Errors[0].Exception.Message | Should -BeLike $faultMessage
            $outcome.Rows.Count | Should -Be 0
            $outcome.Strings | Should -Be @("next statement")
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # sqlwhale22 is shared: the object set is unique per leg and run.
            $loginObjectSet = "${prefix}login"
            Add-NativeObjectSet -Server $loginServer -Name $loginObjectSet
        }
        AfterAll {
            Invoke-NativeFixtureSql -Server $loginServer -Sql "IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_object_sets WHERE object_set_name = N'$loginObjectSet') EXEC msdb.dbo.sp_syspolicy_delete_object_set @object_set_name = N'$loginObjectSet';"
        }

        It "works with -SqlCredential" {
            $results = @(Get-DbaPbmObjectSet -SqlInstance $loginInstance -SqlCredential $loginCred -ObjectSet $loginObjectSet -EnableException)
            $results.Count | Should -Be 1
            $results[0].Name | Should -BeExactly $loginObjectSet
            $results[0].SqlInstance | Should -Be $loginServer.DomainInstanceName
        }

        It "fails cleanly without the credential: a warning as Get-DbaPbmStore and no output" {
            $results = @(Get-DbaPbmObjectSet -SqlInstance $loginInstance -ObjectSet $loginObjectSet -WarningVariable loginWarnings -WarningAction SilentlyContinue -ErrorVariable loginErrors -ErrorAction SilentlyContinue)
            $results.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
            $loginErrors.Count | Should -Be 1
            $loginErrors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaPbmStore(,|$)"
            $loginErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
        }

        It "fails cleanly without the credential under -EnableException, as the pinned function does: it only warns" {
            $results = @(Get-DbaPbmObjectSet -SqlInstance $loginInstance -ObjectSet $loginObjectSet -EnableException -WarningVariable strictLoginWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            ($strictLoginWarnings -join " ") | Should -BeLike "*Failure*"
        }
    }

    Context "Corrections" {
        It "reads a named instance once beside piped stores" {
            # The lab's copy instances may be this instance, so the store is read from it too and the rows are counted.
            $store = New-NativePbmStore -SqlInstance $instance
            $results = @($store, $store | Get-DbaPbmObjectSet -SqlInstance $instance -ObjectSet $objectSetA -EnableException)
            # Two piped stores and the named instance once: three rows, where the per-record read gives four.
            $results.Count | Should -Be 3
        }

        It "matches -ObjectSet wildcards, as the help documents" {
            $results = @(Get-DbaPbmObjectSet -SqlInstance $instance -ObjectSet "${prefix}*" -EnableException)
            @($results.Name | Sort-Object) | Should -Be @(@($objectSetA, $objectSetB, $objectSetShared) | Sort-Object)
            $results = @(Get-DbaPbmObjectSet -SqlInstance $instance -ObjectSet "$($prefix.ToUpperInvariant())?" -EnableException)
            @($results.Name | Sort-Object) | Should -Be @(@($objectSetA, $objectSetB) | Sort-Object)
            $results = @(Get-DbaPbmObjectSet -SqlInstance $instance -ObjectSet "${prefix}s*" -IncludeSystemObject -EnableException)
            @($results.Name | Sort-Object) | Should -Be @(@($objectSetShared, $objectSetSystem) | Sort-Object)
        }
    }
}

Describe "Native Get-DbaPbmObjectSet refuses Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once per test.
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613, or lets the login time out, while it resumes.
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.Message -like "*timed out*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }

    AfterAll {
        if ($azureServer) { $azureServer.ConnectionContext.Disconnect() }
    }

    # Policy-Based Management applies to SQL Server only and keeps its policies and object sets in msdb (Microsoft Learn,
    # "Administer servers by using Policy-Based Management" and "syspolicy_policies": Applies to SQL Server), and Azure
    # SQL Database has no msdb (Microsoft Learn, "msdb database": SQL Server and Azure SQL Managed Instance). The pin's
    # behaviour there is measured by the item's declared red.
    It "refuses Azure SQL Database with a warning as Get-DbaPbmStore and returns nothing" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzure = @{
            SqlInstance     = $azureServer
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
            ErrorAction     = "SilentlyContinue"
            ErrorVariable   = "azureErrors"
        }
        @(Get-DbaPbmObjectSet @splatAzure).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Failure*Azure SQL Database not supported*"
        $azureErrors.Count | Should -Be 1
        $azureErrors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaPbmStore(,|$)"
        $azureErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
        $azureErrors[0].Exception.Message | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "refuses Azure SQL Database under -EnableException with only that warning, as the nested store lookup does" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $strictAzureWarnings = @()
        $splatAzure = @{
            SqlInstance     = $azureServer
            EnableException = $true
            WarningVariable = "strictAzureWarnings"
            WarningAction   = "SilentlyContinue"
            ErrorVariable   = "strictAzureErrors"
        }
        @(Get-DbaPbmObjectSet @splatAzure).Count | Should -Be 0
        ($strictAzureWarnings -join " ") | Should -BeLike "*Failure*Azure SQL Database not supported*"
        $strictAzureErrors.Count | Should -Be 1
        $strictAzureErrors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaPbmStore(,|$)"
        $strictAzureErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
    }
}
