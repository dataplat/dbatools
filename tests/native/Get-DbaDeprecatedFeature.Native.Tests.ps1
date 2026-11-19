#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDeprecatedFeature",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads a performance counter view.

# Expected values below are as the pin measured on both editions: evidence/pin-deprecated-20261104.txt.
# A failed connect writes one warning line naming the server, where the pin writes two (bad-plain, no-credential): an accepted difference,
# harness-edits.md, "Script-scope preferences and the one-line connect warning", points 5 to 7.

BeforeAll {
    $featuresQuery = "SELECT LTRIM(RTRIM(instance_name)) AS DeprecatedFeature, cntr_value AS UsageCount FROM sys.dm_os_performance_counters WHERE object_name LIKE '%SQL%Deprecated Features%' AND cntr_value > 0"
    $pinnedNames = @("ComputerName", "InstanceName", "SqlInstance", "DeprecatedFeature", "UsageCount")
}

Describe "Native Get-DbaDeprecatedFeature" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $missingInstance = "nativedeprecated$(Get-Random)"
        # The fixture's connection is never given to the command. The pinned test uses a deprecated feature the same way.
        $server = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
        $null = $server.ConnectionContext.ExecuteWithResults("SELECT * FROM sys.sysdatabases")
    }

    AfterAll {
        $server.ConnectionContext.Disconnect()
    }

    Context "Output" {
        # shape, named: counters only rise while another session runs, so each row is compared with the independent read by name and by at least its count.
        It "returns one plain object per used feature, with the pinned properties in their order and the view's names and values" {
            $engine = @($server.ConnectionContext.ExecuteWithResults($featuresQuery).Tables[0].Rows)
            $engine.Count | Should -BeGreaterThan 0
            $result = @(Get-DbaDeprecatedFeature -SqlInstance $instance -EnableException)

            $result.Count | Should -BeGreaterOrEqual $engine.Count
            $result[0].PSObject.TypeNames[0] | Should -BeExactly "System.Management.Automation.PSCustomObject"
            $result[0].PSObject.Properties.Name | Should -BeExactly $pinnedNames
            $result[0].ComputerName | Should -BeExactly $server.ComputerName
            $result[0].InstanceName | Should -BeExactly $server.ServiceName
            $result[0].SqlInstance | Should -BeExactly $server.DomainInstanceName
            $result[0].DeprecatedFeature | Should -BeOfType [string]
            $result[0].UsageCount | Should -BeOfType [long]
            $result.DeprecatedFeature | Should -Contain "sysdatabases"

            foreach ($row in $engine) {
                $match = @($result | Where-Object DeprecatedFeature -ceq $row["DeprecatedFeature"])
                $match.Count | Should -BeGreaterThan 0
                ($match | Measure-Object -Property UsageCount -Maximum).Maximum | Should -BeGreaterOrEqual $row["UsageCount"]
            }
        }

        It "lists only features that were used, with their names trimmed" {
            foreach ($feature in @(Get-DbaDeprecatedFeature -SqlInstance $instance -EnableException)) {
                $feature.UsageCount | Should -BeGreaterThan 0
                $feature.DeprecatedFeature | Should -BeExactly $feature.DeprecatedFeature.Trim()
            }
        }

        It "reads through a server object" {
            $own = Connect-DbaInstance -SqlInstance $instance -EnableException
            $result = @($own | Get-DbaDeprecatedFeature -EnableException)
            $result.Count | Should -BeGreaterThan 0
            $result[0].SqlInstance | Should -BeExactly $own.DomainInstanceName
        }
    }

    Context "Instances" {
        # named-twice, piped-twice.
        It "reads each piped instance" -Tag "NativeChecklist:pipeline-multiple" {
            $once = @(Get-DbaDeprecatedFeature -SqlInstance $instance -EnableException).Count
            $twice = @($instance, $instance | Get-DbaDeprecatedFeature -EnableException).Count
            $twice | Should -BeGreaterOrEqual (2 * $once)
        }

        It "reads each instance of an array" {
            $once = @(Get-DbaDeprecatedFeature -SqlInstance $instance -EnableException).Count
            @(Get-DbaDeprecatedFeature -SqlInstance $instance, $instance -EnableException).Count | Should -BeGreaterOrEqual (2 * $once)
        }
    }

    Context "An instance that cannot be reached" {
        # bad-between, bad-ee.
        It "warns and goes on to the next instance" -Tag "NativeChecklist:multi-instance-failure" {
            $warnings = $null
            $results = @(Get-DbaDeprecatedFeature -SqlInstance $missingInstance, $instance -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -BeGreaterThan 0
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDeprecatedFeature\] Failure \| Error connecting to \[$missingInstance\]: "
        }

        It "warns and goes on under -EnableException:`$false" -Tag "NativeChecklist:switch-false" {
            $warnings = $null
            $results = @(Get-DbaDeprecatedFeature -SqlInstance $missingInstance, $instance -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -BeGreaterThan 0
            @($warnings).Count | Should -Be 1
        }

        It "throws the connection failure under -EnableException, before the next instance" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            $collected = $null
            $warnings = $null
            try {
                $null = Get-DbaDeprecatedFeature -SqlInstance $missingInstance, $instance -EnableException -OutVariable collected -WarningVariable warnings -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDeprecatedFeature\] Failure \| Error connecting to \[$missingInstance\]: "
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDeprecatedFeature*"
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
            $streamLine = "\[Get-DbaDeprecatedFeature\] Failure \| Error connecting to \[$missingInstance\]: "
            $streamState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $streamRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($streamState)
            $streamRunspace.Open()
            $streamShell = [System.Management.Automation.PowerShell]::Create()
            $streamShell.Runspace = $streamRunspace
            $streamModulePath = (Get-Module dbatools | Where-Object ModuleType -eq Script | Select-Object -First 1).Path
            $null = $streamShell.AddCommand("Import-Module").AddParameter("Name", $streamModulePath).AddParameter("ErrorAction", "Stop").Invoke()

            function NativeDeprecatedStreamCall {
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
            $call = NativeDeprecatedStreamCall -Script 'param($Target) Get-DbaDeprecatedFeature -SqlInstance $Target; "next statement"'
            $call.Warnings.Count | Should -Be 1
            $call.Warnings[0] | Should -Match $streamLine
            $call.Lines | Should -Contain "next statement"
        }

        It "merges the one line under 3>&1 on a plain call" {
            $call = NativeDeprecatedStreamCall -Script 'param($Target) Get-DbaDeprecatedFeature -SqlInstance $Target 3>&1; "next statement"'
            $call.Merged.Count | Should -Be 1
            $call.Merged[0] | Should -Match $streamLine
            $call.Warnings.Count | Should -Be 0
            $call.Lines | Should -Contain "next statement"
        }

        It "displays nothing under -EnableException, and -WarningVariable holds the one line" -Tag "NativeChecklist:enable-exception" {
            $call = NativeDeprecatedStreamCall -Script 'param($Target) try { Get-DbaDeprecatedFeature -SqlInstance $Target -EnableException -WarningVariable held 3>&1 } catch { "caught " + $PSItem.FullyQualifiedErrorId }; "held " + @($held).Count; foreach ($line in $held) { "line " + $line }'
            $call.Merged.Count | Should -Be 0
            $call.Warnings.Count | Should -Be 0
            @($call.Lines | Where-Object { $PSItem -like "caught dbatools_Get-DbaDeprecatedFeature*" }).Count | Should -Be 1
            $call.Lines | Should -Contain "held 1"
            @($call.Lines | Where-Object { $PSItem -like "line *" -and $PSItem -match $streamLine }).Count | Should -Be 1
        }

        It "leaves the warning stream empty under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $call = NativeDeprecatedStreamCall -Script 'param($Target) try { Get-DbaDeprecatedFeature -SqlInstance $Target -EnableException } catch { "caught " + $PSItem.FullyQualifiedErrorId }'
            $call.Warnings.Count | Should -Be 0
            @($call.Lines | Where-Object { $PSItem -like "caught dbatools_Get-DbaDeprecatedFeature*" }).Count | Should -Be 1
        }

        # piped-null: the engine writes the binder's record for that one input and the instances beside it are still read.
        It "writes the binder's record for a piped null, and reads the instances beside it" {
            $expected = @(Get-DbaDeprecatedFeature -SqlInstance $instance -EnableException).Count
            $streamShell.Commands.Clear()
            $streamShell.Streams.Error.Clear()
            $null = $streamShell.AddScript('param($Target) @($Target, $null, $Target | Get-DbaDeprecatedFeature).Count; "next statement"').AddArgument($instance)
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
        # named-null-element: the command's own binder refuses it.
        It "refuses <Name> at the binder, with no warning and no output" -ForEach @(
            @{ Name = "a null element"; Value = @($null, "unused"); Id = "ParameterArgumentValidationErrorNullNotAllowed"; Reason = "is null" }
            @{ Name = "a null value"; Value = $null; Id = "ParameterArgumentValidationErrorNullNotAllowed"; Reason = "is null" }
            @{ Name = "an empty array"; Value = @(); Id = "ParameterArgumentValidationErrorEmptyArrayNotAllowed"; Reason = "is an empty array" }
        ) {
            $caught = $null
            $warnings = $null
            $collected = $null
            try {
                $null = Get-DbaDeprecatedFeature -SqlInstance $Value -OutVariable collected -WarningVariable warnings -WarningAction SilentlyContinue
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

Describe "Native Get-DbaDeprecatedFeature on Azure SQL Database" -Tag IntegrationTests {
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
                # A paused serverless database answers 40613 or times out (-2, 258) while it resumes, and the lab's mobile internet can drop a name lookup (11001, "No such host is known").
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

    # azure-connection, azure-by-name: read-only. The instance name is null there, and how many counters have been used depends on the database's last resume, so an independent read decides.
    It "returns the counters on a connection to the database, and leaves it there" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $engine = @($azureServer.ConnectionContext.ExecuteWithResults($featuresQuery).Tables[0].Rows)
        $warnings = $null
        $result = @(Get-DbaDeprecatedFeature -SqlInstance $azureServer -WarningVariable warnings -WarningAction SilentlyContinue)
        @($warnings).Count | Should -Be 0
        $result.Count | Should -BeGreaterOrEqual $engine.Count
        foreach ($row in $result) {
            $row.PSObject.Properties.Name | Should -BeExactly $pinnedNames
            $row.ComputerName | Should -BeExactly $azureServer.ComputerName
            $row.InstanceName | Should -BeNullOrEmpty
            $row.SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
            $row.UsageCount | Should -BeOfType [long]
        }
        $azureServer.ConnectionContext.CurrentDatabase | Should -BeExactly $TestConfig.AzureSqlDbName
    }

    It "returns the counters on a connection by name" {
        $warnings = $null
        $result = @(Get-DbaDeprecatedFeature -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -WarningVariable warnings -WarningAction SilentlyContinue)
        @($warnings).Count | Should -Be 0
        foreach ($row in $result) {
            $row.PSObject.Properties.Name | Should -BeExactly $pinnedNames
            $row.InstanceName | Should -BeNullOrEmpty
        }
    }
}

Describe "Native Get-DbaDeprecatedFeature over SQL authentication" -Tag IntegrationTests {
    BeforeAll {
        $loginInstance = $TestConfig.InstanceSqlLogin
        $loginCred = $TestConfig.SqlLoginCred
        # Unique per leg and run: the instance is shared.
        $stamp = Get-Random
        $homeName = "dbatoolsci_ndep_home_$stamp"
        $lowName = "dbatoolsci_ndep_low_$stamp"
        $lowPassword = "Ndep-$([guid]::NewGuid().ToString('N'))"
        $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
        $denied = "An exception occurred while executing a Transact-SQL statement or batch.VIEW SERVER PERFORMANCE STATE permission was denied on object 'server', database 'master'.`r`nThe user does not have permission to perform this action."

        # The instance is shared, so a fixture statement can be a deadlock victim; only error 1205 is tried again, a bounded number of times, and never a call of the command or an assertion.
        # -Finished names the one server error that means the statement has nothing left to do.
        function Invoke-NativeFixtureStatement {
            param([string]$Text, [int]$Finished = 0)
            for ($attempt = 1; ; $attempt++) {
                try {
                    return $fixture.ConnectionContext.ExecuteNonQuery($Text)
                } catch {
                    $numbers = @()
                    for ($cause = $PSItem.Exception; $null -ne $cause; $cause = $cause.InnerException) {
                        if ($cause.PSObject.Properties["Number"]) { $numbers += $cause.Number }
                    }
                    if ($Finished -ne 0 -and $numbers -contains $Finished) { return }
                    if ($numbers -notcontains 1205 -or $attempt -ge 5) { throw }
                    Start-Sleep -Seconds 2
                }
            }
        }

        # A plain call in a runspace of its own, so no try of Pester's encloses it, with a next statement after it. -Values pipes them in.
        function Invoke-NativeOutsideTry {
            param([hashtable]$Arguments = @{ }, [object[]]$Values)
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaDeprecatedFeature -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaDeprecatedFeature", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $outsideStop = $null
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                if ($Values) {
                    $null = $outsideShell.AddScript('param($Arguments, $Values) $Values | Get-DbaDeprecatedFeature @Arguments; "next statement"').AddArgument($Arguments).AddArgument($Values)
                } else {
                    $null = $outsideShell.AddScript('param($Arguments) Get-DbaDeprecatedFeature @Arguments; "next statement"').AddArgument($Arguments)
                }
                try {
                    $null = $outsideShell.Invoke($null, $outsideOutput)
                } catch {
                    # The stop leaves the runspace's script through Invoke, as a method call's exception.
                    $outsideStop = $PSItem.Exception.InnerException
                }
                [pscustomobject]@{
                    Rows     = @($outsideOutput | Where-Object { $null -ne $PSItem.PSObject.Properties["DeprecatedFeature"] })
                    Next     = @($outsideOutput | Where-Object { "$($PSItem.PSObject.BaseObject)" -ceq "next statement" }).Count -gt 0
                    Errors   = @($outsideShell.Streams.Error)
                    Warnings = @($outsideShell.Streams.Warning)
                    Stop     = $outsideStop
                }
            } finally {
                $outsideShell.Dispose()
                $outsideRunspace.Dispose()
            }
        }

        # The record of the $server.Query that faulted, as low-plain measured it.
        function Assert-NativeDeniedRecord {
            param($Record)
            $Record.FullyQualifiedErrorId | Should -BeLike "ScriptMethodRuntimeException*"
            "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
            $Record.CategoryInfo.Reason | Should -BeExactly "MethodInvocationException"
            $Record.TargetObject | Should -BeNullOrEmpty
            $Record.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.MethodInvocationException"
            $Record.Exception.Message | Should -BeExactly "Exception calling `"Query`" with `"1`" argument(s): `"$denied`""
            $Record.Exception.InnerException.GetType().FullName | Should -BeExactly "System.Management.Automation.RuntimeException"
            $Record.Exception.InnerException.Message | Should -BeExactly $denied
            $Record.Exception.InnerException.InnerException.GetType().FullName | Should -BeExactly "System.Management.Automation.RuntimeException"
            $Record.Exception.InnerException.InnerException.Message | Should -BeExactly $denied
        }

        # The fixture's connections below are passed only where a test names them.
        $fixture = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -NonPooledConnection -EnableException
        $null = Invoke-NativeFixtureStatement "USE [master]; CREATE DATABASE [$homeName];"
        $null = Invoke-NativeFixtureStatement "USE [master]; CREATE LOGIN [$lowName] WITH PASSWORD = '$lowPassword', CHECK_POLICY = OFF;"
        $null = Invoke-NativeFixtureStatement "USE [$homeName]; CREATE USER [$lowName] FOR LOGIN [$lowName]; USE [master];"
        $null = $fixture.ConnectionContext.ExecuteWithResults("SELECT * FROM sys.sysdatabases")
        $goodConnection = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -NonPooledConnection -EnableException
        $lowConnection = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $lowCred -NonPooledConnection -EnableException
    }

    AfterAll {
        $goodConnection.ConnectionContext.Disconnect()
        $lowConnection.ConnectionContext.Disconnect()
        [Microsoft.Data.SqlClient.SqlConnection]::ClearAllPools()
        foreach ($row in @($fixture.ConnectionContext.ExecuteWithResults("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$lowName';").Tables[0].Rows)) {
            # A session this block has just disconnected can end between the read above and this KILL: error 6106, as on the 2022 7 leg of result 20261104T1330554703653Z, and then it needs no KILL.
            $null = Invoke-NativeFixtureStatement "KILL $($row["session_id"]);" -Finished 6106
        }
        $null = Invoke-NativeFixtureStatement "IF DB_ID(N'$homeName') IS NOT NULL BEGIN ALTER DATABASE [$homeName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$homeName]; END;"
        $null = Invoke-NativeFixtureStatement "IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];"
        $fixture.ConnectionContext.Disconnect()
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        It "works with -SqlCredential" {
            $result = @(Get-DbaDeprecatedFeature -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException)
            $result.Count | Should -BeGreaterThan 0
            $result[0].UsageCount | Should -BeOfType [long]
        }

        # no-credential.
        It "fails cleanly without the credential: a warning and no output" {
            $warnings = $null
            $result = Get-DbaDeprecatedFeature -SqlInstance $loginInstance -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match ("\[Get-DbaDeprecatedFeature\] Failure \| Error connecting to \[" + [regex]::Escape($loginInstance) + "\]: Login failed")
        }

        # no-credential-ee.
        It "throws the connection failure under -EnableException" {
            { Get-DbaDeprecatedFeature -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue } | Should -Throw -ExpectedMessage "*Login failed*" -ErrorId "dbatools_Get-DbaDeprecatedFeature*"
        }
    }

    Context "A login that may not read the counters" {
        # low-plain.
        It "outside any try, writes the pinned record and goes on" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $lowConnection }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeDeniedRecord -Record $outside.Errors[0]
            $outside.Rows.Count | Should -Be 0
            $outside.Warnings.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        # low-silent.
        It "outside any try, -ErrorAction SilentlyContinue writes no record and goes on" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $lowConnection; ErrorAction = "SilentlyContinue" }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        # low-ee: the pin writes the record and goes on; an accepted difference, the keep-going section's point 3.
        It "outside any try, -EnableException ends the command at the record and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($lowConnection, $goodConnection); EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeDeniedRecord -Record $outside.Errors[0]
            $outside.Rows.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        # low-stop: an accepted difference, the stop PowerShell gives WriteError.
        It "outside any try, -ErrorAction Stop turns the record into the stop PowerShell gives WriteError" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $lowConnection; ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outside.Next | Should -BeFalse
        }

        # low-try, low-ee-try, by name as the pin was measured.
        It "inside a caller's try, the catch receives the record and the command does not go on" {
            foreach ($splat in @{ }, @{ EnableException = $true }) {
                $failure = $null
                $after = $false
                try {
                    $null = Get-DbaDeprecatedFeature -SqlInstance $loginInstance -SqlCredential $lowCred @splat
                    $after = $true
                } catch {
                    $failure = $PSItem
                }
                Assert-NativeDeniedRecord -Record $failure
                $after | Should -BeFalse
            }
        }

        # low-stop-try.
        It "inside a caller's try, -ErrorAction Stop reaches the catch" {
            $failure = $null
            try {
                $null = Get-DbaDeprecatedFeature -SqlInstance $lowConnection -ErrorAction Stop
            } catch {
                $failure = $PSItem
            }
            Assert-NativeDeniedRecord -Record $failure
        }

        # stale-low-then-good: an instance after the fault is read as usual.
        It "goes on to the next instance after the record" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($lowConnection, $goodConnection) }
            $outside.Errors.Count | Should -Be 1
            $outside.Rows.Count | Should -BeGreaterThan 0
            $outside.Next | Should -BeTrue
        }

        # Correction stale-rows: stale-good-then-low wrote the first instance's rows again under the name of the instance that failed.
        It "writes no rows for an instance whose read failed, after an instance given by name" {
            $alone = @(Get-DbaDeprecatedFeature -SqlInstance $goodConnection -EnableException).Count
            $alone | Should -BeGreaterThan 0
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($goodConnection, $lowConnection) }
            $outside.Errors.Count | Should -Be 1
            $outside.Rows.Count | Should -BeGreaterOrEqual $alone
            $outside.Rows.Count | Should -BeLessThan (2 * $alone)
            $outside.Next | Should -BeTrue
        }

        # Correction stale-rows: stale-piped-good-then-low, across process blocks.
        It "writes no rows for an instance whose read failed, after a piped instance" {
            $alone = @(Get-DbaDeprecatedFeature -SqlInstance $goodConnection -EnableException).Count
            $alone | Should -BeGreaterThan 0
            $outside = Invoke-NativeOutsideTry -Values @($goodConnection, $lowConnection)
            $outside.Errors.Count | Should -Be 1
            $outside.Rows.Count | Should -BeGreaterOrEqual $alone
            $outside.Rows.Count | Should -BeLessThan (2 * $alone)
            $outside.Next | Should -BeTrue
        }
    }

    # caller-home, caller-denied: the query runs on the connection as it stands, with no switch of database, so denied CONNECT on its home database changes nothing.
    Context "A caller's connection in its own database" {
        It "reports the same record, and stays there" {
            $caller = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $lowCred -Database $homeName -NonPooledConnection -EnableException
            try {
                $outside = Invoke-NativeOutsideTry @{ SqlInstance = $caller }
                $outside.Errors.Count | Should -Be 1
                Assert-NativeDeniedRecord -Record $outside.Errors[0]
                $caller.ConnectionContext.CurrentDatabase | Should -BeExactly $homeName
            } finally {
                $caller.ConnectionContext.Disconnect()
            }
        }

        It "reports the same record with CONNECT denied there, and no restore warning" {
            $caller = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $lowCred -Database $homeName -NonPooledConnection -EnableException
            try {
                $null = $caller.ConnectionContext.ExecuteScalar("SELECT 1;")
                $null = Invoke-NativeFixtureStatement "USE [$homeName]; DENY CONNECT TO [$lowName]; USE [master];"
                $outside = Invoke-NativeOutsideTry @{ SqlInstance = $caller }
                $outside.Errors.Count | Should -Be 1
                Assert-NativeDeniedRecord -Record $outside.Errors[0]
                $outside.Warnings.Count | Should -Be 0
                $outside.Next | Should -BeTrue
            } finally {
                $caller.ConnectionContext.Disconnect()
                $null = Invoke-NativeFixtureStatement "USE [$homeName]; GRANT CONNECT TO [$lowName]; USE [master];"
            }
        }
    }
}
