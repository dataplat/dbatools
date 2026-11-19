#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Enable-DbaTraceFlag",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

BeforeDiscovery {
    # The manager approved the 2019 lane, whose editions run sequentially, for shared global state.
    $nativeTraceSharedLane = [string]$TestConfig.Temp -match '-2019$'
}

Describe "Native Enable-DbaTraceFlag" -Tag IntegrationTests {
    BeforeAll {
        function Test-NativeGlobalFlag($server, [int]$flag) {
            $data = $server.ConnectionContext.ExecuteWithResults("DBCC TRACESTATUS(-1)")
            try {
                return @($data.Tables[0].Rows | Where-Object { $_.TraceFlag -eq $flag -and $_.Global -eq 1 -and $_.Status -eq 1 }).Count -gt 0
            } finally { $data.Dispose() }
        }
        function New-NativeTraceFixture($instance, $credential) {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $credential -EnableException
            # 2528 disables parallel DBCC checks; it changes no data and avoids the pin's 3226 fixture.
            $flag = 2528
            [pscustomobject]@{ Server = $server; Flag = $flag; InitiallyOn = (Test-NativeGlobalFlag $server $flag) }
        }
        function Remove-NativeTraceFixture($fixture) {
            if (-not $fixture.InitiallyOn) { $fixture.Server.ConnectionContext.ExecuteNonQuery("DBCC TRACEOFF($($fixture.Flag), -1)") }
            (Test-NativeGlobalFlag $fixture.Server $fixture.Flag) | Should -Be $fixture.InitiallyOn
        }
        function Assert-NativeTraceEnabled($fixture, $output) {
            @($output).Count | Should -Be 1
            $output = @($output)[0]
            $output.TraceFlag | Should -Be $fixture.Flag
            if ($fixture.InitiallyOn) { $output.Status | Should -BeExactly 'Skipped' }
            else { $output.Status | Should -BeExactly 'Successful' }
            $output.SourceServer | Should -Not -BeNullOrEmpty
            $output.InstanceName | Should -Not -BeNullOrEmpty
            $output.SqlInstance | Should -Not -BeNullOrEmpty
            $output.DateTime | Should -BeOfType Dataplat.Dbatools.Utility.DbaDateTime
            (@($output.PSObject.Properties.Name) -join ',') | Should -BeExactly 'SourceServer,InstanceName,SqlInstance,TraceFlag,Status,Notes,DateTime'
            (Test-NativeGlobalFlag $fixture.Server $fixture.Flag) | Should -BeTrue
        }
        $nativeTraceBadInstance = 'Data Source=localhost,1;Initial Catalog=master;Integrated Security=True;Connect Timeout=1;Encrypt=False'
    }

    It "honors WhatIf then enables and independently reads the global flag" -Tag 'NativeChecklist:whatif-confirm', 'NativeChecklist:switch-false' {
        $fixture = New-NativeTraceFixture $TestConfig.InstanceSingle $null
        try {
            $preview = @(Enable-DbaTraceFlag -SqlInstance $fixture.Server -TraceFlag $fixture.Flag -WhatIf -Confirm:$false -EnableException -WarningAction SilentlyContinue)
            if ($fixture.InitiallyOn) { $preview[0].Status | Should -BeExactly 'Skipped' }
            else { $preview.Count | Should -Be 0 }
            (Test-NativeGlobalFlag $fixture.Server $fixture.Flag) | Should -Be $fixture.InitiallyOn
            $output = Enable-DbaTraceFlag -SqlInstance $fixture.Server -TraceFlag $fixture.Flag -WhatIf:$false -Confirm:$false -EnableException -WarningAction SilentlyContinue
            Assert-NativeTraceEnabled $fixture $output
        } finally { Remove-NativeTraceFixture $fixture }
    }

    It "writes an already-running result before its warning even with WhatIf" {
        $fixture = New-NativeTraceFixture $TestConfig.InstanceSingle $null
        try {
            $fixture.Server.ConnectionContext.ExecuteNonQuery("DBCC TRACEON($($fixture.Flag), -1)")
            $records = @(Enable-DbaTraceFlag -SqlInstance $fixture.Server -TraceFlag $fixture.Flag -WhatIf -Confirm:$false -EnableException -WarningAction Continue 3>&1)
            $records.Count | Should -Be 2
            $records[0].Status | Should -BeExactly 'Skipped'
            $records[0].Notes | Should -BeExactly 'The Trace flag is already running.'
            $records[1] | Should -BeOfType System.Management.Automation.WarningRecord
            $records[1].Message.Contains('The Trace flag [2528] is already running globally.') | Should -BeTrue
            (Test-NativeGlobalFlag $fixture.Server $fixture.Flag) | Should -BeTrue
        } finally { Remove-NativeTraceFixture $fixture }
    }

    It "continues after a failed pipeline instance when EnableException is false" -Tag 'NativeChecklist:pipeline-multiple', 'NativeChecklist:multi-instance-failure', 'NativeChecklist:enable-exception' {
        $fixture = New-NativeTraceFixture $TestConfig.InstanceSingle $null
        try {
            $warnings = @()
            $output = @(@($nativeTraceBadInstance, $TestConfig.InstanceSingle) | Enable-DbaTraceFlag -TraceFlag $fixture.Flag -EnableException:$false -Confirm:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            Assert-NativeTraceEnabled $fixture $output
            $warnings | Should -Not -BeNullOrEmpty
        } finally { Remove-NativeTraceFixture $fixture }
    }

    It "preserves a prior pipeline result when the next connection terminates" -Tag 'NativeChecklist:enable-exception' {
        $fixture = New-NativeTraceFixture $TestConfig.InstanceSingle $null
        try {
            $seen = New-Object System.Collections.ArrayList
            $failure = $null
            try {
                @($TestConfig.InstanceSingle, $nativeTraceBadInstance) | Enable-DbaTraceFlag -TraceFlag $fixture.Flag -EnableException -Confirm:$false -WarningAction SilentlyContinue | ForEach-Object { $null = $seen.Add($_) }
            } catch { $failure = $_ }
            $seen.Count | Should -Be 1
            Assert-NativeTraceEnabled $fixture $seen[0]
            $failure | Should -Not -BeNullOrEmpty
            $failure.FullyQualifiedErrorId | Should -BeLike 'dbatools_Enable-DbaTraceFlag*'
        } finally { Remove-NativeTraceFixture $fixture }
    }

    It "rejects the SQL-login target without credentials on every leg" -Tag 'NativeChecklist:sql-login' {
        $warnings = @()
        # Pin public/Enable-DbaTraceFlag.ps1:87-92 (verbatim):
        # foreach ($instance in $SqlInstance) {
        #     try {
        #         $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        #     } catch {
        #         Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        #     }
        # The base already ships a compiled wrapper and the upstream pin predates src/:
        # no buildable commit runs the pinned function. Excerpt route: watchman 63b67fd6.
        @(Enable-DbaTraceFlag -SqlInstance $TestConfig.InstanceSqlLogin -TraceFlag 2528 -WhatIf -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
        $warnings | Should -Not -BeNullOrEmpty
        # Pin public/Enable-DbaTraceFlag.ps1:87-92 (verbatim):
        # foreach ($instance in $SqlInstance) {
        #     try {
        #         $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        #     } catch {
        #         Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        #     }
        # The base already ships a compiled wrapper and the upstream pin predates src/:
        # no buildable commit runs the pinned function. Excerpt route: watchman 63b67fd6.
        # Its own Stop-Function observes EnableException and terminates; no nested-call inference.
        { Enable-DbaTraceFlag -SqlInstance $TestConfig.InstanceSqlLogin -TraceFlag 2528 -WhatIf -EnableException } | Should -Throw
    }

    It "authenticates with SQL credentials without changing shared global state on every leg" -Tag 'NativeChecklist:sql-login' {
        $fixture = New-NativeTraceFixture $TestConfig.InstanceSqlLogin $TestConfig.SqlLoginCred
        # The 2019 lane can toggle 2528 concurrently. Preview an absent flag instead.
        $fixture.Flag = [int]::MaxValue
        $fixture.InitiallyOn = Test-NativeGlobalFlag $fixture.Server $fixture.Flag
        $warnings = @()
        $output = @(Enable-DbaTraceFlag -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -TraceFlag $fixture.Flag -WhatIf -Confirm:$false -EnableException -WarningAction SilentlyContinue -WarningVariable warnings)
        if ($fixture.InitiallyOn) {
            $output.Count | Should -Be 1
            $output[0].Status | Should -BeExactly 'Skipped'
        } else { $output.Count | Should -Be 0 }
        ($warnings -join ' ') | Should -Not -Match 'Failure'
        (Test-NativeGlobalFlag $fixture.Server $fixture.Flag) | Should -Be $fixture.InitiallyOn
    }

    if ($nativeTraceSharedLane) {
        It "enables and restores a global flag using SQL authentication on the shared lane" -Tag 'NativeChecklist:sql-login' {
            $fixture = New-NativeTraceFixture $TestConfig.InstanceSqlLogin $TestConfig.SqlLoginCred
            try {
                $output = Enable-DbaTraceFlag -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -TraceFlag $fixture.Flag -Confirm:$false -EnableException -WarningAction SilentlyContinue
                Assert-NativeTraceEnabled $fixture $output
            } finally { Remove-NativeTraceFixture $fixture }
        }


    }

    It "never attempts TRACEON after a capture-mode active-flag read failure" {
        # Real SMO CaptureSql fixture measured against the full pin on both editions:
        # Get-DbaTraceFlag:90 faults and Enable-DbaTraceFlag:94 continues into TRACEON.
        # Watchman d4082586 and 9acc0c64 require a separate no-TRACEON correction proof.
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -ErrorAction Stop
        $context = $server.ConnectionContext
        $prior = $context.SqlExecutionModes
        $initiallyOn = Test-NativeGlobalFlag $server 2528
        if ($initiallyOn) {
            $context.Disconnect()
            throw 'Refusing capture fixture: trace flag 2528 is already enabled.'
        }
        $runspace = $null
        $shell = $null
        try {
            $context.SqlExecutionModes = [Microsoft.SqlServer.Management.Common.SqlExecutionModes]::CaptureSql
            $directFailure = $null
            try { $null = $server.EnumActiveGlobalTraceFlags() } catch { $directFailure = $_ }
            $directFailure | Should -Not -BeNullOrEmpty
            $directFailure.Exception.Message | Should -Match 'EnumActiveGlobalTraceFlags'
            $context.CapturedSql.Clear()

            # The subject call has no caller try or inherited Pester preferences.
            $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
            $runspace.Open()
            $shell = [System.Management.Automation.PowerShell]::Create()
            $shell.Runspace = $runspace
            $manifest = Join-Path (Get-Module dbatools).ModuleBase 'dbatools.psd1'
            $call = {
                param($Module, $Target)
                Import-Module $Module -Force -ErrorAction Stop
                $ErrorActionPreference = 'Continue'
                if ((Get-Command Enable-DbaTraceFlag).CommandType -ne 'Cmdlet') { throw 'Native command required.' }
                Enable-DbaTraceFlag -SqlInstance $Target -TraceFlag 2528 -EnableException:$false -Confirm:$false -ErrorAction Continue
            }
            $null = $shell.AddScript($call.ToString()).AddArgument($manifest).AddArgument($server)
            try { $null = $shell.Invoke() } catch { }
            # The deletion-only before may swallow the method record. Verify that the subject
            # reached the real read, then let the guard assertion detect its unsafe continuation.
            @($context.CapturedSql.Text | Where-Object { $_ -match '\bDBCC\s+TRACESTATUS\s*\(' }).Count | Should -BeGreaterThan 0
            @($context.CapturedSql.Text | Where-Object { $_ -match '\bDBCC\s+TRACEON\s*\(' }).Count | Should -Be 0
        } finally {
            if ($shell) { $shell.Dispose() }
            if ($runspace) { $runspace.Dispose() }
            $context.SqlExecutionModes = $prior
            $context.Disconnect()
            # A separate normal-execution connection independently verifies and restores state.
            $cleanup = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -ErrorAction Stop
            try {
                $cleanup.ConnectionContext.SqlExecutionModes = [Microsoft.SqlServer.Management.Common.SqlExecutionModes]::ExecuteSql
                $wasEnabled = Test-NativeGlobalFlag $cleanup 2528
                if ($wasEnabled) { $cleanup.ConnectionContext.ExecuteNonQuery('DBCC TRACEOFF(2528, -1)') }
                (Test-NativeGlobalFlag $cleanup 2528) | Should -BeFalse
                $wasEnabled | Should -BeFalse
            } finally { $cleanup.ConnectionContext.Disconnect() }
        }
    }

    Context "when reading the active flags fails" {
        BeforeAll {
            function Get-TraceEntrySequence($entries) {
                @(foreach ($entry in $entries) {
                    $record = if ($entry -is [System.Management.Automation.ErrorRecord]) { $entry } else { $entry.ErrorRecord }
                    "$($entry.GetType().Name):$($record.FullyQualifiedErrorId)"
                }) -join "|"
            }
            function Get-TraceExceptionChain($record) {
                @(for ($ex = $record.Exception; $ex; $ex = $ex.InnerException) {
                    "$($ex.GetType().FullName) $($ex.Message)"
                }) -join " <- "
            }
        }

        It "reports the method fault and handles the next instance under <Mode>" -ForEach @(
            @{ Mode = "plain" }
            @{ Mode = "try" }
            @{ Mode = "quiet" }
            @{ Mode = "stop" }
            @{ Mode = "enable" }
        ) {
            $bad = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -ErrorAction Stop
            $good = $null
            $runspace = $null
            $shell = $null
            try {
                $good = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -ErrorAction Stop
                $bad.ConnectionContext.SqlExecutionModes = [Microsoft.SqlServer.Management.Common.SqlExecutionModes]::CaptureSql
                $good.ConnectionContext.SqlExecutionModes = [Microsoft.SqlServer.Management.Common.SqlExecutionModes]::ExecuteAndCaptureSql
                $reference = $null
                try { $null = $bad.EnumActiveGlobalTraceFlags() } catch { $reference = $PSItem }
                $reference.FullyQualifiedErrorId | Should -BeExactly "NullReferenceException"
                $bad.ConnectionContext.CapturedSql.Clear()
                $good.ConnectionContext.CapturedSql.Clear()

                # Run outside Pester's enclosing try so only the explicit caller try can catch the fault.
                $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
                $runspace.Open()
                $shell = [System.Management.Automation.PowerShell]::Create()
                $shell.Runspace = $runspace
                $call = {
                    param($Module, $First, $Second, $Mode)
                    Import-Module $Module -Force -ErrorAction Stop
                    $ErrorActionPreference = "Continue"
                    $options = @{ SqlInstance = @($First, $Second); TraceFlag = 2528; WhatIf = $true; ErrorVariable = "traceEntries" }
                    if ($Mode -eq "quiet") { $options.ErrorAction = "SilentlyContinue" }
                    if ($Mode -eq "stop") { $options.ErrorAction = "Stop" }
                    if ($Mode -eq "enable") { $options.EnableException = $true }
                    $traceEntries = @()
                    $traceCaught = $null
                    $traceNext = $false
                    $global:Error.Clear()
                    if ($Mode -eq "try") {
                        try { Enable-DbaTraceFlag @options } catch { $traceCaught = $PSItem }
                    } else {
                        Enable-DbaTraceFlag @options
                    }
                    $traceNext = $true
                }
                $manifest = Join-Path (Get-Module dbatools).ModuleBase "dbatools.psd1"
                $null = $shell.AddScript($call.ToString(), $false).AddArgument($manifest).AddArgument($bad).AddArgument($good).AddArgument($Mode)
                try { $null = $shell.Invoke() } catch { if ($Mode -ne "stop") { throw } }
                $proxy = $runspace.SessionStateProxy
                $caught = $proxy.GetVariable("traceCaught")
                $history = $proxy.GetVariable("Error")
                $entries = $proxy.GetVariable("traceEntries")
                $methodId = "NullReferenceException,Dataplat.Dbatools.Commands.EnableDbaTraceFlagCommand"
                $bare = "ErrorRecord:$methodId"
                $terminating = "CmdletInvocationException:$methodId"
                $shouldContinue = $Mode -in "plain", "quiet"
                $readPattern = "\bDBCC\s+TRACESTATUS\s*\("
                @($bad.ConnectionContext.CapturedSql.Text -match $readPattern).Count | Should -BeGreaterThan 0
                (@($good.ConnectionContext.CapturedSql.Text -match $readPattern).Count -gt 0) | Should -Be $shouldContinue
                @($good.ConnectionContext.CapturedSql.Text -match "\bDBCC\s+TRACEON\s*\(").Count | Should -Be 0
                $expectedStream = if ($Mode -in "plain", "enable") { $bare } else { "" }
                $expectedEntries = if ($shouldContinue) { $bare } elseif ($Mode -eq "stop") { "ActionPreferenceStopException:$methodId" } else { $terminating }
                $expectedHistory = if ($Mode -eq "stop") { "ActionPreferenceStopException:$methodId|$bare" } else { $bare }
                (Get-TraceEntrySequence $shell.Streams.Error) | Should -BeExactly $expectedStream
                (Get-TraceEntrySequence $entries) | Should -BeExactly $expectedEntries
                (Get-TraceEntrySequence $history) | Should -BeExactly $expectedHistory
                $proxy.GetVariable("traceNext") | Should -Be ($Mode -ne "stop")
                if ($Mode -eq "try") {
                    $caught.FullyQualifiedErrorId | Should -BeExactly $methodId
                } else {
                    $caught | Should -BeNullOrEmpty
                }
                $records = @($history[$history.Count - 1]) + @($shell.Streams.Error)
                if ($caught) { $records += $caught }
                foreach ($record in $records) {
                    $record.FullyQualifiedErrorId | Should -BeExactly $methodId
                    $record.CategoryInfo.Activity | Should -BeExactly "Enable-DbaTraceFlag"
                    $record.CategoryInfo.Category | Should -Be $reference.CategoryInfo.Category
                    $record.CategoryInfo.Reason | Should -BeExactly $reference.CategoryInfo.Reason
                    $record.CategoryInfo.TargetName | Should -BeExactly $reference.CategoryInfo.TargetName
                    $record.CategoryInfo.TargetType | Should -BeExactly $reference.CategoryInfo.TargetType
                    $record.TargetObject | Should -Be $reference.TargetObject
                    (Get-TraceExceptionChain $record) | Should -BeExactly (Get-TraceExceptionChain $reference)
                }
            } finally {
                if ($shell) { $shell.Dispose() }
                if ($runspace) { $runspace.Dispose() }
                if ($good) { $good.ConnectionContext.Disconnect() }
                $bad.ConnectionContext.Disconnect()
            }
        }
    }

    It "refuses Azure SQL Database before enabling global trace flags" -Tag 'NativeChecklist:azure-sqldb' {
        $azure = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -Database $TestConfig.AzureSqlDbName -EnableException
                break
            } catch {
                $errorException = $_.Exception
                $resuming = $false
                while ($errorException) {
                    if ($errorException.Number -in 40613, -2 -or $errorException -is [System.TimeoutException] -or $errorException.Message -match 'timed out|timeout|wait operation') { $resuming = $true }
                    $errorException = $errorException.InnerException
                }
                if (-not $resuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        try {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly 'SqlDatabase'
            $warnings = @()
            @(Enable-DbaTraceFlag -SqlInstance $azure -TraceFlag 2528 -Confirm:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            ($warnings -join ' ') | Should -Match 'Azure SQL Database not supported'
            { Enable-DbaTraceFlag -SqlInstance $azure -TraceFlag 2528 -Confirm:$false -EnableException } | Should -Throw '*Azure SQL Database not supported*'
        } finally { $azure.ConnectionContext.Disconnect() }
    }
}
