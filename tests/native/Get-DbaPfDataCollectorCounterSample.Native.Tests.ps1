#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaPfDataCollectorCounterSample",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads performance counters.
# NativeChecklist: azure-sqldb N/A -- The command never opens a SQL Server connection on any code path, parameter set or pipeline input: it samples Windows performance counters of computers through the Performance Data Helper (https://learn.microsoft.com/windows/win32/perfctrs/using-the-pdh-functions-to-consume-counter-data), and lists them through Get-DbaPfDataCollectorCounter's Performance Logs and Alerts collector sets, which Azure SQL Database does not have.
# NativeChecklist: sql-login N/A -- The pinned function declares no SqlCredential and never connects to SQL Server.
# NativeChecklist: platform windows-only -- windows-binary: pdh.dll (the Performance Data Helper) and advapi32 LogonUserW, read in this process, and the Task Scheduler and Pla.DataCollectorSet COM servers of Windows through Get-DbaPfDataCollectorCounter.

Describe "Native Get-DbaPfDataCollectorCounterSample" -Tag IntegrationTests {
    BeforeAll {
        $properties = "ComputerName", "DataCollectorSet", "DataCollector", "Name", "Timestamp", "Path", "InstanceName", "CookedValue", "RawValue", "SecondValue", "MultipleCount", "CounterType", "SampleTimestamp", "SampleTimestamp100NSec", "Status", "DefaultScale", "TimeBase", "Sample", "CounterSampleObject"
        $sampleType = "Microsoft.PowerShell.Commands.GetCounter.PerformanceCounterSample"
        $setType = "Microsoft.PowerShell.Commands.GetCounter.PerformanceCounterSampleSet"
        $processorPath = '\Processor(_Total)\% Processor Time'
        $missingPath = '\dbatoolsci NoSuchObject\No Such Counter'
        $missingInstancePath = '\Process(dbatoolsci_nosuchprocess)\% Processor Time'
        $unreachableComputer = "dbatoolsci-nohost.invalid"
        $wrongTypeLine = "\[Get-DbaPfDataCollectorCounterSample\] InputObject is not of the right type\. Please use Get-DbaPfDataCollectorCounter\."
        # A made-up credential: a LOGON32_LOGON_NEW_CREDENTIALS logon takes it without checking, and this computer's counters are read
        # as the caller.
        $madeUpCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "dbatoolsci\nouser", (ConvertTo-SecureString "dbatoolsci-not-a-secret" -AsPlainText -Force)

        # Child-command error owner (operator, 2026-11-12): a record the pin passes on from Get-Counter carries this command's type in
        # place of GetCounterCommand in its id, and the activity of its owner; everything else equals Get-Counter's own record, measured
        # on the same leg.
        function Assert-NativeOwnedRecord {
            param($Actual, $Expected, [string]$ErrorId)
            $Expected | Should -Not -BeNullOrEmpty
            $Actual | Should -Not -BeNullOrEmpty
            $Expected.FullyQualifiedErrorId | Should -BeExactly "$ErrorId,Microsoft.PowerShell.Commands.GetCounterCommand"
            $Actual.FullyQualifiedErrorId | Should -BeExactly "$ErrorId,Dataplat.Dbatools.Commands.GetDbaPfDataCollectorCounterSampleCommand"
            $Actual.CategoryInfo.Activity | Should -BeExactly "Get-DbaPfDataCollectorCounterSample"
            $Actual.Exception.GetType().FullName | Should -BeExactly $Expected.Exception.GetType().FullName
            $Actual.Exception.Message | Should -BeExactly $Expected.Exception.Message
            "$($Actual.CategoryInfo.Category)" | Should -BeExactly "$($Expected.CategoryInfo.Category)"
            $Actual.CategoryInfo.Reason | Should -BeExactly $Expected.CategoryInfo.Reason
            "$($Actual.CategoryInfo.TargetName)" | Should -BeExactly "$($Expected.CategoryInfo.TargetName)"
            "$($Actual.CategoryInfo.TargetType)" | Should -BeExactly "$($Expected.CategoryInfo.TargetType)"
            "$($Actual.TargetObject)" | Should -BeExactly "$($Expected.TargetObject)"
            ($null -eq $Actual.TargetObject) | Should -Be ($null -eq $Expected.TargetObject)
            "$($Actual.ErrorDetails)" | Should -BeExactly "$($Expected.ErrorDetails)"
            $actualChain = @()
            $current = $Actual.Exception.InnerException
            while ($null -ne $current) { $actualChain += "$($current.GetType().FullName): $($current.Message)"; $current = $current.InnerException }
            $expectedChain = @()
            $current = $Expected.Exception.InnerException
            while ($null -ne $current) { $expectedChain += "$($current.GetType().FullName): $($current.Message)"; $current = $current.InnerException }
            ($actualChain -join " <- ") | Should -BeExactly ($expectedChain -join " <- ")
        }

        # A counter row as Get-DbaPfDataCollectorCounter returns it, with the properties this command reads.
        function New-NativeCounterRow {
            param([string]$Name, [string]$Computer = $env:COMPUTERNAME, [string]$Set = "nativeset", [string]$Collector = "nativecollector", $Credential)
            [pscustomobject]@{
                ComputerName     = $Computer
                DataCollectorSet = $Set
                DataCollector    = $Collector
                Name             = $Name
                CounterObject    = $true
                Credential       = $Credential
            }
        }

        # Pester wraps It bodies in try, which makes a statement error end the command. Plain calls run here, in a runspace of
        # their own, as StatementFault.Engine.Native.Tests.ps1 does.
        function Invoke-NativeOutsideTry {
            param([object[]]$Rows, [hashtable]$Arguments = @{ })
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaPfDataCollectorCounterSample -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaPfDataCollectorCounterSample", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                $outsideScript = {
                    param($pipedRows, $sampleArguments)
                    $outsideErrors = @()
                    $pipedRows | Get-DbaPfDataCollectorCounterSample @sampleArguments -ErrorVariable outsideErrors
                }
                $null = $outsideShell.AddScript($outsideScript.ToString()).AddArgument($Rows).AddArgument($Arguments)
                $outsideStop = $null
                try {
                    $null = $outsideShell.Invoke($null, $outsideOutput)
                } catch {
                    $outsideStop = $PSItem
                }
                [pscustomobject]@{
                    Output = @($outsideOutput)
                    Errors = @($outsideRunspace.SessionStateProxy.GetVariable("outsideErrors"))
                    # $Error of the runspace, newest first.
                    DollarError = @($outsideRunspace.SessionStateProxy.GetVariable("Error"))
                    # The error stream: under -EnableException the stop's record is written here as an ErrorRecord.
                    Stream = @($outsideShell.Streams.Error)
                    Stop   = $outsideStop
                }
            } finally {
                $outsideShell.Dispose()
                $outsideRunspace.Dispose()
                $outsideOutput.Dispose()
            }
        }
    }

    Context "The local computer" {
        It "samples the counters of this computer's collector sets, with the pinned properties and view" {
            $warnings = @()
            $row = Get-DbaPfDataCollectorCounterSample -WarningVariable warnings -WarningAction SilentlyContinue | Select-Object -First 1
            $row | Should -Not -BeNullOrEmpty -Because "warnings: $($warnings -join ' / ')"
            $row.ComputerName | Should -Be $env:COMPUTERNAME
            $row.Name | Should -Not -BeNullOrEmpty
            @($row.PSObject.Properties.Name) | Should -Be $properties
            # Select-DefaultView -ExcludeProperty: the remaining properties as Get-Member lists them, by name.
            @($row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) | Should -Be @($properties | Where-Object { $PSItem -notin "Sample", "CounterSampleObject" } | Sort-Object)
            $row.CounterSampleObject | Should -BeTrue
            @($row.Sample)[0].GetType().FullName | Should -Be $sampleType
            $row.Path | Should -BeLike "\\$($env:COMPUTERNAME.ToLowerInvariant())\*"
        }
    }

    Context "Counter rows piped in" {
        It "samples a counter as Get-Counter samples it" {
            $expected = @((Get-Counter -Counter $processorPath).CounterSamples)[0]
            $rows = @(New-NativeCounterRow -Name $processorPath | Get-DbaPfDataCollectorCounterSample -EnableException)
            $rows.Count | Should -Be 1
            $row = $rows[0]
            $row.ComputerName | Should -BeExactly $env:COMPUTERNAME
            $row.DataCollectorSet | Should -BeExactly "nativeset"
            $row.DataCollector | Should -BeExactly "nativecollector"
            $row.Name | Should -BeExactly $processorPath
            $row.Path | Should -BeExactly $expected.Path
            $row.InstanceName | Should -BeExactly $expected.InstanceName
            $row.CounterType | Should -Be $expected.CounterType
            $row.CounterType.GetType() | Should -Be $expected.CounterType.GetType()
            $row.DefaultScale | Should -Be $expected.DefaultScale
            $row.TimeBase | Should -Be $expected.TimeBase
            $row.Status | Should -Be 0
            $row.CookedValue | Should -BeOfType [double]
            foreach ($name in "RawValue", "SecondValue", "SampleTimestamp100NSec", "TimeBase") {
                $row.$name.GetType() | Should -Be ([uint64]) -Because $name
            }
            foreach ($name in "MultipleCount", "Status", "DefaultScale") {
                $row.$name.GetType() | Should -Be ([uint32]) -Because $name
            }
            $row.Timestamp | Should -BeOfType [datetime]
            $row.SampleTimestamp | Should -BeOfType [datetime]
            @($row.Sample).Count | Should -Be 1
            @($row.Sample)[0].Path | Should -BeExactly $expected.Path
            $row.Sample.GetType().FullName | Should -Be "$sampleType[]"
        }

        It "takes one sample and returns rows with -Continuous and -EnableException passed as false" -Tag "NativeChecklist:switch-false" {
            $warnings = @()
            $rows = @(New-NativeCounterRow -Name $processorPath | Get-DbaPfDataCollectorCounterSample -Continuous:$false -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
            $warnings.Count | Should -Be 0 -Because "warnings: $($warnings -join ' / ')"
            $rows.Count | Should -Be 1
            @($rows[0].PSObject.Properties.Name) | Should -Be $properties
        }

        It "takes -MaxSamples samples -SampleInterval seconds apart" {
            $rows = @(New-NativeCounterRow -Name $processorPath | Get-DbaPfDataCollectorCounterSample -MaxSamples 2 -SampleInterval 2 -EnableException)
            $rows.Count | Should -Be 2
            ($rows[1].Timestamp - $rows[0].Timestamp).TotalSeconds | Should -BeGreaterThan 1.5
        }

        It "reads one row for each instance of a wildcard counter path, as Get-Counter does" {
            $expected = @((Get-Counter -Counter '\Processor(*)\% Processor Time').CounterSamples | ForEach-Object Path)
            $rows = @(New-NativeCounterRow -Name '\Processor(*)\% Processor Time' | Get-DbaPfDataCollectorCounterSample -EnableException)
            @($rows | ForEach-Object Path) | Should -Be $expected
            @($rows | ForEach-Object Name | Select-Object -Unique) | Should -Be @('\Processor(*)\% Processor Time')
        }

        It "samples only the piped counters named by -Counter, ignoring case" {
            $piped = (New-NativeCounterRow -Name $processorPath), (New-NativeCounterRow -Name '\Memory\Available MBytes')
            $rows = @($piped | Get-DbaPfDataCollectorCounterSample -Counter '\MEMORY\available mbytes' -EnableException)
            @($rows | ForEach-Object Name) | Should -Be @('\Memory\Available MBytes')
        }

        It "samples several piped counters in order" -Tag "NativeChecklist:pipeline-multiple" {
            $piped = (New-NativeCounterRow -Name $processorPath), (New-NativeCounterRow -Name '\Memory\Available MBytes' -Set "otherset")
            $rows = @($piped | Get-DbaPfDataCollectorCounterSample -EnableException)
            @($rows | ForEach-Object { "$($PSItem.DataCollectorSet)|$($PSItem.Name)" }) | Should -Be @("nativeset|$processorPath", 'otherset|\Memory\Available MBytes')
        }

        It "warns for a computer that cannot be read and samples the next computer" -Tag "NativeChecklist:multi-instance-failure" {
            # A name that cannot resolve (RFC 2606), then this computer: the first row's Get-Counter fails, the second is sampled.
            $warnings = @()
            $piped = (New-NativeCounterRow -Name $processorPath -Computer $unreachableComputer), (New-NativeCounterRow -Name $processorPath)
            $rows = @($piped | Get-DbaPfDataCollectorCounterSample -WarningVariable warnings -WarningAction SilentlyContinue)
            # Get-Counter's own failure for that computer on this leg, read after the command's.
            $expected = $null
            try {
                $null = Get-Counter -ComputerName $unreachableComputer -Counter $processorPath -ErrorAction Stop
            } catch {
                $expected = $PSItem
            }
            $expected | Should -Not -BeNullOrEmpty
            $warnings.Count | Should -Be 1 -Because "warnings: $($warnings -join ' / ')"
            "$($warnings[0])" | Should -Match ("\[Get-DbaPfDataCollectorCounterSample\] Failure for $([regex]::Escape($processorPath)) on $([regex]::Escape($unreachableComputer))\. \| " + [regex]::Escape($expected.Exception.Message) + "$")
            @($rows | ForEach-Object { "$($PSItem.ComputerName)|$($PSItem.Name)" }) | Should -Be @("$($env:COMPUTERNAME)|$processorPath")
            $rows[0].Status | Should -Be 0
        }

        It "warns for a counter that cannot be read and samples the next one" {
            $warnings = @()
            $piped = (New-NativeCounterRow -Name $missingPath), (New-NativeCounterRow -Name $processorPath)
            $rows = @($piped | Get-DbaPfDataCollectorCounterSample -WarningVariable warnings -WarningAction SilentlyContinue)
            $warnings.Count | Should -Be 1 -Because "warnings: $($warnings -join ' / ')"
            "$($warnings[0])" | Should -Match "\[Get-DbaPfDataCollectorCounterSample\] Failure for $([regex]::Escape($missingPath)) on $([regex]::Escape($env:COMPUTERNAME))\. \| \S"
            @($rows | ForEach-Object Name) | Should -Be @($processorPath)
        }

        It "stops at a counter that cannot be read under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $piped = (New-NativeCounterRow -Name $missingPath), (New-NativeCounterRow -Name $processorPath)
            $rows = New-Object System.Collections.ArrayList
            $failure = $null
            try {
                $piped | Get-DbaPfDataCollectorCounterSample -EnableException -WarningAction SilentlyContinue | ForEach-Object { $null = $rows.Add($PSItem) }
            } catch {
                $failure = $PSItem
            }
            $failure | Should -Not -BeNullOrEmpty
            # Stop-Function -EnableException throws the record of the failed read: pdh.dll's own text for PDH_CSTATUS_NO_OBJECT.
            "$failure" | Should -Match "The specified object was not found on the computer\."
            $rows.Count | Should -Be 0
        }

        It "warns that the input is not of the right type and samples nothing" {
            $warnings = @()
            $rows = @([pscustomobject]@{ Name = $processorPath } | Get-DbaPfDataCollectorCounterSample -WarningVariable warnings -WarningAction SilentlyContinue)
            $rows.Count | Should -Be 0
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match $wrongTypeLine
        }
    }

    Context "A credential" {
        BeforeAll {
            $remoteComputer = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException).ComputerName
        }

        # Correction take-credential: Get-Counter has no -Credential, so upstream failed every call that had one.
        It "opens a remote computer with the credential, which a made-up one cannot" {
            # This must be the process's first read of that computer: pdh.dll keeps a computer's connection for the process once it is
            # open, whatever credential later reads bring (measured, evidence/pdh-impersonation-20261112.txt).
            $warnings = @()
            $rows = @(New-NativeCounterRow -Name $processorPath -Computer $remoteComputer | Get-DbaPfDataCollectorCounterSample -Credential $madeUpCredential -WarningVariable warnings -WarningAction SilentlyContinue)
            $rows.Count | Should -Be 0 -Because "the made-up credential cannot open $remoteComputer"
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match "Failure for $([regex]::Escape($processorPath)) on $([regex]::Escape($remoteComputer))\. \| \S"
            "$($warnings[0])" | Should -Not -Match "parameter name 'Credential'"
        }

        It "reads a remote computer's counter as the caller without a credential" {
            $expected = @((Get-Counter -ComputerName $remoteComputer -Counter $processorPath).CounterSamples)[0]
            $rows = @(New-NativeCounterRow -Name $processorPath -Computer $remoteComputer | Get-DbaPfDataCollectorCounterSample -EnableException)
            $rows.Count | Should -Be 1
            $rows[0].ComputerName | Should -BeExactly $remoteComputer
            $rows[0].Path | Should -BeExactly $expected.Path
            $rows[0].Status | Should -Be 0
        }

        It "samples with -Credential" {
            $warnings = @()
            $rows = @(New-NativeCounterRow -Name $processorPath | Get-DbaPfDataCollectorCounterSample -Credential $madeUpCredential -WarningVariable warnings -WarningAction SilentlyContinue)
            $warnings.Count | Should -Be 0 -Because "warnings: $($warnings -join ' / ')"
            @($rows | ForEach-Object Name) | Should -Be @($processorPath)
            $rows[0].Status | Should -Be 0
        }

        It "samples with the credential of a piped counter row" {
            $warnings = @()
            $rows = @(New-NativeCounterRow -Name $processorPath -Credential $madeUpCredential | Get-DbaPfDataCollectorCounterSample -WarningVariable warnings -WarningAction SilentlyContinue)
            $warnings.Count | Should -Be 0 -Because "warnings: $($warnings -join ' / ')"
            @($rows | ForEach-Object Name) | Should -Be @($processorPath)
        }
    }

    Context "Continuous sampling" {
        It "writes Get-Counter's sample sets one interval apart until stopped" {
            $continuousState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $continuousType = (Get-Command Get-DbaPfDataCollectorCounterSample -CommandType Cmdlet).ImplementingType
            $continuousState.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaPfDataCollectorCounterSample", $continuousType, $null))
            $continuousRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($continuousState)
            $continuousShell = [System.Management.Automation.PowerShell]::Create()
            $continuousOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            try {
                $continuousRunspace.Open()
                $continuousShell.Runspace = $continuousRunspace
                $null = $continuousShell.AddScript({ param($pipedRow) $pipedRow | Get-DbaPfDataCollectorCounterSample -Continuous }.ToString()).AddArgument((New-NativeCounterRow -Name $processorPath))
                $handle = $continuousShell.BeginInvoke([System.Management.Automation.PSDataCollection[psobject]]$null, $continuousOutput)
                $deadline = (Get-Date).AddSeconds(30)
                while ($continuousOutput.Count -lt 3 -and (Get-Date) -lt $deadline -and -not $handle.IsCompleted) {
                    Start-Sleep -Milliseconds 200
                }
                $stopWatch = [System.Diagnostics.Stopwatch]::StartNew()
                $continuousShell.Stop()
                $stopWatch.Stop()
                $sets = @($continuousOutput)
                $sets.Count | Should -BeGreaterOrEqual 3 -Because "errors: $(@($continuousShell.Streams.Error) -join ' / ')"
                $stopWatch.Elapsed.TotalSeconds | Should -BeLessThan 5
                $sets[0].PSObject.TypeNames[0] | Should -Be $setType
                @($sets[0].CounterSamples)[0].GetType().FullName | Should -Be $sampleType
                @($sets[0].CounterSamples)[0].Path | Should -BeLike "\\*\processor(_total)\% processor time"
                ($sets[2].Timestamp - $sets[1].Timestamp).TotalSeconds | Should -BeGreaterThan 0.5
                @($continuousShell.Streams.Error).Count | Should -Be 0
            } finally {
                $continuousShell.Dispose()
                $continuousRunspace.Dispose()
                $continuousOutput.Dispose()
            }
        }
    }

    Context "-Continuous with -MaxSamples, which Get-Counter refuses" {
        BeforeAll {
            $refusal = "The Continuous parameter and the MaxSamples parameter cannot be used in the same command\."
            $refusedRows = (New-NativeCounterRow -Name $processorPath), (New-NativeCounterRow -Name '\Memory\Available MBytes')
        }

        It "writes the refusal for each counter and goes on, outside any try" {
            $result = Invoke-NativeOutsideTry -Rows $refusedRows -Arguments @{ Continuous = $true; MaxSamples = 2 }
            $result.Stop | Should -BeNullOrEmpty
            $result.Output.Count | Should -Be 0
            $result.Errors.Count | Should -Be 2
            foreach ($record in $result.Errors) {
                "$record" | Should -Match $refusal
            }
        }

        It "stops at the first counter under -EnableException, without ending the caller's script" -Tag "NativeChecklist:enable-exception" {
            $result = Invoke-NativeOutsideTry -Rows $refusedRows -Arguments @{ Continuous = $true; MaxSamples = 2; EnableException = $true }
            $result.Stop | Should -BeNullOrEmpty
            $result.Stream.Count | Should -Be 1
            "$($result.Stream[0])" | Should -Match $refusal
        }

        It "stops at the first counter under -ErrorAction Stop" {
            $result = Invoke-NativeOutsideTry -Rows $refusedRows -Arguments @{ Continuous = $true; MaxSamples = 2; ErrorAction = "Stop" }
            $result.Stop | Should -Not -BeNullOrEmpty
            "$($result.Stop)" | Should -Match $refusal
        }

        It "stops at the first counter inside a caller's try, with or without -EnableException or -ErrorAction Stop" {
            foreach ($extra in @{ }, @{ EnableException = $true }, @{ ErrorAction = "Stop" }) {
                $caught = $null
                try {
                    $refusedRows | Get-DbaPfDataCollectorCounterSample -Continuous -MaxSamples 2 @extra
                } catch {
                    $caught = $PSItem
                }
                $caught | Should -Not -BeNullOrEmpty
                "$caught" | Should -Match $refusal
            }
        }

        It "carries Get-Counter's refusal record in the error stream, -ErrorVariable, `$Error and a caller's catch" {
            # Child-command error owner (operator, 2026-11-12), id CounterContinuousOrMaxSamples: Get-Counter's own record on this leg.
            $expected = $null
            try {
                $null = Get-Counter -Counter $processorPath -Continuous -MaxSamples 2
            } catch {
                $expected = $PSItem
            }
            $result = Invoke-NativeOutsideTry -Rows $refusedRows -Arguments @{ Continuous = $true; MaxSamples = 2 }
            # The pin, outside any try: one record per counter in each (evidence/pin-pfsample-records-20261112.txt, both editions).
            $records = @($result.Errors | Where-Object { $PSItem -is [System.Management.Automation.ErrorRecord] })
            $records.Count | Should -Be 2
            $result.Stream.Count | Should -Be 2
            $result.DollarError.Count | Should -Be 2
            foreach ($record in $records + $result.Stream + $result.DollarError) {
                Assert-NativeOwnedRecord -Actual $record -Expected $expected -ErrorId "CounterContinuousOrMaxSamples"
            }
            foreach ($extra in @{ }, @{ EnableException = $true }, @{ ErrorAction = "Stop" }) {
                $caught = $null
                try {
                    $refusedRows | Get-DbaPfDataCollectorCounterSample -Continuous -MaxSamples 2 @extra
                } catch {
                    $caught = $PSItem
                }
                Assert-NativeOwnedRecord -Actual $caught -Expected $expected -ErrorId "CounterContinuousOrMaxSamples"
            }
        }
    }

    Context "-Continuous with a counter Get-Counter cannot read" {
        It "writes Get-Counter's record for a missing object and for a missing instance, and samples nothing" {
            # Child-command error owner (operator, 2026-11-12), ids CounterApiError and CounterPathIsInvalid: Get-Counter -Continuous writes
            # the error and returns when no path is left (evidence/pin-pfsample-records-20261112.txt, both editions).
            foreach ($case in @{ Path = $missingPath; ErrorId = "CounterApiError" }, @{ Path = $missingInstancePath; ErrorId = "CounterPathIsInvalid" }) {
                $expectedErrors = @()
                $null = Get-Counter -Counter $case.Path -Continuous -ErrorVariable expectedErrors -ErrorAction SilentlyContinue
                $expectedErrors.Count | Should -Be 1 -Because $case.Path
                $result = Invoke-NativeOutsideTry -Rows (New-NativeCounterRow -Name $case.Path) -Arguments @{ Continuous = $true }
                $result.Stop | Should -BeNullOrEmpty -Because $case.Path
                $result.Output.Count | Should -Be 0 -Because $case.Path
                $result.Errors.Count | Should -Be 1 -Because $case.Path
                $result.Stream.Count | Should -Be 1 -Because $case.Path
                $result.DollarError.Count | Should -Be 1 -Because $case.Path
                foreach ($record in $result.Errors + $result.Stream + $result.DollarError) {
                    Assert-NativeOwnedRecord -Actual $record -Expected $expectedErrors[0] -ErrorId $case.ErrorId
                }
            }
        }
    }

    Context "The record of a failed Get-Counter call, kept beside the warning" {
        It "keeps Get-Counter's record in `$Error and -ErrorVariable without showing it, with Stop-Function's" {
            # The pin catches Get-Counter -ErrorAction Stop: $Error holds Stop-Function's record, then Get-Counter's; -ErrorVariable holds
            # Get-Counter's, then Stop-Function's; nothing is shown (evidence/pin-pfsample-records-20261112.txt, both editions).
            foreach ($case in @{ Path = $missingPath; ErrorId = "CounterApiError" }, @{ Path = $missingInstancePath; ErrorId = "CounterPathIsInvalid" }) {
                $expected = $null
                try {
                    $null = Get-Counter -Counter $case.Path -ErrorAction Stop
                } catch {
                    $expected = $PSItem
                }
                $result = Invoke-NativeOutsideTry -Rows (New-NativeCounterRow -Name $case.Path), (New-NativeCounterRow -Name $processorPath)
                $result.Stop | Should -BeNullOrEmpty -Because $case.Path
                @($result.Output | ForEach-Object Name) | Should -Be @($processorPath) -Because $case.Path
                $result.Stream.Count | Should -Be 0 -Because $case.Path
                $result.DollarError.Count | Should -Be 2 -Because $case.Path
                $result.DollarError[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaPfDataCollectorCounterSample*" -Because $case.Path
                Assert-NativeOwnedRecord -Actual $result.DollarError[1] -Expected $expected -ErrorId $case.ErrorId
                $records = @($result.Errors | Where-Object { $PSItem -is [System.Management.Automation.ErrorRecord] })
                $records.Count | Should -Be 2 -Because $case.Path
                Assert-NativeOwnedRecord -Actual $records[0] -Expected $expected -ErrorId $case.ErrorId
                $records[1].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaPfDataCollectorCounterSample*" -Because $case.Path
            }
        }
    }

    Context "A counter row property that cannot be read" {
        BeforeAll {
            # The statement errors of the pin's body: reading $InputObject.Credential and reading $InputObject.CounterObject. A compiled
            # getter throws, not a script property, whose script block would belong to this runspace and not the helper's.
            if (-not ("NativePfSampleTests.FaultingCounterRow" -as [type])) {
                Add-Type -TypeDefinition @"
using System;
namespace NativePfSampleTests {
    public sealed class FaultingCounterRow {
        private readonly string _fault;
        private readonly string _computer;
        public FaultingCounterRow(string fault, string computer) { _fault = fault; _computer = computer; }
        private object Read(string name, object value) {
            if (name == _fault) { throw new InvalidOperationException("dbatoolsci fault"); }
            return value;
        }
        public object ComputerName { get { return Read("ComputerName", _computer); } }
        public object DataCollectorSet { get { return Read("DataCollectorSet", "faultyset"); } }
        public object DataCollector { get { return Read("DataCollector", "faultycollector"); } }
        public object Name { get { return Read("Name", "\\System\\Processes"); } }
        public object CounterObject { get { return Read("CounterObject", true); } }
        public object Credential { get { return Read("Credential", null); } }
    }
}
"@
            }
            $faultMessage = "dbatoolsci fault"
            $faultRows = {
                param([string]$Property)
                (New-NativeCounterRow -Name '\System\Threads' -Set "goodfirst"), (New-Object NativePfSampleTests.FaultingCounterRow -ArgumentList $Property, $env:COMPUTERNAME)
            }
        }

        It "writes the error and samples every counter, outside any try" {
            foreach ($property in "Credential", "CounterObject") {
                $result = Invoke-NativeOutsideTry -Rows (& $faultRows $property)
                $result.Stop | Should -BeNullOrEmpty -Because $property
                @($result.Output | ForEach-Object { "$($PSItem.DataCollectorSet)|$($PSItem.Name)" }) | Should -Be @('goodfirst|\System\Threads', 'faultyset|\System\Processes') -Because $property
                $result.Errors.Count | Should -Be 1 -Because $property
                "$($result.Errors[0])" | Should -Match $faultMessage -Because $property
            }
        }

        It "stops at the faulting row under -EnableException" -Tag "NativeChecklist:enable-exception" {
            foreach ($property in "Credential", "CounterObject") {
                $result = Invoke-NativeOutsideTry -Rows (& $faultRows $property) -Arguments @{ EnableException = $true }
                $result.Stop | Should -BeNullOrEmpty -Because $property
                @($result.Output | ForEach-Object { "$($PSItem.DataCollectorSet)|$($PSItem.Name)" }) | Should -Be @('goodfirst|\System\Threads') -Because $property
                $result.Stream.Count | Should -Be 1 -Because $property
                "$($result.Stream[0])" | Should -Match $faultMessage -Because $property
            }
        }

        It "stops at the faulting row under -ErrorAction Stop and inside a caller's try" {
            foreach ($property in "Credential", "CounterObject") {
                $result = Invoke-NativeOutsideTry -Rows (& $faultRows $property) -Arguments @{ ErrorAction = "Stop" }
                "$($result.Stop)" | Should -Match $faultMessage -Because $property
                @($result.Output | ForEach-Object { "$($PSItem.DataCollectorSet)|$($PSItem.Name)" }) | Should -Be @('goodfirst|\System\Threads') -Because $property
                $caught = $null
                $rows = New-Object System.Collections.ArrayList
                try {
                    & $faultRows $property | Get-DbaPfDataCollectorCounterSample | ForEach-Object { $null = $rows.Add($PSItem) }
                } catch {
                    $caught = $PSItem
                }
                "$caught" | Should -Match $faultMessage -Because $property
                $rows.Count | Should -Be 1 -Because $property
            }
        }
    }
}
