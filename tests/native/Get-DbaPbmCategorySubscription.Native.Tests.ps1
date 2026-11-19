#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaPbmCategorySubscription",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned command does not declare SupportsShouldProcess, so it has no -WhatIf or -Confirm.
# NativeChecklist: azure-sqldb N/A -- Policy-Based Management applies to SQL Server only and stores its policies, categories and category subscriptions in msdb (Microsoft Learn, Policy-Based Management Storage; syspolicy_policy_category_subscriptions), which Azure SQL Database does not have (Microsoft Learn, msdb database: SQL Server and Azure SQL Managed Instance). The command refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does, tested below.
Describe "Native Get-DbaPbmCategorySubscription" -Tag IntegrationTests {
    BeforeAll {
        $pbmServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $pbmSuffix = [guid]::NewGuid().ToString("N").Substring(0, 12)
        $pbmCategory = "dbatoolsci_pbmcs_$pbmSuffix"
        $pbmMissing = "nf" + [guid]::NewGuid().ToString("N").Substring(0, 12)

        function Invoke-NativePbmSql ($Server, $Sql) {
            $Server.Databases["msdb"].ExecuteWithResults($Sql).Tables | ForEach-Object { $PSItem.Rows }
        }
        function Add-NativePbmSubscription ($Server, $Category) {
            # A category without mandated subscriptions, and one subscription of master to it; returns the subscription id.
            $null = Invoke-NativePbmSql -Server $Server -Sql "DECLARE @policy_category_id int; EXEC msdb.dbo.sp_syspolicy_add_policy_category @name = N'$Category', @mandate_database_subscriptions = 0, @policy_category_id = @policy_category_id OUTPUT"
            $row = Invoke-NativePbmSql -Server $Server -Sql "DECLARE @subscription_id int; EXEC msdb.dbo.sp_syspolicy_add_policy_category_subscription @target_type = N'DATABASE', @target_object = N'master', @policy_category = N'$Category', @policy_category_subscription_id = @subscription_id OUTPUT; SELECT @subscription_id AS id"
            [int](@($row)[-1].id)
        }
        function Remove-NativePbmSubscription ($Server, $Category) {
            $null = Invoke-NativePbmSql -Server $Server -Sql "DECLARE @subscription_id int; SELECT @subscription_id = s.policy_category_subscription_id FROM msdb.dbo.syspolicy_policy_category_subscriptions AS s INNER JOIN msdb.dbo.syspolicy_policy_categories AS c ON c.policy_category_id = s.policy_category_id WHERE c.name = N'$Category'; IF @subscription_id IS NOT NULL EXEC msdb.dbo.sp_syspolicy_delete_policy_category_subscription @policy_category_subscription_id = @subscription_id; IF EXISTS (SELECT 1 FROM msdb.dbo.syspolicy_policy_categories WHERE name = N'$Category') EXEC msdb.dbo.sp_syspolicy_delete_policy_category @name = N'$Category'"
        }
        function New-NativePbmStore ($Server, $ComputerName, $InstanceName, $SqlInstance) {
            # A store built as the pinned Get-DbaPbmStore builds it, with its three note properties. A call with no input
            # loads the DMF library first, as the command's begin block does.
            $null = Get-DbaPbmCategorySubscription
            $splatStoreConnection = @{
                TypeName     = "Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection"
                ArgumentList = @(, $Server.ConnectionContext.SqlConnectionObject)
            }
            $storeConnection = New-Object @splatStoreConnection
            $store = New-Object -TypeName Microsoft.SqlServer.Management.Dmf.PolicyStore -ArgumentList $storeConnection
            Add-Member -Force -InputObject $store -MemberType NoteProperty -Name ComputerName -Value $ComputerName
            Add-Member -Force -InputObject $store -MemberType NoteProperty -Name InstanceName -Value $InstanceName
            Add-Member -Force -InputObject $store -MemberType NoteProperty -Name SqlInstance -Value $SqlInstance
            $store
        }

        $pbmSubscriptionId = Add-NativePbmSubscription -Server $pbmServer -Category $pbmCategory
    }

    AfterAll {
        Remove-NativePbmSubscription -Server $pbmServer -Category $pbmCategory
    }

    It "returns the instance's subscriptions decorated as the pin decorates them" {
        $pbmSubscriptionId | Should -BeGreaterThan 0
        $catalogBefore = @(Invoke-NativePbmSql -Server $pbmServer -Sql "SELECT policy_category_subscription_id AS id FROM msdb.dbo.syspolicy_policy_category_subscriptions").id
        $results = @(Get-DbaPbmCategorySubscription -SqlInstance $TestConfig.InstanceSingle -ErrorVariable pbmErrors -WarningVariable pbmWarnings)
        $catalogAfter = @(Invoke-NativePbmSql -Server $pbmServer -Sql "SELECT policy_category_subscription_id AS id FROM msdb.dbo.syspolicy_policy_category_subscriptions").id
        $pbmErrors | Should -BeNullOrEmpty
        $pbmWarnings | Should -BeNullOrEmpty

        # Other lanes may add or drop their own subscriptions meanwhile: every id in both reads comes back, nothing outside them.
        @($catalogBefore | Where-Object { $PSItem -in $catalogAfter -and $PSItem -notin $results.ID }) | Should -BeNullOrEmpty
        @($results.ID | Where-Object { $PSItem -notin $catalogBefore -and $PSItem -notin $catalogAfter }) | Should -BeNullOrEmpty
        @($results.ID | Select-Object -Unique).Count | Should -Be $results.Count

        $mine = @($results | Where-Object PolicyCategory -eq $pbmCategory)
        $mine.Count | Should -Be 1
        $mine[0] | Should -BeOfType [Microsoft.SqlServer.Management.Dmf.PolicyCategorySubscription]
        $mine[0].ID | Should -Be $pbmSubscriptionId
        $mine[0].ComputerName | Should -BeExactly $pbmServer.ComputerName
        $mine[0].InstanceName | Should -BeExactly $pbmServer.ServiceName
        $mine[0].SqlInstance | Should -BeExactly $pbmServer.DomainInstanceName

        # Select-DefaultView -ExcludeProperty Properties, Urn, Parent: every other property, note properties first.
        $display = @($mine[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames)
        $display[0..2] -join "," | Should -BeExactly "ComputerName,InstanceName,SqlInstance"
        $display | Should -Contain "PolicyCategory"
        $display | Should -Contain "ID"
        @($display | Where-Object { $PSItem -in "Properties", "Urn", "Parent" }) | Should -BeNullOrEmpty

        # The store the nested Get-DbaPbmStore builds carries its own decoration and default view.
        $mine[0].Parent | Should -BeOfType [Microsoft.SqlServer.Management.Dmf.PolicyStore]
        $mine[0].Parent.SqlInstance | Should -BeExactly $pbmServer.DomainInstanceName
        $storeDisplay = @($mine[0].Parent.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames)
        $storeDisplay | Should -Contain "ComputerName"
        @($storeDisplay | Where-Object { $PSItem -in "SqlStoreConnection", "ConnectionContext", "Properties", "Urn", "Parent", "DomainInstanceName", "Metadata", "IdentityKey", "Name" }) | Should -BeNullOrEmpty
    }

    It "reads each piped store and takes the instance names from the store" -Tag "NativeChecklist:pipeline-multiple" {
        $storeA = New-NativePbmStore -Server $pbmServer -ComputerName "dbatoolsci_computer_a" -InstanceName "dbatoolsci_instance_a" -SqlInstance "dbatoolsci_sqlinstance_a"
        $storeB = New-NativePbmStore -Server $pbmServer -ComputerName "dbatoolsci_computer_b" -InstanceName "dbatoolsci_instance_b" -SqlInstance "dbatoolsci_sqlinstance_b"
        $results = @($storeA, $storeB | Get-DbaPbmCategorySubscription -ErrorVariable pbmErrors)
        $pbmErrors | Should -BeNullOrEmpty
        $mine = @($results | Where-Object PolicyCategory -eq $pbmCategory)
        $mine.Count | Should -Be 2
        $mine[0].ComputerName | Should -BeExactly "dbatoolsci_computer_a"
        $mine[0].InstanceName | Should -BeExactly "dbatoolsci_instance_a"
        $mine[0].SqlInstance | Should -BeExactly "dbatoolsci_sqlinstance_a"
        $mine[1].ComputerName | Should -BeExactly "dbatoolsci_computer_b"
        $mine[1].SqlInstance | Should -BeExactly "dbatoolsci_sqlinstance_b"
        @($mine[1].PSObject.Properties | Where-Object Name -eq "ComputerName").Count | Should -Be 1

        # A piped object without the property brings nothing and says nothing.
        $plain = [pscustomobject]@{ Name = "dbatoolsci_not_a_store" }
        @($plain | Get-DbaPbmCategorySubscription -ErrorVariable plainErrors -WarningVariable plainWarnings).Count | Should -Be 0
        $plainErrors | Should -BeNullOrEmpty
        $plainWarnings | Should -BeNullOrEmpty
    }

    It "returns each instance's subscriptions and goes on past one that fails to connect" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
        $warnings = @()
        $splatInstances = @{
            SqlInstance     = $TestConfig.InstanceSingle, $pbmMissing, $TestConfig.InstanceSingle
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "warnings"
        }
        $results = @(Get-DbaPbmCategorySubscription @splatInstances)
        @($results | Where-Object PolicyCategory -eq $pbmCategory).Count | Should -Be 2
        $warnings.Count | Should -Be 1
        # One line naming the nested Get-DbaPbmStore, its failure message and the instance (brackets matched literally).
        "$($warnings[0])" | Should -Match ([regex]::Escape("[Get-DbaPbmStore] Failure | Error connecting to [$pbmMissing]: "))
    }

    # PS (pin, public/Get-DbaPbmCategorySubscription.ps1): $InputObject += Get-DbaPbmStore -SqlInstance $instance -SqlCredential
    # $SqlCredential passes no -EnableException, and Get-DbaPbmStore's connection catch is Stop-Function -Continue in its own
    # scope, where $EnableException is its own unbound switch: it warns and brings no store, whatever this command's switch.
    It "warns and does not throw for a failed connection under -EnableException, as the nested Get-DbaPbmStore does" -Tag "NativeChecklist:enable-exception" {
        $warnings = @()
        # A throw here fails the test.
        $results = @(Get-DbaPbmCategorySubscription -SqlInstance $pbmMissing -EnableException -WarningAction SilentlyContinue -WarningVariable warnings)
        $results.Count | Should -Be 0
        $warnings.Count | Should -Be 1
        "$($warnings[0])" | Should -Match ([regex]::Escape("[Get-DbaPbmStore] Failure | Error connecting to [$pbmMissing]: "))
    }

    # PS: $all = $store.PolicycategorySubscriptions. Outside strict mode the engine reads a member whose getter fails as $null,
    # with no error a try can catch (measured: this item's red, 20261111T1512290677902Z, and Get-DbaLinkedServer's pin probe
    # pin-azure-lsgetter), so such a store brings nothing and the call goes on. The unreadable store is a closed MemoryStream
    # whose Position, read through an alias property, throws.
    Context "A store whose subscriptions cannot be read" {
        BeforeAll {
            $unreadable = New-Object System.IO.MemoryStream
            $unreadable.Dispose()
            Add-Member -InputObject $unreadable -MemberType AliasProperty -Name PolicyCategorySubscriptions -Value Position
            Add-Member -InputObject $unreadable -MemberType NoteProperty -Name ComputerName -Value "dbatoolsci_unreadable"
            Add-Member -InputObject $unreadable -MemberType NoteProperty -Name InstanceName -Value "dbatoolsci_unreadable"
            Add-Member -InputObject $unreadable -MemberType NoteProperty -Name SqlInstance -Value "dbatoolsci_unreadable"

        }

        It "reads nothing from a store whose subscriptions cannot be read and goes on to the next store, under -EnableException too" {
            # Independent checks: the alias is there and its getter fails, yet the engine's own read gives $null.
            $unreadable.PSObject.Properties.Name | Should -Contain "PolicyCategorySubscriptions"
            { $null = $unreadable.PSObject.BaseObject.get_Position() } | Should -Throw
            $unreadable.PolicyCategorySubscriptions | Should -BeNullOrEmpty

            $storeA = New-NativePbmStore -Server $pbmServer -ComputerName "dbatoolsci_computer_a" -InstanceName "dbatoolsci_instance_a" -SqlInstance "dbatoolsci_sqlinstance_a"
            $storeB = New-NativePbmStore -Server $pbmServer -ComputerName "dbatoolsci_computer_b" -InstanceName "dbatoolsci_instance_b" -SqlInstance "dbatoolsci_sqlinstance_b"
            foreach ($stop in $false, $true) {
                $errors = @()
                $results = @($storeA, $unreadable, $storeB | Get-DbaPbmCategorySubscription -EnableException:$stop -ErrorVariable errors)
                $errors | Should -BeNullOrEmpty
                $mine = @($results | Where-Object PolicyCategory -eq $pbmCategory)
                $mine.ComputerName -join "," | Should -BeExactly "dbatoolsci_computer_a,dbatoolsci_computer_b"
                @($results | Where-Object ComputerName -eq "dbatoolsci_unreadable") | Should -BeNullOrEmpty
            }
        }
    }

    # PS: foreach ($current in $all) { ... } over a collection whose enumeration fails part way: the statement ends at the
    # fault, what it already wrote stays, and the pin goes on with its next store. The port's StatementFault site: a plain
    # call writes the record and goes on, -EnableException ends the command, -ErrorAction Stop and a caller's try stop at it.
    # The failing collection is a LINQ Select whose selector throws on the second item, made in the runspace that runs it.
    Context "A store whose subscriptions fail part way through" {
        BeforeAll {
            $faultSetup = @'
param($Arguments)
$first = [pscustomobject]@{ Name = "dbatoolsci_first" }
$second = [pscustomobject]@{ Name = "dbatoolsci_second" }
$selector = [Func[object, object]] { param($item) if ($item.Name -eq "dbatoolsci_second") { throw "dbatoolsci enumeration fault" }; $item }
$faulting = [pscustomobject]@{ ComputerName = "dbatoolsci_fault"; InstanceName = "dbatoolsci_fault"; SqlInstance = "dbatoolsci_fault"; PolicyCategorySubscriptions = [System.Linq.Enumerable]::Select([object[]]@($first, $second), $selector) }
$healthy = [pscustomobject]@{ ComputerName = "dbatoolsci_next"; InstanceName = "dbatoolsci_next"; SqlInstance = "dbatoolsci_next"; PolicyCategorySubscriptions = @([pscustomobject]@{ Name = "dbatoolsci_next" }) }
'@
            $plainBody = '$faulting, $healthy | Get-DbaPbmCategorySubscription @Arguments; "next statement"'
            $tryBody = 'try { $faulting, $healthy | Get-DbaPbmCategorySubscription @Arguments; "after call" } catch { $PSItem }; "next statement"'

            # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
            function Invoke-NativeFaultOutsideTry ([hashtable]$Arguments, [string]$Body) {
                $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $outsideType = (Get-Command Get-DbaPbmCategorySubscription -CommandType Cmdlet).ImplementingType
                $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaPbmCategorySubscription", $outsideType, $null
                $outsideState.Commands.Add($outsideEntry)
                $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
                $outsideShell = [System.Management.Automation.PowerShell]::Create()
                $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                $outsideStop = $null
                try {
                    $outsideRunspace.Open()
                    $outsideShell.Runspace = $outsideRunspace
                    $null = $outsideShell.AddScript($faultSetup + "`n" + $Body).AddArgument($Arguments)
                    try {
                        $null = $outsideShell.Invoke($null, $outsideOutput)
                    } catch {
                        # The stop leaves the runspace's script through Invoke, as a method call's exception.
                        $outsideStop = $PSItem.Exception.InnerException
                    }
                    [pscustomobject]@{
                        Rows    = @($outsideOutput | Where-Object { $PSItem -isnot [string] })
                        Strings = @($outsideOutput | Where-Object { $PSItem -is [string] } | ForEach-Object { [string]$PSItem })
                        Errors  = @($outsideShell.Streams.Error)
                        Stop    = $outsideStop
                    }
                } finally {
                    $outsideShell.Dispose()
                    $outsideRunspace.Dispose()
                }
            }

            # The record names the selector's fault somewhere in its exception chain.
            function Test-NativeFaultChain ($Record) {
                $exception = $Record.Exception
                while ($exception) {
                    if ($exception.Message -like "*dbatoolsci enumeration fault*") { return $true }
                    $exception = $exception.InnerException
                }
                $false
            }
        }

        It "outside any try, a plain call writes the fault, keeps what the store gave before it, and reads the next store" {
            $outcome = Invoke-NativeFaultOutsideTry -Arguments @{} -Body $plainBody
            $outcome.Stop | Should -BeNullOrEmpty
            @($outcome.Rows | ForEach-Object Name) | Should -Be @("dbatoolsci_first", "dbatoolsci_next")
            $outcome.Rows[0].ComputerName | Should -BeExactly "dbatoolsci_fault"
            $outcome.Errors.Count | Should -Be 1
            Test-NativeFaultChain -Record $outcome.Errors[0] | Should -BeTrue
            $outcome.Strings | Should -Be @("next statement")
        }

        It "outside any try, -EnableException ends the command at the fault and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outcome = Invoke-NativeFaultOutsideTry -Arguments @{ EnableException = $true } -Body $plainBody
            $outcome.Stop | Should -BeNullOrEmpty
            @($outcome.Rows | ForEach-Object Name) | Should -Be @("dbatoolsci_first")
            $outcome.Errors.Count | Should -Be 1
            Test-NativeFaultChain -Record $outcome.Errors[0] | Should -BeTrue
            $outcome.Strings | Should -Be @("next statement")
        }

        It "outside any try, -ErrorAction Stop stops the script at the fault" {
            $outcome = Invoke-NativeFaultOutsideTry -Arguments @{ ErrorAction = "Stop" } -Body $plainBody
            $outcome.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Test-NativeFaultChain -Record $outcome.Stop.ErrorRecord | Should -BeTrue
            @($outcome.Rows | ForEach-Object Name) | Should -Be @("dbatoolsci_first")
            $outcome.Strings.Count | Should -Be 0
        }

        It "inside a caller's try without -EnableException, the catch receives the fault and nothing follows it" {
            $outcome = Invoke-NativeFaultOutsideTry -Arguments @{} -Body $tryBody
            $outcome.Stop | Should -BeNullOrEmpty
            $outcome.Rows.Count | Should -Be 2
            $outcome.Rows[0].Name | Should -BeExactly "dbatoolsci_first"
            $outcome.Rows[1] | Should -BeOfType System.Management.Automation.ErrorRecord
            Test-NativeFaultChain -Record $outcome.Rows[1] | Should -BeTrue
            $outcome.Strings | Should -Be @("next statement")
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            $loginCategory = "dbatoolsci_pbmcslogin_" + [guid]::NewGuid().ToString("N").Substring(0, 12)
            $loginSubscriptionId = Add-NativePbmSubscription -Server $loginServer -Category $loginCategory
        }

        AfterAll {
            Remove-NativePbmSubscription -Server $loginServer -Category $loginCategory
        }

        It "works with -SqlCredential" {
            $results = @(Get-DbaPbmCategorySubscription -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException | Where-Object PolicyCategory -eq $loginCategory)
            $results.Count | Should -Be 1
            $results[0].ID | Should -Be $loginSubscriptionId
            $results[0].SqlInstance | Should -BeExactly $loginServer.DomainInstanceName
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = @()
            $result = Get-DbaPbmCategorySubscription -SqlInstance $loginInstance -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warnings | Should -Not -BeNullOrEmpty
        }

        # The pin connects only through the nested Get-DbaPbmStore without -EnableException (see the enable-exception test).
        It "fails cleanly without the credential under -EnableException, as the pinned function does: a warning, no output, no throw" {
            $warnings = @()
            # A throw here fails the test.
            $results = @(Get-DbaPbmCategorySubscription -SqlInstance $loginInstance -EnableException -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            $warnings | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Native Get-DbaPbmCategorySubscription refuses Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once per call.
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
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.NativeErrorCode -eq 258 -or $azureError.Message -like "*timed out*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }

    # Correction azure-unsupported: the nested Get-DbaPbmStore refuses the engine as Connect-DbaInstance -AzureUnsupported does,
    # with its "Failure" warning and no store, under -EnableException too, because the pin passes that switch no further.
    It "refuses Azure SQL Database with the nested Get-DbaPbmStore warning and no output" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $azureErrors = @()
        $splatAzure = @{
            SqlInstance     = $azureServer
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
            ErrorVariable   = "azureErrors"
            ErrorAction     = "SilentlyContinue"
        }
        @(Get-DbaPbmCategorySubscription @splatAzure).Count | Should -Be 0
        $azureWarnings.Count | Should -Be 1
        "$($azureWarnings[0])" | Should -BeLike "*[[]Get-DbaPbmStore[]] Failure*Azure SQL Database not supported*"
        @($azureErrors | Where-Object { "$($PSItem.Exception.Message)" -notlike "*Azure SQL Database not supported*" }) | Should -BeNullOrEmpty

        $eeWarnings = @()
        # A throw here fails the test.
        $eeResults = @(Get-DbaPbmCategorySubscription -SqlInstance $azureServer -EnableException -WarningAction SilentlyContinue -WarningVariable eeWarnings)
        $eeResults.Count | Should -Be 0
        $eeWarnings.Count | Should -Be 1
        "$($eeWarnings[0])" | Should -BeLike "*Azure SQL Database not supported*"
    }
}
