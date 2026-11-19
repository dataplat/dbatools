#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaErrorLog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads the error log.

# Expected values below are as the pin measured on both editions: evidence/pin-errorlog-20261104.txt and pin-errorlog2-20261104.txt, whose case names the comments use.
# A failed connect writes one warning line naming the server, where the pin writes two (bad-plain, no-credential): an accepted difference,
# harness-edits.md, "Script-scope preferences and the one-line connect warning", points 5 to 7.
# Logs are long and only ever read here, so each test reads log 0 where it can, narrowed by its own marker rows. No test cycles a log.

BeforeAll {
    # A plain call in a runspace of its own, so no try of Pester's encloses it, with a next statement after it. -Piped sends -Values down the pipeline.
    function Invoke-NativeOutsideTry {
        param([hashtable]$Arguments = @{ }, [object[]]$Values, [switch]$Piped)
        $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $outsideType = (Get-Command Get-DbaErrorLog -CommandType Cmdlet).ImplementingType
        $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaErrorLog", $outsideType, $null
        $outsideState.Commands.Add($outsideEntry)
        $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
        $outsideShell = [System.Management.Automation.PowerShell]::Create()
        $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
        $outsideStop = $null
        try {
            $outsideRunspace.Open()
            $outsideShell.Runspace = $outsideRunspace
            if ($Piped) {
                $null = $outsideShell.AddScript('param($Arguments, $Values) $Values | Get-DbaErrorLog @Arguments; "next statement"').AddArgument($Arguments).AddArgument($Values)
            } else {
                $null = $outsideShell.AddScript('param($Arguments) Get-DbaErrorLog @Arguments; "next statement"').AddArgument($Arguments)
            }
            try {
                $null = $outsideShell.Invoke($null, $outsideOutput)
            } catch {
                # The stop leaves the runspace's script through Invoke, as a method call's exception.
                $outsideStop = $PSItem.Exception.InnerException
            }
            [pscustomobject]@{
                Rows     = @($outsideOutput | Where-Object { $PSItem.PSObject.BaseObject -is [System.Data.DataRow] })
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

    # The record of a $server.ReadErrorLog that faulted, as low-plain measured it.
    function Assert-NativeLogFault {
        param($Record, [string]$FaultType, [string]$FaultText)
        $Record.FullyQualifiedErrorId | Should -BeLike "$($FaultType.Split('.')[-1])*"
        "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
        $Record.CategoryInfo.Reason | Should -BeExactly "MethodInvocationException"
        $Record.TargetObject | Should -BeNullOrEmpty
        $Record.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.MethodInvocationException"
        $Record.Exception.Message | Should -BeExactly "Exception calling `"ReadErrorLog`" with `"1`" argument(s): `"$FaultText`""
        $Record.Exception.InnerException.GetType().FullName | Should -BeExactly $FaultType
        $Record.Exception.InnerException.Message | Should -BeExactly $FaultText
    }
}

Describe "Native Get-DbaErrorLog" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $missingInstance = "nativeerrorlog$(Get-Random)"
        $stamp = "dbatoolsci_nerl_$(Get-Random)"
        $firstMarker = "$stamp first"
        $secondMarker = "$stamp second"

        # Two sessions, so the two marker rows have two sources. These connections are passed to the command only where a test names them.
        $firstSession = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
        $secondSession = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
        $null = $firstSession.ConnectionContext.ExecuteNonQuery("RAISERROR(N'$firstMarker', 1, 1) WITH LOG;")
        $null = $secondSession.ConnectionContext.ExecuteNonQuery("RAISERROR(N'$secondMarker', 1, 1) WITH LOG;")

        # The independent read of the markers, with the server's own procedure on the fixture's connection. The last row of a log can carry a line break until the next is written, so texts are compared trimmed.
        function Read-NativeMarkerRow {
            @($firstSession.ConnectionContext.ExecuteWithResults("EXEC sys.xp_readerrorlog 0, 1, N'$stamp';").Tables[0].Rows)
        }

        $markerRows = @()
        for ($attempt = 1; $attempt -le 10; $attempt++) {
            $markerRows = Read-NativeMarkerRow
            if ($markerRows.Count -ge 2) { break }
            Start-Sleep -Seconds 1
        }
        $firstRow = @($markerRows | Where-Object { "$($PSItem.Text)".TrimEnd() -ceq $firstMarker })[0]
        $secondRow = @($markerRows | Where-Object { "$($PSItem.Text)".TrimEnd() -ceq $secondMarker })[0]
        if ($null -eq $firstRow -or $null -eq $secondRow) {
            throw "The fixture's marker rows did not reach the error log of $instance."
        }
        $firstSource = "$($firstRow.ProcessInfo)"
        $secondSource = "$($secondRow.ProcessInfo)"
        $logged = [datetime]$firstRow.LogDate
    }

    AfterAll {
        $firstSession.ConnectionContext.Disconnect()
        $secondSession.ConnectionContext.Disconnect()
    }

    Context "Output" {
        # shape.
        It "returns each row as the DataRow, with the instance notes, the Source alias and the default view" {
            $result = @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Text $firstMarker -EnableException)
            $result.Count | Should -Be 1
            $row = $result[0]
            $row.PSObject.BaseObject | Should -BeOfType [System.Data.DataRow]
            $row.PSObject.TypeNames | Should -BeExactly @("System.Data.DataRow", "System.Object")
            $row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance", "LogDate", "Source", "Text")
            foreach ($note in "ComputerName", "InstanceName", "SqlInstance") {
                "$($row.PSObject.Properties[$note].MemberType)" | Should -BeExactly "NoteProperty"
            }
            "$($row.PSObject.Properties["Source"].MemberType)" | Should -BeExactly "AliasProperty"
            $row.ComputerName | Should -BeExactly $firstSession.ComputerName
            $row.InstanceName | Should -BeExactly $firstSession.ServiceName
            $row.SqlInstance | Should -BeExactly $firstSession.DomainInstanceName
            $row.LogDate | Should -BeOfType [datetime]
            $row.LogDate | Should -Be $logged
            $row.ProcessInfo | Should -BeExactly $firstSource
            $row.Source | Should -BeExactly $firstSource
            $row.Text.TrimEnd() | Should -BeExactly $firstMarker
        }

        # verbose-one-log.
        It "writes one verbose message for each row it returns" {
            $stream = @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Text $firstMarker -Verbose 4>&1)
            @($stream | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*Processing System.Data.DataRow" }).Count | Should -Be 1
            @($stream | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] }).Count | Should -Be 1
        }
    }

    Context "-LogNumber" {
        BeforeAll {
            # The pinned file has cycled this instance's log on this leg, so both logs exist and neither takes new rows in this window: from the last row of log 1, read with the server's own procedure,
            # to the marker row in log 0, a few rows each. Older logs end before it. Rows after the marker do not count, so these reads stay the same however many are written meanwhile.
            $oneLast = [datetime]@($firstSession.ConnectionContext.ExecuteWithResults("EXEC sys.xp_readerrorlog 1, 1;").Tables[0].Rows)[-1].LogDate
            $window = @{ After = $oneLast; Before = $logged; EnableException = $true }
            $zeroDates = @(@(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 @window) | ForEach-Object LogDate)
            $oneDates = @(@(Get-DbaErrorLog -SqlInstance $instance -LogNumber 1 @window) | ForEach-Object LogDate)
        }

        It "finds rows in both logs" {
            $zeroDates.Count | Should -BeGreaterThan 0
            $oneDates.Count | Should -BeGreaterThan 0
        }

        # lognumber-one-zero, lognumber-zero-one, lognumber-repeated.
        It "reads the numbers given, in their order, and again when one repeats" {
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 1, 0 @window | ForEach-Object LogDate) | Should -Be ($oneDates + $zeroDates)
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0, 1 @window | ForEach-Object LogDate) | Should -Be ($zeroDates + $oneDates)
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0, 0 @window | ForEach-Object LogDate) | Should -Be ($zeroDates + $zeroDates)
        }

        # default-all-logs: the window holds rows of logs 1 and 0 only, so the oldest-first order shows as log 1 before log 0.
        It "reads every log from the oldest to the newest when no number is given" {
            @(Get-DbaErrorLog -SqlInstance $instance @window | ForEach-Object LogDate) | Should -Be ($oneDates + $zeroDates)
        }

        # lognumber-missing, lognumber-empty.
        It "reads no rows and writes nothing for <Name>" -ForEach @(
            @{ Name = "a log that does not exist"; Value = 98 }
            @{ Name = "an empty array"; Value = @() }
        ) {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $firstSession; LogNumber = $Value }
            $outside.Rows.Count | Should -Be 0
            $outside.Errors.Count | Should -Be 0
            $outside.Warnings.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        # lognumber-outside, lognumber-negative, lognumber-null.
        It "refuses <Name> at the binder" -ForEach @(
            @{ Name = "a number above the range"; Value = 100; Text = "The 100 argument is greater than the maximum allowed range of 99. Supply an argument that is less than or equal to 99 and then try the command again." }
            @{ Name = "a number below the range"; Value = -1; Text = "The -1 argument is less than the minimum allowed range of 0. Supply an argument that is greater than or equal to 0 and then try the command again." }
            @{ Name = "null"; Value = $null; Text = "The argument is null, empty, or an element of the argument collection contains a null value. Supply a collection that does not contain any null values and then try the command again." }
        ) {
            $caught = $null
            try {
                $null = Get-DbaErrorLog -SqlInstance $instance -LogNumber $Value
            } catch {
                $caught = $PSItem
            }
            $caught.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationError,*"
            "$($caught.CategoryInfo.Category)" | Should -BeExactly "InvalidData"
            $caught.Exception.Message | Should -BeExactly "Cannot validate argument on parameter 'LogNumber'. $Text"
        }
    }

    Context "-Source" {
        # source-one, filter-source-text.
        It "returns only the rows of the source given" {
            $result = @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Source $firstSource -Text $stamp -EnableException)
            $result.Count | Should -Be 1
            $result[0].Text.TrimEnd() | Should -BeExactly $firstMarker
        }

        # source-case.
        It "compares without regard to case" {
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Source $firstSource.ToUpper() -Text $stamp -EnableException).Count | Should -Be 1
        }

        # source-one-in-array.
        It "takes one value in an array" {
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Source @($firstSource) -Text $stamp -EnableException).Count | Should -Be 1
        }

        # source-wildcard, source-missing.
        It "does not read a wildcard, and returns nothing for a source that is not there" {
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Source "$($firstSource.Substring(0, 2))*" -Text $stamp -EnableException).Count | Should -Be 0
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Source "dbatoolsci_nope" -Text $stamp -EnableException).Count | Should -Be 0
        }

        # source-empty, source-empty-array, source-null.
        It "does not filter for <Name>" -ForEach @(
            @{ Name = "an empty string"; Value = "" }
            @{ Name = "an empty array"; Value = @() }
            @{ Name = "null"; Value = $null }
        ) {
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Source $Value -Text $stamp -EnableException).Count | Should -Be 2
        }

        # Correction source-array: source-two returned nothing, with no error.
        It "returns the rows of every source given, for two values" {
            $firstSource | Should -Not -BeExactly $secondSource
            $result = @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Source $firstSource, $secondSource -Text $stamp -EnableException)
            $result.Count | Should -Be 2
            $result[0].Text.TrimEnd() | Should -BeExactly $firstMarker
            $result[1].Text.TrimEnd() | Should -BeExactly $secondMarker
        }

        # Correction source-array: source-two-same returned nothing.
        It "returns a row once when the same source is given twice" {
            $result = @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Source $firstSource, $firstSource -Text $stamp -EnableException)
            $result.Count | Should -Be 1
            $result[0].Text.TrimEnd() | Should -BeExactly $firstMarker
        }

        # Correction source-array: source-null-element returned nothing.
        It "returns the rows of the source beside a null" {
            $result = @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Source $null, $firstSource -Text $stamp -EnableException)
            $result.Count | Should -Be 1
            $result[0].Text.TrimEnd() | Should -BeExactly $firstMarker
        }
    }

    Context "-Text" {
        # text-word.
        It "finds the words given" {
            $result = @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Text $secondMarker -EnableException)
            $result.Count | Should -Be 1
            $result[0].ProcessInfo | Should -BeExactly $secondSource
        }

        # text-case, text-star, text-question, text-bracket.
        It "reads the text as a wildcard pattern, without regard to case" {
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Text $firstMarker.ToUpper() -EnableException).Count | Should -Be 1
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Text "${stamp}*first" -EnableException).Count | Should -Be 1
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Text "${stamp}?first" -EnableException).Count | Should -Be 1
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Text "[d]$($stamp.Substring(1)) first" -EnableException).Count | Should -Be 1
        }

        # text-missing.
        It "returns nothing for a text that is not there" {
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Text "$stamp nope" -EnableException).Count | Should -Be 0
        }

        # text-empty, text-null.
        It "does not filter for <Name>" -ForEach @(
            @{ Name = "an empty string"; Value = "" }
            @{ Name = "null"; Value = $null }
        ) {
            $result = @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Source $firstSource -Text $Value -EnableException)
            @($result | Where-Object { $PSItem.Text.TrimEnd() -ceq $firstMarker }).Count | Should -Be 1
        }

        Context "A pattern that is not valid" {
            BeforeAll {
                $badPattern = "nope ["

                function Assert-NativePatternFault {
                    param($Record)
                    $Record.FullyQualifiedErrorId | Should -BeLike "RuntimeException*"
                    "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
                    $Record.CategoryInfo.Reason | Should -BeExactly "WildcardPatternException"
                    $Record.TargetObject | Should -BeNullOrEmpty
                    $Record.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.WildcardPatternException"
                    $Record.Exception.Message | Should -BeExactly "The specified wildcard character pattern is not valid: *nope [*"
                }
            }

            # text-lone-bracket: the pattern faults the pin's if statement on each row, so the row goes out; -Source is tested first, so a row it refuses has no record.
            It "writes one record for each row that -Source lets through, and that row goes out" {
                $outside = Invoke-NativeOutsideTry @{ SqlInstance = $firstSession; LogNumber = 0; Source = $firstSource; Text = $badPattern }
                $outside.Rows.Count | Should -BeGreaterThan 0
                $outside.Errors.Count | Should -Be $outside.Rows.Count
                Assert-NativePatternFault -Record $outside.Errors[0]
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Next | Should -BeTrue
                @($outside.Rows | Where-Object { $PSItem.Text.TrimEnd() -ceq $firstMarker }).Count | Should -Be 1
            }

            # The fault comes before -After is tested.
            It "lets the row out with -After and -Before untested" {
                $outside = Invoke-NativeOutsideTry @{ SqlInstance = $firstSession; LogNumber = 0; Source = $firstSource; Text = $badPattern; After = $logged.AddDays(1) }
                $outside.Rows.Count | Should -BeGreaterThan 0
                $outside.Errors.Count | Should -Be $outside.Rows.Count
            }

            # The keep-going section's point 3, as at the read.
            It "under -EnableException stops at the first record, with no row" -Tag "NativeChecklist:enable-exception" {
                $outside = Invoke-NativeOutsideTry @{ SqlInstance = $firstSession; LogNumber = 0; Source = $firstSource; Text = $badPattern; EnableException = $true }
                $outside.Errors.Count | Should -Be 1
                Assert-NativePatternFault -Record $outside.Errors[0]
                $outside.Rows.Count | Should -Be 0
                $outside.Next | Should -BeTrue
            }

            It "inside a caller's try, the catch receives the record and the command does not go on" {
                $failure = $null
                $after = $false
                try {
                    $null = Get-DbaErrorLog -SqlInstance $firstSession -LogNumber 0 -Source $firstSource -Text $badPattern
                    $after = $true
                } catch {
                    $failure = $PSItem
                }
                Assert-NativePatternFault -Record $failure
                $after | Should -BeFalse
            }
        }
    }

    Context "-After and -Before" {
        # filter-after-hour, filter-before-hour, at the row's own time: a row at the bound stays, as -lt and -gt read it.
        It "keeps a row at the time given and drops it past that time" {
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Text $firstMarker -After $logged -EnableException).Count | Should -Be 1
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Text $firstMarker -Before $logged -EnableException).Count | Should -Be 1
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Text $firstMarker -After $logged.AddMilliseconds(1) -EnableException).Count | Should -Be 0
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Text $firstMarker -Before $logged.AddMilliseconds(-1) -EnableException).Count | Should -Be 0
        }

        # filter-after-future, filter-before-future, filter-after-minvalue, filter-before-minvalue: a bound date counts even at its smallest value.
        It "reads the far ends of time" {
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Text $firstMarker -After $logged.AddDays(1) -EnableException).Count | Should -Be 0
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Text $firstMarker -Before $logged.AddDays(1) -EnableException).Count | Should -Be 1
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Text $firstMarker -After ([datetime]::MinValue) -EnableException).Count | Should -Be 1
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Text $firstMarker -Before ([datetime]::MinValue) -EnableException).Count | Should -Be 0
        }

        # The help's two examples: a date given as a string.
        It "takes a date as a string" {
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Text $firstMarker -After '2016-11-14 00:00:00' -EnableException).Count | Should -Be 1
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Text $firstMarker -Before '2016-08-16 00:00:00' -EnableException).Count | Should -Be 0
        }

        # filter-after-before, filter-source-after.
        It "applies every filter given" {
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Source $firstSource -Text $stamp -After $logged.AddMinutes(-1) -Before $logged.AddMinutes(1) -EnableException).Count | Should -Be 1
            @(Get-DbaErrorLog -SqlInstance $instance -LogNumber 0 -Source $secondSource -Text $firstMarker -After $logged.AddMinutes(-1) -EnableException).Count | Should -Be 0
        }
    }

    Context "Instances" {
        # no-instance, instance-null, instance-empty.
        It "reads nothing and writes nothing for <Name>" -ForEach @(
            @{ Name = "no instance"; Arguments = @{ LogNumber = 0 } }
            @{ Name = "a null instance"; Arguments = @{ SqlInstance = $null; LogNumber = 0 } }
            @{ Name = "an empty array"; Arguments = @{ SqlInstance = @(); LogNumber = 0 } }
        ) {
            $outside = Invoke-NativeOutsideTry $Arguments
            $outside.Rows.Count | Should -Be 0
            $outside.Errors.Count | Should -Be 0
            $outside.Warnings.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        # piped-null, piped-empty.
        It "reads nothing and writes nothing for a piped null and for a piped empty array" {
            $pipedNull = Invoke-NativeOutsideTry @{ LogNumber = 0 } -Values @($null) -Piped
            $pipedEmpty = Invoke-NativeOutsideTry @{ LogNumber = 0 } -Values @() -Piped
            foreach ($outside in $pipedNull, $pipedEmpty) {
                $outside.Rows.Count | Should -Be 0
                $outside.Errors.Count | Should -Be 0
                $outside.Warnings.Count | Should -Be 0
                $outside.Next | Should -BeTrue
            }
        }

        # piped-twice.
        It "reads each piped instance" -Tag "NativeChecklist:pipeline-multiple" {
            @($instance, $instance | Get-DbaErrorLog -LogNumber 0 -Text $firstMarker -EnableException).Count | Should -Be 2
        }

        # named-twice.
        It "reads each instance of an array" {
            @(Get-DbaErrorLog -SqlInstance $instance, $instance -LogNumber 0 -Text $firstMarker -EnableException).Count | Should -Be 2
        }

        It "reads through a server object" {
            $result = @($firstSession | Get-DbaErrorLog -LogNumber 0 -Text $firstMarker -EnableException)
            $result.Count | Should -Be 1
            $result[0].SqlInstance | Should -BeExactly $firstSession.DomainInstanceName
        }

        # instance-null-element, instance-null-element-try: the nested connect's binder fault, inside the pinned try.
        It "warns of a null element and reads the others" {
            foreach ($value in @(@($null, $instance), @($instance, $null))) {
                $warnings = $null
                $result = @(Get-DbaErrorLog -SqlInstance $value -LogNumber 0 -Text $firstMarker -WarningVariable warnings -WarningAction SilentlyContinue)
                $result.Count | Should -Be 1
                @($warnings).Count | Should -Be 1
                "$($warnings[0])" | Should -Match "\[Get-DbaErrorLog\] Failure \| Cannot bind argument to parameter 'SqlInstance' because it is null\.$"
            }
        }

        # instance-null-element-ee.
        It "throws a null element under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $failure = $null
            try {
                $null = Get-DbaErrorLog -SqlInstance @($null, $instance) -LogNumber 0 -Text $firstMarker -EnableException -WarningAction SilentlyContinue
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.Message | Should -BeExactly "Cannot bind argument to parameter 'SqlInstance' because it is null."
            $failure.Exception.InnerException | Should -BeOfType System.Management.Automation.ParameterBindingException
            $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaErrorLog*"
            "$($failure.CategoryInfo.Category)" | Should -BeExactly "InvalidData"
            $failure.TargetObject | Should -BeNullOrEmpty
        }
    }

    Context "An instance that cannot be reached" {
        # bad-between, bad-ee.
        It "warns and goes on to the next instance" -Tag "NativeChecklist:multi-instance-failure" {
            $warnings = $null
            $results = @(Get-DbaErrorLog -SqlInstance $missingInstance, $instance -LogNumber 0 -Text $firstMarker -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 1
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaErrorLog\] Failure \| Error connecting to \[$missingInstance\]: "
        }

        It "warns and goes on under -EnableException:`$false" -Tag "NativeChecklist:switch-false" {
            $warnings = $null
            $results = @(Get-DbaErrorLog -SqlInstance $missingInstance, $instance -LogNumber 0 -Text $firstMarker -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 1
            @($warnings).Count | Should -Be 1
        }

        It "throws the connection failure under -EnableException, before the next instance" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            $collected = $null
            $warnings = $null
            try {
                $null = Get-DbaErrorLog -SqlInstance $missingInstance, $instance -LogNumber 0 -Text $firstMarker -EnableException -OutVariable collected -WarningVariable warnings -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaErrorLog\] Failure \| Error connecting to \[$missingInstance\]: "
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaErrorLog*"
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
            $streamLine = "\[Get-DbaErrorLog\] Failure \| Error connecting to \[$missingInstance\]: "
            $streamState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $streamRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($streamState)
            $streamRunspace.Open()
            $streamShell = [System.Management.Automation.PowerShell]::Create()
            $streamShell.Runspace = $streamRunspace
            $streamModulePath = (Get-Module dbatools | Where-Object ModuleType -eq Script | Select-Object -First 1).Path
            $null = $streamShell.AddCommand("Import-Module").AddParameter("Name", $streamModulePath).AddParameter("ErrorAction", "Stop").Invoke()

            function Invoke-NativeStreamCall {
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
            $call = Invoke-NativeStreamCall -Script 'param($Target) Get-DbaErrorLog -SqlInstance $Target; "next statement"'
            $call.Warnings.Count | Should -Be 1
            $call.Warnings[0] | Should -Match $streamLine
            $call.Lines | Should -Contain "next statement"
        }

        It "merges the one line under 3>&1 on a plain call" {
            $call = Invoke-NativeStreamCall -Script 'param($Target) Get-DbaErrorLog -SqlInstance $Target 3>&1; "next statement"'
            $call.Merged.Count | Should -Be 1
            $call.Merged[0] | Should -Match $streamLine
            $call.Warnings.Count | Should -Be 0
            $call.Lines | Should -Contain "next statement"
        }

        It "displays nothing under -EnableException, and -WarningVariable holds the one line" -Tag "NativeChecklist:enable-exception" {
            $call = Invoke-NativeStreamCall -Script 'param($Target) try { Get-DbaErrorLog -SqlInstance $Target -EnableException -WarningVariable held 3>&1 } catch { "caught " + $PSItem.FullyQualifiedErrorId }; "held " + @($held).Count; foreach ($line in $held) { "line " + $line }'
            $call.Merged.Count | Should -Be 0
            $call.Warnings.Count | Should -Be 0
            @($call.Lines | Where-Object { $PSItem -like "caught dbatools_Get-DbaErrorLog*" }).Count | Should -Be 1
            $call.Lines | Should -Contain "held 1"
            @($call.Lines | Where-Object { $PSItem -like "line *" -and $PSItem -match $streamLine }).Count | Should -Be 1
        }

        It "leaves the warning stream empty under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $call = Invoke-NativeStreamCall -Script 'param($Target) try { Get-DbaErrorLog -SqlInstance $Target -EnableException } catch { "caught " + $PSItem.FullyQualifiedErrorId }'
            $call.Warnings.Count | Should -Be 0
            @($call.Lines | Where-Object { $PSItem -like "caught dbatools_Get-DbaErrorLog*" }).Count | Should -Be 1
        }
    }
}

Describe "Native Get-DbaErrorLog on Azure SQL Database" -Tag IntegrationTests {
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

        # One marker row in log 0 of the instance read after Azure, so a test can see that the command went on to it.
        $instance = $TestConfig.InstanceSingle
        $azureMarker = "dbatoolsci_nerla_$(Get-Random)"
        $markerSession = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
        $null = $markerSession.ConnectionContext.ExecuteNonQuery("RAISERROR(N'$azureMarker', 1, 1) WITH LOG;")
        $markerSeen = $false
        for ($attempt = 1; $attempt -le 10; $attempt++) {
            if (@($markerSession.ConnectionContext.ExecuteWithResults("EXEC sys.xp_readerrorlog 0, 1, N'$azureMarker';").Tables[0].Rows).Count -ge 1) {
                $markerSeen = $true
                break
            }
            Start-Sleep -Seconds 1
        }
        if (-not $markerSeen) {
            throw "The fixture's marker row did not reach the error log of $instance."
        }
        $refusalLine = "*Failure | *Azure SQL Database not supported*"
    }

    AfterAll {
        if ($markerSession) {
            $markerSession.ConnectionContext.Disconnect()
        }
    }

    # Azure SQL Database has no error log, and sp_readerrorlog applies to SQL Server only (Learn, sys.sp_readerrorlog). The pin connected and wrote
    # SMO's UnsupportedFeatureException for each log number (azure-zero, azure-two, azure-ee, azure-try, azure-by-name); the port refuses it as
    # Connect-DbaInstance -AzureUnsupported does (correction azure-refusal).
    It "refuses Azure SQL Database, which has no error log, and goes on to the next instance" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($azureServer, $instance); LogNumber = 0; Text = $azureMarker }
        $outside.Stop | Should -BeNullOrEmpty
        $outside.Warnings.Count | Should -Be 1
        "$($outside.Warnings[0])" | Should -BeLike $refusalLine
        @($outside.Errors | Where-Object { $PSItem.FullyQualifiedErrorId -like "UnsupportedFeatureException*" }).Count | Should -Be 0
        $outside.Rows.Count | Should -Be 1
        "$($outside.Rows[0].Text)".TrimEnd() | Should -BeExactly $azureMarker
        $outside.Next | Should -BeTrue
    }

    It "refuses Azure SQL Database on a connection by name" {
        $warnings = $null
        $results = @(Get-DbaErrorLog -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -LogNumber 0 -WarningVariable warnings -WarningAction SilentlyContinue)
        $results.Count | Should -Be 0
        @($warnings).Count | Should -Be 1
        "$($warnings[0])" | Should -BeLike $refusalLine
    }

    It "throws the refusal under -EnableException, before the next instance" -Tag "NativeChecklist:enable-exception" {
        $caught = $null
        $collected = $null
        try {
            $null = Get-DbaErrorLog -SqlInstance $azureServer, $instance -LogNumber 0 -Text $azureMarker -EnableException -OutVariable collected -WarningAction SilentlyContinue
        } catch {
            $caught = $PSItem
        }
        $caught.Exception.Message | Should -BeLike "*Azure SQL Database not supported*"
        $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaErrorLog*"
        "$($caught.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
        @($collected).Count | Should -Be 0
    }

    It "inside a caller's try, a plain call warns of the refusal and reads the next instance" {
        $failure = $null
        $after = $false
        $warnings = $null
        $results = $null
        try {
            $results = @(Get-DbaErrorLog -SqlInstance $azureServer, $instance -LogNumber 0 -Text $azureMarker -WarningVariable warnings -WarningAction SilentlyContinue)
            $after = $true
        } catch {
            $failure = $PSItem
        }
        $failure | Should -BeNullOrEmpty
        $after | Should -BeTrue
        @($warnings).Count | Should -Be 1
        "$($warnings[0])" | Should -BeLike $refusalLine
        @($results).Count | Should -Be 1
    }
}

Describe "Native Get-DbaErrorLog over SQL authentication" -Tag IntegrationTests {
    BeforeAll {
        $loginInstance = $TestConfig.InstanceSqlLogin
        $loginCred = $TestConfig.SqlLoginCred
        # Unique per leg and run: the instance is shared.
        $lowName = "dbatoolsci_nerl_low_$(Get-Random)"
        $lowPassword = "Nerl-$([guid]::NewGuid().ToString('N'))"
        $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
        $lowFaultType = "Microsoft.SqlServer.Management.Smo.FailedOperationException"

        # The instance is shared, so a fixture statement can be a deadlock victim; only error 1205 is tried again, a bounded number of times, and never a call of the command or an assertion.
        # -Finished names the one server error that means the statement has nothing left to do.
        function Invoke-NativeFixtureStatement {
            param([string]$Statement, [int]$Finished = 0)
            for ($attempt = 1; ; $attempt++) {
                try {
                    return $fixture.ConnectionContext.ExecuteNonQuery($Statement)
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

        # The fixture's connections below are passed only where a test names them.
        $fixture = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -NonPooledConnection -EnableException
        $null = Invoke-NativeFixtureStatement "USE [master]; CREATE LOGIN [$lowName] WITH PASSWORD = '$lowPassword', CHECK_POLICY = OFF;"
        $goodConnection = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -NonPooledConnection -EnableException
        $lowConnection = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $lowCred -NonPooledConnection -EnableException
        $lowFaultText = "Read error log failed for Server '$($lowConnection.Name)'. "
        # Server rows are written only at a start or a cycle, and this log is not cycled, so two reads give the same count.
        $serverRows = @{ LogNumber = 0; Source = "Server" }
    }

    AfterAll {
        $goodConnection.ConnectionContext.Disconnect()
        $lowConnection.ConnectionContext.Disconnect()
        [Microsoft.Data.SqlClient.SqlConnection]::ClearAllPools()
        foreach ($row in @($fixture.ConnectionContext.ExecuteWithResults("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$lowName';").Tables[0].Rows)) {
            # A session this block has just disconnected can end between the read above and this KILL: error 6106, and then it needs no KILL.
            $null = Invoke-NativeFixtureStatement "KILL $($row["session_id"]);" -Finished 6106
        }
        $null = Invoke-NativeFixtureStatement "IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];"
        $fixture.ConnectionContext.Disconnect()
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        It "works with -SqlCredential" {
            $result = @(Get-DbaErrorLog -SqlInstance $loginInstance -SqlCredential $loginCred @serverRows -EnableException)
            $result.Count | Should -BeGreaterThan 0
            $result[0].Source | Should -BeExactly "Server"
        }

        # no-credential.
        It "fails cleanly without the credential: a warning and no output" {
            $warnings = $null
            $result = Get-DbaErrorLog -SqlInstance $loginInstance -LogNumber 0 -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match ("\[Get-DbaErrorLog\] Failure \| Error connecting to \[" + [regex]::Escape($loginInstance) + "\]: Login failed")
        }

        # no-credential-ee.
        It "throws the connection failure under -EnableException" {
            { Get-DbaErrorLog -SqlInstance $loginInstance -LogNumber 0 -EnableException -WarningAction SilentlyContinue } | Should -Throw -ExpectedMessage "*Login failed*" -ErrorId "dbatools_Get-DbaErrorLog*"
        }
    }

    Context "A login that may not read the log" {
        # low-plain.
        It "outside any try, writes the pinned record and goes on" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $lowConnection; LogNumber = 0 }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeLogFault -Record $outside.Errors[0] -FaultType $lowFaultType -FaultText $lowFaultText
            $outside.Errors[0].Exception.GetBaseException().Message | Should -BeExactly "Caller does not have permissions to execute the stored procedure."
            $outside.Rows.Count | Should -Be 0
            $outside.Warnings.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        # low-two-logs, low-all-logs.
        It "writes one record for each log number" {
            (Invoke-NativeOutsideTry @{ SqlInstance = $lowConnection; LogNumber = @(1, 0) }).Errors.Count | Should -Be 2
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $lowConnection }
            $outside.Errors.Count | Should -Be 100
            $outside.Rows.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        # low-silent.
        It "outside any try, -ErrorAction SilentlyContinue writes no record and goes on" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $lowConnection; LogNumber = @(1, 0); ErrorAction = "SilentlyContinue" }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        # low-ee: the pin writes the record and goes on; an accepted difference, the keep-going section's point 3.
        It "outside any try, -EnableException ends the command at the record and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($lowConnection, $goodConnection); LogNumber = @(1, 0); Source = "Server"; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeLogFault -Record $outside.Errors[0] -FaultType $lowFaultType -FaultText $lowFaultText
            $outside.Rows.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        # low-stop: an accepted difference, the stop PowerShell gives WriteError.
        It "outside any try, -ErrorAction Stop turns the record into the stop PowerShell gives WriteError" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $lowConnection; LogNumber = @(1, 0); ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outside.Next | Should -BeFalse
        }

        # low-try, low-ee-try, by name as the pin was measured.
        It "inside a caller's try, the catch receives the record and the command does not go on" {
            foreach ($splat in @{ }, @{ EnableException = $true }) {
                $failure = $null
                $after = $false
                try {
                    $null = Get-DbaErrorLog -SqlInstance $loginInstance -SqlCredential $lowCred -LogNumber 1, 0 @splat
                    $after = $true
                } catch {
                    $failure = $PSItem
                }
                Assert-NativeLogFault -Record $failure -FaultType $lowFaultType -FaultText $lowFaultText
                $after | Should -BeFalse
            }
        }

        # low-stop-try.
        It "inside a caller's try, -ErrorAction Stop reaches the catch" {
            $failure = $null
            try {
                $null = Get-DbaErrorLog -SqlInstance $lowConnection -LogNumber 1, 0 -ErrorAction Stop
            } catch {
                $failure = $PSItem
            }
            Assert-NativeLogFault -Record $failure -FaultType $lowFaultType -FaultText $lowFaultText
        }

        # low-then-good, good-then-low: the other instance's rows come out, once.
        It "reads the other instance around the record" {
            $alone = @(Get-DbaErrorLog -SqlInstance $goodConnection @serverRows -EnableException).Count
            $alone | Should -BeGreaterThan 0
            $lowFirst = Invoke-NativeOutsideTry @{ SqlInstance = @($lowConnection, $goodConnection); LogNumber = 0; Source = "Server" }
            $goodFirst = Invoke-NativeOutsideTry @{ SqlInstance = @($goodConnection, $lowConnection); LogNumber = 0; Source = "Server" }
            foreach ($outside in $lowFirst, $goodFirst) {
                $outside.Errors.Count | Should -Be 1
                $outside.Rows.Count | Should -Be $alone
                $outside.Next | Should -BeTrue
            }
        }
    }
}
