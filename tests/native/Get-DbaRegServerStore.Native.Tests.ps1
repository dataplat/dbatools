#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaRegServerStore",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only opens the store.

Describe "Native Get-DbaRegServerStore" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $server = Connect-DbaInstance -SqlInstance $instance -EnableException
        $badInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        # The connect warning names the target as DbaInstanceParameter shows it, TCP:127.0.0.1,1 for this connection string.
        # A warning record's message starts with its time, "[18:35:37][Get-DbaRegServerStore] ...", so the line is not anchored.
        $badLine = "\[Get-DbaRegServerStore\] Failure \| Error connecting to \[[^\]]*127\.0\.0\.1,1\]: "
        $excludedView = @("ServerConnection", "DomainInstanceName", "DomainName", "Urn", "Properties", "Metadata", "Parent", "ConnectionContext", "PropertyMetadataChanged", "PropertyChanged", "ParentServer", "IsNewConnection")
        $localFile = [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore]::LocalFileStore.DomainInstanceName
    }

    Context "Central Management Server store" {
        It "returns the instance's store with the instance columns and its own connection" {
            $results = @(Get-DbaRegServerStore -SqlInstance $instance -EnableException)
            $results.Count | Should -Be 1
            $store = $results[0]
            $store.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore"
            $store.DisplayName | Should -Be "Central Management Servers"
            $store.ComputerName | Should -Be $server.ComputerName
            $store.InstanceName | Should -Be $server.ServiceName
            $store.SqlInstance | Should -Be $server.DomainInstanceName
            $store.ParentServer | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Server]
            $store.ParentServer.DomainInstanceName | Should -Be $server.DomainInstanceName
            $store.IsNewConnection | Should -BeTrue
        }

        It "marks a Server object of the caller as not its own connection" {
            $store = Get-DbaRegServerStore -SqlInstance $server -EnableException
            $store.IsNewConnection | Should -BeFalse
            $store.ParentServer.DomainInstanceName | Should -Be $server.DomainInstanceName
        }

        It "reads the instance's top-level server groups through the store, as msdb lists them" {
            $store = Get-DbaRegServerStore -SqlInstance $instance -EnableException
            $query = "SELECT g.name FROM msdb.dbo.sysmanagement_shared_server_groups AS g WHERE g.parent_id = (SELECT r.server_group_id FROM msdb.dbo.sysmanagement_shared_server_groups AS r WHERE r.parent_id IS NULL AND r.name = N'DatabaseEngineServerGroup');"
            $expected = @($server.Query($query) | ForEach-Object { $PSItem.name } | Sort-Object)
            # Joined, so an instance with no groups compares "" with "".
            (@($store.DatabaseEngineServerGroup.ServerGroups | ForEach-Object Name | Sort-Object) -join "|") | Should -BeExactly ($expected -join "|")
        }

        It "shows every property but the pin's excluded ones by default" {
            $store = Get-DbaRegServerStore -SqlInstance $instance -EnableException
            $view = @($store.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames)
            foreach ($name in "ComputerName", "InstanceName", "SqlInstance", "DatabaseEngineServerGroup", "CentralManagementServerGroup", "DisplayName") {
                $view | Should -Contain $name
            }
            foreach ($name in $excludedView) {
                $view | Should -Not -Contain $name
            }
        }
    }

    Context "Local file store" {
        It "returns the local store, unchanged, when -SqlInstance is not given" {
            $results = @(Get-DbaRegServerStore -EnableException)
            $results.Count | Should -Be 1
            $results[0].GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore"
            $results[0].PSObject.Properties["IsNewConnection"] | Should -BeNullOrEmpty
            Test-Path -Path $localFile | Should -BeTrue
        }

        It "returns the local store for an empty -SqlInstance too, as the pin's bound-value test reads it" {
            $results = @(Get-DbaRegServerStore -SqlInstance @() -EnableException)
            $results.Count | Should -Be 1
            $results[0].GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore"
        }
    }

    # The local store's read failure, a statement fault of the pin outside any try (StatementFault.Surface). It is provoked
    # without changing the store: the file is held open with FileShare.None for the length of one call, so InitChildObjects
    # cannot read it. Measured on the pin, both editions: evidence/pin-localstore-fault-r2-20261112.txt.
    Context "Local file store read failure" {
        BeforeAll {
            $storeFaultMessage = 'Exception calling "Invoke" with "2" argument(s): "Unable to read the list of previously registered servers on this system. Re-register your servers in the ''Registered Servers'' window."'

            function Lock-NativeStore {
                [System.IO.File]::Open($localFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
            }

            # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
            function Invoke-NativeOutsideTry {
                param([hashtable]$Arguments)
                $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $outsideType = (Get-Command Get-DbaRegServerStore -CommandType Cmdlet).ImplementingType
                $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaRegServerStore", $outsideType, $null
                $outsideState.Commands.Add($outsideEntry)
                $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
                $outsideShell = [System.Management.Automation.PowerShell]::Create()
                $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                $outsideStop = $null
                try {
                    $outsideRunspace.Open()
                    $outsideShell.Runspace = $outsideRunspace
                    $null = $outsideShell.AddScript('param($Arguments) Get-DbaRegServerStore @Arguments; "next statement"').AddArgument($Arguments)
                    $lock = Lock-NativeStore
                    try {
                        $null = $outsideShell.Invoke($null, $outsideOutput)
                    } catch {
                        # The stop leaves the runspace's script through Invoke, as a method call's exception.
                        $outsideStop = $PSItem.Exception.InnerException
                    } finally {
                        $lock.Dispose()
                    }
                    [pscustomobject]@{
                        Stores = @($outsideOutput | Where-Object { $PSItem.psobject.BaseObject -is [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore] })
                        Next   = @($outsideOutput | Where-Object { "$($PSItem.psobject.BaseObject)" -ceq "next statement" }).Count -gt 0
                        Errors = @($outsideShell.Streams.Error)
                        Stop   = $outsideStop
                    }
                } finally {
                    $outsideShell.Dispose()
                    $outsideRunspace.Dispose()
                }
            }

            function Assert-NativeStoreFault {
                param($Record)
                $Record.FullyQualifiedErrorId | Should -BeLike "RegisteredServerException*"
                $Record.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.MethodInvocationException"
                $Record.Exception.Message | Should -BeExactly $storeFaultMessage
                "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
                $Record.CategoryInfo.Reason | Should -BeExactly "MethodInvocationException"
                $Record.TargetObject | Should -BeNullOrEmpty
                $Record.Exception.InnerException.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.RegisteredServers.RegisteredServerException"
                $Record.Exception.InnerException.InnerException.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Sdk.Sfc.SfcSerializationException"
                $Record.Exception.InnerException.InnerException.InnerException.GetType().FullName | Should -BeExactly "System.IO.IOException"
            }
        }

        It "outside any try, a plain call writes the record, returns no store and the script goes on" {
            $outside = Invoke-NativeOutsideTry @{ }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeStoreFault -Record $outside.Errors[0]
            $outside.Stores.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        It "outside any try, -EnableException ends the command at the record and the script goes on" {
            $outside = Invoke-NativeOutsideTry @{ EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeStoreFault -Record $outside.Errors[0]
            $outside.Stores.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        It "outside any try, -ErrorAction Stop turns the record into the stop PowerShell gives WriteError" {
            $outside = Invoke-NativeOutsideTry @{ ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeStoreFault -Record $outside.Stop.ErrorRecord
            $outside.Stores.Count | Should -Be 0
            $outside.Next | Should -BeFalse
        }

        It "inside a caller's try, the catch receives the record and the command does not go on" {
            $failure = $null
            $after = $false
            $lock = Lock-NativeStore
            try {
                $null = Get-DbaRegServerStore
                $after = $true
            } catch {
                $failure = $PSItem
            } finally {
                $lock.Dispose()
            }
            $failure | Should -Not -BeNullOrEmpty
            Assert-NativeStoreFault -Record $failure
            $failure.CategoryInfo.Activity | Should -BeExactly "Get-DbaRegServerStore"
            $after | Should -BeFalse
        }

        It "under -EnableException and under -ErrorAction Stop inside a caller's try, the catch receives the record" {
            foreach ($splatStop in @(@{ EnableException = $true }, @{ ErrorAction = "Stop" })) {
                $failure = $null
                $after = $false
                $lock = Lock-NativeStore
                try {
                    $null = Get-DbaRegServerStore @splatStop
                    $after = $true
                } catch {
                    $failure = $PSItem
                } finally {
                    $lock.Dispose()
                }
                $failure | Should -Not -BeNullOrEmpty
                Assert-NativeStoreFault -Record $failure
                $after | Should -BeFalse
            }
        }
    }

    Context "Pipeline" {
        It "takes several instances from the pipeline, one store each in order and no local store" -Tag "NativeChecklist:pipeline-multiple" {
            $copyServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
            $results = @($instance, $TestConfig.InstanceCopy1 | Get-DbaRegServerStore -EnableException)
            $results.Count | Should -Be 2
            $results[0].SqlInstance | Should -Be $server.DomainInstanceName
            $results[1].SqlInstance | Should -Be $copyServer.DomainInstanceName
        }
    }

    Context "Failed instances" {
        It "warns of a failed instance and returns the others" -Tag "NativeChecklist:multi-instance-failure" {
            $failedWarnings = @()
            $splatFailed = @{
                SqlInstance     = $badInstance, $instance
                WarningVariable = "failedWarnings"
                WarningAction   = "SilentlyContinue"
                ErrorVariable   = "failedErrors"
                ErrorAction     = "SilentlyContinue"
            }
            $results = @(Get-DbaRegServerStore @splatFailed)
            $results.Count | Should -Be 1
            $results[0].SqlInstance | Should -Be $server.DomainInstanceName
            # One line naming the failed server (harness-edits.md, "Script-scope preferences and the one-line connect warning", point 5).
            @($failedWarnings).Count | Should -Be 1
            "$($failedWarnings[0])" | Should -Match $badLine
            $failedErrors.Count | Should -Be 1
            $failedErrors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaRegServerStore(,|$)"
            $failedErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
        }

        It "throws for a failed instance under -EnableException, before the next instance" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            $collected = $null
            $enableWarnings = $null
            try {
                $null = Get-DbaRegServerStore -SqlInstance $badInstance, $instance -EnableException -OutVariable collected -WarningVariable enableWarnings -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            $caught | Should -Not -BeNullOrEmpty
            @($enableWarnings).Count | Should -Be 1
            "$($enableWarnings[0])" | Should -Match $badLine
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaRegServerStore*"
            "$($caught.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            @($collected).Count | Should -Be 0
        }

        It "only warns under -EnableException:`$false" -Tag "NativeChecklist:switch-false" {
            $results = @(Get-DbaRegServerStore -SqlInstance $badInstance -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
            $results.Count | Should -Be 0
            @($falseWarnings).Count | Should -Be 1
            "$($falseWarnings[0])" | Should -Match $badLine
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
        }

        It "works with -SqlCredential" {
            $results = @(Get-DbaRegServerStore -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException)
            $results.Count | Should -Be 1
            $results[0].SqlInstance | Should -Be $loginServer.DomainInstanceName
            $results[0].DisplayName | Should -Be "Central Management Servers"
            $null = @($results[0].DatabaseEngineServerGroup.ServerGroups).Count
        }

        It "fails cleanly without the credential: a warning and no output" {
            $results = @(Get-DbaRegServerStore -SqlInstance $loginInstance -WarningVariable loginWarnings -WarningAction SilentlyContinue -ErrorVariable loginErrors -ErrorAction SilentlyContinue)
            $results.Count | Should -Be 0
            @($loginWarnings).Count | Should -Be 1
            "$($loginWarnings[0])" | Should -Match ("\[Get-DbaRegServerStore\] Failure \| Error connecting to \[" + [regex]::Escape("$loginInstance") + "\]: Login failed")
            $loginErrors.Count | Should -Be 1
            $loginErrors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaRegServerStore(,|$)"
            $loginErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
        }

        It "throws without the credential under -EnableException, as the pinned function does" {
            { Get-DbaRegServerStore -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue } | Should -Throw -ExpectedMessage "*Login failed*" -ErrorId "dbatools_Get-DbaRegServerStore*"
        }
    }
}

Describe "Native Get-DbaRegServerStore refuses Azure SQL Database" -Tag IntegrationTests {
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

    # Central Management Servers apply to SQL Server only (Microsoft Learn, "Administer multiple servers using Central
    # Management Servers": Applies to SQL Server) and are granted through two roles in msdb (Microsoft Learn, "Create a
    # Central Management Server and server group", Permissions), and Azure SQL Database has no msdb (Microsoft Learn,
    # "msdb database": SQL Server and Azure SQL Managed Instance). The pin's behaviour there is measured by the item's
    # declared red.
    It "refuses Azure SQL Database with a warning and returns nothing" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $splatAzure = @{
            SqlInstance     = $azureServer
            WarningVariable = "azureWarnings"
            WarningAction   = "SilentlyContinue"
            ErrorAction     = "SilentlyContinue"
            ErrorVariable   = "azureErrors"
        }
        @(Get-DbaRegServerStore @splatAzure).Count | Should -Be 0
        ($azureWarnings -join " ") | Should -BeLike "*Failure*Azure SQL Database not supported*"
        $azureErrors.Count | Should -Be 1
        $azureErrors[0].FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaRegServerStore(,|$)"
        $azureErrors[0].CategoryInfo.Category | Should -Be "ConnectionError"
        $azureErrors[0].Exception.Message | Should -BeLike "*Azure SQL Database not supported*"
    }

    It "refuses Azure SQL Database under -EnableException by throwing that refusal" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        { Get-DbaRegServerStore -SqlInstance $azureServer -EnableException -WarningAction SilentlyContinue } | Should -Throw "*Azure SQL Database not supported*"
    }
}
