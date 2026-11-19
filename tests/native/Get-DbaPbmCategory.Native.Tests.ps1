#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaPbmCategory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads policy categories.
# NativeChecklist: platform windows-only -- windows-smo: the DMF PolicyStore that Add-PbmLibrary loads; off Windows the nested Get-DbaPbmStore refuses, as the pin does.

Describe "Native Get-DbaPbmCategory" -Tag IntegrationTests {
    BeforeAll {
        # The legs of one SQL version share the instances; every name carries this run's number.
        $instance = $TestConfig.InstanceSingle
        $server = Connect-DbaInstance -SqlInstance $instance -EnableException
        $stamp = Get-Random
        $categoryA = "dbatoolsci_pbmcat_${stamp}_a"
        $categoryB = "dbatoolsci_pbmcat_${stamp}_b"
        $missingCategory = "dbatoolsci_pbmcat_${stamp}_none"
        $null = $server.Query("DECLARE @id int; EXEC msdb.dbo.sp_syspolicy_add_policy_category @name = N'$categoryA', @mandate_database_subscriptions = 0, @policy_category_id = @id OUTPUT;")
        $null = $server.Query("DECLARE @id int; EXEC msdb.dbo.sp_syspolicy_add_policy_category @name = N'$categoryB', @mandate_database_subscriptions = 1, @policy_category_id = @id OUTPUT;")
        $badInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $bindingMessage = "Cannot bind argument to parameter 'SqlInstance' because it is null."
        # The first call loads the DMF assemblies, which New-NativePbmStore needs.
        $null = Get-DbaPbmCategory -SqlInstance $instance -Category $missingCategory -EnableException

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

        function Get-NativeCatalogCategory ($Server) {
            $Server.Query("SELECT policy_category_id, name, mandate_database_subscriptions FROM msdb.dbo.syspolicy_policy_categories;") |
                ForEach-Object { "{0}|{1}|{2}" -f $PSItem.policy_category_id, $PSItem.name, [bool]$PSItem.mandate_database_subscriptions } |
                Sort-Object
        }

        # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
        function Invoke-NativeOutsideTry {
            param([hashtable]$Arguments, [string]$Script = 'param($Arguments) Get-DbaPbmCategory @Arguments; "next statement"')
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaPbmCategory -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaPbmCategory", $outsideType, $null
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
        foreach ($name in $categoryA, $categoryB) {
            $null = $server.Query("IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_policy_categories WHERE name = N'$name') EXEC msdb.dbo.sp_syspolicy_delete_policy_category @name = N'$name';")
        }
    }

    Context "Output" {
        It "returns every category of the instance with its id and subscription mandate" {
            $results = @(Get-DbaPbmCategory -SqlInstance $instance -EnableException)
            $actual = @($results | ForEach-Object { "{0}|{1}|{2}" -f $PSItem.Id, $PSItem.Name, $PSItem.MandateDatabaseSubscriptions } | Sort-Object)
            $actual | Should -Be @(Get-NativeCatalogCategory -Server $server)
            ($results | Where-Object Name -eq $categoryA).MandateDatabaseSubscriptions | Should -BeFalse
            ($results | Where-Object Name -eq $categoryB).MandateDatabaseSubscriptions | Should -BeTrue
        }

        It "keeps the DMF type, the instance columns and the pinned default view" {
            $row = Get-DbaPbmCategory -SqlInstance $instance -Category $categoryA -EnableException
            $row.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Dmf.PolicyCategory"
            $row.ComputerName | Should -Be $server.ComputerName
            $row.InstanceName | Should -Be $server.ServiceName
            $row.SqlInstance | Should -Be $server.DomainInstanceName
            $row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Be @("ComputerName", "InstanceName", "SqlInstance", "Id", "Name", "MandateDatabaseSubscriptions")
        }
    }

    Context "-Category" {
        It "returns only the named categories, without regard to case" {
            $results = @(Get-DbaPbmCategory -SqlInstance $instance -Category $categoryA.ToUpperInvariant(), $missingCategory -EnableException)
            $results.Count | Should -Be 1
            $results[0].Name | Should -BeExactly $categoryA
        }

        It "gives nothing and no warning for a name no category has" {
            $results = @(Get-DbaPbmCategory -SqlInstance $instance -Category $missingCategory -WarningVariable missingWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            $missingWarnings | Should -BeNullOrEmpty
        }

        It "reads -Category by its truth, so a lone empty value filters nothing" {
            @(Get-DbaPbmCategory -SqlInstance $instance -Category "" -EnableException).Count | Should -Be @(Get-NativeCatalogCategory -Server $server).Count
        }
    }

    Context "Stores" {
        It "reads several piped stores, each with its own instance columns" -Tag "NativeChecklist:pipeline-multiple" {
            $stores = @(New-NativePbmStore -SqlInstance $instance; New-NativePbmStore -SqlInstance $TestConfig.InstanceCopy1)
            $stores.Count | Should -Be 2
            $results = @($stores | Get-DbaPbmCategory -Category "Availability database errors" -EnableException)
            $results.Count | Should -Be 2
            $results[0].SqlInstance | Should -Be $stores[0].SqlInstance
            $results[1].SqlInstance | Should -Be $stores[1].SqlInstance
        }

        It "takes stores by -InputObject and puts the named instances after them" {
            $store = New-NativePbmStore -SqlInstance $TestConfig.InstanceCopy1
            $results = @(Get-DbaPbmCategory -InputObject $store -SqlInstance $instance -Category "Availability database errors" -EnableException)
            $results.Count | Should -Be 2
            $results[0].SqlInstance | Should -Be $store.SqlInstance
            $results[1].SqlInstance | Should -Be $server.DomainInstanceName
        }

        It "gives nothing and no error for an object that is no store" {
            $results = @(Get-DbaPbmCategory -InputObject "dbatoolsci_notastore" -ErrorVariable junkErrors -WarningVariable junkWarnings -WarningAction SilentlyContinue)
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
                    Category        = $categoryA
                    EnableException = $enable
                    WarningVariable = "failedWarnings"
                    WarningAction   = "SilentlyContinue"
                    ErrorVariable   = "failedErrors"
                }
                $results = @(Get-DbaPbmCategory @splatFailed)
                $results.Count | Should -Be 1
                $results[0].Name | Should -BeExactly $categoryA
                ($failedWarnings -join " ") | Should -BeLike "*Failure*"
                $failedErrors.Count | Should -Be 1
                $failedErrors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaPbmStore(,|$)"
                $failedErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
            }
        }

        It "only warns under -EnableException:`$false too" -Tag "NativeChecklist:switch-false" {
            $results = @(Get-DbaPbmCategory -SqlInstance $badInstance -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            ($falseWarnings -join " ") | Should -BeLike "*Failure*"
        }
    }

    Context "Null elements" {
        It "outside any try, a plain call writes the binding fault of the nested Get-DbaPbmStore and reads the other instances" {
            foreach ($instances in @(@($null, $instance), @($instance, $null))) {
                $outcome = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = $instances; Category = $categoryA }
                $outcome.Stop | Should -BeNullOrEmpty
                $outcome.Rows.Count | Should -Be 1
                $outcome.Rows[0].Name | Should -BeExactly $categoryA
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
            $script = 'param($Arguments) try { Get-DbaPbmCategory @Arguments; "after call" } catch { $PSItem }; "next statement"'
            foreach ($extra in @{}, @{ EnableException = $true }, @{ ErrorAction = "Stop" }) {
                $arguments = @{ SqlInstance = @($null, $instance); Category = $categoryA } + $extra
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
            $outcome = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = @($null, $instance); Category = $categoryA; EnableException = $true }
            $outcome.Stop | Should -BeNullOrEmpty
            $outcome.Rows.Count | Should -Be 0
            $outcome.Errors.Count | Should -Be 1
            $outcome.Errors[0].Exception.Message | Should -BeExactly $bindingMessage
            $outcome.Strings | Should -Be @("next statement")
        }

        It "outside any try, -ErrorAction Stop turns the fault into the stop PowerShell gives WriteError" {
            $outcome = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = @($null, $instance); Category = $categoryA; ErrorAction = "Stop" }
            $outcome.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outcome.Stop.ErrorRecord.Exception.Message | Should -BeExactly $bindingMessage
            $outcome.Stop.ErrorRecord.FullyQualifiedErrorId | Should -Match "^ParameterArgumentValidationErrorNullNotAllowed(,|$)"
            $outcome.Stop.ErrorRecord.CategoryInfo.Activity | Should -BeExactly "Get-DbaPbmCategory"
            $outcome.Rows.Count | Should -Be 0
            $outcome.Strings.Count | Should -Be 0
        }
    }

    Context "Enumeration faults" {
        BeforeAll {
            # A store whose categories cannot be read: getting their enumerator throws, as an SFC collection does when it
            # cannot load its members. The same code path takes a real store whose connection is gone.
            if (-not ("NativePbmCategoryTests.FailingCollection" -as [type])) {
                Add-Type -TypeDefinition @"
using System;
using System.Collections;
namespace NativePbmCategoryTests {
    public sealed class FailingCollection : IEnumerable {
        public IEnumerator GetEnumerator() { throw new InvalidOperationException("dbatoolsci enumeration fault"); }
    }
}
"@
            }
            $faultMessage = "*dbatoolsci enumeration fault*"
            $failingStore = [pscustomobject]@{
                PolicyCategories = New-Object NativePbmCategoryTests.FailingCollection
                ComputerName     = "dbatoolsci"
                InstanceName     = "MSSQLSERVER"
                SqlInstance      = "dbatoolsci"
            }
            $healthyStore = New-NativePbmStore -SqlInstance $instance
        }

        It "outside any try, a plain call writes one record per pinned statement and reads the next store" {
            $outcome = Invoke-NativeOutsideTry -Arguments @{ InputObject = @($failingStore, $healthyStore); Category = $categoryA }
            $outcome.Stop | Should -BeNullOrEmpty
            # The IsSystemObject filter, the -Category filter and the foreach each enumerate the collection again.
            $outcome.Errors.Count | Should -Be 3
            foreach ($record in $outcome.Errors) {
                $record.Exception.Message | Should -BeLike $faultMessage
            }
            $outcome.Rows.Count | Should -Be 1
            $outcome.Rows[0].Name | Should -BeExactly $categoryA
            $outcome.Strings | Should -Be @("next statement")
        }

        It "outside any try, -EnableException ends the command at the first fault and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outcome = Invoke-NativeOutsideTry -Arguments @{ InputObject = @($failingStore, $healthyStore); Category = $categoryA; EnableException = $true }
            $outcome.Stop | Should -BeNullOrEmpty
            $outcome.Errors.Count | Should -Be 1
            $outcome.Errors[0].Exception.Message | Should -BeLike $faultMessage
            $outcome.Rows.Count | Should -Be 0
            $outcome.Strings | Should -Be @("next statement")
        }

        It "outside any try, -ErrorAction Stop turns the fault into the stop PowerShell gives WriteError" {
            $outcome = Invoke-NativeOutsideTry -Arguments @{ InputObject = @($failingStore, $healthyStore); Category = $categoryA; ErrorAction = "Stop" }
            $outcome.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outcome.Stop.ErrorRecord.Exception.Message | Should -BeLike $faultMessage
            $outcome.Rows.Count | Should -Be 0
            $outcome.Strings.Count | Should -Be 0
        }

        It "inside a caller's try, the fault stops the command and the catch receives it" {
            $script = 'param($Arguments) try { Get-DbaPbmCategory @Arguments; "after call" } catch { $PSItem }; "next statement"'
            foreach ($extra in @{}, @{ EnableException = $true }, @{ ErrorAction = "Stop" }) {
                $arguments = @{ InputObject = @($failingStore, $healthyStore); Category = $categoryA } + $extra
                $outcome = Invoke-NativeOutsideTry -Arguments $arguments -Script $script
                $outcome.Rows.Count | Should -Be 1
                $outcome.Rows[0] | Should -BeOfType System.Management.Automation.ErrorRecord
                $outcome.Rows[0].Exception.Message | Should -BeLike $faultMessage
                $outcome.Strings | Should -Be @("next statement")
            }
        }

        It "with -ExcludeSystemObject and no -Category, only the foreach faults, once" {
            $outcome = Invoke-NativeOutsideTry -Arguments @{ InputObject = @($failingStore); ExcludeSystemObject = $true }
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
            # sqlwhale22 is shared: the category is unique per leg and run.
            $loginCategory = "dbatoolsci_pbmcat_${stamp}_login"
            $null = $loginServer.Query("DECLARE @id int; EXEC msdb.dbo.sp_syspolicy_add_policy_category @name = N'$loginCategory', @mandate_database_subscriptions = 0, @policy_category_id = @id OUTPUT;")
        }
        AfterAll {
            $null = $loginServer.Query("IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_policy_categories WHERE name = N'$loginCategory') EXEC msdb.dbo.sp_syspolicy_delete_policy_category @name = N'$loginCategory';")
        }

        It "works with -SqlCredential" {
            $results = @(Get-DbaPbmCategory -SqlInstance $loginInstance -SqlCredential $loginCred -Category $loginCategory -EnableException)
            $results.Count | Should -Be 1
            $results[0].Name | Should -BeExactly $loginCategory
            $results[0].SqlInstance | Should -Be $loginServer.DomainInstanceName
        }

        It "fails cleanly without the credential: a warning as Get-DbaPbmStore and no output" {
            $results = @(Get-DbaPbmCategory -SqlInstance $loginInstance -Category $loginCategory -WarningVariable loginWarnings -WarningAction SilentlyContinue -ErrorVariable loginErrors -ErrorAction SilentlyContinue)
            $results.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
            $loginErrors.Count | Should -Be 1
            $loginErrors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaPbmStore(,|$)"
            $loginErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
        }

        It "fails cleanly without the credential under -EnableException, as the pinned function does: it only warns" {
            $results = @(Get-DbaPbmCategory -SqlInstance $loginInstance -Category $loginCategory -EnableException -WarningVariable strictLoginWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            ($strictLoginWarnings -join " ") | Should -BeLike "*Failure*"
        }
    }

    Context "Corrections" {
        It "reads a named instance once beside piped stores" {
            # The lab's copy instances may be this instance, so the store is read from it too and the rows are counted.
            $store = New-NativePbmStore -SqlInstance $instance
            $results = @($store, $store | Get-DbaPbmCategory -SqlInstance $instance -Category $categoryA -EnableException)
            # Two piped stores and the named instance once: three rows, where the per-record read gives four.
            $results.Count | Should -Be 3
        }
    }
}

Describe "Native Get-DbaPbmCategory refuses Azure SQL Database" -Tag IntegrationTests {
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

    # Policy-Based Management applies to SQL Server only and keeps its policies and categories in msdb (Microsoft Learn,
    # "Administer servers by using Policy-Based Management" and "syspolicy_policy_categories": Applies to SQL Server), and
    # Azure SQL Database has no msdb (Microsoft Learn, "msdb database": SQL Server and Azure SQL Managed Instance). The
    # pin's behaviour there is measured in the item's evidence.
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
        @(Get-DbaPbmCategory @splatAzure).Count | Should -Be 0
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
        @(Get-DbaPbmCategory @splatAzure).Count | Should -Be 0
        ($strictAzureWarnings -join " ") | Should -BeLike "*Failure*Azure SQL Database not supported*"
        $strictAzureErrors.Count | Should -Be 1
        $strictAzureErrors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaPbmStore(,|$)"
        $strictAzureErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
    }
}
