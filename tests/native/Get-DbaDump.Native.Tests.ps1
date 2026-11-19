#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDump",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads a DMV.

# Expected values below are as the pin measured on both editions: evidence/pin-dump2-20261104.txt. That instance held no dump, so a row's values come from an independent read of the view here.
# A failed connect writes one warning line naming the server, where the pin writes two (connect-failed, connect-merged): an accepted difference,
# harness-edits.md, "Script-scope preferences and the one-line connect warning", points 5 to 7.

Describe "Native Get-DbaDump" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $missingInstance = "nativedump$(Get-Random)"
        $sql = "SELECT filename, creation_time, size_in_bytes FROM sys.dm_server_memory_dumps"

        # Times for reading after a run, kept past it because a passing run's folder is removed. A file that cannot be written decides nothing.
        # Each leg writes its own file; a file left by an earlier run is removed here once it is 12 hours old.
        $timesFolder = "C:\native\dump-times"
        $timesFile = Join-Path $timesFolder "$($instance -replace '[\\/:]', '_')-$($PSVersionTable.PSEdition)-$([datetime]::UtcNow.ToString('yyyyMMddTHHmmssfff')).txt"
        $testsStarted = @{ Number = 0 }
        function NativeDumpWriteTime {
            param([string]$Text)
            try {
                Add-Content -LiteralPath $timesFile -Value "$([datetime]::UtcNow.ToString('o')) $Text" -ErrorAction Stop
            } catch {
                $null = $PSItem
            }
        }
        try {
            $null = New-Item -Path $timesFolder -ItemType Directory -Force -ErrorAction Stop
            Get-ChildItem -LiteralPath $timesFolder -Filter "*.txt" -ErrorAction Stop | Where-Object LastWriteTimeUtc -lt ([datetime]::UtcNow.AddHours(-12)) | Remove-Item -ErrorAction Stop
        } catch {
            $null = $PSItem
        }

        # The pinned file's DBCC STACKDUMP stalls the instance while it runs: new connections time out at 15 seconds (evidence/measure-stall-v*-20261104.txt, measure-quiet-*-20261104.txt).
        # This wait on a connection of its own runs after that file: 90 seconds in which SELECT 1 always answers within 2 seconds, a late or failed answer starting them again,
        # at most 600 seconds in all, after which the tests run anyway. It wraps no port call or assertion, so a timeout after it fails its test.
        # The port's calls with no wait passed on both editions in measure-quiet, on one host, so the wait is not shown to be needed or to cure result 20261104T0354213241115Z; what caused
        # that result is unmeasured. Its use is that a timeout after it, in a test's logged time, cannot be put down to a dump still running on this leg.
        function NativeDumpWaitForQuiet {
            $quietConnect = "Data Source=$instance;Integrated Security=True;TrustServerCertificate=True;Pooling=False;Connect Timeout=3;Application Name=nativedump-wait"
            NativeDumpWriteTime "quiet period starts"
            $quietTotal = [System.Diagnostics.Stopwatch]::StartNew()
            $quietSince = [System.Diagnostics.Stopwatch]::StartNew()
            $quietRestarts = 0
            while ($quietSince.Elapsed.TotalSeconds -lt 90 -and $quietTotal.Elapsed.TotalSeconds -lt 600) {
                $answerTime = [System.Diagnostics.Stopwatch]::StartNew()
                $answerFailure = $null
                $quietConnection = New-Object Microsoft.Data.SqlClient.SqlConnection -ArgumentList $quietConnect
                try {
                    $quietConnection.Open()
                    $quietCommand = $quietConnection.CreateCommand()
                    $quietCommand.CommandTimeout = 3
                    $quietCommand.CommandText = "SELECT 1"
                    $null = $quietCommand.ExecuteScalar()
                } catch {
                    $answerFailure = $PSItem.Exception.Message
                } finally {
                    $quietConnection.Dispose()
                }
                if ($null -ne $answerFailure -or $answerTime.Elapsed.TotalSeconds -ge 2) {
                    $quietRestarts++
                    $quietSince.Restart()
                    NativeDumpWriteTime "quiet period restarts after $($answerTime.ElapsedMilliseconds) ms: $answerFailure"
                }
                Start-Sleep -Seconds 1
            }
            NativeDumpWriteTime "quiet period ends: held $($quietSince.Elapsed.TotalSeconds -ge 90), restarts $quietRestarts, seconds $([int]$quietTotal.Elapsed.TotalSeconds)"
        }

        NativeDumpWaitForQuiet
        # The fixture's connection is never given to the command.
        $server = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
        # The pinned test makes its dumps the same way; an instance that already has one is left alone.
        # The server's clock before the dump marks the files this file makes; the AfterAll removes those, and only those.
        $nativeDumpMade = @{ Since = $null }
        if ($server.ConnectionContext.ExecuteWithResults($sql).Tables[0].Rows.Count -eq 0) {
            $nativeDumpMade.Since = $server.ConnectionContext.ExecuteScalar("SELECT SYSDATETIMEOFFSET()")
            NativeDumpWriteTime "fixture dump starts"
            $null = $server.ConnectionContext.ExecuteWithResults("DBCC STACKDUMP")
            NativeDumpWriteTime "fixture dump returned"
            NativeDumpWaitForQuiet
        }
    }

    AfterAll {
        # Operator, 2026-11-04: "the tests should clean up after themselves". Every dump the fixture made goes, with the
        # .txt and .log files SQL Server writes beside it under the same name, each by its literal path as the view
        # gives it; a dump made before this file ran, by the pinned file or anything else, is left alone.
        try {
            if ($null -ne $nativeDumpMade -and $null -ne $nativeDumpMade.Since) {
                $madeDumps = @($server.ConnectionContext.ExecuteWithResults($sql).Tables[0].Rows | Where-Object { $PSItem["creation_time"] -ge $nativeDumpMade.Since } | ForEach-Object { [string]$PSItem["filename"] })
                $madeFiles = @(foreach ($dump in $madeDumps) {
                        $dump
                        [System.IO.Path]::ChangeExtension($dump, ".txt")
                        [System.IO.Path]::ChangeExtension($dump, ".log")
                    })
                NativeDumpWriteTime "fixture dumps removed: $($madeDumps -join ', ')"
                if ($madeFiles.Count -gt 0) {
                    $leftFiles = @(Invoke-Command -ComputerName $server.ComputerName -ArgumentList (, $madeFiles) -ErrorAction Stop -ScriptBlock {
                            param($files)
                            foreach ($file in $files) {
                                if (Test-Path -LiteralPath $file) {
                                    Remove-Item -LiteralPath $file -Force -ErrorAction Stop
                                }
                            }
                            foreach ($file in $files) {
                                if (Test-Path -LiteralPath $file) { $file }
                            }
                        })
                    $leftFiles.Count | Should -Be 0
                }
            }
        } finally {
            $server.ConnectionContext.Disconnect()
        }
    }

    BeforeEach {
        $testsStarted.Number++
        NativeDumpWriteTime "test $($testsStarted.Number) starts: $($____Pester.CurrentTest.ExpandedPath)"
    }

    Context "Output" {
        It "returns one plain object per dump, with the pinned properties in their order and the view's values" {
            $engine = @($server.ConnectionContext.ExecuteWithResults("$sql ORDER BY filename").Tables[0].Rows)
            $engine.Count | Should -BeGreaterThan 0
            $result = @(Get-DbaDump -SqlInstance $instance -EnableException | Sort-Object -Property FileName)

            $result.Count | Should -BeGreaterOrEqual $engine.Count
            $result[0].PSObject.TypeNames[0] | Should -BeExactly "System.Management.Automation.PSCustomObject"
            $result[0].PSObject.Properties.Name | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance", "FileName", "CreationTime", "Size")
            $result[0].ComputerName | Should -BeExactly $server.ComputerName
            $result[0].InstanceName | Should -BeExactly $server.ServiceName
            $result[0].SqlInstance | Should -BeExactly $server.DomainInstanceName

            # A dump added between the two reads is not in the independent read, so each row it read is looked up.
            foreach ($row in $engine) {
                $match = @($result | Where-Object FileName -eq $row["filename"])
                $match.Count | Should -Be 1
                $match[0].CreationTime | Should -Be $row["creation_time"]
                $match[0].CreationTime.GetType().FullName | Should -BeExactly $row["creation_time"].GetType().FullName
                $match[0].Size | Should -BeOfType Dataplat.Dbatools.Utility.Size
                $match[0].Size.Byte | Should -Be $row["size_in_bytes"]
            }
        }

        It "reads through a server object" {
            $own = Connect-DbaInstance -SqlInstance $instance -EnableException
            $result = @($own | Get-DbaDump -EnableException)
            $result.Count | Should -BeGreaterThan 0
            $result[0].SqlInstance | Should -BeExactly $own.DomainInstanceName
        }
    }

    Context "Instances" {
        It "reads each piped instance" -Tag "NativeChecklist:pipeline-multiple" {
            $once = @(Get-DbaDump -SqlInstance $instance -EnableException).Count
            $twice = @($instance, $instance | Get-DbaDump -EnableException).Count
            $twice | Should -BeGreaterOrEqual (2 * $once)
        }
    }

    Context "An instance that cannot be reached" {
        It "warns and goes on to the next instance" -Tag "NativeChecklist:multi-instance-failure" {
            $warnings = $null
            $results = @(Get-DbaDump -SqlInstance $missingInstance, $instance -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -BeGreaterThan 0
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDump\] Failure \| Error connecting to \[$missingInstance\]: "
        }

        It "warns and goes on under -EnableException:`$false" -Tag "NativeChecklist:switch-false" {
            $warnings = $null
            $results = @(Get-DbaDump -SqlInstance $missingInstance, $instance -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -BeGreaterThan 0
            @($warnings).Count | Should -Be 1
        }

        It "throws the connection failure under -EnableException, before the next instance" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            $collected = $null
            $warnings = $null
            try {
                $null = Get-DbaDump -SqlInstance $missingInstance, $instance -EnableException -OutVariable collected -WarningVariable warnings -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDump\] Failure \| Error connecting to \[$missingInstance\]: "
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDump*"
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
            $streamLine = "\[Get-DbaDump\] Failure \| Error connecting to \[$missingInstance\]: "
            $streamRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace([System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault())
            $streamRunspace.Open()
            $streamShell = [System.Management.Automation.PowerShell]::Create()
            $streamShell.Runspace = $streamRunspace
            $streamModulePath = (Get-Module dbatools | Where-Object ModuleType -eq Script | Select-Object -First 1).Path
            $null = $streamShell.AddCommand("Import-Module").AddParameter("Name", $streamModulePath).AddParameter("ErrorAction", "Stop").Invoke()

            function NativeDumpStreamCall {
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
            $call = NativeDumpStreamCall -Script 'param($Target) Get-DbaDump -SqlInstance $Target; "next statement"'
            $call.Warnings.Count | Should -Be 1
            $call.Warnings[0] | Should -Match $streamLine
            $call.Lines | Should -Contain "next statement"
        }

        It "merges the one line under 3>&1 on a plain call" {
            $call = NativeDumpStreamCall -Script 'param($Target) Get-DbaDump -SqlInstance $Target 3>&1; "next statement"'
            $call.Merged.Count | Should -Be 1
            $call.Merged[0] | Should -Match $streamLine
            $call.Warnings.Count | Should -Be 0
            $call.Lines | Should -Contain "next statement"
        }

        It "displays nothing under -EnableException, and -WarningVariable holds the one line" -Tag "NativeChecklist:enable-exception" {
            $call = NativeDumpStreamCall -Script 'param($Target) try { Get-DbaDump -SqlInstance $Target -EnableException -WarningVariable held 3>&1 } catch { "caught " + $PSItem.FullyQualifiedErrorId }; "held " + @($held).Count; foreach ($line in $held) { "line " + $line }'
            $call.Merged.Count | Should -Be 0
            $call.Warnings.Count | Should -Be 0
            @($call.Lines | Where-Object { $PSItem -like "caught dbatools_Get-DbaDump*" }).Count | Should -Be 1
            $call.Lines | Should -Contain "held 1"
            @($call.Lines | Where-Object { $PSItem -like "line *" -and $PSItem -match $streamLine }).Count | Should -Be 1
        }

        It "leaves the warning stream empty under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $call = NativeDumpStreamCall -Script 'param($Target) try { Get-DbaDump -SqlInstance $Target -EnableException } catch { "caught " + $PSItem.FullyQualifiedErrorId }'
            $call.Warnings.Count | Should -Be 0
            @($call.Lines | Where-Object { $PSItem -like "caught dbatools_Get-DbaDump*" }).Count | Should -Be 1
        }

        # piped-null: the engine writes the binder's record for that one input and the instances beside it are still read.
        It "writes the binder's record for a piped null, and reads the instances beside it" {
            $expected =@(Get-DbaDump -SqlInstance $instance -EnableException).Count
            $streamShell.Commands.Clear()
            $streamShell.Streams.Error.Clear()
            $null = $streamShell.AddScript('param($Target) @($Target, $null, $Target | Get-DbaDump).Count; "next statement"').AddArgument($instance)
            $output = @($streamShell.Invoke())
            [int]"$($output[0])" | Should -BeGreaterOrEqual (2 * $expected)
            "$($output[1])" | Should -BeExactly "next statement"
            $streamShell.Streams.Error.Count | Should -Be 1
            $streamShell.Streams.Error[0].FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
            "$($streamShell.Streams.Error[0].CategoryInfo.Category)" | Should -BeExactly "InvalidData"
            $streamShell.Streams.Error[0].Exception.Message | Should -BeExactly "Cannot bind argument to parameter 'SqlInstance' because it is null."
        }
    }

    Context "A null or empty -SqlInstance" {
        # instance-null and instance-empty: the command's own binder refuses it.
        It "refuses at the binder, with no warning and no output: <Name>" -ForEach @(
            @{ Name = "a null element"; Value = @($null, "unused"); Id = "ParameterArgumentValidationErrorNullNotAllowed"; Reason = "is null" }
            @{ Name = "a null value"; Value = $null; Id = "ParameterArgumentValidationErrorNullNotAllowed"; Reason = "is null" }
            @{ Name = "an empty array"; Value = @(); Id = "ParameterArgumentValidationErrorEmptyArrayNotAllowed"; Reason = "is an empty array" }
        ) {
            $caught = $null
            $warnings = $null
            $collected = $null
            try {
                $null = Get-DbaDump -SqlInstance $Value -OutVariable collected -WarningVariable warnings -WarningAction SilentlyContinue
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
}

Describe "Native Get-DbaDump over SQL authentication" -Tag IntegrationTests {
    BeforeAll {
        $loginInstance = $TestConfig.InstanceSqlLogin
        $loginCred = $TestConfig.SqlLoginCred
        # Unique per leg and run: the instance is shared.
        $lowName = "dbatoolsci_ndp_low_$(Get-Random)"
        $lowPassword = "Ndp-$([guid]::NewGuid().ToString('N'))"
        $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
        $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
        $null = $loginServer.Query("CREATE LOGIN [$lowName] WITH PASSWORD = '$lowPassword', CHECK_POLICY = OFF;")
    }

    AfterAll {
        foreach ($row in @($loginServer.Query("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$lowName';"))) {
            $null = $loginServer.Query("KILL $($row.session_id);")
        }
        $null = $loginServer.Query("IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];")
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        It "works with -SqlCredential" {
            $warnings = $null
            $null = Get-DbaDump -SqlInstance $loginInstance -SqlCredential $loginCred -WarningVariable warnings -WarningAction SilentlyContinue
            @($warnings).Count | Should -Be 0
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = $null
            $result = Get-DbaDump -SqlInstance $loginInstance -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match ("\[Get-DbaDump\] Failure \| Error connecting to \[" + [regex]::Escape($loginInstance) + "\]: Login failed")
        }

        It "throws the connection failure under -EnableException" {
            { Get-DbaDump -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue } | Should -Throw -ExpectedMessage "*Login failed*" -ErrorId "dbatools_Get-DbaDump*"
        }
    }

    # low-login: the view needs VIEW SERVER PERFORMANCE STATE on this 2022 instance, and the login does not have it.
    Context "A login that may not read the view" {
        BeforeAll {
            $denied = "An exception occurred while executing a Transact-SQL statement or batch.VIEW SERVER PERFORMANCE STATE permission was denied on object 'server', database 'master'.`r`nThe user does not have permission to perform this action."
        }

        It "warns of the failure and goes on to the next instance" {
            $warnings = $null
            $null = Get-DbaDump -SqlInstance $loginInstance, $loginInstance -SqlCredential $lowCred -WarningVariable warnings -WarningAction SilentlyContinue
            @($warnings).Count | Should -Be 2
            foreach ($warning in $warnings) {
                "$warning" | Should -Match "\[Get-DbaDump\] Issue collecting data on \[[^\]]+\] \| "
                "$warning".EndsWith(" | $denied", [System.StringComparison]::Ordinal) | Should -BeTrue
            }
        }

        It "throws it under -EnableException, with the method call's record inside and the server as its target" -Tag "NativeChecklist:enable-exception" {
            $record = $null
            try {
                $null = Get-DbaDump -SqlInstance $loginInstance -SqlCredential $lowCred -EnableException -WarningAction SilentlyContinue
            } catch {
                $record = $PSItem
            }
            $record.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDump*"
            "$($record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
            "$($record.TargetObject)" | Should -BeExactly $loginInstance
            $record.Exception.Message | Should -BeExactly $denied
            $record.Exception.InnerException | Should -BeOfType System.Management.Automation.MethodInvocationException
            $record.Exception.InnerException.Message | Should -BeExactly "Exception calling ""Query"" with ""1"" argument(s): ""$denied"""
        }

        # Not among this pin's cases; Get-DbaDbccProcCache's pin measured the same Stop-Function shape.
        It "keeps the warning and does not throw under -ErrorAction Stop" {
            $warnings = $null
            $result = Get-DbaDump -SqlInstance $loginInstance -SqlCredential $lowCred -ErrorAction Stop -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
        }
    }
}

Describe "Native Get-DbaDump on Azure SQL Database" -Tag IntegrationTests {
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
                # A paused serverless database answers 40613 or times out (-2, 258) while it resumes, and the lab's mobile
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
        $azureRefusal = "Azure SQL Database not supported"
    }

    # Read-only. sys.dm_server_memory_dumps applies to SQL Server only
    # (https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-server-memory-dumps-transact-sql),
    # so the command refuses Azure SQL Database at connect, as Connect-DbaInstance -AzureUnsupported does (correction azure-refusal),
    # instead of sending the query and reporting the missing view.
    It "refuses Azure SQL Database on a connection to the database, with a warning and no output" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $warnings = $null
        $result = @(Get-DbaDump -SqlInstance $azureServer -WarningVariable warnings -WarningAction SilentlyContinue)
        $result.Count | Should -Be 0
        ($warnings -join " ") | Should -BeLike "*$azureRefusal*"
        ($warnings -join " ") | Should -Not -BeLike "*sys.dm_server_memory_dumps*"
    }

    It "refuses Azure SQL Database on a connection by name, with a warning and no output" {
        $warnings = $null
        $result = @(Get-DbaDump -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -WarningVariable warnings -WarningAction SilentlyContinue)
        $result.Count | Should -Be 0
        ($warnings -join " ") | Should -BeLike "*$azureRefusal*"
        ($warnings -join " ") | Should -Not -BeLike "*sys.dm_server_memory_dumps*"
    }

    It "throws the Azure SQL Database refusal under -EnableException" {
        $record = $null
        try {
            $null = Get-DbaDump -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -EnableException -WarningAction SilentlyContinue
        } catch {
            $record = $PSItem
        }
        $record | Should -Not -BeNullOrEmpty
        $record.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDump*"
        "$($record.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
        $record.Exception.Message | Should -BeLike "*$azureRefusal*"
    }
}
