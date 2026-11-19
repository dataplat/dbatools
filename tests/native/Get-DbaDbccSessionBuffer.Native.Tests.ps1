#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbccSessionBuffer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads DBCC INPUTBUFFER and OUTPUTBUFFER.

# Expected values below are as the pin measured on both editions: evidence/pin-sessionbuffer-20261103.txt. The case names in the comments are that file's.
# A failed connect writes one warning line naming the server, where the pin writes two: an accepted difference, harness-edits.md, "Script-scope preferences and the one-line
# connect warning", points 5 to 7. Other lanes open and close sessions on the same instances, so no -All test here counts sessions or warnings exactly.

Describe "Native Get-DbaDbccSessionBuffer" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $missingInstance = "nativesessionbuffer$(Get-Random)"
        $idleBatch = "SELECT @@SPID AS spid, REPLICATE('dbatoolsci.dot.text ', 100) AS marker"

        # The reader of the independent values; never given to the command unless a test says so.
        $server = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
        # A session that stays idle after its one batch, so that both of its buffers hold still between two reads.
        $idle = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
        $idleSpid = [int]$idle.ConnectionContext.ExecuteWithResults($idleBatch).Tables[0].Rows[0].spid

        function Read-NativeSessionDump {
            param([int]$Target)
            foreach ($row in $server.ConnectionContext.ExecuteWithResults("DBCC OUTPUTBUFFER($Target) WITH NO_INFOMSGS").Tables[0].Rows) {
                $row[0].ToString()
            }
        }

        function Read-NativeVerboseLines {
            param([hashtable]$Arguments)
            @(Get-DbaDbccSessionBuffer @Arguments -Verbose 4>&1 | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message })
        }
    }

    AfterAll {
        $idle.ConnectionContext.Disconnect()
        $server.ConnectionContext.Disconnect()
    }

    Context "Input buffer" {
        It "returns one plain object per row, with the pinned properties in their order and the row's values" {
            $engine = $server.ConnectionContext.ExecuteWithResults("DBCC INPUTBUFFER($idleSpid) WITH NO_INFOMSGS").Tables[0]
            $result = @(Get-DbaDbccSessionBuffer -SqlInstance $instance -Operation InputBuffer -SessionId $idleSpid -EnableException)

            $result.Count | Should -Be $engine.Rows.Count
            $result[0].PSObject.TypeNames[0] | Should -BeExactly "System.Management.Automation.PSCustomObject"
            $result[0].PSObject.Properties.Name | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance", "SessionId", "EventType", "Parameters", "EventInfo")
            $result[0].PSStandardMembers.DefaultDisplayPropertySet | Should -BeNullOrEmpty
            $result[0].ComputerName | Should -BeExactly $server.ComputerName
            $result[0].InstanceName | Should -BeExactly $server.ServiceName
            $result[0].SqlInstance | Should -BeExactly $server.DomainInstanceName
            $result[0].SessionId | Should -BeOfType [int]
            $result[0].SessionId | Should -Be $idleSpid
            $result[0].EventType | Should -BeExactly $engine.Rows[0][0]
            $result[0].Parameters | Should -BeOfType [int16]
            $result[0].Parameters | Should -Be $engine.Rows[0][1]
            $result[0].EventInfo | Should -BeExactly $idleBatch
        }

        It "runs the query the pin builds: <Name>" -ForEach @(
            @{ Name = "the default operation keeps its case"; Extra = @{ }; Query = "DBCC InputBuffer({0}) WITH NO_INFOMSGS" }
            @{ Name = "a named operation is upper-cased"; Extra = @{ Operation = "InputBuffer" }; Query = "DBCC INPUTBUFFER({0}) WITH NO_INFOMSGS" }
            @{ Name = "a lower-case operation is upper-cased"; Extra = @{ Operation = "inputbuffer" }; Query = "DBCC INPUTBUFFER({0}) WITH NO_INFOMSGS" }
            @{ Name = "a request id follows the session"; Extra = @{ Operation = "InputBuffer"; RequestId = 0 }; Query = "DBCC INPUTBUFFER({0}, 0) WITH NO_INFOMSGS" }
        ) {
            # A session reading itself sees the batch it was given in its own input buffer.
            $own = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
            try {
                $ownSpid = [int]$own.ConnectionContext.ExecuteScalar("SELECT @@SPID")
                $result = @(Get-DbaDbccSessionBuffer -SqlInstance $own -SessionId $ownSpid -EnableException @Extra)
                $result.Count | Should -Be 1
                $result[0].EventInfo | Should -BeExactly ($Query -f $ownSpid)
            } finally {
                $own.ConnectionContext.Disconnect()
            }
        }

        It "reads the named sessions in the order given" {
            $serverSpid = [int]$server.ConnectionContext.ExecuteScalar("SELECT @@SPID")
            $result = @(Get-DbaDbccSessionBuffer -SqlInstance $instance -SessionId $idleSpid, $serverSpid, $idleSpid -EnableException)
            ($result.SessionId -join ",") | Should -BeExactly "$idleSpid,$serverSpid,$idleSpid"
        }

        It "writes the template, then the query, and no output line" {
            $verbose = Read-NativeVerboseLines @{ SqlInstance = $instance; SessionId = $idleSpid; EnableException = $true }
            $queries = @($verbose | Where-Object { $PSItem -like "*Get-DbaDbccSessionBuffer*Query to run: *" })
            $queries.Count | Should -Be 2
            $queries[0].EndsWith("Query to run: DBCC InputBuffer(#Operation#) WITH NO_INFOMSGS", [System.StringComparison]::Ordinal) | Should -BeTrue
            $queries[1].EndsWith("Query to run: DBCC InputBuffer($idleSpid) WITH NO_INFOMSGS", [System.StringComparison]::Ordinal) | Should -BeTrue
            @($verbose | Where-Object { $PSItem -like "*Output Buffer" }).Count | Should -Be 0
        }
    }

    Context "Output buffer" {
        It "returns one object per session, with the pinned properties and default view" {
            $result = @(Get-DbaDbccSessionBuffer -SqlInstance $instance -Operation OutputBuffer -SessionId $idleSpid -EnableException)
            $result.Count | Should -Be 1
            $result[0].PSObject.TypeNames[0] | Should -BeExactly "System.Management.Automation.PSCustomObject"
            $result[0].PSObject.Properties.Name | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance", "SessionId", "Buffer", "HexBuffer")
            $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance", "SessionId", "Buffer")
            $result[0].ComputerName | Should -BeExactly $server.ComputerName
            $result[0].InstanceName | Should -BeExactly $server.ServiceName
            $result[0].SqlInstance | Should -BeExactly $server.DomainInstanceName
            $result[0].SessionId | Should -BeOfType [int]
            $result[0].SessionId | Should -Be $idleSpid
        }

        It "returns the hex column of the dump in HexBuffer, every byte in order" {
            $result = Get-DbaDbccSessionBuffer -SqlInstance $instance -Operation OutputBuffer -SessionId $idleSpid -EnableException
            $hex = New-Object System.Text.StringBuilder
            foreach ($line in Read-NativeSessionDump -Target $idleSpid) {
                $line.Length | Should -Be 77
                $null = $hex.Append($line.Substring(11, 48).Replace(" ", ""))
            }
            $result.HexBuffer | Should -BeExactly $hex.ToString()
        }

        # Correction buffer-dots. The fixture's last batch returns dots, so the dump holds byte 2e: as that text on a plain connection, among random bytes on an encrypted one (the
        # probe's connection to the login instance, where markerInBuffer is false).
        It "keeps a real dot in Buffer and drops the dots that stand for other bytes" {
            $result = Get-DbaDbccSessionBuffer -SqlInstance $instance -Operation OutputBuffer -SessionId $idleSpid -EnableException
            $expected = New-Object System.Text.StringBuilder
            $column = New-Object System.Text.StringBuilder
            $realDots = 0
            foreach ($line in Read-NativeSessionDump -Target $idleSpid) {
                $hex = $line.Substring(11, 48)
                $text = $line.Substring(61, 16)
                $null = $column.Append($text)
                for ($position = 0; $position -lt 16; $position++) {
                    $isRealDot = $hex.Substring($position * 3, 2) -eq "2e"
                    if ($isRealDot) {
                        # The dump prints byte 2e as a dot, like the bytes it cannot print.
                        $text[$position] | Should -BeExactly ([char]".")
                        $realDots++
                    }
                    if ($isRealDot -or $text[$position] -ne [char]".") {
                        $null = $expected.Append($text[$position])
                    }
                }
            }
            $realDots | Should -BeGreaterThan 0
            $result.Buffer | Should -BeExactly $expected.ToString().TrimEnd()
            $result.Buffer | Should -Not -BeExactly $column.ToString().Replace(".", "").TrimEnd()
            $result.Buffer.Contains(".") | Should -BeTrue
        }

        It "writes the template, the query and the output line" {
            $verbose = Read-NativeVerboseLines @{ SqlInstance = $instance; Operation = "OutputBuffer"; SessionId = $idleSpid; RequestId = 0; EnableException = $true }
            $queries = @($verbose | Where-Object { $PSItem -like "*Get-DbaDbccSessionBuffer*Query to run: *" })
            $queries.Count | Should -Be 2
            $queries[0].EndsWith("Query to run: DBCC OUTPUTBUFFER(#Operation#) WITH NO_INFOMSGS", [System.StringComparison]::Ordinal) | Should -BeTrue
            $queries[1].EndsWith("Query to run: DBCC OUTPUTBUFFER($idleSpid, 0) WITH NO_INFOMSGS", [System.StringComparison]::Ordinal) | Should -BeTrue
            @($verbose | Where-Object { $PSItem -like "*Output Buffer" }).Count | Should -Be 1
        }
    }

    Context "All sessions" {
        It "reads every listed session, with its id as the list has it: <Operation>" -ForEach @(
            @{ Operation = "InputBuffer" }
            @{ Operation = "OutputBuffer" }
        ) {
            $result = @(Get-DbaDbccSessionBuffer -SqlInstance $instance -Operation $Operation -All -WarningAction SilentlyContinue)
            $result.SessionId | Should -Contain $idleSpid
            $result[0].SessionId | Should -BeOfType [int]
        }

        It "reads the same values for a session as when it is named" {
            $named = Get-DbaDbccSessionBuffer -SqlInstance $instance -Operation OutputBuffer -SessionId $idleSpid -EnableException
            $listed = @(Get-DbaDbccSessionBuffer -SqlInstance $instance -Operation OutputBuffer -All -WarningAction SilentlyContinue | Where-Object SessionId -eq $idleSpid)
            $listed.Count | Should -Be 1
            $listed[0].HexBuffer | Should -BeExactly $named.HexBuffer
            $listed[0].Buffer | Should -BeExactly $named.Buffer
            $listed[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance", "SessionId", "Buffer")
        }

        It "overrides -SessionId and -RequestId" {
            $serverSpid = [int]$server.ConnectionContext.ExecuteScalar("SELECT @@SPID")
            $result = @(Get-DbaDbccSessionBuffer -SqlInstance $instance -All -SessionId $idleSpid -RequestId 99 -WarningAction SilentlyContinue)
            $result.SessionId | Should -Contain $idleSpid
            $result.SessionId | Should -Contain $serverSpid
        }

        It "writes each query once, without the template or the output line" {
            $verbose = Read-NativeVerboseLines @{ SqlInstance = $instance; Operation = "OutputBuffer"; All = $true; WarningAction = "SilentlyContinue" }
            @($verbose | Where-Object { $PSItem -like "*Query to run: DBCC OUTPUTBUFFER($idleSpid) WITH NO_INFOMSGS" }).Count | Should -Be 1
            @($verbose | Where-Object { $PSItem -like "*#Operation#*" }).Count | Should -Be 0
            @($verbose | Where-Object { $PSItem -like "*Output Buffer" }).Count | Should -Be 0
        }

        # Correction all-false: the pin's Test-Bound reads the switch set to false as -All (all-false-session).
        It "an -All switch set to false with -SessionId reads only that session" -Tag "NativeChecklist:switch-false" {
            $result = @(Get-DbaDbccSessionBuffer -SqlInstance $instance -All:$false -SessionId $idleSpid -EnableException)
            $result.Count | Should -Be 1
            $result[0].SessionId | Should -Be $idleSpid
        }

        # Correction all-false: all-false-alone.
        It "an -All switch set to false without -SessionId asks for one and reads nothing" -Tag "NativeChecklist:switch-false" {
            $warnings = $null
            $result = @(Get-DbaDbccSessionBuffer -SqlInstance $instance -All:$false -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 0
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -BeLike "*You must specify either a SessionId or use the -All switch."
        }
    }

    Context "Neither a session nor -All" {
        # no-session
        It "warns once and reads nothing, for every piped instance" {
            $warnings = $null
            $result = @($instance, $instance | Get-DbaDbccSessionBuffer -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 0
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -BeLike "*Get-DbaDbccSessionBuffer*You must specify either a SessionId or use the -All switch."
        }

        # no-session-ee
        It "throws the message under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $record = $null
            try {
                $null = Get-DbaDbccSessionBuffer -SqlInstance $instance -EnableException -WarningAction SilentlyContinue
            } catch {
                $record = $PSItem
            }
            $record.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbccSessionBuffer*"
            "$($record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
            $record.TargetObject | Should -BeNullOrEmpty
            $record.Exception.Message | Should -BeExactly "You must specify either a SessionId or use the -All switch."
        }
    }

    Context "A session the server refuses" {
        BeforeAll {
            $invalidText = "An exception occurred while executing a Transact-SQL statement or batch.Invalid SPID 32000 specified."
        }

        # invalid-session, invalid-output-session
        It "warns with the joined server messages and writes nothing: <Operation>" -ForEach @(
            @{ Operation = "InputBuffer" }
            @{ Operation = "OutputBuffer" }
        ) {
            $warnings = $null
            $result = @(Get-DbaDbccSessionBuffer -SqlInstance $instance -Operation $Operation -SessionId 32000 -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 0
            @($warnings).Count | Should -Be 1
            "$($warnings[0])".EndsWith("[Get-DbaDbccSessionBuffer] Failure | $invalidText", [System.StringComparison]::Ordinal) | Should -BeTrue
        }

        # invalid-then-own
        It "goes on to the next session" {
            $warnings = $null
            $result = @(Get-DbaDbccSessionBuffer -SqlInstance $instance -SessionId 32000, $idleSpid -WarningVariable warnings -WarningAction SilentlyContinue)
            @($warnings).Count | Should -Be 1
            $result.Count | Should -Be 1
            $result[0].SessionId | Should -Be $idleSpid
        }

        # invalid-session-ee
        It "throws the same text under -EnableException, before the next session, with the server as its target" -Tag "NativeChecklist:enable-exception" {
            $record = $null
            $collected = $null
            try {
                $null = Get-DbaDbccSessionBuffer -SqlInstance $instance -SessionId 32000, $idleSpid -EnableException -OutVariable collected -WarningAction SilentlyContinue
            } catch {
                $record = $PSItem
            }
            $record.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbccSessionBuffer*"
            "$($record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
            "$($record.TargetObject)" | Should -BeExactly ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$server).FullSmoName
            $record.Exception.GetType().FullName | Should -BeExactly "System.Exception"
            $record.Exception.Message | Should -BeExactly $invalidText
            $record.Exception.InnerException | Should -BeOfType System.Management.Automation.MethodInvocationException
            $record.Exception.InnerException.Message | Should -BeExactly "Exception calling ""Query"" with ""1"" argument(s): ""$invalidText"""
            $record.Exception.InnerException.InnerException.GetType().FullName | Should -BeExactly "System.Management.Automation.RuntimeException"
            $record.Exception.InnerException.InnerException.InnerException.GetType().FullName | Should -BeExactly "System.Management.Automation.RuntimeException"
            @($collected).Count | Should -Be 0
        }

        It "keeps the warning and does not throw under -ErrorAction Stop" {
            $warnings = $null
            $result = Get-DbaDbccSessionBuffer -SqlInstance $instance -SessionId 32000 -ErrorAction Stop -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
        }
    }

    Context "Instances" {
        It "reads each piped instance" -Tag "NativeChecklist:pipeline-multiple" {
            $results = @($instance, $instance | Get-DbaDbccSessionBuffer -SessionId $idleSpid -EnableException)
            $results.Count | Should -Be 2
            $results[0].SqlInstance | Should -BeExactly $server.DomainInstanceName
            $results[1].SqlInstance | Should -BeExactly $server.DomainInstanceName
        }

        It "reads each instance of an array" {
            @(Get-DbaDbccSessionBuffer -SqlInstance $instance, $instance -SessionId $idleSpid -EnableException).Count | Should -Be 2
        }

        It "reads through a server object" {
            $result = @($server | Get-DbaDbccSessionBuffer -SessionId $idleSpid -EnableException)
            $result.Count | Should -Be 1
            $result[0].EventInfo | Should -BeExactly $idleBatch
        }
    }

    Context "An instance that cannot be reached" {
        It "warns and goes on to the next instance" -Tag "NativeChecklist:multi-instance-failure" {
            $warnings = $null
            $results = @(Get-DbaDbccSessionBuffer -SqlInstance $missingInstance, $instance -SessionId $idleSpid -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 1
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDbccSessionBuffer\] Failure \| Error connecting to \[$missingInstance\]: "
        }

        It "warns and goes on under -EnableException:`$false" -Tag "NativeChecklist:switch-false" {
            $warnings = $null
            $results = @(Get-DbaDbccSessionBuffer -SqlInstance $missingInstance, $instance -SessionId $idleSpid -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 1
            @($warnings).Count | Should -Be 1
        }

        It "warns and goes on with -All" {
            $warnings = $null
            $results = @(Get-DbaDbccSessionBuffer -SqlInstance $missingInstance, $instance -All -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.SessionId | Should -Contain $idleSpid
            "$($warnings[0])" | Should -Match "\[Get-DbaDbccSessionBuffer\] Failure \| Error connecting to \[$missingInstance\]: "
        }

        It "throws the connection failure under -EnableException, before the next instance" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            $collected = $null
            $warnings = $null
            try {
                $null = Get-DbaDbccSessionBuffer -SqlInstance $missingInstance, $instance -SessionId $idleSpid -EnableException -OutVariable collected -WarningVariable warnings -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDbccSessionBuffer\] Failure \| Error connecting to \[$missingInstance\]: "
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbccSessionBuffer*"
            "$($caught.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            "$($caught.TargetObject)" | Should -BeExactly $missingInstance
            # The line names the server; the caught record stays the server's own message.
            $caught.Exception.Message | Should -Not -BeLike "*Error connecting to*"
            @($collected).Count | Should -Be 0
        }
    }

    # In a runspace of its own, where Streams.Warning can be read and nothing else sets a preference. Points 5 and 6 of the section named above.
    Context "The warning stream of a failed connect" {
        BeforeAll {
            $streamLine = "\[Get-DbaDbccSessionBuffer\] Failure \| Error connecting to \[$missingInstance\]: "
            $streamState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $streamRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($streamState)
            $streamRunspace.Open()
            $streamShell = [System.Management.Automation.PowerShell]::Create()
            $streamShell.Runspace = $streamRunspace
            $streamModulePath = (Get-Module dbatools | Where-Object ModuleType -eq Script | Select-Object -First 1).Path
            $null = $streamShell.AddCommand("Import-Module").AddParameter("Name", $streamModulePath).AddParameter("ErrorAction", "Stop").Invoke()

            function Invoke-NativeSessionBufferStream {
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
            $call = Invoke-NativeSessionBufferStream -Script 'param($Target) Get-DbaDbccSessionBuffer -SqlInstance $Target -SessionId 1; "next statement"'
            $call.Warnings.Count | Should -Be 1
            $call.Warnings[0] | Should -Match $streamLine
            $call.Lines | Should -Contain "next statement"
        }

        It "merges the one line under 3>&1 on a plain call" {
            $call = Invoke-NativeSessionBufferStream -Script 'param($Target) Get-DbaDbccSessionBuffer -SqlInstance $Target -SessionId 1 3>&1; "next statement"'
            $call.Merged.Count | Should -Be 1
            $call.Merged[0] | Should -Match $streamLine
            $call.Warnings.Count | Should -Be 0
            $call.Lines | Should -Contain "next statement"
        }

        It "displays nothing under -EnableException, and -WarningVariable holds the one line" -Tag "NativeChecklist:enable-exception" {
            $call = Invoke-NativeSessionBufferStream -Script 'param($Target) try { Get-DbaDbccSessionBuffer -SqlInstance $Target -SessionId 1 -EnableException -WarningVariable held 3>&1 } catch { "caught " + $PSItem.FullyQualifiedErrorId }; "held " + @($held).Count; foreach ($line in $held) { "line " + $line }'
            $call.Merged.Count | Should -Be 0
            $call.Warnings.Count | Should -Be 0
            @($call.Lines | Where-Object { $PSItem -like "caught dbatools_Get-DbaDbccSessionBuffer*" }).Count | Should -Be 1
            $call.Lines | Should -Contain "held 1"
            @($call.Lines | Where-Object { $PSItem -like "line *" -and $PSItem -match $streamLine }).Count | Should -Be 1
        }

        It "leaves the warning stream empty under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $call = Invoke-NativeSessionBufferStream -Script 'param($Target) try { Get-DbaDbccSessionBuffer -SqlInstance $Target -SessionId 1 -EnableException } catch { "caught " + $PSItem.FullyQualifiedErrorId }'
            $call.Warnings.Count | Should -Be 0
            @($call.Lines | Where-Object { $PSItem -like "caught dbatools_Get-DbaDbccSessionBuffer*" }).Count | Should -Be 1
        }
    }

    Context "A null or empty -SqlInstance" {
        # The command's own binder refuses it, before any nested command.
        It "refuses <Name> at the binder, with no warning and no output" -ForEach @(
            @{ Name = "a null element"; Value = @($null, "unused"); Id = "ParameterArgumentValidationErrorNullNotAllowed"; Reason = "is null" }
            @{ Name = "a null value"; Value = $null; Id = "ParameterArgumentValidationErrorNullNotAllowed"; Reason = "is null" }
            @{ Name = "an empty array"; Value = @(); Id = "ParameterArgumentValidationErrorEmptyArrayNotAllowed"; Reason = "is an empty array" }
        ) {
            $caught = $null
            $warnings = $null
            $collected = $null
            try {
                $null = Get-DbaDbccSessionBuffer -SqlInstance $Value -SessionId 1 -OutVariable collected -WarningVariable warnings -WarningAction SilentlyContinue
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

Describe "Native Get-DbaDbccSessionBuffer on Azure SQL Database" -Tag IntegrationTests {
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
        $azureSpid = [int]$azureServer.ConnectionContext.ExecuteScalar("SELECT @@SPID")
        $azureRefused = "*Failure | An exception occurred while executing a Transact-SQL statement or batch.DBCC command 'OUTPUTBUFFER' is not supported in this version of SQL Server."
    }

    # azure-input-own: read-only, and the instance name is null there.
    It "reads the input buffer of its own session, and stays in the database" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $warnings = $null
        $result = @(Get-DbaDbccSessionBuffer -SqlInstance $azureServer -SessionId $azureSpid -WarningVariable warnings -WarningAction SilentlyContinue)
        @($warnings).Count | Should -Be 0
        $result.Count | Should -Be 1
        $result[0].PSObject.Properties.Name | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance", "SessionId", "EventType", "Parameters", "EventInfo")
        $result[0].ComputerName | Should -BeExactly $azureServer.ComputerName
        $result[0].InstanceName | Should -BeNullOrEmpty
        $result[0].SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
        $result[0].SessionId | Should -Be $azureSpid
        $result[0].EventInfo | Should -BeExactly "DBCC InputBuffer($azureSpid) WITH NO_INFOMSGS"
        $azureServer.ConnectionContext.CurrentDatabase | Should -BeExactly $azureDatabase
    }

    # azure-input-all
    It "lists the sessions of the database with -All" -Tag "NativeChecklist:azure-sqldb" {
        $result = @(Get-DbaDbccSessionBuffer -SqlInstance $azureServer -All -WarningAction SilentlyContinue)
        $result.SessionId | Should -Contain $azureSpid
    }

    # azure-output-own: Microsoft Learn lists DBCC OUTPUTBUFFER for SQL Server and Managed Instance only.
    It "warns that OUTPUTBUFFER is not supported there" -Tag "NativeChecklist:azure-sqldb" {
        $warnings = $null
        $result = @(Get-DbaDbccSessionBuffer -SqlInstance $azureServer -Operation OutputBuffer -SessionId $azureSpid -WarningVariable warnings -WarningAction SilentlyContinue)
        $result.Count | Should -Be 0
        @($warnings).Count | Should -Be 1
        "$warnings" | Should -BeLike $azureRefused
    }

    # azure-output-all
    It "warns of that refusal for each listed session with -All" -Tag "NativeChecklist:azure-sqldb" {
        $warnings = $null
        $result = @(Get-DbaDbccSessionBuffer -SqlInstance $azureServer -Operation OutputBuffer -All -WarningVariable warnings -WarningAction SilentlyContinue)
        $result.Count | Should -Be 0
        @($warnings).Count | Should -BeGreaterThan 0
        "$($warnings[0])" | Should -BeLike $azureRefused
    }
}

Describe "Native Get-DbaDbccSessionBuffer over SQL authentication" -Tag IntegrationTests {
    BeforeAll {
        $loginInstance = $TestConfig.InstanceSqlLogin
        $loginCred = $TestConfig.SqlLoginCred
        # Unique per leg and run: the instance is shared. No DENY: a new login has neither permission, and it reaches master as guest.
        $lowName = "dbatoolsci_nsb_low_$(Get-Random)"
        $lowPassword = "Nsb-$([guid]::NewGuid().ToString('N'))"
        $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
        $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -NonPooledConnection -EnableException
        $loginSpid = [int]$loginServer.ConnectionContext.ExecuteScalar("SELECT @@SPID")
        $null = $loginServer.Query("CREATE LOGIN [$lowName] WITH PASSWORD = '$lowPassword', CHECK_POLICY = OFF;")
        $low = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $lowCred -NonPooledConnection -EnableException
        $lowSpid = [int]$low.ConnectionContext.ExecuteScalar("SELECT @@SPID")
        # VIEW SERVER PERFORMANCE STATE from SQL Server 2022, VIEW SERVER STATE before it.
        $listDenied = "An exception occurred while executing a Transact-SQL statement or batch.VIEW SERVER *STATE permission was denied on object 'server', database 'master'.*The user does not have permission to perform this action."

        # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
        function Invoke-NativeOutsideTry {
            param([hashtable]$Arguments)
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaDbccSessionBuffer -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaDbccSessionBuffer", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $outsideStop = $null
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                $null = $outsideShell.AddScript('param($Arguments) Get-DbaDbccSessionBuffer @Arguments; "next statement"').AddArgument($Arguments)
                try {
                    $null = $outsideShell.Invoke($null, $outsideOutput)
                } catch {
                    # The stop leaves the runspace's script through Invoke, as a method call's exception.
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

        function Assert-NativeListRecord {
            param($Record)
            $Record.FullyQualifiedErrorId | Should -BeLike "ScriptMethodRuntimeException,*"
            "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
            $Record.TargetObject | Should -BeNullOrEmpty
            $Record.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.MethodInvocationException"
            $Record.Exception.Message | Should -BeLike "Exception calling ""Query"" with ""1"" argument(s): ""$listDenied"""
            $Record.Exception.InnerException.GetType().FullName | Should -BeExactly "System.Management.Automation.RuntimeException"
            $Record.Exception.InnerException.Message | Should -BeLike $listDenied
            $Record.Exception.InnerException.InnerException.GetType().FullName | Should -BeExactly "System.Management.Automation.RuntimeException"
        }
    }

    AfterAll {
        $low.ConnectionContext.Disconnect()
        # The disconnect above may already have ended the session, and a query with no rows must not read as one null row.
        foreach ($row in @($loginServer.Query("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$lowName';") | Where-Object { $null -ne $PSItem })) {
            $null = $loginServer.Query("KILL $($row.session_id);")
        }
        $null = $loginServer.Query("IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];")
        $loginServer.ConnectionContext.Disconnect()
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        It "works with -SqlCredential" {
            $result = @(Get-DbaDbccSessionBuffer -SqlInstance $loginInstance -SqlCredential $loginCred -SessionId $lowSpid -EnableException)
            $result.Count | Should -Be 1
            $result[0].SessionId | Should -Be $lowSpid
            $result[0].SqlInstance | Should -BeExactly $loginServer.DomainInstanceName
        }

        It "reads every session with -All and -SqlCredential" {
            $result = @(Get-DbaDbccSessionBuffer -SqlInstance $loginInstance -SqlCredential $loginCred -All -WarningAction SilentlyContinue)
            $result.SessionId | Should -Contain $lowSpid
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = $null
            $result = Get-DbaDbccSessionBuffer -SqlInstance $loginInstance -SessionId 1 -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match ("\[Get-DbaDbccSessionBuffer\] Failure \| Error connecting to \[" + [regex]::Escape($loginInstance) + "\]: Login failed")
        }

        It "throws the connection failure under -EnableException" {
            { Get-DbaDbccSessionBuffer -SqlInstance $loginInstance -SessionId 1 -EnableException -WarningAction SilentlyContinue } | Should -Throw -ExpectedMessage "*Login failed*" -ErrorId "dbatools_Get-DbaDbccSessionBuffer*"
        }
    }

    # Measured on this instance: system-session, system-output-session.
    Context "A system session" {
        It "reads No Event, with a null event info kept as the row's DBNull" {
            $result = @(Get-DbaDbccSessionBuffer -SqlInstance $loginServer -SessionId 1 -EnableException)
            $result.Count | Should -Be 1
            $result[0].EventType | Should -BeExactly "No Event"
            $result[0].EventInfo.GetType().FullName | Should -BeExactly "System.DBNull"
        }

        It "gives one object with empty buffers for a dump with no rows" {
            $result = @(Get-DbaDbccSessionBuffer -SqlInstance $loginServer -Operation OutputBuffer -SessionId 1 -EnableException)
            $result.Count | Should -Be 1
            $result[0].SessionId | Should -Be 1
            $result[0].Buffer | Should -BeExactly ""
            $result[0].HexBuffer | Should -BeExactly ""
        }
    }

    Context "A login that may read only its own input buffer" {
        # low-own
        It "reads its own input buffer" {
            $result = @(Get-DbaDbccSessionBuffer -SqlInstance $low -SessionId $lowSpid -EnableException)
            $result.Count | Should -Be 1
            $result[0].EventInfo | Should -BeExactly "DBCC InputBuffer($lowSpid) WITH NO_INFOMSGS"
        }

        # low-own-output
        It "warns that it may not read its output buffer" {
            $warnings = $null
            $result = @(Get-DbaDbccSessionBuffer -SqlInstance $low -Operation OutputBuffer -SessionId $lowSpid -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 0
            @($warnings).Count | Should -Be 1
            "$warnings".EndsWith("[Get-DbaDbccSessionBuffer] Failure | An exception occurred while executing a Transact-SQL statement or batch.User 'guest' does not have permission to run DBCC OUTPUTBUFFER.", [System.StringComparison]::Ordinal) | Should -BeTrue
        }

        # low-other
        It "warns that it may not read another session's input buffer, and goes on" {
            $warnings = $null
            $result = @(Get-DbaDbccSessionBuffer -SqlInstance $low -SessionId $loginSpid, $lowSpid -WarningVariable warnings -WarningAction SilentlyContinue)
            @($warnings).Count | Should -Be 1
            "$warnings".EndsWith("[Get-DbaDbccSessionBuffer] Failure | An exception occurred while executing a Transact-SQL statement or batch.User 'guest' does not have permission to run DBCC inputbuffer.", [System.StringComparison]::Ordinal) | Should -BeTrue
            $result.Count | Should -Be 1
            $result[0].SessionId | Should -Be $lowSpid
        }

        # low-other-ee
        It "throws that refusal under -EnableException, with the server as its target" -Tag "NativeChecklist:enable-exception" {
            $record = $null
            try {
                $null = Get-DbaDbccSessionBuffer -SqlInstance $low -SessionId $loginSpid -EnableException -WarningAction SilentlyContinue
            } catch {
                $record = $PSItem
            }
            $record.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbccSessionBuffer*"
            "$($record.TargetObject)" | Should -BeExactly $loginInstance
            $record.Exception.Message | Should -BeExactly "An exception occurred while executing a Transact-SQL statement or batch.User 'guest' does not have permission to run DBCC inputbuffer."
            $record.Exception.InnerException | Should -BeOfType System.Management.Automation.MethodInvocationException
        }
    }

    Context "A login that may not list the sessions, outside any try" {
        # low-all, low-all-output
        It "a plain call writes the record, reads nothing and goes on: <Operation>" -ForEach @(
            @{ Operation = "InputBuffer" }
            @{ Operation = "OutputBuffer" }
        ) {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $low; Operation = $Operation; All = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeListRecord -Record $outside.Errors[0]
            $outside.Warnings.Count | Should -Be 0
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        # low-then-good-all
        It "a plain call goes on to the next instance, which reads its own list" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($low, $loginServer); All = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeListRecord -Record $outside.Errors[0]
            $outside.Output[-1] | Should -BeExactly "next statement"
            @($outside.Output | Where-Object { $PSItem.SessionId -eq $lowSpid }).Count | Should -Be 1
            @($outside.Output | Where-Object { $PSItem.SessionId -eq $loginSpid }).Count | Should -Be 1
        }

        # good-then-low-all: the list of the instance before is walked again, on this login's connection.
        It "a plain call walks the list of the instance before: each row true, each refused session warned" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($loginServer, $low); All = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeListRecord -Record $outside.Errors[0]
            $own = @($outside.Output | Where-Object { $PSItem.SessionId -eq $lowSpid })
            $own.Count | Should -Be 2
            $own[1].EventInfo | Should -BeExactly "DBCC InputBuffer($lowSpid) WITH NO_INFOMSGS"
            @($outside.Output | Where-Object { $PSItem.SessionId -eq $loginSpid }).Count | Should -Be 1
            @($outside.Warnings | Where-Object { $PSItem.Message -like "*User 'guest' does not have permission to run DBCC inputbuffer." }).Count | Should -BeGreaterThan 0
            $outside.Output[-1] | Should -BeExactly "next statement"
        }

        # Accepted difference, keep-going: low-all-ee and low-then-good-all-ee go on where the port stops.
        It "-EnableException ends the command at the record and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($low, $loginServer); All = $true; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeListRecord -Record $outside.Errors[0]
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        # Accepted difference, keep-going: low-all-stop ends the function's statement only.
        It "-ErrorAction Stop turns the record into the stop PowerShell gives WriteError" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($low, $loginServer); All = $true; ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeListRecord -Record $outside.Stop.ErrorRecord
            $outside.Output.Count | Should -Be 0
        }
    }

    Context "A login that may not list the sessions, inside a caller's try" {
        # low-all-try, low-all-try-ee, low-all-try-stop
        It "the catch receives the record and the command does not go on: <Name>" -ForEach @(
            @{ Name = "plain"; Extra = @{ } }
            @{ Name = "-EnableException"; Extra = @{ EnableException = $true } }
            @{ Name = "-ErrorAction Stop"; Extra = @{ ErrorAction = "Stop" } }
        ) {
            $streamed = New-Object System.Collections.ArrayList
            $failure = $null
            $after = $false
            try {
                Get-DbaDbccSessionBuffer -SqlInstance $low, $loginServer -All @Extra | ForEach-Object { $null = $streamed.Add($PSItem) }
                $after = $true
            } catch {
                $failure = $PSItem
            }
            Assert-NativeListRecord -Record $failure
            $after | Should -BeFalse
            $streamed.Count | Should -Be 0
        }
    }
}
