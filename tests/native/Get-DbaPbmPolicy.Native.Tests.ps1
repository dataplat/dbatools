#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaPbmPolicy",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads policies.
# NativeChecklist: platform windows-only -- windows-smo: the DMF PolicyStore that Add-PbmLibrary loads; off Windows the nested Get-DbaPbmStore refuses, as the pin does.

Describe "Native Get-DbaPbmPolicy" -Tag IntegrationTests {
    BeforeAll {
        # The legs of one SQL version share the instances; every name carries this run's number.
        $instance = $TestConfig.InstanceSingle
        $server = Connect-DbaInstance -SqlInstance $instance -EnableException
        $stamp = Get-Random
        $category = "dbatoolsci_pbmpol_${stamp}_cat"
        $condition = "dbatoolsci_pbmpol_${stamp}_cond"
        $policyA = "dbatoolsci_pbmpol_${stamp}_a"
        $policyB = "dbatoolsci_pbmpol_${stamp}_b"
        $missingPolicy = "dbatoolsci_pbmpol_${stamp}_none"
        $badInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $bindingMessage = "Cannot bind argument to parameter 'SqlInstance' because it is null."
        $hiddenProperties = @("HelpText", "HelpLink", "Urn", "Properties", "Metadata", "Parent", "IdentityKey", "HasScript", "PolicyEvaluationStarted", "ConnectionProcessingStarted", "TargetProcessed", "ConnectionProcessingFinished", "PolicyEvaluationFinished", "PropertyMetadataChanged", "PropertyChanged")

        function Invoke-NativePbmSql ($Server, $Sql) {
            $Server.Databases["msdb"].ExecuteWithResults($Sql).Tables | ForEach-Object { $PSItem.Rows }
        }

        # One policy on its own object set, on a condition shared by this run's policies, in -Category ("" is the default).
        function Add-NativePolicy ($Server, $Name, $Category) {
            if ($Category -and -not (Invoke-NativePbmSql -Server $Server -Sql "SELECT 1 AS found FROM msdb.dbo.syspolicy_policy_categories WHERE name = N'$Category'")) {
                $null = Invoke-NativePbmSql -Server $Server -Sql "DECLARE @policy_category_id int; EXEC msdb.dbo.sp_syspolicy_add_policy_category @name = N'$Category', @mandate_database_subscriptions = 0, @policy_category_id = @policy_category_id OUTPUT"
            }
            if (-not (Invoke-NativePbmSql -Server $Server -Sql "SELECT 1 AS found FROM msdb.dbo.syspolicy_conditions WHERE name = N'$condition'")) {
                $null = Invoke-NativePbmSql -Server $Server -Sql "DECLARE @condition_id int; EXEC msdb.dbo.sp_syspolicy_add_condition @name = N'$condition', @description = N'', @facet = N'Database', @expression = N'<Operator><TypeClass>Bool</TypeClass><OpType>GE</OpType><Count>2</Count><Attribute><TypeClass>Numeric</TypeClass><Name>SpaceAvailable</Name></Attribute><Constant><TypeClass>Numeric</TypeClass><ObjType>System.Double</ObjType><Value>0</Value></Constant></Operator>', @is_name_condition = 0, @obj_name = N'', @condition_id = @condition_id OUTPUT"
            }
            $objectSet = "${Name}_set"
            $null = Invoke-NativePbmSql -Server $Server -Sql "DECLARE @object_set_id int; EXEC msdb.dbo.sp_syspolicy_add_object_set @object_set_name = N'$objectSet', @facet = N'Database', @object_set_id = @object_set_id OUTPUT"
            $null = Invoke-NativePbmSql -Server $Server -Sql "DECLARE @target_set_id int; EXEC msdb.dbo.sp_syspolicy_add_target_set @object_set_name = N'$objectSet', @type_skeleton = N'Server/Database', @type = N'DATABASE', @enabled = True, @target_set_id = @target_set_id OUTPUT; EXEC msdb.dbo.sp_syspolicy_add_target_set_level @target_set_id = @target_set_id, @type_skeleton = N'Server/Database', @level_name = N'Database', @condition_name = N'', @target_set_level_id = 0"
            $null = Invoke-NativePbmSql -Server $Server -Sql "DECLARE @policy_id int; EXEC msdb.dbo.sp_syspolicy_add_policy @name = N'$Name', @condition_name = N'$condition', @policy_category = N'$Category', @execution_mode = 0, @policy_id = @policy_id OUTPUT, @object_set = N'$objectSet'"
        }

        # Policies first, then their object sets, the shared condition and the category.
        function Remove-NativePolicy ($Server, [string[]]$Names) {
            foreach ($name in $Names) {
                $null = Invoke-NativePbmSql -Server $Server -Sql "IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_policies WHERE name = N'$name') EXEC msdb.dbo.sp_syspolicy_delete_policy @name = N'$name'"
                $null = Invoke-NativePbmSql -Server $Server -Sql "IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_object_sets WHERE object_set_name = N'${name}_set') EXEC msdb.dbo.sp_syspolicy_delete_object_set @object_set_name = N'${name}_set'"
            }
            $null = Invoke-NativePbmSql -Server $Server -Sql "IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_conditions WHERE name = N'$condition') EXEC msdb.dbo.sp_syspolicy_delete_condition @name = N'$condition'"
            $null = Invoke-NativePbmSql -Server $Server -Sql "IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_policy_categories WHERE name = N'$category') EXEC msdb.dbo.sp_syspolicy_delete_policy_category @name = N'$category'"
        }

        # Other legs and commands add and drop their own dbatoolsci policies on the shared instances while this runs, so the
        # comparisons keep this run's policies and every policy not named dbatoolsci.
        function Select-NativeStableName ([string[]]$Names) {
            @($Names | Where-Object { ($PSItem -in @($policyA, $policyB)) -or ($PSItem -notlike "dbatoolsci*") } | Sort-Object)
        }

        function Get-NativeCatalogPolicyName ($Server) {
            Select-NativeStableName -Names @(Invoke-NativePbmSql -Server $Server -Sql "SELECT name FROM msdb.dbo.syspolicy_policies" | ForEach-Object { $PSItem.name })
        }

        Add-NativePolicy -Server $server -Name $policyA -Category $category
        Add-NativePolicy -Server $server -Name $policyB -Category ""
        # The lab's copy instance may be this instance: the policy is made there only when it is missing.
        $copyServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        $copyMade = $false
        if (-not (Invoke-NativePbmSql -Server $copyServer -Sql "SELECT 1 AS found FROM msdb.dbo.syspolicy_policies WHERE name = N'$policyA'")) {
            Add-NativePolicy -Server $copyServer -Name $policyA -Category $category
            $copyMade = $true
        }
        # The first call loads the DMF assemblies, which New-NativePbmStore needs.
        $null = Get-DbaPbmPolicy -SqlInstance $instance -Policy $missingPolicy -EnableException

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
            param([hashtable]$Arguments, [string]$Script = 'param($Arguments) Get-DbaPbmPolicy @Arguments; "next statement"')
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaPbmPolicy -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaPbmPolicy", $outsideType, $null
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
        Remove-NativePolicy -Server $server -Names $policyA, $policyB
        if ($copyMade) {
            Remove-NativePolicy -Server $copyServer -Names $policyA
        }
    }

    Context "Output" {
        It "returns the instance's policies with their category and condition" {
            $results = @(Get-DbaPbmPolicy -SqlInstance $instance -EnableException)
            $results.Name | Should -Contain $policyA
            $results.Name | Should -Contain $policyB
            $rowA = $results | Where-Object Name -eq $policyA
            $rowA.PolicyCategory | Should -BeExactly $category
            $rowA.Condition | Should -BeExactly $condition
            $rowA.ObjectSet | Should -BeExactly "${policyA}_set"
            ($results | Where-Object Name -eq $policyB).Condition | Should -BeExactly $condition
        }

        It "keeps the DMF type, the instance columns and the pinned default view" {
            $row = Get-DbaPbmPolicy -SqlInstance $instance -Policy $policyA -EnableException
            $row.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Dmf.Policy"
            $row.ComputerName | Should -Be $server.ComputerName
            $row.InstanceName | Should -Be $server.ServiceName
            $row.SqlInstance | Should -Be $server.DomainInstanceName
            # Select-DefaultView -ExcludeProperty: every property Get-Member lists, in its order, except the excluded ones.
            $expected = @(($row | Get-Member | Where-Object MemberType -in "Property", "NoteProperty", "AliasProperty" | Where-Object { $PSItem.Name -notin $hiddenProperties }).Name)
            $shown = @($row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames)
            $shown | Should -Be $expected
            foreach ($name in "ComputerName", "InstanceName", "SqlInstance", "ID", "Name", "Enabled", "PolicyCategory", "AutomatedPolicyEvaluationMode", "Condition", "IsSystemObject", "ObjectSet") {
                $shown | Should -Contain $name
            }
            foreach ($name in $hiddenProperties) {
                $shown | Should -Not -Contain $name
            }
        }
    }

    Context "-IncludeSystemObject" {
        It "leaves out system policies by default and returns every policy with the switch" {
            $catalog = @(Get-NativeCatalogPolicyName -Server $server)
            $all = @(Get-DbaPbmPolicy -SqlInstance $instance -IncludeSystemObject -EnableException)
            $allNames = @(Select-NativeStableName -Names $all.Name)
            $allNames | Should -Contain $policyA
            ($allNames -join "|") | Should -BeExactly ($catalog -join "|")
            $userOnly = @(Get-DbaPbmPolicy -SqlInstance $instance -EnableException)
            @($userOnly | Where-Object IsSystemObject).Count | Should -Be 0
            $userNames = @(Select-NativeStableName -Names $userOnly.Name)
            $expectedUser = @(Select-NativeStableName -Names @($all | Where-Object { -not $PSItem.IsSystemObject } | ForEach-Object Name))
            ($userNames -join "|") | Should -BeExactly ($expectedUser -join "|")
        }
    }

    Context "-Policy and -Category" {
        It "returns only the named policies, without regard to case" {
            $results = @(Get-DbaPbmPolicy -SqlInstance $instance -Policy $policyA.ToUpperInvariant(), $missingPolicy -EnableException)
            $results.Count | Should -Be 1
            $results[0].Name | Should -BeExactly $policyA
        }

        It "gives nothing and no warning for a name no policy has" {
            $results = @(Get-DbaPbmPolicy -SqlInstance $instance -Policy $missingPolicy -WarningVariable missingWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            $missingWarnings | Should -BeNullOrEmpty
        }

        It "returns only the policies of the named categories" {
            $results = @(Get-DbaPbmPolicy -SqlInstance $instance -Category $category.ToUpperInvariant() -EnableException)
            $results.Count | Should -Be 1
            $results[0].Name | Should -BeExactly $policyA
        }

        It "applies -Category and -Policy together" {
            @(Get-DbaPbmPolicy -SqlInstance $instance -Category $category -Policy $policyB -EnableException).Count | Should -Be 0
            $both = @(Get-DbaPbmPolicy -SqlInstance $instance -Category $category -Policy $policyA, $policyB -EnableException)
            $both.Count | Should -Be 1
            $both[0].Name | Should -BeExactly $policyA
        }

        It "reads -Policy and -Category by their truth, so a lone empty value filters nothing" {
            $expected = (Select-NativeStableName -Names @(Get-DbaPbmPolicy -SqlInstance $instance -EnableException).Name) -join "|"
            $expected | Should -BeLike "*$policyB*"
            (Select-NativeStableName -Names @(Get-DbaPbmPolicy -SqlInstance $instance -Policy "" -EnableException).Name) -join "|" | Should -BeExactly $expected
            (Select-NativeStableName -Names @(Get-DbaPbmPolicy -SqlInstance $instance -Category "" -EnableException).Name) -join "|" | Should -BeExactly $expected
        }
    }

    Context "Stores" {
        It "reads several piped stores, each with its own instance columns" -Tag "NativeChecklist:pipeline-multiple" {
            $stores = @(New-NativePbmStore -SqlInstance $instance; New-NativePbmStore -SqlInstance $TestConfig.InstanceCopy1)
            $stores.Count | Should -Be 2
            $results = @($stores | Get-DbaPbmPolicy -Policy $policyA -EnableException)
            $results.Count | Should -Be 2
            $results[0].SqlInstance | Should -Be $stores[0].SqlInstance
            $results[1].SqlInstance | Should -Be $stores[1].SqlInstance
        }

        It "takes stores by -InputObject and puts the named instances after them" {
            $store = New-NativePbmStore -SqlInstance $TestConfig.InstanceCopy1
            $results = @(Get-DbaPbmPolicy -InputObject $store -SqlInstance $instance -Policy $policyA -EnableException)
            $results.Count | Should -Be 2
            $results[0].SqlInstance | Should -Be $store.SqlInstance
            $results[1].SqlInstance | Should -Be $server.DomainInstanceName
        }

        It "gives nothing and no error for an object that is no store" {
            $results = @(Get-DbaPbmPolicy -InputObject "dbatoolsci_notastore" -ErrorVariable junkErrors -WarningVariable junkWarnings -WarningAction SilentlyContinue)
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
                    Policy          = $policyA
                    EnableException = $enable
                    WarningVariable = "failedWarnings"
                    WarningAction   = "SilentlyContinue"
                    ErrorVariable   = "failedErrors"
                }
                $results = @(Get-DbaPbmPolicy @splatFailed)
                $results.Count | Should -Be 1
                $results[0].Name | Should -BeExactly $policyA
                ($failedWarnings -join " ") | Should -BeLike "*Failure*"
                $failedErrors.Count | Should -Be 1
                $failedErrors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaPbmStore(,|$)"
                $failedErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
            }
        }

        It "only warns under -EnableException:`$false too" -Tag "NativeChecklist:switch-false" {
            $results = @(Get-DbaPbmPolicy -SqlInstance $badInstance -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            ($falseWarnings -join " ") | Should -BeLike "*Failure*"
        }
    }

    Context "Null elements" {
        It "outside any try, a plain call writes the binding fault of the nested Get-DbaPbmStore and reads the other instances" {
            foreach ($instances in @(@($null, $instance), @($instance, $null))) {
                $outcome = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = $instances; Policy = $policyA }
                $outcome.Stop | Should -BeNullOrEmpty
                $outcome.Rows.Count | Should -Be 1
                $outcome.Rows[0].Name | Should -BeExactly $policyA
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
            $script = 'param($Arguments) try { Get-DbaPbmPolicy @Arguments; "after call" } catch { $PSItem }; "next statement"'
            foreach ($extra in @{}, @{ EnableException = $true }, @{ ErrorAction = "Stop" }) {
                $arguments = @{ SqlInstance = @($null, $instance); Policy = $policyA } + $extra
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
            $outcome = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = @($null, $instance); Policy = $policyA; EnableException = $true }
            $outcome.Stop | Should -BeNullOrEmpty
            $outcome.Rows.Count | Should -Be 0
            $outcome.Errors.Count | Should -Be 1
            $outcome.Errors[0].Exception.Message | Should -BeExactly $bindingMessage
            $outcome.Strings | Should -Be @("next statement")
        }

        It "outside any try, -ErrorAction Stop turns the fault into the stop PowerShell gives WriteError" {
            $outcome = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = @($null, $instance); Policy = $policyA; ErrorAction = "Stop" }
            $outcome.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outcome.Stop.ErrorRecord.Exception.Message | Should -BeExactly $bindingMessage
            $outcome.Stop.ErrorRecord.FullyQualifiedErrorId | Should -Match "^ParameterArgumentValidationErrorNullNotAllowed(,|$)"
            $outcome.Stop.ErrorRecord.CategoryInfo.Activity | Should -BeExactly "Get-DbaPbmPolicy"
            $outcome.Rows.Count | Should -Be 0
            $outcome.Strings.Count | Should -Be 0
        }
    }

    Context "Enumeration faults" {
        BeforeAll {
            # A store whose policies cannot be read: getting their enumerator throws, as an SFC collection does when it
            # cannot load its members. The same code path takes a real store whose connection is gone.
            if (-not ("NativePbmPolicyTests.FailingCollection" -as [type])) {
                Add-Type -TypeDefinition @"
using System;
using System.Collections;
namespace NativePbmPolicyTests {
    public sealed class FailingCollection : IEnumerable {
        public IEnumerator GetEnumerator() { throw new InvalidOperationException("dbatoolsci enumeration fault"); }
    }
}
"@
            }
            $faultMessage = "*dbatoolsci enumeration fault*"
            $failingStore = [pscustomobject]@{
                Policies     = New-Object NativePbmPolicyTests.FailingCollection
                ComputerName = "dbatoolsci"
                InstanceName = "MSSQLSERVER"
                SqlInstance  = "dbatoolsci"
            }
            $healthyStore = New-NativePbmStore -SqlInstance $instance
        }

        It "outside any try, a plain call writes one record per pinned statement and reads the next store" {
            # The IsSystemObject filter, each of the -Category and -Policy filters given, and the foreach each enumerate the
            # collection again.
            foreach ($case in @(
                    @{ Filters = @{ Policy = $policyA }; Records = 3 },
                    @{ Filters = @{ Category = $category; Policy = $policyA }; Records = 4 }
                )) {
                $outcome = Invoke-NativeOutsideTry -Arguments (@{ InputObject = @($failingStore, $healthyStore) } + $case.Filters)
                $outcome.Stop | Should -BeNullOrEmpty
                $outcome.Errors.Count | Should -Be $case.Records
                foreach ($record in $outcome.Errors) {
                    $record.Exception.Message | Should -BeLike $faultMessage
                }
                $outcome.Rows.Count | Should -Be 1
                $outcome.Rows[0].Name | Should -BeExactly $policyA
                $outcome.Strings | Should -Be @("next statement")
            }
        }

        It "outside any try, -EnableException ends the command at the first fault and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outcome = Invoke-NativeOutsideTry -Arguments @{ InputObject = @($failingStore, $healthyStore); Policy = $policyA; EnableException = $true }
            $outcome.Stop | Should -BeNullOrEmpty
            $outcome.Errors.Count | Should -Be 1
            $outcome.Errors[0].Exception.Message | Should -BeLike $faultMessage
            $outcome.Rows.Count | Should -Be 0
            $outcome.Strings | Should -Be @("next statement")
        }

        It "outside any try, -ErrorAction Stop turns the fault into the stop PowerShell gives WriteError" {
            $outcome = Invoke-NativeOutsideTry -Arguments @{ InputObject = @($failingStore, $healthyStore); Policy = $policyA; ErrorAction = "Stop" }
            $outcome.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outcome.Stop.ErrorRecord.Exception.Message | Should -BeLike $faultMessage
            $outcome.Rows.Count | Should -Be 0
            $outcome.Strings.Count | Should -Be 0
        }

        It "inside a caller's try, the fault stops the command and the catch receives it" {
            $script = 'param($Arguments) try { Get-DbaPbmPolicy @Arguments; "after call" } catch { $PSItem }; "next statement"'
            foreach ($extra in @{}, @{ EnableException = $true }, @{ ErrorAction = "Stop" }) {
                $arguments = @{ InputObject = @($failingStore, $healthyStore); Policy = $policyA } + $extra
                $outcome = Invoke-NativeOutsideTry -Arguments $arguments -Script $script
                $outcome.Rows.Count | Should -Be 1
                $outcome.Rows[0] | Should -BeOfType System.Management.Automation.ErrorRecord
                $outcome.Rows[0].Exception.Message | Should -BeLike $faultMessage
                $outcome.Strings | Should -Be @("next statement")
            }
        }

        It "with -IncludeSystemObject and no -Category or -Policy, only the foreach faults, once" {
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
            # sqlwhale22 is shared by the legs of every SQL version at once, and concurrent PBM writes in its msdb fail, so
            # these tests only read: its policies, system ones included, against its catalog.
        }

        It "works with -SqlCredential" {
            $catalog = @(Get-NativeCatalogPolicyName -Server $loginServer)
            $catalog.Count | Should -BeGreaterThan 0
            $results = @(Get-DbaPbmPolicy -SqlInstance $loginInstance -SqlCredential $loginCred -IncludeSystemObject -EnableException)
            ((Select-NativeStableName -Names $results.Name) -join "|") | Should -BeExactly ($catalog -join "|")
            $results[0].SqlInstance | Should -Be $loginServer.DomainInstanceName
        }

        It "fails cleanly without the credential: a warning as Get-DbaPbmStore and no output" {
            $results = @(Get-DbaPbmPolicy -SqlInstance $loginInstance -IncludeSystemObject -WarningVariable loginWarnings -WarningAction SilentlyContinue -ErrorVariable loginErrors -ErrorAction SilentlyContinue)
            $results.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
            $loginErrors.Count | Should -Be 1
            $loginErrors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaPbmStore(,|$)"
            $loginErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
        }

        It "fails cleanly without the credential under -EnableException, as the pinned function does: it only warns" {
            $results = @(Get-DbaPbmPolicy -SqlInstance $loginInstance -IncludeSystemObject -EnableException -WarningVariable strictLoginWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            ($strictLoginWarnings -join " ") | Should -BeLike "*Failure*"
        }
    }

    Context "Corrections" {
        It "reads a named instance once beside piped stores" {
            # The store is read from this instance too, so the rows are counted.
            $store = New-NativePbmStore -SqlInstance $instance
            $results = @($store, $store | Get-DbaPbmPolicy -SqlInstance $instance -Policy $policyA -EnableException)
            # Two piped stores and the named instance once: three rows, where the per-record read gives four.
            $results.Count | Should -Be 3
        }
    }
}

Describe "Native Get-DbaPbmPolicy refuses Azure SQL Database" -Tag IntegrationTests {
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

    # Policy-Based Management applies to SQL Server only and keeps its policies in msdb (Microsoft Learn,
    # "syspolicy_policies": Applies to SQL Server, msdb), and Azure SQL Database has no msdb (Microsoft Learn,
    # "msdb database": SQL Server and Azure SQL Managed Instance). The pin's behaviour there is measured by the item's
    # declared red.
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
        @(Get-DbaPbmPolicy @splatAzure).Count | Should -Be 0
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
        @(Get-DbaPbmPolicy @splatAzure).Count | Should -Be 0
        ($strictAzureWarnings -join " ") | Should -BeLike "*Failure*Azure SQL Database not supported*"
        $strictAzureErrors.Count | Should -Be 1
        $strictAzureErrors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaPbmStore(,|$)"
        $strictAzureErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
    }
}
