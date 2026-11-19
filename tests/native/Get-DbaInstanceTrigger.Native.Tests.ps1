#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: whatif-confirm N/A -- the pinned command does not declare SupportsShouldProcess, so it has no -WhatIf or -Confirm.
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaInstanceTrigger",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Get-DbaInstanceTrigger" -Tag IntegrationTests {
    BeforeAll {
        $trgServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $trgTag = [guid]::NewGuid().ToString("N").Substring(0, 10)
        $trgOn = "dbatoolsci_itr_${trgTag}_on"
        $trgOff = "dbatoolsci_itr_${trgTag}_off"
        $trgMissing = "nf" + [guid]::NewGuid().ToString("N").Substring(0, 12)

        # Server-level DDL from the other PowerShell edition's lane on the same instance can make this setup a deadlock
        # victim (error 1205), so the setup and cleanup statements, never the command under test, are retried a fixed
        # number of times when they are.
        function Invoke-NativeTriggerSql {
            param($Server, [string]$Sql)
            for ($attempt = 1; $attempt -le 5; $attempt++) {
                try {
                    return $Server.Query($Sql)
                } catch {
                    $sqlError = $PSItem.Exception
                    $isDeadlock = $false
                    while ($sqlError) {
                        if ($sqlError.Number -eq 1205 -or $sqlError.Message -match "deadlocked") { $isDeadlock = $true }
                        $sqlError = $sqlError.InnerException
                    }
                    if (-not $isDeadlock -or $attempt -eq 5) { throw }
                    Start-Sleep -Seconds 2
                }
            }
        }

        # Two server-level DDL triggers that only print; one is disabled.
        $null = Invoke-NativeTriggerSql $trgServer "CREATE TRIGGER [$trgOn] ON ALL SERVER FOR CREATE_DATABASE AS PRINT 'dbatoolsci';"
        $null = Invoke-NativeTriggerSql $trgServer "CREATE TRIGGER [$trgOff] ON ALL SERVER FOR CREATE_DATABASE AS PRINT 'dbatoolsci';"
        $null = Invoke-NativeTriggerSql $trgServer "DISABLE TRIGGER [$trgOff] ON ALL SERVER;"

        # Independent read: the catalog view, on the test's own connection.
        $catalogSql = "SELECT name, object_id, is_disabled, create_date, modify_date FROM sys.server_triggers"
        function Get-NativeTriggerCatalog {
            @(Invoke-NativeTriggerSql $trgServer $catalogSql)
        }
    }

    AfterAll {
        foreach ($name in $trgOn, $trgOff) {
            $null = Invoke-NativeTriggerSql $trgServer "IF EXISTS (SELECT 1 FROM sys.server_triggers WHERE name = N'$name') DROP TRIGGER [$name] ON ALL SERVER;"
        }
    }

    It "returns every server trigger the catalog lists, decorated as the pin decorates them" {
        # The other PowerShell edition's lane may add or drop its own triggers on this instance meanwhile, so the catalog is
        # read before and after: every name in both reads comes back, and nothing outside them does.
        $catalog = Get-NativeTriggerCatalog
        @($catalog | Where-Object name -in $trgOn, $trgOff).Count | Should -Be 2
        $results = @(Get-DbaInstanceTrigger -SqlInstance $TestConfig.InstanceSingle -ErrorVariable trgErrors)
        $catalogAfter = Get-NativeTriggerCatalog
        $trgErrors | Should -BeNullOrEmpty
        @($catalog.name | Where-Object { $PSItem -in $catalogAfter.name -and $PSItem -notin $results.Name }) | Should -BeNullOrEmpty
        @($results.Name | Where-Object { $PSItem -notin $catalog.name -and $PSItem -notin $catalogAfter.name }) | Should -BeNullOrEmpty
        @($results.Name | Select-Object -Unique).Count | Should -Be $results.Count

        foreach ($result in $results) {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.ServerDdlTrigger]
            $result.ComputerName | Should -BeExactly $trgServer.ComputerName
            $result.InstanceName | Should -BeExactly $trgServer.ServiceName
            $result.SqlInstance | Should -BeExactly $trgServer.DomainInstanceName
            $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join "," | Should -BeExactly "ComputerName,InstanceName,SqlInstance,ID,Name,AnsiNullsStatus,AssemblyName,BodyStartIndex,ClassName,CreateDate,DateLastModified,DdlTriggerEvents,ExecutionContext,ExecutionContextLogin,ImplementationType,IsDesignMode,IsEnabled,IsEncrypted,IsSystemObject,MethodName,QuotedIdentifierStatus,State,TextHeader,TextMode"
        }

        # The catalog values are compared on this test's own triggers, which nothing else changes meanwhile.
        foreach ($result in @($results | Where-Object Name -in $trgOn, $trgOff)) {
            $row = $catalog | Where-Object name -eq $result.Name
            $result.ID | Should -Be $row.object_id
            $result.IsEnabled | Should -Be (-not [bool]$row.is_disabled)
            $result.CreateDate | Should -Be $row.create_date
            $result.DateLastModified | Should -Be $row.modify_date
        }

        ($results | Where-Object Name -eq $trgOn).IsEnabled | Should -BeTrue
        ($results | Where-Object Name -eq $trgOff).IsEnabled | Should -BeFalse
    }

    It "replaces its notes when the same server's object comes back" {
        $first = Get-DbaInstanceTrigger -SqlInstance $trgServer | Where-Object Name -eq $trgOn
        $second = Get-DbaInstanceTrigger -SqlInstance $trgServer | Where-Object Name -eq $trgOn
        $second.SqlInstance | Should -BeExactly $first.SqlInstance
        @($second.PSObject.Properties | Where-Object Name -eq "SqlInstance").Count | Should -Be 1
        @($second.PSObject.Properties | Where-Object Name -eq "ComputerName").Count | Should -Be 1
        @($second.PSObject.Properties | Where-Object Name -eq "InstanceName").Count | Should -Be 1
    }

    It "returns the triggers of each piped instance and goes on past one that fails" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
        $warnings = @()
        $results = @(@($TestConfig.InstanceSingle, $trgMissing, $TestConfig.InstanceSingle) | Get-DbaInstanceTrigger -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
        @($results | Where-Object Name -eq $trgOn).Count | Should -Be 2
        @($results | Where-Object Name -eq $trgOff).Count | Should -Be 2
        $warnings.Count | Should -Be 1
        "$($warnings[0])" | Should -Match ([regex]::Escape("[Get-DbaInstanceTrigger] Failure | Error connecting to [$trgMissing]: "))
    }

    It "reads several named instances" {
        $results = @(Get-DbaInstanceTrigger -SqlInstance $TestConfig.InstanceSingle, $TestConfig.InstanceSingle)
        @($results | Where-Object Name -eq $trgOn).Count | Should -Be 2
    }

    It "throws the connection failure under -EnableException" -Tag "NativeChecklist:enable-exception" {
        $caught = $null
        try {
            $null = Get-DbaInstanceTrigger -SqlInstance $trgMissing -EnableException -WarningAction SilentlyContinue
        } catch {
            $caught = $PSItem
        }
        $caught | Should -Not -BeNullOrEmpty
        $caught.CategoryInfo.Category | Should -Be "ConnectionError"
    }

    Context "A login denied the server trigger catalog" {
        BeforeAll {
            # The pin reads $server.Triggers outside any try. A SQL login whose master user is denied SELECT on
            # sys.server_triggers connects (Connect-DbaInstance's own SELECT succeeds), and the read then faults. sysadmin
            # ignores DENY, so the login has no server role.
            $denyName = "dbatoolsci_itr_${trgTag}_deny"
            $denyPassword = "Itr-" + [guid]::NewGuid().ToString("N")
            $denyCred = New-Object System.Management.Automation.PSCredential -ArgumentList $denyName, (ConvertTo-SecureString -String $denyPassword -AsPlainText -Force)
            $null = $trgServer.Query("CREATE LOGIN [$denyName] WITH PASSWORD = N'$denyPassword', CHECK_POLICY = OFF, DEFAULT_DATABASE = [master];")
            $null = $trgServer.Query("USE [master]; CREATE USER [$denyName] FOR LOGIN [$denyName]; DENY SELECT ON OBJECT::sys.server_triggers TO [$denyName];")

            function New-NativeDeniedServer {
                Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -SqlCredential $denyCred -EnableException
            }

            # The pin's record for this fault: the engine's foreach over a collection whose GetEnumerator throws.
            function Assert-NativeTriggerReadFault {
                param($Record)
                ($Record.FullyQualifiedErrorId -split ",")[0] | Should -BeExactly "ExceptionInGetEnumerator"
                $Record.Exception | Should -BeOfType [System.Management.Automation.ExtendedTypeSystemException]
                $Record.Exception.InnerException | Should -BeOfType [Microsoft.SqlServer.Management.Common.ExecutionFailureException]
                $Record.Exception.Message | Should -BeExactly ('The following exception occurred while trying to enumerate the collection: "{0}".' -f $Record.Exception.InnerException.Message)
                $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::NotSpecified)
                "$($Record.TargetObject)" | Should -BeExactly ""
            }

            # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
            function Invoke-NativeTriggerOutsideTry {
                param([hashtable]$Arguments)
                $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $outsideType = (Get-Command Get-DbaInstanceTrigger -CommandType Cmdlet).ImplementingType
                $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaInstanceTrigger", $outsideType, $null
                $outsideState.Commands.Add($outsideEntry)
                $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
                $outsideShell = [System.Management.Automation.PowerShell]::Create()
                $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                $outsideStop = $null
                try {
                    $outsideRunspace.Open()
                    $outsideShell.Runspace = $outsideRunspace
                    $null = $outsideShell.AddScript('param($Arguments) Get-DbaInstanceTrigger @Arguments; "next statement"').AddArgument($Arguments)
                    try {
                        $null = $outsideShell.Invoke($null, $outsideOutput)
                    } catch {
                        $outsideStop = $PSItem.Exception.InnerException
                    }
                    [pscustomobject]@{
                        Output   = @($outsideOutput)
                        Errors   = @($outsideShell.Streams.Error)
                        Warnings = @($outsideShell.Streams.Warning)
                        Stop     = $outsideStop
                    }
                } finally {
                    $outsideShell.Dispose()
                    $outsideRunspace.Dispose()
                }
            }
        }

        AfterAll {
            foreach ($row in @($trgServer.Query("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$denyName';"))) {
                $null = $trgServer.Query("KILL $($row.session_id);")
            }
            $null = $trgServer.Query("USE [master]; IF USER_ID(N'$denyName') IS NOT NULL DROP USER [$denyName];")
            $null = $trgServer.Query("IF SUSER_ID(N'$denyName') IS NOT NULL DROP LOGIN [$denyName];")
        }

        It "writes each instance's read fault and goes on, outside any try" {
            $outside = Invoke-NativeTriggerOutsideTry @{ SqlInstance = @((New-NativeDeniedServer), (New-NativeDeniedServer)) }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Warnings.Count | Should -Be 0
            $outside.Errors.Count | Should -Be 2
            foreach ($record in $outside.Errors) {
                Assert-NativeTriggerReadFault -Record $record
            }
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "goes on to the next instance's triggers after a read fault" {
            $outside = Invoke-NativeTriggerOutsideTry @{ SqlInstance = @((New-NativeDeniedServer), $trgServer) }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeTriggerReadFault -Record $outside.Errors[0]
            @($outside.Output | Where-Object { $PSItem.Name -eq $trgOn }).Count | Should -Be 1
            @($outside.Output)[-1] | Should -BeExactly "next statement"
        }

        It "stops at the first read fault under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeTriggerOutsideTry @{ SqlInstance = @((New-NativeDeniedServer), (New-NativeDeniedServer)); EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeTriggerReadFault -Record $outside.Errors[0]
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "lets a caller's try catch the first read fault" {
            $first = New-NativeDeniedServer
            $second = New-NativeDeniedServer
            $callerOutput = @(try { Get-DbaInstanceTrigger -SqlInstance $first, $second; "after" } catch { $_ })
            $callerOutput.Count | Should -Be 1
            $callerOutput[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
            Assert-NativeTriggerReadFault -Record $callerOutput[0]
        }

        It "stops at the first read fault under -ErrorAction Stop, outside a try" {
            $outside = Invoke-NativeTriggerOutsideTry @{ SqlInstance = @((New-NativeDeniedServer), (New-NativeDeniedServer)); ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeTriggerReadFault -Record $outside.Stop.ErrorRecord
            $outside.Output.Count | Should -Be 0
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            # Every leg shares this instance at once, and server-level DDL from parallel legs deadlocks there (error 1205), so
            # this context creates nothing: it reads the instance's triggers as they are and compares them with the
            # catalog, read on the test's own SQL-login connection before and after the call.
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
        }

        It "works with -SqlCredential" {
            $loginCatalog = @($loginServer.Query("SELECT name FROM sys.server_triggers").name)
            $result = @(Get-DbaInstanceTrigger -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException -ErrorVariable loginErrors)
            $loginCatalogAfter = @($loginServer.Query("SELECT name FROM sys.server_triggers").name)
            $loginErrors | Should -BeNullOrEmpty
            @($loginCatalog | Where-Object { $PSItem -in $loginCatalogAfter -and $PSItem -notin $result.Name }) | Should -BeNullOrEmpty
            @($result.Name | Where-Object { $PSItem -notin $loginCatalog -and $PSItem -notin $loginCatalogAfter }) | Should -BeNullOrEmpty
            foreach ($row in $result) {
                $row | Should -BeOfType [Microsoft.SqlServer.Management.Smo.ServerDdlTrigger]
                $row.SqlInstance | Should -BeExactly $loginServer.DomainInstanceName
            }
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = @()
            $result = Get-DbaInstanceTrigger -SqlInstance $loginInstance -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warnings | Should -Not -BeNullOrEmpty
        }

        It "throws without the credential under -EnableException, as the pinned Stop-Function does" {
            { Get-DbaInstanceTrigger -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue } | Should -Throw
        }
    }

    Context "Azure SQL Database" -Tag NativeChecklist:azure-sqldb {
        BeforeAll {
            # Server-level DDL triggers do not exist in Azure SQL Database: sys.server_triggers applies to SQL Server and
            # Azure SQL Managed Instance only, and ON ALL SERVER triggers are not supported there.
            # https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-server-triggers-transact-sql
            # https://learn.microsoft.com/data-migration/sql-server/database/assessment-rules#server-scoped-triggers
            # Fleet.md step 4 (operator, 2026-10-28): a command Azure SQL Database cannot support refuses it as
            # Connect-DbaInstance -AzureUnsupported does (correction azure-refusal).
            $azure = $null
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
                    break
                } catch {
                    $azureError = $PSItem.Exception
                    $isResuming = $false
                    while ($azureError) {
                        if ($azureError.Number -in 40613, -2 -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                        $azureError = $azureError.InnerException
                    }
                    if (-not $isResuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
        }

        AfterAll {
            if ($azure) { $azure.ConnectionContext.Disconnect() }
        }

        It "refuses Azure SQL Database, which has no server triggers, and goes on to the next instance" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $azureWarnings = @()
            $rows = @(Get-DbaInstanceTrigger -SqlInstance $azure, $TestConfig.InstanceSingle -EnableException:$false -WarningAction SilentlyContinue -WarningVariable azureWarnings)
            $azureWarnings.Count | Should -Be 1
            "$($azureWarnings[0])" | Should -Match ([regex]::Escape("[Get-DbaInstanceTrigger] Failure | ") + ".*" + [regex]::Escape("Azure SQL Database not supported"))
            @($rows | Where-Object SqlInstance -ne $trgServer.DomainInstanceName).Count | Should -Be 0
            @($rows | Where-Object Name -eq $trgOn).Count | Should -Be 1
        }

        It "throws the Azure SQL Database refusal under -EnableException" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $azureCaught = $null
            try {
                $null = Get-DbaInstanceTrigger -SqlInstance $azure -EnableException -WarningAction SilentlyContinue
            } catch {
                $azureCaught = $PSItem
            }
            $azureCaught | Should -Not -BeNullOrEmpty
            "$($azureCaught.Exception.Message)" | Should -Match ([regex]::Escape("Azure SQL Database not supported"))
            $azureCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}
