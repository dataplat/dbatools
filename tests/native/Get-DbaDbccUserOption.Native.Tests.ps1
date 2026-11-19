#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbccUserOption",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads DBCC USEROPTIONS.

# Expected values below are as the pin measured on both editions: evidence/pin-useroption-20261103.txt and evidence/pin-useroption3-20261104.txt.
# A failed connect writes one warning line naming the server, where the pin writes two (connect-failed, login-failed): an accepted difference,
# harness-edits.md, "Script-scope preferences and the one-line connect warning", points 5 to 7.

Describe "Native Get-DbaDbccUserOption" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $missingInstance = "nativeuseroption$(Get-Random)"
        # The fixture's connection is never given to the command.
        $server = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
    }

    AfterAll {
        $server.ConnectionContext.Disconnect()
    }

    Context "Output" {
        It "returns one plain object per option the server reports, with the pinned properties in their order" {
            $engine = @($server.ConnectionContext.ExecuteWithResults("DBCC USEROPTIONS WITH NO_INFOMSGS").Tables[0].Rows)
            $result = @(Get-DbaDbccUserOption -SqlInstance $instance -EnableException)

            $result.Count | Should -Be $engine.Count
            $result[0].PSObject.TypeNames[0] | Should -BeExactly "System.Management.Automation.PSCustomObject"
            $result[0].PSObject.Properties.Name | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance", "Option", "Value")
            $result[0].ComputerName | Should -BeExactly $server.ComputerName
            $result[0].InstanceName | Should -BeExactly $server.ServiceName
            $result[0].SqlInstance | Should -BeExactly $server.DomainInstanceName
            @($result.Option) | Should -BeExactly @($engine | ForEach-Object { $PSItem[0] })
            @($result.Value) | Should -BeExactly @($engine | ForEach-Object { $PSItem[1] })
            $result[0].Option | Should -BeOfType [string]
            $result[0].Value | Should -BeOfType [string]
        }

        # nonpooled-context-lock-timeout.
        It "reports the setting of the session it reads" {
            $own = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
            try {
                $null = $own.ConnectionContext.ExecuteNonQuery("SET LOCK_TIMEOUT 4321;")
                $result = @(Get-DbaDbccUserOption -SqlInstance $own -Option lock_timeout -EnableException)
                $result.Count | Should -Be 1
                "$($result[0].Value)" | Should -BeExactly "4321"
            } finally {
                $own.ConnectionContext.Disconnect()
            }
        }

        It "writes the pinned verbose line" {
            $verbose = @(Get-DbaDbccUserOption -SqlInstance $instance -Verbose -EnableException 4>&1 | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message })
            @($verbose | Where-Object { $PSItem -like "*Get-DbaDbccUserOption*Query to run: DBCC USEROPTIONS WITH NO_INFOMSGS" }).Count | Should -Be 1
        }
    }

    Context "-Option" {
        It "returns only the options asked for, in the server's order" {
            $all = @(Get-DbaDbccUserOption -SqlInstance $instance -EnableException)
            $wanted = @($all.Option | Where-Object { $PSItem -in "ansi_nulls", "datefirst" })
            $wanted.Count | Should -Be 2
            $result = @(Get-DbaDbccUserOption -SqlInstance $instance -Option datefirst, ansi_nulls -EnableException)
            @($result.Option) | Should -BeExactly $wanted
        }

        It "matches an option name whatever its case" {
            $result = @(Get-DbaDbccUserOption -SqlInstance $instance -Option ANSI_NULLS -EnableException)
            $result.Count | Should -Be 1
            $result[0].Option | Should -BeExactly "ansi_nulls"
        }

        # option-twice.
        It "returns an option named twice once" {
            $result = @(Get-DbaDbccUserOption -SqlInstance $instance -Option ansi_nulls, ansi_nulls -EnableException)
            $result.Count | Should -Be 1
        }

        # option-empty-array: the parameter is bound, so no row matches.
        It "returns nothing for an empty -Option" {
            $warnings = $null
            $result = @(Get-DbaDbccUserOption -SqlInstance $instance -Option @() -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 0
            @($warnings).Count | Should -Be 0
        }

        # nonpooled-context-quoted-identifier-off.
        It "returns nothing for an option the session does not report" {
            # DBCC USEROPTIONS lists quoted_identifier only while it is on.
            $own = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
            try {
                $null = $own.ConnectionContext.ExecuteNonQuery("SET QUOTED_IDENTIFIER OFF;")
                $warnings = $null
                $result = @(Get-DbaDbccUserOption -SqlInstance $own -Option quoted_identifier -WarningVariable warnings -WarningAction SilentlyContinue)
                $result.Count | Should -Be 0
                @($warnings).Count | Should -Be 0
            } finally {
                $own.ConnectionContext.Disconnect()
            }
        }

        It "accepts the option whose name holds a space" {
            $result = @(Get-DbaDbccUserOption -SqlInstance $instance -Option "isolation level" -EnableException)
            $result.Count | Should -Be 1
            $result[0].Option | Should -BeExactly "isolation level"
        }

        It "refuses a name outside the pinned set at the binder" {
            $caught = $null
            try {
                $null = Get-DbaDbccUserOption -SqlInstance $instance -Option nosuchoption
            } catch {
                $caught = $PSItem
            }
            $caught.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationError,*"
        }
    }

    Context "Instances" {
        It "reads each piped instance" -Tag "NativeChecklist:pipeline-multiple" {
            $results = @($instance, $instance | Get-DbaDbccUserOption -Option ansi_nulls -EnableException)
            $results.Count | Should -Be 2
        }

        It "reads through a server object" {
            $own = Connect-DbaInstance -SqlInstance $instance -EnableException
            $result = @($own | Get-DbaDbccUserOption -Option ansi_nulls -EnableException)
            $result.Count | Should -Be 1
            $result[0].SqlInstance | Should -BeExactly $own.DomainInstanceName
        }
    }

    # The row loop outside the pin's try, on what such a session returns in place of the options. No record in any of these (session-showplan-text, session-noexec, session-parseonly, session-fmtonly).
    Context "A session that does not run the DBCC" {
        It "reads a past-the-end column of a plan row as nothing, with no record" {
            $own = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
            try {
                $null = $own.ConnectionContext.ExecuteNonQuery("SET SHOWPLAN_TEXT ON;")
                $result = @(Get-DbaDbccUserOption -SqlInstance $own -EnableException)
                $result.Count | Should -Be 1
                $result[0].Option | Should -BeLike "*DBCC USEROPTIONS*"
                $result[0].Value | Should -BeNullOrEmpty
            } finally {
                $own.ConnectionContext.Disconnect()
            }
        }

        It "returns nothing and warns of nothing under <Statement>" -ForEach @(
            @{ Statement = "SET NOEXEC ON;" }
            @{ Statement = "SET PARSEONLY ON;" }
            @{ Statement = "SET FMTONLY ON;" }
        ) {
            $own = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
            try {
                $null = $own.ConnectionContext.ExecuteNonQuery($Statement)
                $warnings = $null
                $result = @(Get-DbaDbccUserOption -SqlInstance $own -WarningVariable warnings -WarningAction SilentlyContinue)
                $result.Count | Should -Be 0
                @($warnings).Count | Should -Be 0
            } finally {
                $own.ConnectionContext.Disconnect()
            }
        }
    }

    Context "An instance that cannot be reached" {
        It "warns and goes on to the next instance" -Tag "NativeChecklist:multi-instance-failure" {
            $warnings = $null
            $results = @(Get-DbaDbccUserOption -SqlInstance $missingInstance, $instance -Option ansi_nulls -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 1
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDbccUserOption\] Failure \| Error connecting to \[$missingInstance\]: "
        }

        It "warns and goes on under -EnableException:`$false" -Tag "NativeChecklist:switch-false" {
            $warnings = $null
            $results = @(Get-DbaDbccUserOption -SqlInstance $missingInstance, $instance -Option ansi_nulls -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 1
            @($warnings).Count | Should -Be 1
        }

        It "throws the connection failure under -EnableException, before the next instance" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            $collected = $null
            $warnings = $null
            try {
                $null = Get-DbaDbccUserOption -SqlInstance $missingInstance, $instance -EnableException -OutVariable collected -WarningVariable warnings -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDbccUserOption\] Failure \| Error connecting to \[$missingInstance\]: "
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbccUserOption*"
            "$($caught.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            "$($caught.TargetObject)" | Should -BeExactly $missingInstance
            # The line names the server; the caught record stays the server's own message.
            $caught.Exception.Message | Should -Not -BeLike "*Error connecting to*"
            @($collected).Count | Should -Be 0
        }
    }

    # In a runspace of its own, where the streams can be read and nothing else sets a preference. Points 5 and 6 of the section named above.
    Context "The streams of a plain call" {
        BeforeAll {
            $streamLine = "\[Get-DbaDbccUserOption\] Failure \| Error connecting to \[$missingInstance\]: "
            $streamRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace([System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault())
            $streamRunspace.Open()
            $streamShell = [System.Management.Automation.PowerShell]::Create()
            $streamShell.Runspace = $streamRunspace
            $streamModulePath = (Get-Module dbatools | Where-Object ModuleType -eq Script | Select-Object -First 1).Path
            $null = $streamShell.AddCommand("Import-Module").AddParameter("Name", $streamModulePath).AddParameter("ErrorAction", "Stop").Invoke()

            function NativeUserOptionStreamCall {
                param([string]$Script)
                $streamShell.Commands.Clear()
                $streamShell.Streams.Warning.Clear()
                $null = $streamShell.AddScript($Script).AddArgument($missingInstance)
                $output = @($streamShell.Invoke())
                [pscustomobject]@{
                    Lines    = @($output | Where-Object { $PSItem.psobject.BaseObject -is [string] } | ForEach-Object { "$PSItem" })
                    Merged   = @($output | Where-Object { $PSItem.psobject.BaseObject -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $PSItem.Message })
                    Warnings = @($streamShell.Streams.Warning | ForEach-Object { $PSItem.Message })
                }
            }
        }

        AfterAll {
            $streamShell.Dispose()
            $streamRunspace.Dispose()
        }

        It "holds the one line in the warning stream of a plain call, which goes on" {
            $call = NativeUserOptionStreamCall -Script 'param($Target) Get-DbaDbccUserOption -SqlInstance $Target; "next statement"'
            $call.Warnings.Count | Should -Be 1
            $call.Warnings[0] | Should -Match $streamLine
            $call.Lines | Should -Contain "next statement"
        }

        It "merges the one line under 3>&1 on a plain call" {
            $call = NativeUserOptionStreamCall -Script 'param($Target) Get-DbaDbccUserOption -SqlInstance $Target 3>&1; "next statement"'
            $call.Merged.Count | Should -Be 1
            $call.Merged[0] | Should -Match $streamLine
            $call.Warnings.Count | Should -Be 0
            $call.Lines | Should -Contain "next statement"
        }

        It "displays nothing under -EnableException, and -WarningVariable holds the one line" -Tag "NativeChecklist:enable-exception" {
            $call = NativeUserOptionStreamCall -Script 'param($Target) try { Get-DbaDbccUserOption -SqlInstance $Target -EnableException -WarningVariable held 3>&1 } catch { "caught " + $PSItem.FullyQualifiedErrorId }; "held " + @($held).Count; foreach ($line in $held) { "line " + $line }'
            $call.Merged.Count | Should -Be 0
            $call.Warnings.Count | Should -Be 0
            @($call.Lines | Where-Object { $PSItem -like "caught dbatools_Get-DbaDbccUserOption*" }).Count | Should -Be 1
            $call.Lines | Should -Contain "held 1"
            @($call.Lines | Where-Object { $PSItem -like "line *" -and $PSItem -match $streamLine }).Count | Should -Be 1
        }

        It "leaves the warning stream empty under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $call = NativeUserOptionStreamCall -Script 'param($Target) try { Get-DbaDbccUserOption -SqlInstance $Target -EnableException } catch { "caught " + $PSItem.FullyQualifiedErrorId }'
            $call.Warnings.Count | Should -Be 0
            @($call.Lines | Where-Object { $PSItem -like "caught dbatools_Get-DbaDbccUserOption*" }).Count | Should -Be 1
        }

        # piped-null-middle: the engine writes the binder's record for that one input and the instances beside it are still read.
        It "writes the binder's record for a piped null, and reads the instances beside it" {
            $streamShell.Commands.Clear()
            $streamShell.Streams.Error.Clear()
            $null = $streamShell.AddScript('param($Target) @($Target, $null, $Target | Get-DbaDbccUserOption -Option ansi_nulls).Count; "next statement"').AddArgument($instance)
            $output = @($streamShell.Invoke())
            "$($output[0])" | Should -BeExactly "2"
            "$($output[1])" | Should -BeExactly "next statement"
            $streamShell.Streams.Error.Count | Should -Be 1
            $streamShell.Streams.Error[0].FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
            "$($streamShell.Streams.Error[0].CategoryInfo.Category)" | Should -BeExactly "InvalidData"
            $streamShell.Streams.Error[0].Exception.Message | Should -BeExactly "Cannot bind argument to parameter 'SqlInstance' because it is null."
        }
    }

    Context "A null or empty -SqlInstance" {
        # instance-null, null-first and instance-empty: the command's own binder refuses it.
        It "refuses <Name> at the binder, with no warning and no output" -ForEach @(
            @{ Name = "a null element"; Value = @($null, "unused"); Id = "ParameterArgumentValidationErrorNullNotAllowed"; Reason = "is null" }
            @{ Name = "a null value"; Value = $null; Id = "ParameterArgumentValidationErrorNullNotAllowed"; Reason = "is null" }
            @{ Name = "an empty array"; Value = @(); Id = "ParameterArgumentValidationErrorEmptyArrayNotAllowed"; Reason = "is an empty array" }
        ) {
            $caught = $null
            $warnings = $null
            $collected = $null
            try {
                $null = Get-DbaDbccUserOption -SqlInstance $Value -OutVariable collected -WarningVariable warnings -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            $caught.FullyQualifiedErrorId | Should -BeLike "$Id,*"
            "$($caught.CategoryInfo.Category)" | Should -BeExactly "InvalidData"
            $caught.Exception.Message | Should -BeExactly "Cannot bind argument to parameter 'SqlInstance' because it $Reason."
            # A binder refusal may leave these unset; @($null) would count 1.
            $warnings | Should -BeNullOrEmpty
            $collected | Should -BeNullOrEmpty
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
        }

        It "works with -SqlCredential" {
            $result = @(Get-DbaDbccUserOption -SqlInstance $loginInstance -SqlCredential $loginCred -Option ansi_nulls -EnableException)
            $result.Count | Should -Be 1
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = $null
            $result = Get-DbaDbccUserOption -SqlInstance $loginInstance -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match ("\[Get-DbaDbccUserOption\] Failure \| Error connecting to \[" + [regex]::Escape($loginInstance) + "\]: Login failed")
        }

        It "throws the connection failure under -EnableException" {
            { Get-DbaDbccUserOption -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue } | Should -Throw -ExpectedMessage "*Login failed*" -ErrorId "dbatools_Get-DbaDbccUserOption*"
        }
    }

    # A caller's connection that breaks after Connect-DbaInstance has it. Each caller has a login of its own: a failed login puts its connection string's pool
    # in SqlClient's blocking period, so the next connect with that login fails too (808e3104 against 24e684f8). The DBCC needs only the public role, and the pin's "Failure running"
    # catch had no real form in the measure, so these all end at the connect's own SELECT or, killed, reconnect.
    Context "A caller whose connection breaks" {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $brokenStamp = Get-Random
            $brokenHome = "dbatoolsci_nuo_home_$brokenStamp"
            $brokenPrefix = "dbatoolsci_nuo_low_$brokenStamp"
            $brokenPassword = "Nuo-$([guid]::NewGuid().ToString('N'))"
            # Non-pooled, so a USE stays until the next one: every statement names its database first.
            $brokenFixture = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $TestConfig.SqlLoginCred -NonPooledConnection -EnableException
            $null = $brokenFixture.Query("USE [master]; CREATE DATABASE [$brokenHome];")
            # The fixture's connection, so the good instance beside a broken one is never the broken login.
            $brokenNext = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $TestConfig.SqlLoginCred -NonPooledConnection -EnableException

            function NativeUserOptionBrokenSessions {
                foreach ($row in @($brokenFixture.Query("USE [master]; SELECT session_id FROM sys.dm_exec_sessions WHERE login_name LIKE N'$brokenPrefix%';") | Where-Object { $null -ne $PSItem })) {
                    $null = $brokenFixture.Query("USE [master]; KILL $($row.session_id);")
                }
            }

            function NativeUserOptionBrokenCaller {
                param([string]$Form)
                $name = "$($brokenPrefix)_$(Get-Random)"
                $null = $brokenFixture.Query("USE [master]; CREATE LOGIN [$name] WITH PASSWORD = '$brokenPassword', CHECK_POLICY = OFF;")
                $null = $brokenFixture.Query("USE [$brokenHome]; CREATE USER [$name] FOR LOGIN [$name]; USE [master];")
                $credential = New-Object System.Management.Automation.PSCredential -ArgumentList $name, (ConvertTo-SecureString -String $brokenPassword -AsPlainText -Force)
                $splatCaller = @{ SqlInstance = $loginInstance; SqlCredential = $credential; Database = $brokenHome; EnableException = $true }
                if ($Form -eq "killed") {
                    $splatCaller.NonPooledConnection = $true
                }
                $caller = Connect-DbaInstance @splatCaller
                $null = $caller.ConnectionContext.ExecuteScalar("SELECT 1;")
                if ($Form -eq "disabled") {
                    $null = $brokenFixture.Query("USE [master]; ALTER LOGIN [$name] DISABLE;")
                }
                if ($Form -eq "denied") {
                    $null = $brokenFixture.Query("USE [$brokenHome]; DENY CONNECT TO [$name]; USE [master];")
                }
                NativeUserOptionBrokenSessions
                [Microsoft.Data.SqlClient.SqlConnection]::ClearAllPools()
                [pscustomobject]@{ Name = $name; Caller = $caller }
            }
        }

        AfterAll {
            $brokenNext.ConnectionContext.Disconnect()
            [Microsoft.Data.SqlClient.SqlConnection]::ClearAllPools()
            NativeUserOptionBrokenSessions
            $null = $brokenFixture.Query("USE [master]; IF DB_ID(N'$brokenHome') IS NOT NULL BEGIN ALTER DATABASE [$brokenHome] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$brokenHome]; END;")
            foreach ($row in @($brokenFixture.Query("USE [master]; SELECT name FROM sys.server_principals WHERE name LIKE N'$brokenPrefix%';") | Where-Object { $null -ne $PSItem })) {
                $null = $brokenFixture.Query("USE [master]; DROP LOGIN [$($row.name)];")
            }
            $brokenFixture.ConnectionContext.Disconnect()
        }

        # disabled-plain, denied-plain: the connect's catch, not "Failure running", and the next instance is read.
        It "warns as a failed connect and goes on when the caller's login is <Form>" -ForEach @(
            @{ Form = "disabled"; Reason = "Login failed for user" }
            @{ Form = "denied"; Reason = "Cannot open database" }
        ) {
            $broken = NativeUserOptionBrokenCaller -Form $Form
            $warnings = $null
            $result = @(Get-DbaDbccUserOption -SqlInstance $broken.Caller, $brokenNext -Option ansi_nulls -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 1
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match ("\[Get-DbaDbccUserOption\] Failure \| Error connecting to \[" + [regex]::Escape($loginInstance) + "\]: $Reason")
            "$($warnings[0])" | Should -Not -BeLike "*Failure running*"
        }

        # disabled-ee-try: the record of a failed connect, and the next instance is not read.
        It "throws the failed connect under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $broken = NativeUserOptionBrokenCaller -Form "disabled"
            $caught = $null
            $collected = $null
            try {
                $null = Get-DbaDbccUserOption -SqlInstance $broken.Caller, $brokenNext -Option ansi_nulls -EnableException -OutVariable collected -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbccUserOption*"
            "$($caught.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            "$($caught.TargetObject)" | Should -BeExactly $loginInstance
            $caught.Exception.Message | Should -BeExactly "Login failed for user '$($broken.Name)'. Reason: The account is disabled."
            @($collected).Count | Should -Be 0
        }

        # killed-plain, killed-ee: the non-pooled connection reconnects, so nothing is reported at all.
        It "reads through a caller whose session was killed, with no warning" {
            $broken = NativeUserOptionBrokenCaller -Form "killed"
            try {
                $warnings = $null
                $result = @(Get-DbaDbccUserOption -SqlInstance $broken.Caller, $brokenNext -Option ansi_nulls -WarningVariable warnings -WarningAction SilentlyContinue)
                $result.Count | Should -Be 2
                @($warnings).Count | Should -Be 0
            } finally {
                $broken.Caller.ConnectionContext.Disconnect()
            }
        }
    }
}

Describe "Native Get-DbaDbccUserOption on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $azureDatabase = $TestConfig.AzureSqlDbName
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $azureDatabase
            SqlCredential   = $TestConfig.AzureSqlDbCred
            EnableException = $true
        }
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613 or times out (-2, 258, as the pin's azure-server-object case did on 5.1) while it resumes, and the lab's mobile
                # internet can drop a name lookup (11001, "No such host is known").
                $azureError = $PSItem.Exception
                $isResuming = "$($PSItem.Exception.Message)" -like "*timed out*"
                while ($azureError) {
                    if ($azureError.Number -in 40613, -2, 258, 11001 -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }

    # Read-only. azure-server-object: the login reads its own session in the database, and the instance name is null there.
    It "returns the session's options on a connection to the database, and leaves it there" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $warnings = $null
        $result = @(Get-DbaDbccUserOption -SqlInstance $azureServer -WarningVariable warnings -WarningAction SilentlyContinue)
        @($warnings).Count | Should -Be 0
        $result.Count | Should -BeGreaterThan 0
        $result[0].PSObject.Properties.Name | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance", "Option", "Value")
        $result[0].ComputerName | Should -BeExactly $azureServer.ComputerName
        $result[0].SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
        $result[0].InstanceName | Should -BeNullOrEmpty
        @($result.Option) | Should -Contain "ansi_nulls"
        $azureServer.ConnectionContext.CurrentDatabase | Should -BeExactly $azureDatabase
    }

    # azure-by-name: DBCC USEROPTIONS needs no switch and no right in master, so a connection by name reads the same rows.
    It "returns the session's options on a connection by name" -Tag "NativeChecklist:azure-sqldb" {
        $warnings = $null
        $result = @(Get-DbaDbccUserOption -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -WarningVariable warnings -WarningAction SilentlyContinue)
        @($warnings).Count | Should -Be 0
        $result.Count | Should -BeGreaterThan 0
        @($result.Option) | Should -Contain "ansi_nulls"
        $result[0].InstanceName | Should -BeNullOrEmpty
    }
}
