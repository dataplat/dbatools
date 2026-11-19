#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaErrorLogConfig",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads the configuration.

# What these assert was measured on the pin, on both editions: evidence/pin-errorlogconfig-20261104.txt.
Describe "Native Get-DbaErrorLogConfig" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $server = Connect-DbaInstance -SqlInstance $instance -EnableException
        $badInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $propertyNames = "ComputerName,InstanceName,SqlInstance,LogCount,LogSize,LogPath"

        # The independent read of the path, from the server's own property; the count and the size are read from SMO on this test's connection.
        $errorLogFile = "$($server.ConnectionContext.ExecuteScalar("SELECT CAST(SERVERPROPERTY('ErrorLogFileName') AS nvarchar(4000));"))"
        $expectedPath = [System.IO.Path]::GetDirectoryName($errorLogFile)
        $expectedCount = $server.NumberOfLogFiles
        $expectedBytes = [long]$server.ErrorLogSizeKb * 1024

        # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
        function Invoke-NativeOutsideTry {
            param([hashtable]$Arguments, [string]$Script = 'param($Arguments) Get-DbaErrorLogConfig @Arguments; "next statement"')
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaErrorLogConfig -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaErrorLogConfig", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                $null = $outsideShell.AddScript($Script).AddArgument($Arguments)
                $outsideOutput = @($outsideShell.Invoke())
                [pscustomobject]@{
                    Output = $outsideOutput
                    Errors = @($outsideShell.Streams.Error)
                }
            } finally {
                $outsideShell.Dispose()
                $outsideRunspace.Dispose()
            }
        }
    }

    Context "Output" {
        It "returns one custom object with the pin's properties, in order, and no default view" {
            $result = @(Get-DbaErrorLogConfig -SqlInstance $instance -EnableException)
            $result.Count | Should -Be 1
            $result[0].GetType().FullName | Should -BeExactly "System.Management.Automation.PSCustomObject"
            $result[0].PSObject.TypeNames[0] | Should -BeExactly "System.Management.Automation.PSCustomObject"
            (@($result[0].PSObject.Properties).Name -join ",") | Should -BeExactly $propertyNames
            @($result[0].PSObject.Properties | Where-Object MemberType -ne "NoteProperty").Count | Should -Be 0
            $result[0].PSStandardMembers.DefaultDisplayPropertySet | Should -BeNullOrEmpty
        }

        It "reads the instance's names, and the values an independent read gives" {
            $result = Get-DbaErrorLogConfig -SqlInstance $instance -EnableException
            $result.ComputerName | Should -Be $server.ComputerName
            $result.InstanceName | Should -Be $server.ServiceName
            $result.SqlInstance | Should -Be $server.DomainInstanceName
            $result.LogCount | Should -BeOfType [int]
            $result.LogCount | Should -Be $expectedCount
            $result.LogPath | Should -BeOfType [string]
            $result.LogPath | Should -Be $expectedPath
            $result.LogSize.GetType().FullName | Should -BeExactly "Dataplat.Dbatools.Utility.Size"
            $result.LogSize.Byte | Should -Be $expectedBytes
        }
    }

    Context "Instances" {
        It "reads several instances, named or piped" -Tag "NativeChecklist:pipeline-multiple" {
            @(Get-DbaErrorLogConfig -SqlInstance $instance, $instance -EnableException).Count | Should -Be 2
            @($instance, $instance | Get-DbaErrorLogConfig -EnableException).Count | Should -Be 2
            @($server | Get-DbaErrorLogConfig -EnableException).Count | Should -Be 1
        }

        It "refuses a null instance at binding, and the script goes on" {
            $outside = Invoke-NativeOutsideTry -Arguments @{ } -Script 'param($Arguments) $null | Get-DbaErrorLogConfig @Arguments; "next statement"'
            $outside.Errors.Count | Should -Be 1
            $outside.Errors[0].FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "refuses a null element among the named instances at binding" {
            $failure = $null
            try {
                $null = Get-DbaErrorLogConfig -SqlInstance @($null, $instance)
            } catch {
                $failure = $PSItem
            }
            $failure.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
        }

        It "warns of a failed instance among good ones and reads the others" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
            $warnings = @()
            $result = @(Get-DbaErrorLogConfig -SqlInstance $instance, $badInstance, $instance -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            $result.Count | Should -Be 2
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaErrorLogConfig\] Failure"
        }

        It "throws the failed connection under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $failure = $null
            try {
                $null = Get-DbaErrorLogConfig -SqlInstance $badInstance -EnableException -WarningAction SilentlyContinue
            } catch {
                $failure = $PSItem
            }
            $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaErrorLogConfig*"
            "$($failure.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            "$($failure.TargetObject)" | Should -BeExactly "TCP:127.0.0.1,1"
        }
    }
}

Describe "Native Get-DbaErrorLogConfig over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            # sqlwhale22 is shared: the login is unique per leg and run.
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            $lowName = "dbatoolsci_nelcl_$(Get-Random)"
            $lowPassword = "Nelc-$([guid]::NewGuid().ToString('N'))"
            $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
            $null = $loginServer.Query("CREATE LOGIN [$lowName] WITH PASSWORD = N'$lowPassword', CHECK_POLICY = OFF;")
        }

        AfterAll {
            [Microsoft.Data.SqlClient.SqlConnection]::ClearAllPools()
            # Each KILL has its own TRY: a session may end between the SELECT and its KILL.
            $null = $loginServer.Query("DECLARE @kill nvarchar(max) = N''; SELECT @kill += N'BEGIN TRY KILL ' + CAST(session_id AS nvarchar(10)) + N'; END TRY BEGIN CATCH END CATCH; ' FROM sys.dm_exec_sessions WHERE login_name = N'$lowName'; EXEC sys.sp_executesql @kill;")
            $null = $loginServer.Query("IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];")
        }

        It "works with -SqlCredential" {
            $result = @(Get-DbaErrorLogConfig -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException)
            $result.Count | Should -Be 1
            $result[0].SqlInstance | Should -Be $loginServer.DomainInstanceName
            $result[0].LogPath | Should -Be $loginServer.ErrorLogPath
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = @()
            @(Get-DbaErrorLogConfig -SqlInstance $loginInstance -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaErrorLogConfig\] Failure .*Login failed"
        }

        It "throws without the credential under -EnableException, as the pinned function does" -Tag "NativeChecklist:enable-exception" {
            $failure = $null
            try {
                $null = Get-DbaErrorLogConfig -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue
            } catch {
                $failure = $PSItem
            }
            $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaErrorLogConfig*"
            "$($failure.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
        }

        It "reads the same values for a login with no rights, with no error" {
            $lowErrors = @()
            $warnings = @()
            $result = @(Get-DbaErrorLogConfig -SqlInstance $loginInstance -SqlCredential $lowCred -ErrorVariable lowErrors -WarningAction SilentlyContinue -WarningVariable warnings)
            $lowErrors.Count | Should -Be 0
            $warnings.Count | Should -Be 0
            $result.Count | Should -Be 1
            $result[0].LogCount | Should -Be $loginServer.NumberOfLogFiles
            $result[0].LogSize.Byte | Should -Be ([long]$loginServer.ErrorLogSizeKb * 1024)
            $result[0].LogPath | Should -Be $loginServer.ErrorLogPath
        }
    }

    # As measured on the pin, both editions (evidence/lost-connection-pin-<edition>-20261104.txt, probe probes/lost-connection-20261104.ps1): a server object
    # passed in whose connection is lost before the call fails at the connect step's test query, so the command writes the failed-connect record and goes on.
    # The three reads follow the connect at once, so no break reaches them alone. The port's connect step runs the same test query.
    Context "A server object passed in whose connection is lost" {
        BeforeAll {
            # sqlwhale22 is shared: the login is unique per leg and run.
            $lostInstance = $TestConfig.InstanceSqlLogin
            $lostFixture = Connect-DbaInstance -SqlInstance $lostInstance -SqlCredential $TestConfig.SqlLoginCred -NonPooledConnection -EnableException
            $lostName = "dbatoolsci_nelcb_$(Get-Random)"
            $lostPassword = "Nelcb-$([guid]::NewGuid().ToString('N'))"
            $lostCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lostName, (ConvertTo-SecureString -String $lostPassword -AsPlainText -Force)
            $lostCallers = New-Object System.Collections.ArrayList
            # Each KILL has its own TRY: a session may end between the read and its KILL. The closing wait lets the killed connections' resets reach the
            # caller before its next call, so SqlClient sees the break before it sends, as in the probe; without it a reset seen only on the read
            # skipped the recovery (result 20261105T0053481967538Z, 2017 on 5.1).
            $endSessionsSql = "DECLARE @session int, @kill nvarchar(40); DECLARE sessions CURSOR LOCAL FAST_FORWARD FOR SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$lostName'; OPEN sessions; FETCH NEXT FROM sessions INTO @session; WHILE @@FETCH_STATUS = 0 BEGIN SET @kill = N'KILL ' + CAST(@session AS nvarchar(10)); BEGIN TRY EXEC sys.sp_executesql @kill; END TRY BEGIN CATCH END CATCH; FETCH NEXT FROM sessions INTO @session; END; CLOSE sessions; DEALLOCATE sessions; WAITFOR DELAY '00:00:02';"
            # The login can no longer connect and its sessions end, so SqlClient cannot log in again.
            $disableSql = "USE [master]; ALTER LOGIN [$lostName] DISABLE; $endSessionsSql"
            # The sessions end and the login may come back: SqlClient logs in again and nothing fails.
            $endOnlySql = "USE [master]; $endSessionsSql"

            # Fixture statements only, never the command's calls or asserts: a statement chosen as a deadlock victim (1205) runs again, five tries at most.
            function Invoke-NativeLostStatement {
                param([string]$Statement)
                $try = 0
                while ($true) {
                    $try++
                    try {
                        return $lostFixture.ConnectionContext.ExecuteNonQuery($Statement)
                    } catch {
                        $victim = $false
                        for ($cause = $PSItem.Exception; $null -ne $cause; $cause = $cause.InnerException) {
                            if ($cause -is [Microsoft.Data.SqlClient.SqlException] -and $cause.Number -eq 1205) { $victim = $true }
                        }
                        if (-not $victim -or $try -ge 5) { throw }
                        Start-Sleep -Seconds 2
                    }
                }
            }

            function New-NativeLostCaller {
                $null = Invoke-NativeLostStatement "USE [master]; ALTER LOGIN [$lostName] ENABLE;"
                [Microsoft.Data.SqlClient.SqlConnection]::ClearAllPools()
                $caller = Connect-DbaInstance -SqlInstance $lostInstance -SqlCredential $lostCred -NonPooledConnection -EnableException
                $null = $lostCallers.Add($caller)
                return $caller
            }

            # A Pester It runs its body inside a try, so these calls run in a runspace of their own, with the module, where nothing is inside a try
            # unless the script says so. Output lines, the warning stream and the command's records in the runspace's $Error come back.
            $lostState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $lostRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($lostState)
            $lostRunspace.Open()
            $lostModulePath = (Get-Module dbatools | Where-Object ModuleType -eq Script | Select-Object -First 1).Path
            $lostLoader = [System.Management.Automation.PowerShell]::Create()
            $lostLoader.Runspace = $lostRunspace
            $null = $lostLoader.AddCommand("Import-Module").AddParameter("Name", $lostModulePath).AddParameter("ErrorAction", "Stop").Invoke()
            $lostLoader.Dispose()

            function Invoke-NativeLostCall {
                param([string]$Script, $Values)
                $lostShell = [System.Management.Automation.PowerShell]::Create()
                try {
                    $lostShell.Runspace = $lostRunspace
                    $null = $lostShell.AddScript('$Error.Clear()').AddStatement()
                    $null = $lostShell.AddScript($Script).AddArgument($Values)
                    $lostLines = @($lostShell.Invoke() | ForEach-Object { "$PSItem" })
                    $null = $lostShell.Commands.Clear()
                    $null = $lostShell.AddScript('@($Error | Where-Object { $PSItem -is [System.Management.Automation.ErrorRecord] -and "$($PSItem.FullyQualifiedErrorId)" -like "dbatools_Get-DbaErrorLogConfig*" })')
                    $lostRecords = @($lostShell.Invoke() | ForEach-Object { $PSItem.psobject.BaseObject })
                    [pscustomobject]@{
                        Lines    = $lostLines
                        Warnings = @($lostShell.Streams.Warning | ForEach-Object { $PSItem.Message })
                        Records  = $lostRecords
                    }
                } finally {
                    $lostShell.Dispose()
                }
            }

            # What the pin writes for each such call: one record of the command, the connect step's failure with the server as its target.
            function Assert-NativeLostRecord {
                param($Call)
                $Call.Records.Count | Should -Be 1
                $record = $Call.Records[0]
                $record.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaErrorLogConfig*"
                "$($record.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
                "$($record.TargetObject)" | Should -BeExactly "$lostInstance"
                # The record carries the deepest message of the failure, as the pin's does: the failed login of SqlClient's recovery, as measured, or,
                # when the reset is seen only on the read and there is no recovery, the transport's reset (10054) under a SqlException. Both are the
                # lost connection the pin reports the same way.
                $chain = @()
                for ($cause = $record.Exception; $null -ne $cause; $cause = $cause.InnerException) { $chain += $cause }
                $deepest = $chain[-1]
                if ($deepest -is [System.ComponentModel.Win32Exception]) {
                    $deepest.NativeErrorCode | Should -Be 10054
                    @($chain | Where-Object { $PSItem -is [Microsoft.Data.SqlClient.SqlException] }).Count | Should -BeGreaterThan 0
                } else {
                    $deepest | Should -BeOfType Microsoft.Data.SqlClient.SqlException
                }
                $record.Exception.Message | Should -BeExactly $deepest.Message
                # One warning line naming the server (harness-edits.md, "Script-scope preferences and one connect warning line").
                $Call.Warnings.Count | Should -Be 1
                $Call.Warnings[0].EndsWith("[Get-DbaErrorLogConfig] Failure | Error connecting to [$lostInstance]: $($deepest.Message)", [System.StringComparison]::Ordinal) | Should -BeTrue -Because $Call.Warnings[0]
            }

            $lostScript = 'param($Values) $Arguments = $Values.Arguments; $null = $Values.Fixture.ConnectionContext.ExecuteNonQuery($Values.Sql); Get-DbaErrorLogConfig @Arguments |ForEach-Object { "row: " + $PSItem.SqlInstance }; "next statement"'

            $null = Invoke-NativeLostStatement "USE [master]; CREATE LOGIN [$lostName] WITH PASSWORD = N'$lostPassword', CHECK_POLICY = OFF;"
        }

        AfterAll {
            foreach ($caller in $lostCallers) {
                try {
                    $caller.ConnectionContext.Disconnect()
                } catch {
                    # A lost connection may refuse its disconnect; the KILL below ends what is left.
                    $null = $PSItem
                }
            }
            $lostRunspace.Dispose()
            [Microsoft.Data.SqlClient.SqlConnection]::ClearAllPools()
            $null = Invoke-NativeLostStatement $endOnlySql
            $null = Invoke-NativeLostStatement "USE [master]; IF SUSER_ID(N'$lostName') IS NOT NULL DROP LOGIN [$lostName];"
            $lostFixture.ConnectionContext.Disconnect()
        }

        It "writes the failed-connect record and no row, and the script goes on" {
            $call = Invoke-NativeLostCall -Script $lostScript -Values @{ Fixture = $lostFixture; Sql = $disableSql; Arguments = @{ SqlInstance = (New-NativeLostCaller) } }
            Assert-NativeLostRecord -Call $call
            ($call.Lines -join ",") | Should -BeExactly "next statement"
        }

        It "goes on under -ErrorAction Stop, as the pin does" {
            $call = Invoke-NativeLostCall -Script $lostScript -Values @{ Fixture = $lostFixture; Sql = $disableSql; Arguments = @{ SqlInstance = (New-NativeLostCaller); ErrorAction = "Stop" } }
            Assert-NativeLostRecord -Call $call
            ($call.Lines -join ",") | Should -BeExactly "next statement"
        }

        It "is not caught by a caller's try without -EnableException, as the pin does" {
            $tryScript = 'param($Values) $Arguments = $Values.Arguments; $null = $Values.Fixture.ConnectionContext.ExecuteNonQuery($Values.Sql); try { Get-DbaErrorLogConfig @Arguments |ForEach-Object { "row: " + $PSItem.SqlInstance }; "after the call inside the try" } catch { "caught" }; "next statement"'
            $call = Invoke-NativeLostCall -Script $tryScript -Values @{ Fixture = $lostFixture; Sql = $disableSql; Arguments = @{ SqlInstance = (New-NativeLostCaller) } }
            Assert-NativeLostRecord -Call $call
            ($call.Lines -join ",") | Should -BeExactly "after the call inside the try,next statement"
        }

        It "throws the record to a caller's try under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $eeScript = 'param($Values) $Arguments = $Values.Arguments; $null = $Values.Fixture.ConnectionContext.ExecuteNonQuery($Values.Sql); try { Get-DbaErrorLogConfig @Arguments |ForEach-Object { "row: " + $PSItem.SqlInstance }; "after the call inside the try" } catch { "caught: " + $PSItem.FullyQualifiedErrorId + " | " + $PSItem.CategoryInfo.Category + " | " + $PSItem.TargetObject }; "next statement"'
            $call = Invoke-NativeLostCall -Script $eeScript -Values @{ Fixture = $lostFixture; Sql = $disableSql; Arguments = @{ SqlInstance = (New-NativeLostCaller); EnableException = $true } }
            $call.Lines.Count | Should -Be 2
            $call.Lines[0] | Should -BeLike "caught: dbatools_Get-DbaErrorLogConfig* | ConnectionError | $lostInstance"
            $call.Lines[1] | Should -BeExactly "next statement"
        }

        It "reads the next server after the lost one" {
            $call = Invoke-NativeLostCall -Script $lostScript -Values @{ Fixture = $lostFixture; Sql = $disableSql; Arguments = @{ SqlInstance = @((New-NativeLostCaller), $lostFixture) } }
            Assert-NativeLostRecord -Call $call
            ($call.Lines -join ",") | Should -BeExactly "row: $($lostFixture.DomainInstanceName),next statement"
        }

        It "writes the row of a piped server, then the record of the next one, lost after that row" {
            $first = New-NativeLostCaller
            $second = Connect-DbaInstance -SqlInstance $lostInstance -SqlCredential $lostCred -NonPooledConnection -EnableException
            $null = $lostCallers.Add($second)
            $pipedScript = 'param($Values) $broke = $false; $Values.Callers | Get-DbaErrorLogConfig | ForEach-Object { "row: " + $PSItem.SqlInstance; if (-not $broke) { $broke = $true; $null = $Values.Fixture.ConnectionContext.ExecuteNonQuery($Values.Sql) } }; "next statement"'
            $call = Invoke-NativeLostCall -Script $pipedScript -Values @{ Fixture = $lostFixture; Sql = $disableSql; Callers = @($first, $second) }
            Assert-NativeLostRecord -Call $call
            ($call.Lines -join ",") | Should -BeExactly "row: $($first.DomainInstanceName),next statement"
        }

        # Not a lost connection: SqlClient logs in again and the call reads the server.
        It "writes the row and no record when the sessions end and the login may connect again, as the pin does" {
            $caller = New-NativeLostCaller
            $call = Invoke-NativeLostCall -Script $lostScript -Values @{ Fixture = $lostFixture; Sql = $endOnlySql; Arguments = @{ SqlInstance = $caller } }
            $call.Records.Count | Should -Be 0
            $call.Warnings.Count | Should -Be 0
            ($call.Lines -join ",") | Should -BeExactly "row: $($caller.DomainInstanceName),next statement"
        }
    }
}

Describe "Native Get-DbaErrorLogConfig on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
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
                # A paused serverless database answers 40613 or times out (-2) while it resumes, and the lab's mobile
                # internet can drop a name lookup (11001, "No such host is known").
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -in 40613, -2, 11001) { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }

    AfterAll {
        if ($azureServer) {
            $azureServer.ConnectionContext.Disconnect()
        }
    }

    # Azure SQL Database has no instance error log: its settings and file are instance-level and file-system configuration, which it does not offer
    # (https://learn.microsoft.com/azure/azure-sql/database/transact-sql-tsql-differences-sql-server, "Overview";
    # https://learn.microsoft.com/sql/database-engine/configure-windows/scm-services-configure-sql-server-error-logs applies to SQL Server only).
    # The pin returns a row of nulls there with no error (evidence/pin-errorlogconfig-20261104.txt); the port refuses it as Connect-DbaInstance
    # -AzureUnsupported does (corrections.json, azure-errorlog-refusal).
    It "refuses Azure SQL Database with the canonical message and goes on to the next instance" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $warnings = $null
        $results = @(Get-DbaErrorLogConfig -SqlInstance $azureServer, $TestConfig.InstanceSingle -WarningVariable warnings -WarningAction SilentlyContinue)
        @($warnings).Count | Should -Be 1
        "$($warnings[0])" | Should -BeLike "*Failure | *Azure SQL Database not supported*"
        $results.Count | Should -Be 1
        $results[0].SqlInstance | Should -Not -Be $azureServer.DomainInstanceName
        $results[0].LogCount | Should -Not -BeNullOrEmpty
    }

    It "refuses Azure SQL Database on a connection by name" {
        $warnings = $null
        $results = @(Get-DbaErrorLogConfig -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -WarningVariable warnings -WarningAction SilentlyContinue)
        $results.Count | Should -Be 0
        @($warnings).Count | Should -Be 1
        "$($warnings[0])" | Should -BeLike "*Failure | *Azure SQL Database not supported*"
    }

    It "throws the refusal under -EnableException, before the next instance" -Tag "NativeChecklist:enable-exception" {
        $caught = $null
        $collected = $null
        try {
            $null = Get-DbaErrorLogConfig -SqlInstance $azureServer, $TestConfig.InstanceSingle -EnableException -OutVariable collected -WarningAction SilentlyContinue
        } catch {
            $caught = $PSItem
        }
        $caught.Exception.Message | Should -BeLike "*Azure SQL Database not supported*"
        $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaErrorLogConfig*"
        "$($caught.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
        @($collected).Count | Should -Be 0
    }

    It "inside a caller's try, a plain call warns of the refusal and reads the next instance" {
        $failure = $null
        $after = $false
        $warnings = $null
        $results = $null
        try {
            $results = @(Get-DbaErrorLogConfig -SqlInstance $azureServer, $TestConfig.InstanceSingle -WarningVariable warnings -WarningAction SilentlyContinue)
            $after = $true
        } catch {
            $failure = $PSItem
        }
        $failure | Should -BeNullOrEmpty
        $after | Should -BeTrue
        @($warnings).Count | Should -Be 1
        "$($warnings[0])" | Should -BeLike "*Failure | *Azure SQL Database not supported*"
        @($results).Count | Should -Be 1
    }
}
