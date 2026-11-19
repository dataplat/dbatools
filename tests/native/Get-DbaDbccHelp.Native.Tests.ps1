#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbccHelp",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters and changes nothing on the server.

Describe "Native Get-DbaDbccHelp" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $missingInstance = "nativedbcchelp$(Get-Random)"
        $noHelp = "\[Invoke-DbaQuery\] \[[^\]]+\] Failed during execution \| No help available for DBCC statement "
    }

    Context "The help of a DBCC command" {
        It "returns the pinned properties, in order, on a plain object" {
            $result = Get-DbaDbccHelp -SqlInstance $instance -Statement FREESYSTEMCACHE -EnableException
            @($result).Count | Should -Be 1
            @($result.PSObject.Properties.Name) | Should -Be @("Operation", "Cmd", "Output")
            $result.PSObject.TypeNames[0] | Should -Be "System.Management.Automation.PSCustomObject"
            $result.Operation | Should -BeExactly "FREESYSTEMCACHE"
            $result.Cmd | Should -BeExactly "DBCC HELP(FREESYSTEMCACHE)"
            $result.Output | Should -BeOfType [string]
            $result.Output | Should -BeLike "dbcc FREESYSTEMCACHE*"
        }

        It "returns one object per piped instance" -Tag "NativeChecklist:pipeline-multiple" {
            $results = @($instance, $instance | Get-DbaDbccHelp -Statement FREESYSTEMCACHE -EnableException)
            $results.Count | Should -Be 2
            $results[0].Output | Should -BeLike "dbcc FREESYSTEMCACHE*"
            $results[1].Output | Should -BeLike "dbcc FREESYSTEMCACHE*"
        }

        It "reads through a server object" {
            $server = Connect-DbaInstance -SqlInstance $instance
            $result = $server | Get-DbaDbccHelp -Statement CHECKDB -EnableException
            $result.Output | Should -BeLike "dbcc CHECKDB*"
        }

        It "reads the help of <Statement>, and reports the text as given" -ForEach @(
            @{ Statement = "checkdb" }
            @{ Statement = " CHECKDB " }
            @{ Statement = "'CHECKDB'" }
            @{ Statement = "N'CHECKDB'" }
            @{ Statement = "[CHECKDB]" }
            @{ Statement = '"CHECKDB"' }
        ) {
            $warnings = $null
            $result = Get-DbaDbccHelp -SqlInstance $instance -Statement $Statement -WarningVariable warnings -WarningAction SilentlyContinue
            $result.Operation | Should -BeExactly $Statement
            $result.Cmd | Should -BeExactly "DBCC HELP($Statement)"
            $result.Output | Should -BeLike "dbcc CHECKDB*"
            @($warnings).Count | Should -Be 0
        }

        It "lists the DBCC commands for the quoted question mark" {
            $result = Get-DbaDbccHelp -SqlInstance $instance -Statement "'?'" -EnableException
            $result.Cmd | Should -BeExactly "DBCC HELP('?')"
            @($result.Output).Count | Should -BeGreaterThan 1
            @($result.Output | ForEach-Object { "$PSItem".Trim() }) | Should -Contain "checkdb"
        }

        It "writes the pinned verbose lines" {
            $verbose = @(Get-DbaDbccHelp -SqlInstance $instance -Statement CHECKDB -Verbose -EnableException 4>&1 | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message })
            @($verbose | Where-Object { $PSItem -like "*Get-DbaDbccHelp*Get Help Information for CHECKDB" }).Count | Should -Be 1
            @($verbose | Where-Object { $PSItem -like "*Get-DbaDbccHelp*Query to run: DBCC HELP(CHECKDB) WITH NO_INFOMSGS;" }).Count | Should -Be 1
        }
    }

    Context "An undocumented command" {
        It "reads its help under -IncludeUndocumented, and names the flag in the verbose query" {
            $output = @(Get-DbaDbccHelp -SqlInstance $instance -Statement PAGE -IncludeUndocumented -Verbose -EnableException 4>&1)
            $result = @($output | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] })
            $result.Count | Should -Be 1
            $result[0].Output | Should -BeLike "dbcc PAGE*"
            @($output | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*Query to run: DBCC TRACEON (2588) WITH NO_INFOMSGS;DBCC HELP(PAGE) WITH NO_INFOMSGS;" }).Count | Should -Be 1
        }

        It "reports that no help is available without the switch" {
            $warnings = $null
            $result = Get-DbaDbccHelp -SqlInstance $instance -Statement PAGE -WarningVariable warnings -WarningAction SilentlyContinue
            $result.Operation | Should -BeExactly "PAGE"
            $result.Output | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match ($noHelp + "'PAGE'\.")
        }

        # Correction include-undocumented-false.
        It "leaves the flag off when -IncludeUndocumented is passed as false" -Tag "NativeChecklist:switch-false" {
            $warnings = $null
            $result = Get-DbaDbccHelp -SqlInstance $instance -Statement PAGE -IncludeUndocumented:$false -WarningVariable warnings -WarningAction SilentlyContinue
            $result.Output | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match ($noHelp + "'PAGE'\.")
        }
    }

    Context "Text that is not a DBCC command" {
        # Correction statement-injection.
        It "runs nothing of the text after the statement" {
            $text = "CHECKDB) WITH NO_INFOMSGS; SELECT 'injected' AS Marker; --"
            $warnings = $null
            $result = Get-DbaDbccHelp -SqlInstance $instance -Statement $text -WarningVariable warnings -WarningAction SilentlyContinue
            $result.Operation | Should -BeExactly $text
            $result.Cmd | Should -BeExactly "DBCC HELP($text)"
            $result.Output | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match $noHelp
        }

        # Correction statement-injection.
        It "keeps a single quote inside the statement name" {
            $warnings = $null
            $result = Get-DbaDbccHelp -SqlInstance $instance -Statement "O'Brien" -WarningVariable warnings -WarningAction SilentlyContinue
            $result.Output | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match ($noHelp + "'O'Brien'\.")
        }

        # Correction statement-injection: the text is a name now, so the engine reads no variable from it.
        It "reports that no help is available for a variable name" {
            $warnings = $null
            $result = Get-DbaDbccHelp -SqlInstance $instance -Statement "@x" -WarningVariable warnings -WarningAction SilentlyContinue
            $result.Output | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match ($noHelp + "'@x'\.")
        }

        It "warns under the nested query's name for an unknown statement and still returns the object" {
            $warnings = $null
            $captured = @()
            $result = Get-DbaDbccHelp -SqlInstance $instance -Statement NOSUCHDBCC -WarningVariable warnings -WarningAction SilentlyContinue -ErrorVariable captured
            @($result).Count | Should -Be 1
            $result.Operation | Should -BeExactly "NOSUCHDBCC"
            $result.Cmd | Should -BeExactly "DBCC HELP(NOSUCHDBCC)"
            $result.Output | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match ($noHelp + "'NOSUCHDBCC'\.")

            # The caller's -ErrorVariable holds the nested Invoke-DbaQuery Stop-Function record, as the pinned nested call puts it
            # there (watchman 22dc72e0, central CaptureErrorVariable). The pin's also holds the records of the nested query's own
            # caught calls and blank entries: accepted difference omitted-consequential-records.
            $captured = @($captured)
            $captured.Count | Should -Be 1
            $captured[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $captured[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Invoke-DbaQuery*"
            $captured[0].Exception.Message | Should -BeLike "No help available for DBCC statement 'NOSUCHDBCC'*"
        }

        It "does the same under -EnableException, which the nested query is not given" -Tag "NativeChecklist:enable-exception" {
            $warnings = $null
            $captured = @()
            $result = Get-DbaDbccHelp -SqlInstance $instance -Statement NOSUCHDBCC -EnableException -WarningVariable warnings -WarningAction SilentlyContinue -ErrorVariable captured
            @($result).Count | Should -Be 1
            $result.Output | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match ($noHelp + "'NOSUCHDBCC'\.")
            @($captured).Count | Should -Be 1
            @($captured)[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Invoke-DbaQuery*"
        }

        It "drops the warning under -ErrorAction <Action>, as the nested query does" -ForEach @(
            @{ Action = "SilentlyContinue" }
            @{ Action = "Ignore" }
        ) {
            $warnings = $null
            $captured = @()
            $result = Get-DbaDbccHelp -SqlInstance $instance -Statement NOSUCHDBCC -ErrorAction $Action -WarningVariable warnings -WarningAction SilentlyContinue -ErrorVariable captured
            @($result).Count | Should -Be 1
            $result.Output | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 0
            # No nested Stop-Function runs, so nothing reaches -ErrorVariable either.
            @($captured).Count | Should -Be 0
        }

        It "keeps the warning and does not throw under -ErrorAction Stop" {
            $warnings = $null
            $result = Get-DbaDbccHelp -SqlInstance $instance -Statement NOSUCHDBCC -ErrorAction Stop -WarningVariable warnings -WarningAction SilentlyContinue
            @($result).Count | Should -Be 1
            @($warnings).Count | Should -Be 1
        }

        It "reports the syntax error of a bare question mark" {
            $warnings = $null
            $result = Get-DbaDbccHelp -SqlInstance $instance -Statement "?" -WarningVariable warnings -WarningAction SilentlyContinue
            $result.Output | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "Failed during execution \| Incorrect syntax near '\?'\."
        }

        It "reports the missing argument of a <Name> statement, whose text is empty" -ForEach @(
            @{ Name = "empty"; Statement = "" }
            @{ Name = "null"; Statement = $null }
        ) {
            $warnings = $null
            $result = Get-DbaDbccHelp -SqlInstance $instance -Statement $Statement -WarningVariable warnings -WarningAction SilentlyContinue
            $result.Operation | Should -BeExactly ""
            $result.Cmd | Should -BeExactly "DBCC HELP()"
            $result.Output | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "Failed during execution \| An incorrect number of parameters was given to the DBCC statement\."
        }
    }

    Context "No -Statement" {
        It "warns once for piped instances and returns nothing" {
            $warnings = $null
            $results = @($instance, $instance | Get-DbaDbccHelp -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDbccHelp\] You must specify a value for Statement"
        }

        It "throws that warning under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            try {
                $null = Get-DbaDbccHelp -SqlInstance $instance -EnableException -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbccHelp*"
            $caught.Exception.Message | Should -BeExactly "You must specify a value for Statement"
        }
    }

    Context "A null or empty -SqlInstance" {
        # As the pin measured (evidence/pin-dbcchelp-nullinstance-20261103.txt): the command's own binder refuses it, so no nested connect sees it.
        It "refuses <Name> at the binder, with no warning and no output" -ForEach @(
            @{ Name = "a null element"; Value = @($null, "unused"); Id = "ParameterArgumentValidationErrorNullNotAllowed"; Reason = "is null" }
            @{ Name = "a null value"; Value = $null; Id = "ParameterArgumentValidationErrorNullNotAllowed"; Reason = "is null" }
            @{ Name = "an empty array"; Value = @(); Id = "ParameterArgumentValidationErrorEmptyArrayNotAllowed"; Reason = "is an empty array" }
        ) {
            $caught = $null
            $warnings = $null
            $collected = $null
            try {
                $null = Get-DbaDbccHelp -SqlInstance $Value -Statement CHECKDB -OutVariable collected -WarningVariable warnings -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            $caught.FullyQualifiedErrorId | Should -BeLike "$Id,*"
            $caught.CategoryInfo.Category | Should -Be "InvalidData"
            $caught.Exception.Message | Should -BeExactly "Cannot bind argument to parameter 'SqlInstance' because it $Reason."
            # A binder refusal may leave these unset; @($null) would count 1.
            $warnings | Should -BeNullOrEmpty
            $collected | Should -BeNullOrEmpty
        }
    }

    Context "An instance that cannot be reached" {
        It "warns and goes on to the next instance" -Tag "NativeChecklist:multi-instance-failure" {
            $warnings = $null
            $results = @(Get-DbaDbccHelp -SqlInstance $missingInstance, $instance -Statement FREESYSTEMCACHE -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 1
            $results[0].Output | Should -BeLike "dbcc FREESYSTEMCACHE*"
            # One line naming the server (harness-edits.md, "Script-scope preferences and the one-line connect warning", points 5 to 7).
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDbccHelp\] Failure \| Error connecting to \[$missingInstance\]: "
        }

        It "throws the connection failure under -EnableException, before the next instance" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            $collected = $null
            $warnings = $null
            try {
                $null = Get-DbaDbccHelp -SqlInstance $missingInstance, $instance -Statement FREESYSTEMCACHE -EnableException -OutVariable collected -WarningVariable warnings -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbccHelp*"
            $caught.CategoryInfo.Category | Should -Be "ConnectionError"
            "$($caught.TargetObject)" | Should -BeExactly $missingInstance
            @($collected).Count | Should -Be 0
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDbccHelp\] Failure \| Error connecting to \[$missingInstance\]: "
            # The line names the server; the caught record stays the server's own message.
            $caught.Exception.Message | Should -Not -BeLike "*Error connecting to*"
        }
    }

    # In a runspace of its own, so Streams.Warning is read apart from the command's -WarningVariable, on a real failed connection. Nothing listens at the name.
    Context "A connection string holding a password, on a failed connect" {
        BeforeAll {
            $maskSecret = "NativeMask" + [guid]::NewGuid().ToString("N")
            $maskTarget = "Data Source=$missingInstance;User ID=nativemask;Password=$maskSecret;Connect Timeout=3"
            $maskLine = "\[Get-DbaDbccHelp\] Failure \| Error connecting to \[$missingInstance\]: "
            $maskRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace([System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault())
            $maskRunspace.Open()
            $maskShell = [System.Management.Automation.PowerShell]::Create()
            $maskShell.Runspace = $maskRunspace
            $null = $maskShell.AddCommand("Import-Module").AddParameter("Name", (Get-Module dbatools | Where-Object ModuleType -eq Script | Select-Object -First 1).Path).AddParameter("ErrorAction", "Stop").Invoke()
        }

        AfterAll {
            $maskShell.Dispose()
            $maskRunspace.Dispose()
        }

        It "keeps the password out of the one line in the warning stream, and 3>&1 merges the same line" {
            $maskShell.Commands.Clear()
            $maskShell.Streams.Warning.Clear()
            $null = $maskShell.AddCommand("Get-DbaDbccHelp").AddParameter("SqlInstance", $maskTarget).AddParameter("Statement", "CHECKDB").Invoke()
            $streamed = @($maskShell.Streams.Warning | ForEach-Object { $PSItem.Message })
            $streamed.Count | Should -Be 1
            $streamed[0] | Should -Match $maskLine
            $streamed[0].Contains($maskSecret) | Should -BeFalse

            $merged = @(Get-DbaDbccHelp -SqlInstance $maskTarget -Statement CHECKDB 3>&1 | ForEach-Object { "$PSItem" })
            $merged.Count | Should -Be 1
            $merged[0] | Should -Match $maskLine
            $merged[0].Contains($maskSecret) | Should -BeFalse
        }

        It "keeps the password out of what -EnableException holds and throws" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            $warnings = $null
            try {
                $null = Get-DbaDbccHelp -SqlInstance $maskTarget -Statement CHECKDB -EnableException -WarningVariable warnings -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbccHelp*"
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match $maskLine
            "$($warnings[0])".Contains($maskSecret) | Should -BeFalse
            "$caught".Contains($maskSecret) | Should -BeFalse
            $caught.Exception.ToString().Contains($maskSecret) | Should -BeFalse
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
        }

        It "works with -SqlCredential" {
            $result = Get-DbaDbccHelp -SqlInstance $loginInstance -SqlCredential $loginCred -Statement FREESYSTEMCACHE -EnableException
            $result.Output | Should -BeLike "dbcc FREESYSTEMCACHE*"
        }

        It "reads an undocumented command with -SqlCredential" {
            $result = Get-DbaDbccHelp -SqlInstance $loginInstance -SqlCredential $loginCred -Statement PAGE -IncludeUndocumented -EnableException
            $result.Output | Should -BeLike "dbcc PAGE*"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = $null
            $result = Get-DbaDbccHelp -SqlInstance $loginInstance -Statement FREESYSTEMCACHE -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDbccHelp\] Failure \| Error connecting to \[$([regex]::Escape($loginInstance))\]: Login failed"
        }

        It "throws the connection failure under -EnableException, as the pinned function does" {
            { Get-DbaDbccHelp -SqlInstance $loginInstance -Statement FREESYSTEMCACHE -EnableException -WarningAction SilentlyContinue } | Should -Throw -ExpectedMessage "*Login failed*" -ErrorId "dbatools_Get-DbaDbccHelp*"
        }
    }
}

# DBCC HELP applies to SQL Server and Azure SQL Managed Instance only (https://learn.microsoft.com/sql/t-sql/database-console-commands/dbcc-help-transact-sql), and the
# engine says so: DBCC command 'HELP' is not supported in this version of SQL Server (evidence/pin-dbcchelp-azure-20261103.txt). The refusal is -AzureUnsupported's through
# the shared connect: one warning, which keeps the refusal's text, and a stop under -EnableException.
Describe "Native Get-DbaDbccHelp on Azure SQL Database" -Tag IntegrationTests, NativeChecklist:azure-sqldb {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $azureServer = $null
        # A paused serverless database answers while it resumes.
        for ($attempt = 0; $attempt -le 6 -and $null -eq $azureServer; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException -WarningAction SilentlyContinue
            } catch {
                $failure = $PSItem.Exception
                $resuming = $false
                while ($failure) {
                    # "The wait operation timed out" is a connection timeout: its inner Win32Exception carries NativeErrorCode 258.
                    if ($failure.Number -in 40613, -2 -or $failure -is [System.TimeoutException] -or ($failure -is [System.ComponentModel.Win32Exception] -and $failure.NativeErrorCode -eq 258)) {
                        $resuming = $true
                    }
                    $failure = $failure.InnerException
                }
                if (-not $resuming -or $attempt -eq 6) {
                    throw
                }
                Start-Sleep -Seconds 10
            }
        }
    }

    AfterAll {
        if ($azureServer) {
            $azureServer.ConnectionContext.Disconnect()
        }
    }

    It "refuses a server object on Azure SQL Database, with one warning, and goes on to the next instance" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $warnings = $null
        $results = @(Get-DbaDbccHelp -SqlInstance $azureServer, $instance -Statement FREESYSTEMCACHE -WarningVariable warnings -WarningAction SilentlyContinue)
        $results.Count | Should -Be 1
        $results[0].Output | Should -BeLike "dbcc FREESYSTEMCACHE*"
        @($warnings).Count | Should -Be 1
        "$($warnings[0])" | Should -Match "\[Get-DbaDbccHelp\] Failure \| Azure SQL Database not supported$"
    }

    It "refuses Azure SQL Database connected by name" {
        $warnings = $null
        $results = @(Get-DbaDbccHelp -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -Statement CHECKDB -WarningVariable warnings -WarningAction SilentlyContinue)
        $results.Count | Should -Be 0
        @($warnings).Count | Should -Be 1
        "$($warnings[0])" | Should -Match "\[Get-DbaDbccHelp\] Failure \| Azure SQL Database not supported$"
    }

    It "stops on the refusal under -EnableException, before the next instance" -Tag "NativeChecklist:enable-exception" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $caught = $null
        $collected = $null
        try {
            $null = Get-DbaDbccHelp -SqlInstance $azureServer, $instance -Statement FREESYSTEMCACHE -EnableException -OutVariable collected -WarningAction SilentlyContinue
        } catch {
            $caught = $PSItem
        }
        $caught | Should -Not -BeNullOrEmpty
        $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbccHelp*"
        $caught.Exception.Message | Should -BeExactly "Azure SQL Database not supported"
        @($collected).Count | Should -Be 0
    }
}
