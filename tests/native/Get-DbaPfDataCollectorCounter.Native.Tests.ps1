#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaPfDataCollectorCounter",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads collector counters.
# NativeChecklist: azure-sqldb N/A -- The command never opens a SQL Server connection on any code path, parameter set or pipeline input: it reads the Windows Performance Logs and Alerts collector sets of computers through Get-DbaPfDataCollector, the Task Scheduler and Pla.DataCollectorSet COM objects (https://learn.microsoft.com/windows/win32/api/pla/nn-pla-idatacollectorset), locally or over PowerShell remoting.
# NativeChecklist: sql-login N/A -- The pinned function declares no SqlCredential and never connects to SQL Server.
# NativeChecklist: platform windows-only -- windows-binary: the Task Scheduler (Schedule.Service) and Performance Logs and Alerts (Pla.DataCollectorSet) COM servers of Windows, read through Get-DbaPfDataCollector in this process for the local computer and in a remote session otherwise.

Describe "Native Get-DbaPfDataCollectorCounter" -Tag IntegrationTests {
    BeforeAll {
        $properties = "ComputerName", "DataCollectorSet", "DataCollector", "DataCollectorSetXml", "Name", "FileName", "CounterObject", "Credential"
        # Select-DefaultView -ExcludeProperty: the remaining properties as Get-Member lists them, by name.
        $columns = "ComputerName", "DataCollector", "DataCollectorSet", "FileName", "Name"
        $missingComputer = "dbatoolsci-nohost-$(Get-Random)"
        $wrongTypeLine = "\[Get-DbaPfDataCollectorCounter\] InputObject is not of the right type\. Please use Get-DbaPfDataCollector\."
        $setXml = "<DataCollectorSet><Name>nativeset</Name></DataCollectorSet>"

        # A collector as Get-DbaPfDataCollector returns it, with the properties this command reads.
        function New-NativeCollector {
            param([string]$Name, $Counters, [string]$Set = "nativeset", [string]$Computer = "nativehost", [string]$FileName = "nativefile", $Credential)
            [pscustomobject]@{
                ComputerName        = $Computer
                DataCollectorSet    = $Set
                Name                = $Name
                FileName            = $FileName
                DataCollectorSetXml = $setXml
                Counters            = $Counters
                DataCollectorObject = $true
                Credential          = $Credential
            }
        }

        function Format-NativeRow {
            param($Row)
            "$($Row.ComputerName)|$($Row.DataCollectorSet)|$($Row.DataCollector)|$($Row.Name)"
        }

        # An independent read of this computer's collector sets: every PLA task once (TASK_ENUM_HIDDEN lists the hidden and the
        # visible tasks), each set that Pla.DataCollectorSet can query, and the counters of each performance counter collector.
        function Get-NativeLocalCounter {
            $schedule = New-Object -ComObject "Schedule.Service"
            $schedule.Connect()
            $folder = $schedule.GetFolder("Microsoft\Windows\PLA")
            # Sets that other native tests on this computer make for a while are left out.
            $names = @($folder.GetTasks(1) | ForEach-Object { $PSItem.Name } | Where-Object { $PSItem -notlike "dbatoolsci_*" })
            $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject($schedule)
            $query = New-Object -ComObject Pla.DataCollectorSet
            $rows = foreach ($name in $names) {
                # A set that cannot be queried is left out, as the command leaves it out; a refusal is tried again first (see
                # Invoke-NativeLocalRead).
                $queried = $false
                for ($attempt = 1; $attempt -le 3 -and -not $queried; $attempt++) {
                    try {
                        $query.Query($name, $null)
                        $queried = $true
                    } catch {
                        $queried = $false
                    }
                }
                if (-not $queried) {
                    continue
                }
                $document = [xml]$query.Xml
                foreach ($collector in @($document.DataCollectorSet.PerformanceCounterDataCollector)) {
                    foreach ($counter in $collector.Counter) {
                        [pscustomobject]@{
                            Set       = $name
                            Collector = $collector.Name
                            Counter   = $counter
                            Line      = "$env:COMPUTERNAME|$name|$($collector.Name)|$counter"
                        }
                    }
                }
            }
            , @($rows)
        }

        # A read of this computer through the command. The six legs read this computer's collector sets at the same time; when
        # Pla.DataCollectorSet refuses a Query the command warns "Issue with getting Collector Set ..." and leaves the set out, as
        # the pin does, so a read with that warning is made again, at most three times. Every warning is kept for the assertion
        # messages.
        function Invoke-NativeLocalRead {
            param([hashtable]$Arguments = @{ }, [object[]]$Piped)
            $allWarnings = @()
            $rows = @()
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                $readWarnings = @()
                if ($Piped) {
                    $rows = @($Piped | Get-DbaPfDataCollectorCounter @Arguments -WarningVariable readWarnings -WarningAction SilentlyContinue)
                } else {
                    $rows = @(Get-DbaPfDataCollectorCounter @Arguments -WarningVariable readWarnings -WarningAction SilentlyContinue)
                }
                $allWarnings += @($readWarnings | ForEach-Object { "attempt $($attempt): $PSItem" })
                if (@($readWarnings | Where-Object { "$PSItem" -match "Issue with getting Collector Set" }).Count -eq 0) {
                    break
                }
            }
            [pscustomobject]@{
                Rows     = $rows
                Warnings = "warnings: " + ($allWarnings -join " / ")
                # The warnings of the read whose rows are returned.
                Last     = @($readWarnings | ForEach-Object { "$PSItem" })
            }
        }

        # Pester wraps It bodies in try, which makes a statement error end the command. Plain calls run here, in a runspace of
        # their own, as StatementFault.Engine.Native.Tests.ps1 does.
        function Invoke-NativeOutsideTry {
            param([object[]]$Collectors, [hashtable]$Arguments = @{ })
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaPfDataCollectorCounter -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaPfDataCollectorCounter", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                $outsideScript = {
                    param($pipedCollectors, $counterArguments)
                    $outsideErrors = @()
                    $pipedCollectors | Get-DbaPfDataCollectorCounter @counterArguments -ErrorVariable outsideErrors
                }
                $null = $outsideShell.AddScript($outsideScript.ToString()).AddArgument($Collectors).AddArgument($Arguments)
                $outsideStop = $null
                try {
                    $null = $outsideShell.Invoke($null, $outsideOutput)
                } catch {
                    $outsideStop = $PSItem
                }
                [pscustomobject]@{
                    Output = @($outsideOutput)
                    Errors = @($outsideRunspace.SessionStateProxy.GetVariable("outsideErrors"))
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

    Context "Collectors piped in" {
        BeforeAll {
            $collectorA = New-NativeCollector -Name "Collector A" -Counters @('\Processor(_Total)\% Processor Time', '\Memory\Available MBytes')
            $collectorB = New-NativeCollector -Name "Collector B" -Counters '\System\Processes' -FileName $null
        }

        It "returns one row per counter of a piped collector, with the pinned properties" {
            $rows = @($collectorA | Get-DbaPfDataCollectorCounter -EnableException)
            $rows.Count | Should -Be 2
            $rows[0].ComputerName | Should -BeExactly "nativehost"
            $rows[0].DataCollectorSet | Should -BeExactly "nativeset"
            $rows[0].DataCollector | Should -BeExactly "Collector A"
            $rows[0].DataCollectorSetXml | Should -BeExactly $setXml
            $rows[0].Name | Should -BeExactly '\Processor(_Total)\% Processor Time'
            $rows[0].FileName | Should -BeExactly "nativefile"
            $rows[0].CounterObject | Should -BeTrue
            $rows[0].Credential | Should -BeNullOrEmpty
            $rows[1].Name | Should -BeExactly '\Memory\Available MBytes'
        }

        It "returns the pinned properties in order, with the default view of Select-DefaultView -ExcludeProperty" {
            $row = $collectorA | Get-DbaPfDataCollectorCounter -EnableException | Select-Object -First 1
            @($row.PSObject.Properties.Name) | Should -Be $properties
            @($row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) | Should -Be $columns
        }

        It "reads a collector with one counter" {
            $rows = @($collectorB | Get-DbaPfDataCollectorCounter -EnableException)
            @($rows | ForEach-Object { Format-NativeRow $PSItem }) | Should -Be @('nativehost|nativeset|Collector B|\System\Processes')
            $rows[0].FileName | Should -BeNullOrEmpty
        }

        It "reads several piped collectors in order" -Tag "NativeChecklist:pipeline-multiple" {
            $other = New-NativeCollector -Name "Collector C" -Counters '\System\Threads' -Set "otherset" -Computer "otherhost"
            $rows = @($collectorA, $collectorB, $other | Get-DbaPfDataCollectorCounter -EnableException)
            @($rows | ForEach-Object { Format-NativeRow $PSItem }) | Should -Be @(
                'nativehost|nativeset|Collector A|\Processor(_Total)\% Processor Time',
                'nativehost|nativeset|Collector A|\Memory\Available MBytes',
                'nativehost|nativeset|Collector B|\System\Processes',
                'otherhost|otherset|Collector C|\System\Threads'
            )
        }

        It "returns the counter named by -Counter, ignoring case" {
            $rows = @($collectorA, $collectorB | Get-DbaPfDataCollectorCounter -Counter '\MEMORY\available mbytes' -EnableException)
            @($rows | ForEach-Object { Format-NativeRow $PSItem }) | Should -Be @('nativehost|nativeset|Collector A|\Memory\Available MBytes')
        }

        It "returns the counters named by several -Counter values" {
            $rows = @($collectorA, $collectorB | Get-DbaPfDataCollectorCounter -Counter '\System\Processes', '\Processor(_Total)\% Processor Time' -EnableException)
            @($rows.Name) | Should -Be @('\Processor(_Total)\% Processor Time', '\System\Processes')
        }

        It "matches -Counter by the exact counter path, as the help describes" {
            $rows = @($collectorA | Get-DbaPfDataCollectorCounter -Counter '\Memory\*' -EnableException)
            $rows.Count | Should -Be 0
        }

        It "returns nothing for a collector without counters" {
            $rows = @((New-NativeCollector -Name "Empty" -Counters $null) | Get-DbaPfDataCollectorCounter -EnableException)
            $rows.Count | Should -Be 0
        }

        It "reads the collectors Get-DbaPfDataCollector returns for a piped collector set" {
            $collectorXml = "<PerformanceCounterDataCollector><Name>Piped Collector</Name><FileName>pipedfile</FileName><Counter>\Processor(_Total)\% Processor Time</Counter><Counter>\Memory\Available MBytes</Counter></PerformanceCounterDataCollector>"
            $pipedXml = "<DataCollectorSet><Name>pipedset</Name>$collectorXml</DataCollectorSet>"
            $set = [pscustomobject]@{
                ComputerName           = "nativehost"
                Name                   = "pipedset"
                Xml                    = $pipedXml
                DataCollectorSetObject = $true
                Credential             = $null
            }
            $rows = @($set | Get-DbaPfDataCollector -EnableException | Get-DbaPfDataCollectorCounter -EnableException)
            @($rows | ForEach-Object { Format-NativeRow $PSItem }) | Should -Be @(
                'nativehost|pipedset|Piped Collector|\Processor(_Total)\% Processor Time',
                'nativehost|pipedset|Piped Collector|\Memory\Available MBytes'
            )
            @($rows.FileName | Select-Object -Unique) | Should -Be @("pipedfile")
            @($rows.DataCollectorSetXml | Select-Object -Unique) | Should -Be @($pipedXml)
        }

        It "takes the piped collector's credential when -Credential is not given, and -Credential when it is" {
            $password = ConvertTo-SecureString -String "nativepassword" -AsPlainText -Force
            $collectorCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "nativecollector\user", $password
            $givenCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "nativegiven\user", $password
            $withCredential = New-NativeCollector -Name "Collector A" -Counters @('\System\Processes', '\System\Threads') -Credential $collectorCredential
            $rows = @($withCredential | Get-DbaPfDataCollectorCounter -EnableException)
            @($rows | ForEach-Object { $PSItem.Credential.UserName }) | Should -Be @("nativecollector\user", "nativecollector\user")
            $rows = @($withCredential | Get-DbaPfDataCollectorCounter -Credential $givenCredential -EnableException)
            @($rows | ForEach-Object { $PSItem.Credential.UserName }) | Should -Be @("nativegiven\user", "nativegiven\user")
        }

        It "reads the computers of -ComputerName after the piped collectors" {
            $result = Invoke-NativeLocalRead -Piped $collectorB -Arguments @{ ComputerName = $env:COMPUTERNAME }
            $rows = $result.Rows
            $rows.Count | Should -BeGreaterThan 1 -Because $result.Warnings
            Format-NativeRow $rows[0] | Should -BeExactly 'nativehost|nativeset|Collector B|\System\Processes'
            @($rows[1..($rows.Count - 1)].ComputerName | Select-Object -Unique) | Should -Be @($env:COMPUTERNAME)
        }
    }

    Context "Values that are not collectors" {
        It "warns that a piped value is not a collector and returns nothing" {
            $warnings = @()
            $rows = @("foo" | Get-DbaPfDataCollectorCounter -WarningVariable warnings -WarningAction SilentlyContinue)
            $rows.Count | Should -Be 0
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match $wrongTypeLine
        }

        It "reads a collector piped after a wrong value, under -EnableException:`$false too" -Tag "NativeChecklist:switch-false" {
            $warnings = @()
            $collector = New-NativeCollector -Name "Collector A" -Counters @('\System\Processes', '\System\Threads')
            $rows = @("foo", $collector | Get-DbaPfDataCollectorCounter -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
            @($rows.Name) | Should -Be @('\System\Processes', '\System\Threads')
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match $wrongTypeLine
        }

        It "throws for a wrong value under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $failure = $null
            try {
                $null = "foo" | Get-DbaPfDataCollectorCounter -EnableException -WarningAction SilentlyContinue
            } catch {
                $failure = $PSItem
            }
            $failure | Should -Not -BeNullOrEmpty
            $failure.FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaPfDataCollectorCounter(,|$)"
            $failure.Exception.Message | Should -Match "InputObject is not of the right type\. Please use Get-DbaPfDataCollector\."
        }
    }

    Context "A collector property that cannot be read" {
        BeforeAll {
            # The statement errors of the pin's body: reading $InputObject.Credential, reading $InputObject.DataCollectorObject, the
            # counter loop reading $counterobject.Counters and the row reading $counterobject.ComputerName. A compiled getter throws,
            # not a script property, whose script block would belong to this runspace and not the helper's.
            if (-not ("NativePfCounterTests.FaultingCollector" -as [type])) {
                Add-Type -TypeDefinition @"
using System;
namespace NativePfCounterTests {
    public sealed class FaultingCollector {
        private readonly string _fault;
        public FaultingCollector(string fault) { _fault = fault; }
        private object Read(string name, object value) {
            if (name == _fault) { throw new InvalidOperationException("dbatoolsci fault"); }
            return value;
        }
        public object ComputerName { get { return Read("ComputerName", "nativehost"); } }
        public object DataCollectorSet { get { return Read("DataCollectorSet", "faultyset"); } }
        public object Name { get { return Read("Name", "Faulty"); } }
        public object FileName { get { return Read("FileName", "faultyfile"); } }
        public object DataCollectorSetXml { get { return Read("DataCollectorSetXml", "<DataCollectorSet />"); } }
        public object Counters { get { return Read("Counters", new object[] { "\\System\\Processes", "\\System\\Threads" }); } }
        public object DataCollectorObject { get { return Read("DataCollectorObject", true); } }
        public object Credential { get { return Read("Credential", null); } }
    }
}
"@
            }
            function New-NativeFaultCollectors {
                param([string]$Property)
                $faulty = New-Object NativePfCounterTests.FaultingCollector -ArgumentList $Property
                $first = New-NativeCollector -Name "First" -Set "goodfirst" -Counters @('\System\Processes', '\System\Threads')
                $last = New-NativeCollector -Name "Last" -Set "goodlast" -Counters @('\System\Processes', '\System\Threads')
                @($first, $faulty, $last)
            }
            $faultCases = @(
                @{ Property = "Credential"; PlainRows = 6; PlainErrors = 1 },
                @{ Property = "DataCollectorObject"; PlainRows = 6; PlainErrors = 1 },
                @{ Property = "Counters"; PlainRows = 4; PlainErrors = 1 },
                # Each counter of the collector faults on its own.
                @{ Property = "ComputerName"; PlainRows = 4; PlainErrors = 2 }
            )
            $faultMessage = "dbatoolsci fault"
            $firstRows = @('nativehost|goodfirst|First|\System\Processes', 'nativehost|goodfirst|First|\System\Threads')
        }

        It "writes the error and goes on with the next statement, outside any try" {
            foreach ($case in $faultCases) {
                $result = Invoke-NativeOutsideTry -Collectors (New-NativeFaultCollectors -Property $case.Property)
                $result.Stop | Should -BeNullOrEmpty -Because $case.Property
                @($result.Output).Count | Should -Be $case.PlainRows -Because $case.Property
                @($result.Output | Where-Object DataCollectorSet -eq "goodlast").Count | Should -Be 2 -Because $case.Property
                $result.Errors.Count | Should -Be $case.PlainErrors -Because $case.Property
                foreach ($record in $result.Errors) {
                    "$record" | Should -Match $faultMessage -Because $case.Property
                }
            }
        }

        It "stops at the collector under -EnableException, without ending the caller's script" -Tag "NativeChecklist:enable-exception" {
            foreach ($case in $faultCases) {
                $result = Invoke-NativeOutsideTry -Collectors (New-NativeFaultCollectors -Property $case.Property) -Arguments @{ EnableException = $true }
                $result.Stop | Should -BeNullOrEmpty -Because $case.Property
                @($result.Output | ForEach-Object { Format-NativeRow $PSItem }) | Should -Be $firstRows -Because $case.Property
                $result.Stream.Count | Should -Be 1 -Because $case.Property
                $result.Stream[0] | Should -BeOfType System.Management.Automation.ErrorRecord
                "$($result.Stream[0])" | Should -Match $faultMessage -Because $case.Property
            }
        }

        It "stops at the collector under -ErrorAction Stop" {
            foreach ($case in $faultCases) {
                $result = Invoke-NativeOutsideTry -Collectors (New-NativeFaultCollectors -Property $case.Property) -Arguments @{ ErrorAction = "Stop" }
                $result.Stop | Should -Not -BeNullOrEmpty -Because $case.Property
                "$($result.Stop)" | Should -Match $faultMessage -Because $case.Property
                @($result.Output | ForEach-Object { Format-NativeRow $PSItem }) | Should -Be $firstRows -Because $case.Property
            }
        }

        It "stops at the collector inside a caller's try, with or without -EnableException or -ErrorAction Stop" {
            foreach ($case in $faultCases) {
                foreach ($extra in @{ }, @{ EnableException = $true }, @{ ErrorAction = "Stop" }) {
                    $collectors = New-NativeFaultCollectors -Property $case.Property
                    $caught = $null
                    $rows = New-Object System.Collections.ArrayList
                    try {
                        $collectors | Get-DbaPfDataCollectorCounter @extra | ForEach-Object { $null = $rows.Add($PSItem) }
                    } catch {
                        $caught = $PSItem
                    }
                    $caught | Should -Not -BeNullOrEmpty -Because $case.Property
                    "$caught" | Should -Match $faultMessage -Because $case.Property
                    @($rows | ForEach-Object { Format-NativeRow $PSItem }) | Should -Be $firstRows -Because $case.Property
                }
            }
        }
    }

    Context "The local computer" {
        BeforeAll {
            $localCounters = Get-NativeLocalCounter
            $localPick = $localCounters | Select-Object -First 1
        }

        It "returns every counter of every collector of every collector set once" {
            # Read again right before the call, so the comparison spans as short a time as possible.
            $expected = @((Get-NativeLocalCounter).Line)
            $expected.Count | Should -BeGreaterThan 0
            $result = Invoke-NativeLocalRead
            $rows = @($result.Rows | Where-Object DataCollectorSet -notlike "dbatoolsci_*")
            @($rows | ForEach-Object { Format-NativeRow $PSItem } | Sort-Object) | Should -Be @($expected | Sort-Object) -Because $result.Warnings
        }

        It "returns the counters of the set and collector named by -CollectorSet and -Collector" {
            $expected = @($localCounters | Where-Object { $PSItem.Set -eq $localPick.Set -and $PSItem.Collector -eq $localPick.Collector } | ForEach-Object Line)
            $result = Invoke-NativeLocalRead -Arguments @{ CollectorSet = $localPick.Set; Collector = $localPick.Collector }
            @($result.Rows | ForEach-Object { Format-NativeRow $PSItem } | Sort-Object) | Should -Be @($expected | Sort-Object) -Because $result.Warnings
        }

        It "returns only the counter named by -Counter, ignoring case" {
            $expected = @($localCounters | Where-Object Counter -eq $localPick.Counter | ForEach-Object Line)
            $result = Invoke-NativeLocalRead -Arguments @{ Counter = $localPick.Counter.ToUpper() }
            $rows = @($result.Rows | Where-Object DataCollectorSet -notlike "dbatoolsci_*")
            @($rows | ForEach-Object { Format-NativeRow $PSItem } | Sort-Object) | Should -Be @($expected | Sort-Object) -Because $result.Warnings
        }

        It "returns nothing and warns of nothing for a collector set that does not exist" {
            $warnings = @()
            $rows = @(Get-DbaPfDataCollectorCounter -CollectorSet "dbatoolsci-noset-$(Get-Random)" -WarningVariable warnings)
            $rows.Count | Should -Be 0
            $warnings.Count | Should -Be 0
        }
    }

    Context "A remote computer" {
        BeforeAll {
            $remoteServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
            $remoteComputer = $remoteServer.ComputerName
            # An independent read of the same computer in a session of its own: every PLA task once, each counter of each collector.
            $remoteState = Invoke-Command -ComputerName $remoteComputer -ScriptBlock {
                $schedule = New-Object -ComObject "Schedule.Service"
                $schedule.Connect()
                $folder = $schedule.GetFolder("Microsoft\Windows\PLA")
                $names = @($folder.GetTasks(1) | ForEach-Object { $PSItem.Name })
                $query = New-Object -ComObject Pla.DataCollectorSet
                $rows = foreach ($name in $names) {
                    try {
                        $query.Query($name, $null)
                    } catch {
                        continue
                    }
                    $document = [xml]$query.Xml
                    foreach ($collector in @($document.DataCollectorSet.PerformanceCounterDataCollector)) {
                        foreach ($counter in $collector.Counter) {
                            "$env:COMPUTERNAME|$name|$($collector.Name)|$counter"
                        }
                    }
                }
                [pscustomobject]@{
                    Name = $env:COMPUTERNAME
                    Rows = @($rows)
                }
            }
        }

        It "reads the remote computer's counters with its own computer name" {
            $warnings = @()
            $rows = @(Get-DbaPfDataCollectorCounter -ComputerName $remoteComputer -WarningVariable warnings -WarningAction SilentlyContinue)
            @($warnings | Where-Object { "$PSItem" -match "\[Get-DbaPfDataCollectorSet\] Failure" }).Count | Should -Be 0
            (@($rows | ForEach-Object { Format-NativeRow $PSItem } | Sort-Object -Unique) -join ";") | Should -BeExactly (@($remoteState.Rows | Sort-Object -Unique) -join ";")
            @($rows.ComputerName | Select-Object -Unique | Where-Object { $PSItem -ne $remoteState.Name }).Count | Should -Be 0
        }
    }

    Context "A computer that cannot be reached" -Tag "NativeChecklist:multi-instance-failure" {
        It "warns under Get-DbaPfDataCollectorSet and reads the next computer" {
            $result = Invoke-NativeLocalRead -Arguments @{ ComputerName = $missingComputer, $env:COMPUTERNAME }
            $rows = $result.Rows
            $failures = @($result.Last | Where-Object { "$PSItem" -match "\[Get-DbaPfDataCollectorSet\]" })
            $failures.Count | Should -Be 1 -Because $result.Warnings
            "$($failures[0])" | Should -Match "\[Get-DbaPfDataCollectorSet\] Failure \| Connecting to remote server $([regex]::Escape($missingComputer)) failed"
            $rows.Count | Should -BeGreaterThan 0 -Because $result.Warnings
            @($rows.ComputerName | Select-Object -Unique) | Should -Be @($env:COMPUTERNAME)
        }

        It "only warns for that computer under -EnableException, as the nested set command does" -Tag "NativeChecklist:enable-exception" {
            $warnings = @()
            $failure = $null
            try {
                $rows = @(Get-DbaPfDataCollectorCounter -ComputerName $missingComputer -EnableException -WarningVariable warnings -WarningAction SilentlyContinue)
            } catch {
                $failure = $PSItem
            }
            $failure | Should -BeNullOrEmpty
            $rows.Count | Should -Be 0
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaPfDataCollectorSet\] Failure \| Connecting to remote server $([regex]::Escape($missingComputer)) failed"
        }
    }
}
