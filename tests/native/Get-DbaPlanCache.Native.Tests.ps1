#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: whatif-confirm N/A -- the pinned command does not declare SupportsShouldProcess, so it has no -WhatIf or -Confirm.
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaPlanCache",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Get-DbaPlanCache" -Tag IntegrationTests {
    BeforeAll {
        $pcServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $pcTag = [guid]::NewGuid().ToString("N").Substring(0, 10)
        $pcMissing = "nf" + [guid]::NewGuid().ToString("N").Substring(0, 12)
        $pcDisplay = "ComputerName,InstanceName,SqlInstance,Size,UseCount"
        $pcSql = "SELECT SUM(size_in_bytes) AS [bytes] FROM sys.dm_exec_cached_plans;"

        # Independent read: the identity the pinned query reports, on the test's own connection.
        function Get-NativeIdentity {
            param($Server)
            @($Server.Query("SELECT SERVERPROPERTY('MachineName') AS [m], ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS [i], SERVERPROPERTY('ServerName') AS [s];"))[0]
        }

        # The shape of one row: the query's DataRow with a Size note, its values typed as the query types them, Size the
        # [dbasize] of MB in bytes, and the pinned default view.
        function Assert-NativePlanCacheRow {
            param($Row, $Identity)
            $Row.PSObject.BaseObject | Should -BeOfType [System.Data.DataRow]
            foreach ($name in "ComputerName", "InstanceName", "SqlInstance", "MB", "UseCount", "Size") {
                $Row.PSObject.Properties.Name | Should -Contain $name
            }
            ($Row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $pcDisplay
            "$($Row.ComputerName)" | Should -BeExactly "$($Identity.m)"
            "$($Row.InstanceName)" | Should -BeExactly "$($Identity.i)"
            "$($Row.SqlInstance)" | Should -BeExactly "$($Identity.s)"
            $Row.MB | Should -BeOfType [System.Decimal]
            $Row.UseCount | Should -BeOfType [System.Int32]
            $Row.UseCount | Should -BeGreaterOrEqual 0
            $Row.Size | Should -BeOfType [Dataplat.Dbatools.Utility.Size]
            $Row.Size.Byte | Should -Be ([long][System.Math]::Truncate($Row.MB * 1024 * 1024))
            $Row.Size.Byte | Should -BeGreaterOrEqual 0
        }
    }

    It "returns one row of the instance's single-use plan totals, shaped as the pin shapes it" {
        $identity = Get-NativeIdentity $pcServer
        $results = @(Get-DbaPlanCache -SqlInstance $TestConfig.InstanceSingle -ErrorVariable pcErrors -WarningVariable pcWarnings)
        $pcErrors | Should -BeNullOrEmpty
        $pcWarnings | Should -BeNullOrEmpty
        $results.Count | Should -Be 1
        Assert-NativePlanCacheRow -Row $results[0] -Identity $identity
        # The single-use plans are a part of the whole cache, read independently after the command.
        $total = @($pcServer.Query($pcSql))[0].bytes
        $total | Should -BeGreaterThan 0
    }

    It "returns a row for each piped instance and goes on past one that fails" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
        $identity = Get-NativeIdentity $pcServer
        $warnings = @()
        $results = @(@($TestConfig.InstanceSingle, $pcMissing, $TestConfig.InstanceSingle) | Get-DbaPlanCache -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
        $results.Count | Should -Be 2
        foreach ($result in $results) {
            Assert-NativePlanCacheRow -Row $result -Identity $identity
        }
        [object]::ReferenceEquals($results[0].PSObject.BaseObject, $results[1].PSObject.BaseObject) | Should -BeFalse
        $warnings.Count | Should -Be 1
        "$($warnings[0])" | Should -Match ([regex]::Escape("[Get-DbaPlanCache] Failure | Error connecting to [$pcMissing]: "))
    }

    It "reads several named instances" {
        $results = @(Get-DbaPlanCache -SqlInstance $TestConfig.InstanceSingle, $pcServer)
        $results.Count | Should -Be 2
        [object]::ReferenceEquals($results[0].PSObject.BaseObject, $results[1].PSObject.BaseObject) | Should -BeFalse
    }

    It "throws the connection failure under -EnableException" -Tag "NativeChecklist:enable-exception" {
        $caught = $null
        try {
            $null = Get-DbaPlanCache -SqlInstance $pcMissing -EnableException -WarningAction SilentlyContinue
        } catch {
            $caught = $PSItem
        }
        $caught | Should -Not -BeNullOrEmpty
        $caught.CategoryInfo.Category | Should -Be "ConnectionError"
        $caught.Exception.Message | Should -Not -BeNullOrEmpty
    }

    Context "A login without server state permission" {
        BeforeAll {
            # The pin runs $server.Query outside any try. A SQL login with no server permission connects, and the query of
            # sys.dm_exec_cached_plans then faults: it needs VIEW SERVER STATE (VIEW SERVER PERFORMANCE STATE from SQL
            # Server 2022 on), which a new login does not have.
            # https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-objects/sys-dm-exec-cached-plans-transact-sql
            $lowName = "dbatoolsci_pc_${pcTag}_low"
            $lowPassword = "Pc-" + [guid]::NewGuid().ToString("N")
            $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
            $null = $pcServer.Query("CREATE LOGIN [$lowName] WITH PASSWORD = N'$lowPassword', CHECK_POLICY = OFF, DEFAULT_DATABASE = [master];")

            function New-NativeLowServer {
                Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -SqlCredential $lowCred -EnableException
            }

            # Independent read: the record the module's Server.Query script method gives this login for the pinned
            # query's catalog read, called with one argument as the pin calls it.
            $lowReference = $null
            try {
                $null = (New-NativeLowServer).Query($pcSql)
            } catch {
                $lowReference = $PSItem
            }

            # The pin's record for this fault: the method call fault of the Server.Query script method.
            function Assert-NativeQueryFault {
                param($Record)
                $lowReference | Should -Not -BeNullOrEmpty
                ($Record.FullyQualifiedErrorId -split ",")[0] | Should -BeExactly "ScriptMethodRuntimeException"
                ($lowReference.FullyQualifiedErrorId -split ",")[0] | Should -BeExactly "ScriptMethodRuntimeException"
                $Record.Exception | Should -BeOfType [System.Management.Automation.MethodInvocationException]
                $Record.Exception.GetType().FullName | Should -BeExactly $lowReference.Exception.GetType().FullName
                $Record.Exception.Message | Should -BeExactly $lowReference.Exception.Message
                $Record.Exception.Message | Should -BeLike 'Exception calling "Query" with "1" argument(s): *permission*'
                $Record.Exception.InnerException.GetType().FullName | Should -BeExactly $lowReference.Exception.InnerException.GetType().FullName
                $Record.Exception.InnerException.Message | Should -BeExactly $lowReference.Exception.InnerException.Message
                "$($Record.CategoryInfo.Category)" | Should -BeExactly "$($lowReference.CategoryInfo.Category)"
                "$($Record.TargetObject)" | Should -BeExactly ""
            }

            # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own. With
            # -Pipeline the instances are piped in, one pipeline record each; otherwise they are bound by name.
            function Invoke-NativePlanCacheOutsideTry {
                param([hashtable]$Arguments, [object[]]$Pipeline)
                $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $outsideType = (Get-Command Get-DbaPlanCache -CommandType Cmdlet).ImplementingType
                $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaPlanCache", $outsideType, $null
                $outsideState.Commands.Add($outsideEntry)
                $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
                $outsideShell = [System.Management.Automation.PowerShell]::Create()
                $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                $outsideStop = $null
                try {
                    $outsideRunspace.Open()
                    $outsideShell.Runspace = $outsideRunspace
                    $null = $outsideShell.AddScript('param($Arguments, $Pipeline) if ($Pipeline) { $Pipeline | Get-DbaPlanCache @Arguments } else { Get-DbaPlanCache @Arguments }; "next statement"').AddArgument($Arguments).AddArgument($Pipeline)
                    try {
                        $null = $outsideShell.Invoke($null, $outsideOutput)
                    } catch {
                        $outsideStop = $PSItem.Exception.InnerException
                    }
                    [pscustomobject]@{
                        Output   = @($outsideOutput)
                        Rows     = @($outsideOutput | Where-Object { $PSItem -isnot [string] })
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
            foreach ($row in @($pcServer.Query("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$lowName';"))) {
                $null = $pcServer.Query("KILL $($row.session_id);")
            }
            $null = $pcServer.Query("IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];")
        }

        It "writes each instance's query fault and goes on, outside any try" {
            $outside = Invoke-NativePlanCacheOutsideTry -Arguments @{ SqlInstance = @((New-NativeLowServer), (New-NativeLowServer)) }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Warnings.Count | Should -Be 0
            $outside.Errors.Count | Should -Be 2
            foreach ($record in $outside.Errors) {
                Assert-NativeQueryFault -Record $record
            }
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "goes on to the next instance's row after a query fault" {
            $identity = Get-NativeIdentity $pcServer
            $outside = Invoke-NativePlanCacheOutsideTry -Arguments @{ SqlInstance = @((New-NativeLowServer), $pcServer) }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeQueryFault -Record $outside.Errors[0]
            $outside.Rows.Count | Should -Be 1
            Assert-NativePlanCacheRow -Row $outside.Rows[0] -Identity $identity
            @($outside.Output)[-1] | Should -BeExactly "next statement"
        }

        It "does not repeat the previous instance's row when a later instance's query fails" {
            $outside = Invoke-NativePlanCacheOutsideTry -Arguments @{ SqlInstance = @($pcServer, (New-NativeLowServer)) }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeQueryFault -Record $outside.Errors[0]
            $outside.Rows.Count | Should -Be 1
            @($outside.Output)[-1] | Should -BeExactly "next statement"
        }

        It "does not repeat the previous pipeline record's row when the next record's query fails" {
            $outside = Invoke-NativePlanCacheOutsideTry -Arguments @{ } -Pipeline @($pcServer, (New-NativeLowServer))
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeQueryFault -Record $outside.Errors[0]
            $outside.Rows.Count | Should -Be 1
            @($outside.Output)[-1] | Should -BeExactly "next statement"
        }

        It "stops at the first query fault under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativePlanCacheOutsideTry -Arguments @{ SqlInstance = @((New-NativeLowServer), (New-NativeLowServer)); EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeQueryFault -Record $outside.Errors[0]
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "lets a caller's try catch the first query fault" {
            $first = New-NativeLowServer
            $second = New-NativeLowServer
            $callerOutput = @(try { Get-DbaPlanCache -SqlInstance $first, $second; "after" } catch { $_ })
            $callerOutput.Count | Should -Be 1
            $callerOutput[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
            Assert-NativeQueryFault -Record $callerOutput[0]
        }

        It "stops at the first query fault under -ErrorAction Stop, outside a try" {
            $outside = Invoke-NativePlanCacheOutsideTry -Arguments @{ SqlInstance = @((New-NativeLowServer), (New-NativeLowServer)); ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeQueryFault -Record $outside.Stop.ErrorRecord
            $outside.Output.Count | Should -Be 0
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            # Every leg shares this instance at once, so this context creates nothing: it reads the instance's totals.
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
        }

        It "works with -SqlCredential" {
            $identity = Get-NativeIdentity $loginServer
            $result = @(Get-DbaPlanCache -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException -ErrorVariable loginErrors)
            $loginErrors | Should -BeNullOrEmpty
            $result.Count | Should -Be 1
            Assert-NativePlanCacheRow -Row $result[0] -Identity $identity
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = @()
            $result = Get-DbaPlanCache -SqlInstance $loginInstance -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warnings | Should -Not -BeNullOrEmpty
            "$($warnings[0])" | Should -Match ([regex]::Escape("[Get-DbaPlanCache] Failure | Error connecting to ["))
        }

        It "throws without the credential under -EnableException, as the pinned Stop-Function does" {
            { Get-DbaPlanCache -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue } | Should -Throw
        }
    }

    Context "Azure SQL Database" -Tag NativeChecklist:azure-sqldb {
        BeforeAll {
            # sys.dm_exec_cached_plans applies to Azure SQL Database, where it lists the connected tenant's plans.
            # https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-objects/sys-dm-exec-cached-plans-transact-sql
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

        It "returns the single-use plan totals of the Azure SQL Database" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $identity = Get-NativeIdentity $azure
            $azureWarnings = @()
            $rows = @(Get-DbaPlanCache -SqlInstance $azure -WarningAction SilentlyContinue -WarningVariable azureWarnings -ErrorVariable azureErrors -ErrorAction SilentlyContinue)
            $azureErrors | Should -BeNullOrEmpty
            $azureWarnings | Should -BeNullOrEmpty
            $rows.Count | Should -Be 1
            Assert-NativePlanCacheRow -Row $rows[0] -Identity $identity
        }

        It "reads Azure SQL Database under -EnableException and goes on to the next instance" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $rows = @(Get-DbaPlanCache -SqlInstance $azure, $pcServer -EnableException)
            $rows.Count | Should -Be 2
            "$($rows[1].SqlInstance)" | Should -BeExactly "$((Get-NativeIdentity $pcServer).s)"
        }
    }
}
