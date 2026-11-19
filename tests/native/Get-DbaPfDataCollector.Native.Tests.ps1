#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaPfDataCollector",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads collector sets.
# NativeChecklist: azure-sqldb N/A -- The command never opens a SQL Server connection on any code path, parameter set or pipeline input: it reads the Windows Performance Logs and Alerts collector sets of computers through the Task Scheduler and Pla.DataCollectorSet COM objects (https://learn.microsoft.com/windows/win32/api/pla/nn-pla-idatacollectorset), locally or over PowerShell remoting.
# NativeChecklist: sql-login N/A -- The pinned function declares no SqlCredential and never connects to SQL Server.
# NativeChecklist: platform windows-only -- windows-binary: the Task Scheduler (Schedule.Service) and Performance Logs and Alerts (Pla.DataCollectorSet) COM servers of Windows, read in this process for the local computer and in a remote session otherwise.

Describe "Native Get-DbaPfDataCollector" -Tag IntegrationTests {
    BeforeAll {
        $columns = "ComputerName", "DataCollectorSet", "Name", "DataCollectorType", "DataSourceName", "FileName", "FileNameFormat", "FileNameFormatPattern", "LatestOutputLocation", "LogAppend", "LogCircular", "LogFileFormat", "LogOverwrite", "SampleInterval", "SegmentMaxRecords", "Counters"
        $properties = "ComputerName", "DataCollectorSet", "Name", "FileName", "DataCollectorType", "FileNameFormat", "FileNameFormatPattern", "LogAppend", "LogCircular", "LogOverwrite", "LatestOutputLocation", "DataCollectorSetXml", "RemoteLatestOutputLocation", "DataSourceName", "SampleInterval", "SegmentMaxRecords", "LogFileFormat", "Counters", "CounterDisplayNames", "CollectorXml", "DataCollectorObject", "Credential"
        $missingComputer = "dbatoolsci-nohost-$(Get-Random)"
        $wrongTypeLine = "\[Get-DbaPfDataCollector\] InputObject is not of the right type\. Please use Get-DbaPfDataCollectorSet\."

        # A set's XML as PLA writes it: two performance counter collectors, the first with every element, the second with few.
        $collectorA = "<PerformanceCounterDataCollector><DataCollectorType>0</DataCollectorType><Name>Collector A</Name><FileName>fileA</FileName><FileNameFormat>3</FileNameFormat><FileNameFormatPattern>MMddHHmm</FileNameFormatPattern><LogAppend>0</LogAppend><LogCircular>0</LogCircular><LogOverwrite>-1</LogOverwrite><LatestOutputLocation>C:\PerfLogs\Admin\nativeset\fileA.blg</LatestOutputLocation><DataSourceName></DataSourceName><SampleInterval>15</SampleInterval><SegmentMaxRecords>0</SegmentMaxRecords><LogFileFormat>3</LogFileFormat><Counter>\Processor(_Total)\% Processor Time</Counter><Counter>\Memory\Available MBytes</Counter><CounterDisplayName>\Processor(_Total)\% Processor Time</CounterDisplayName><CounterDisplayName>\Memory\Available MBytes</CounterDisplayName></PerformanceCounterDataCollector>"
        $collectorB = "<PerformanceCounterDataCollector><DataCollectorType>0</DataCollectorType><Name>Collector B</Name><LatestOutputLocation></LatestOutputLocation><Counter>\System\Processes</Counter><CounterDisplayName>\System\Processes</CounterDisplayName></PerformanceCounterDataCollector>"
        $syntheticXml = "<DataCollectorSet><Name>nativeset</Name>$collectorA$collectorB</DataCollectorSet>"
        $bracketXml = "<DataCollectorSet><Name>bracketset</Name><PerformanceCounterDataCollector><Name>Collector [1]</Name></PerformanceCounterDataCollector></DataCollectorSet>"

        # A collector set as Get-DbaPfDataCollectorSet returns it, with the properties this command reads.
        function New-NativeSet {
            param([string]$Name, [string]$Xml, [string]$Computer = "nativehost", $Credential)
            [pscustomobject]@{
                ComputerName           = $Computer
                Name                   = $Name
                Xml                    = $Xml
                DataCollectorSetObject = $true
                Credential             = $Credential
            }
        }

        # An independent read of this computer's collector sets: every PLA task once (TASK_ENUM_HIDDEN lists the hidden and the
        # visible tasks), each set that Pla.DataCollectorSet can query, and the names of its performance counter collectors.
        function Get-NativeLocalSet {
            $schedule = New-Object -ComObject "Schedule.Service"
            $schedule.Connect()
            $folder = $schedule.GetFolder("Microsoft\Windows\PLA")
            # The sets other legs on this computer make for a while (Context "A set with a visible task") are left out.
            $names = @($folder.GetTasks(1) | ForEach-Object { $PSItem.Name } | Where-Object { $PSItem -notlike "dbatoolsci_pfvisible_*" })
            $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject($schedule)
            $query = New-Object -ComObject Pla.DataCollectorSet
            $sets = foreach ($name in $names) {
                try {
                    $query.Query($name, $null)
                } catch {
                    continue
                }
                $document = [xml]$query.Xml
                [pscustomobject]@{
                    Name       = $name
                    Collectors = @($document.DataCollectorSet.PerformanceCounterDataCollector | ForEach-Object { $PSItem.Name })
                }
            }
            , @($sets)
        }

        function Format-NativeRow {
            param($Row)
            "$($Row.ComputerName)|$($Row.DataCollectorSet)|$($Row.Name)"
        }

        # Pester wraps It bodies in try, which makes a statement error end the command. Plain calls run here, in a runspace of
        # their own, as StatementFault.Engine.Native.Tests.ps1 does.
        function Invoke-NativeOutsideTry {
            param([object[]]$Sets, [hashtable]$Arguments = @{ })
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaPfDataCollector -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaPfDataCollector", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                $outsideScript = {
                    param($pipedSets, $collectorArguments)
                    $outsideErrors = @()
                    $pipedSets | Get-DbaPfDataCollector @collectorArguments -ErrorVariable outsideErrors
                }
                $null = $outsideShell.AddScript($outsideScript.ToString()).AddArgument($Sets).AddArgument($Arguments)
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

    Context "Collector sets piped in" {
        It "reads each collector of a piped set with the pinned properties" {
            $rows = @(New-NativeSet -Name "nativeset" -Xml $syntheticXml | Get-DbaPfDataCollector -EnableException)
            $rows.Count | Should -Be 2
            $first = $rows[0]
            $first.ComputerName | Should -BeExactly "nativehost"
            $first.DataCollectorSet | Should -BeExactly "nativeset"
            $first.Name | Should -BeExactly "Collector A"
            $first.DataCollectorType | Should -BeExactly "0"
            $first.FileName | Should -BeExactly "fileA"
            $first.FileNameFormat | Should -BeExactly "3"
            $first.FileNameFormatPattern | Should -BeExactly "MMddHHmm"
            $first.LogAppend | Should -BeExactly "0"
            $first.LogCircular | Should -BeExactly "0"
            $first.LogOverwrite | Should -BeExactly "-1"
            $first.LatestOutputLocation | Should -BeExactly 'C:\PerfLogs\Admin\nativeset\fileA.blg'
            $first.RemoteLatestOutputLocation | Should -BeExactly '\\nativehost\C$\PerfLogs\Admin\nativeset\fileA.blg'
            $first.DataSourceName | Should -BeExactly ""
            $first.SampleInterval | Should -BeExactly "15"
            $first.SegmentMaxRecords | Should -BeExactly "0"
            $first.LogFileFormat | Should -BeExactly "3"
            $first.Counters.GetType().FullName | Should -BeExactly "System.Object[]"
            $first.Counters | Should -Be @('\Processor(_Total)\% Processor Time', '\Memory\Available MBytes')
            $first.CounterDisplayNames | Should -Be @('\Processor(_Total)\% Processor Time', '\Memory\Available MBytes')
            $first.CollectorXml | Should -BeOfType [System.Xml.XmlElement]
            $first.CollectorXml.OuterXml | Should -BeExactly $collectorA
            $first.DataCollectorSetXml | Should -BeExactly $syntheticXml
            $first.DataCollectorObject | Should -BeTrue
            $first.Credential | Should -BeNullOrEmpty
            $second = $rows[1]
            $second.Name | Should -BeExactly "Collector B"
            $second.LatestOutputLocation | Should -BeExactly ""
            $second.RemoteLatestOutputLocation | Should -BeNullOrEmpty
            $second.Counters | Should -BeExactly '\System\Processes'
            $second.FileName | Should -BeNullOrEmpty
        }

        It "returns the pinned properties in order, 16 of them shown by default" {
            $row = New-NativeSet -Name "nativeset" -Xml $syntheticXml | Get-DbaPfDataCollector -EnableException | Select-Object -First 1
            # No type name assertion: the pin's rows show Selected.System.Management.Automation.PSCustomObject first once any
            # Select-Object has run on a PSCustomObject in the session (probe pin-pfcollector-20261111, both editions).
            @($row.PSObject.Properties.Name) | Should -Be $properties
            @($row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) | Should -Be $columns
        }

        It "returns the collector named by -Collector, ignoring case" {
            $rows = @(New-NativeSet -Name "nativeset" -Xml $syntheticXml | Get-DbaPfDataCollector -Collector "collector b" -EnableException)
            @($rows.Name) | Should -Be @("Collector B")
        }

        It "still matches a -Collector name that holds wildcard characters exactly" {
            $rows = @(New-NativeSet -Name "bracketset" -Xml $bracketXml | Get-DbaPfDataCollector -Collector "Collector [1]" -EnableException)
            @($rows.Name) | Should -Be @("Collector [1]")
        }

        It "matches -Collector wildcards, as the help describes" {
            $rows = @(New-NativeSet -Name "nativeset" -Xml $syntheticXml | Get-DbaPfDataCollector -Collector "collector*" -EnableException)
            @($rows.Name) | Should -Be @("Collector A", "Collector B")
            $rows = @(New-NativeSet -Name "nativeset" -Xml $syntheticXml | Get-DbaPfDataCollector -Collector "*B" -EnableException)
            @($rows.Name) | Should -Be @("Collector B")
        }

        It "reads several piped sets in order" -Tag "NativeChecklist:pipeline-multiple" {
            $rows = @((New-NativeSet -Name "first" -Xml $syntheticXml), (New-NativeSet -Name "second" -Xml $syntheticXml -Computer "otherhost") | Get-DbaPfDataCollector -EnableException)
            @($rows | ForEach-Object { Format-NativeRow $PSItem }) | Should -Be @("nativehost|first|Collector A", "nativehost|first|Collector B", "otherhost|second|Collector A", "otherhost|second|Collector B")
            $rows[2].RemoteLatestOutputLocation | Should -BeExactly '\\otherhost\C$\PerfLogs\Admin\nativeset\fileA.blg'
        }

        It "takes the piped set's credential when -Credential is not given, and -Credential when it is" {
            $password = ConvertTo-SecureString -String "nativepassword" -AsPlainText -Force
            $setCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "nativeset\user", $password
            $givenCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "nativegiven\user", $password
            $rows = @(New-NativeSet -Name "nativeset" -Xml $syntheticXml -Credential $setCredential | Get-DbaPfDataCollector -EnableException)
            @($rows | ForEach-Object { $PSItem.Credential.UserName }) | Should -Be @("nativeset\user", "nativeset\user")
            $rows = @(New-NativeSet -Name "nativeset" -Xml $syntheticXml -Credential $setCredential | Get-DbaPfDataCollector -Credential $givenCredential -EnableException)
            @($rows | ForEach-Object { $PSItem.Credential.UserName }) | Should -Be @("nativegiven\user", "nativegiven\user")
        }

        It "reads the computers of -ComputerName after the piped sets" {
            $rows = @(New-NativeSet -Name "nativeset" -Xml $syntheticXml | Get-DbaPfDataCollector -ComputerName $env:COMPUTERNAME -WarningAction SilentlyContinue)
            $rows.Count | Should -BeGreaterThan 2
            @($rows[0..1] | ForEach-Object { Format-NativeRow $PSItem }) | Should -Be @("nativehost|nativeset|Collector A", "nativehost|nativeset|Collector B")
            @($rows[2..($rows.Count - 1)].ComputerName | Select-Object -Unique) | Should -Be @($env:COMPUTERNAME)
        }
    }

    Context "Values that are not collector sets" {
        It "warns that a piped value is not a collector set and returns nothing" {
            $warnings = @()
            $rows = @("foo" | Get-DbaPfDataCollector -WarningVariable warnings -WarningAction SilentlyContinue)
            $rows.Count | Should -Be 0
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match $wrongTypeLine
        }

        It "reads a set piped after a wrong value, under -EnableException:`$false too" -Tag "NativeChecklist:switch-false" {
            $warnings = @()
            $rows = @("foo", (New-NativeSet -Name "nativeset" -Xml $syntheticXml) | Get-DbaPfDataCollector -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
            @($rows.Name) | Should -Be @("Collector A", "Collector B")
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match $wrongTypeLine
        }

        It "throws for a wrong value under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $failure = $null
            try {
                $null = "foo" | Get-DbaPfDataCollector -EnableException -WarningAction SilentlyContinue
            } catch {
                $failure = $PSItem
            }
            $failure | Should -Not -BeNullOrEmpty
            $failure.FullyQualifiedErrorId | Should -Match "^dbatools_Get-DbaPfDataCollector(,|$)"
            $failure.Exception.Message | Should -Match "InputObject is not of the right type\. Please use Get-DbaPfDataCollectorSet\."
        }
    }

    Context "A set whose XML cannot be read" {
        BeforeAll {
            $badSets = @(
                (New-NativeSet -Name "goodfirst" -Xml $syntheticXml),
                (New-NativeSet -Name "broken" -Xml "not xml"),
                (New-NativeSet -Name "goodlast" -Xml $syntheticXml)
            )
            $badMessage = 'Cannot convert value "not xml" to type "System\.Xml\.XmlDocument"'
        }

        It "reports no collectors for a set whose XML cannot be read, and goes on" {
            $result = Invoke-NativeOutsideTry -Sets $badSets
            $result.Stop | Should -BeNullOrEmpty
            @($result.Output | ForEach-Object { Format-NativeRow $PSItem }) | Should -Be @("nativehost|goodfirst|Collector A", "nativehost|goodfirst|Collector B", "nativehost|goodlast|Collector A", "nativehost|goodlast|Collector B")
            $result.Errors.Count | Should -Be 1
            "$($result.Errors[0])" | Should -Match $badMessage
        }

        It "stops at the set under -EnableException, without ending the caller's script" -Tag "NativeChecklist:enable-exception" {
            $result = Invoke-NativeOutsideTry -Sets $badSets -Arguments @{ EnableException = $true }
            $result.Stop | Should -BeNullOrEmpty
            @($result.Output | ForEach-Object { Format-NativeRow $PSItem }) | Should -Be @("nativehost|goodfirst|Collector A", "nativehost|goodfirst|Collector B")
            $result.Stream.Count | Should -Be 1
            $result.Stream[0] | Should -BeOfType System.Management.Automation.ErrorRecord
            "$($result.Stream[0])" | Should -Match $badMessage
        }

        It "stops at the set under -ErrorAction Stop" {
            $result = Invoke-NativeOutsideTry -Sets $badSets -Arguments @{ ErrorAction = "Stop" }
            $result.Stop | Should -Not -BeNullOrEmpty
            "$($result.Stop)" | Should -Match $badMessage
            @($result.Output | Where-Object DataCollectorSet -eq "goodlast").Count | Should -Be 0
        }

        It "stops at the set inside a caller's try" {
            $caught = $null
            $rows = New-Object System.Collections.ArrayList
            try {
                $badSets | Get-DbaPfDataCollector | ForEach-Object { $null = $rows.Add($PSItem) }
            } catch {
                $caught = $PSItem
            }
            $caught | Should -Not -BeNullOrEmpty
            "$caught" | Should -Match $badMessage
            @($rows | Where-Object DataCollectorSet -eq "goodlast").Count | Should -Be 0
        }
    }

    Context "A set property that cannot be read" {
        BeforeAll {
            # The other statement errors of the pin's body: reading $InputObject.Credential, reading
            # $InputObject.DataCollectorSetObject, and the per-collector body reading $set.ComputerName. A compiled getter
            # throws, not a script property, whose script block would belong to this runspace and not the helper's.
            if (-not ("NativePfCollectorTests.FaultingSet" -as [type])) {
                Add-Type -TypeDefinition @"
using System;
namespace NativePfCollectorTests {
    public sealed class FaultingSet {
        private readonly string _fault;
        private readonly string _xml;
        public FaultingSet(string fault, string xml) { _fault = fault; _xml = xml; }
        private object Read(string name, object value) {
            if (name == _fault) { throw new InvalidOperationException("dbatoolsci fault"); }
            return value;
        }
        public object ComputerName { get { return Read("ComputerName", "nativehost"); } }
        public object Name { get { return Read("Name", "faulty"); } }
        public object Xml { get { return Read("Xml", _xml); } }
        public object DataCollectorSetObject { get { return Read("DataCollectorSetObject", true); } }
        public object Credential { get { return Read("Credential", null); } }
    }
}
"@
            }
            function New-NativeFaultSets {
                param([string]$Property)
                $faulty = New-Object NativePfCollectorTests.FaultingSet -ArgumentList $Property, $syntheticXml
                @((New-NativeSet -Name "goodfirst" -Xml $syntheticXml), $faulty, (New-NativeSet -Name "goodlast" -Xml $syntheticXml))
            }
            $faultCases = @(
                @{ Property = "Credential"; PlainRows = 6; PlainErrors = 1 },
                @{ Property = "DataCollectorSetObject"; PlainRows = 6; PlainErrors = 1 },
                # Each collector of the set faults on its own.
                @{ Property = "ComputerName"; PlainRows = 4; PlainErrors = 2 }
            )
            $faultMessage = "dbatoolsci fault"
            $firstRows = @("nativehost|goodfirst|Collector A", "nativehost|goodfirst|Collector B")
        }

        It "writes the error and goes on with the next statement, outside any try" {
            foreach ($case in $faultCases) {
                $result = Invoke-NativeOutsideTry -Sets (New-NativeFaultSets -Property $case.Property)
                $result.Stop | Should -BeNullOrEmpty -Because $case.Property
                @($result.Output).Count | Should -Be $case.PlainRows -Because $case.Property
                @($result.Output | Where-Object DataCollectorSet -eq "goodlast").Count | Should -Be 2 -Because $case.Property
                $result.Errors.Count | Should -Be $case.PlainErrors -Because $case.Property
                foreach ($record in $result.Errors) {
                    "$record" | Should -Match $faultMessage -Because $case.Property
                }
            }
        }

        It "stops at the set under -EnableException, without ending the caller's script" -Tag "NativeChecklist:enable-exception" {
            foreach ($case in $faultCases) {
                $result = Invoke-NativeOutsideTry -Sets (New-NativeFaultSets -Property $case.Property) -Arguments @{ EnableException = $true }
                $result.Stop | Should -BeNullOrEmpty -Because $case.Property
                @($result.Output | ForEach-Object { Format-NativeRow $PSItem }) | Should -Be $firstRows -Because $case.Property
                $result.Stream.Count | Should -Be 1 -Because $case.Property
                $result.Stream[0] | Should -BeOfType System.Management.Automation.ErrorRecord
                "$($result.Stream[0])" | Should -Match $faultMessage -Because $case.Property
            }
        }

        It "stops at the set under -ErrorAction Stop" {
            foreach ($case in $faultCases) {
                $result = Invoke-NativeOutsideTry -Sets (New-NativeFaultSets -Property $case.Property) -Arguments @{ ErrorAction = "Stop" }
                $result.Stop | Should -Not -BeNullOrEmpty -Because $case.Property
                "$($result.Stop)" | Should -Match $faultMessage -Because $case.Property
                @($result.Output | ForEach-Object { Format-NativeRow $PSItem }) | Should -Be $firstRows -Because $case.Property
            }
        }

        It "stops at the set inside a caller's try, with or without -EnableException or -ErrorAction Stop" {
            foreach ($case in $faultCases) {
                foreach ($extra in @{ }, @{ EnableException = $true }, @{ ErrorAction = "Stop" }) {
                    $sets = New-NativeFaultSets -Property $case.Property
                    $caught = $null
                    $rows = New-Object System.Collections.ArrayList
                    try {
                        $sets | Get-DbaPfDataCollector @extra | ForEach-Object { $null = $rows.Add($PSItem) }
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
            $localSets = Get-NativeLocalSet
            $localExpected = @(foreach ($set in $localSets) {
                    foreach ($collector in $set.Collectors) {
                        "$env:COMPUTERNAME|$($set.Name)|$collector"
                    }
                })
            $localSet = $localSets | Where-Object { $PSItem.Collectors.Count -gt 0 } | Select-Object -First 1
        }

        It "reads every collector of every collector set once, as the Task Scheduler lists them" {
            # Read again right before the call, so the comparison spans as short a time as possible.
            $localExpected = @(foreach ($set in (Get-NativeLocalSet)) {
                    foreach ($collector in $set.Collectors) {
                        "$env:COMPUTERNAME|$($set.Name)|$collector"
                    }
                })
            $localExpected.Count | Should -BeGreaterThan 0
            $rows = @(Get-DbaPfDataCollector -WarningAction SilentlyContinue | Where-Object DataCollectorSet -notlike "dbatoolsci_pfvisible_*")
            @($rows | ForEach-Object { Format-NativeRow $PSItem } | Sort-Object) | Should -Be @($localExpected | Sort-Object)
        }

        It "returns the collectors of the set named by -CollectorSet, ignoring case" {
            $rows = @(Get-DbaPfDataCollector -CollectorSet $localSet.Name.ToUpper() -WarningAction SilentlyContinue)
            @($rows.DataCollectorSet | Select-Object -Unique) | Should -Be @($localSet.Name)
            @($rows.Name | Sort-Object -Unique) | Should -Be @($localSet.Collectors | Sort-Object -Unique)
        }

        It "matches -CollectorSet wildcards, as the help describes" {
            $pattern = $localSet.Name.Substring(0, [Math]::Min(3, $localSet.Name.Length)) + "*"
            $rows = @(Get-DbaPfDataCollector -CollectorSet $pattern -WarningAction SilentlyContinue)
            @($rows | Where-Object DataCollectorSet -eq $localSet.Name | ForEach-Object Name | Sort-Object -Unique) | Should -Be @($localSet.Collectors | Sort-Object -Unique)
            @($rows.DataCollectorSet | Where-Object { $PSItem -notlike $pattern }).Count | Should -Be 0
        }

        It "returns nothing and warns of nothing for a collector set that does not exist" {
            $warnings = @()
            $rows = @(Get-DbaPfDataCollector -CollectorSet "dbatoolsci-noset-$(Get-Random)" -WarningVariable warnings)
            $rows.Count | Should -Be 0
            $warnings.Count | Should -Be 0
        }
    }

    Context "A set with a visible task" {
        BeforeAll {
            # A user-defined collector set whose scheduled task in Microsoft\Windows\PLA a user has un-hidden, as Task Scheduler
            # lets one do (PLA makes the task hidden: evidence pin-pfvisible-20261111). GetTasks(0) (visible tasks) and
            # GetTasks(1) (TASK_ENUM_HIDDEN, hidden and visible tasks) then both list it.
            $visibleName = "dbatoolsci_pfvisible_$(Get-Random)"
            $visibleXml = "<DataCollectorSet><Name>$visibleName</Name><DisplayName>$visibleName</DisplayName><PerformanceCounterDataCollector><Name>dbatoolsci_collector</Name><SampleInterval>15</SampleInterval><Counter>\Processor(_Total)\% Processor Time</Counter></PerformanceCounterDataCollector></DataCollectorSet>"
            $visibleSet = New-Object -ComObject Pla.DataCollectorSet
            $visibleSet.SetXml($visibleXml)
            $null = $visibleSet.Commit("Service\$visibleName", $null, 0x0003)
            $visibleCommitted = $true
            $schedule = New-Object -ComObject "Schedule.Service"
            $schedule.Connect()
            $folder = $schedule.GetFolder("Microsoft\Windows\PLA")
            $definition = $folder.GetTask($visibleName).Definition
            $definition.Settings.Hidden = $false
            # TASK_UPDATE (4), the same principal and logon type.
            $null = $folder.RegisterTaskDefinition($visibleName, $definition, 4, $null, $null, $definition.Principal.LogonType)
            $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject($schedule)
        }

        AfterAll {
            if ($visibleCommitted) {
                $cleanup = New-Object -ComObject Pla.DataCollectorSet
                $cleanup.Query("Service\$visibleName", $null)
                $cleanup.Delete()
            }
        }

        It "lists the collectors of a set whose task is visible once" {
            $schedule = New-Object -ComObject "Schedule.Service"
            $schedule.Connect()
            $folder = $schedule.GetFolder("Microsoft\Windows\PLA")
            @($folder.GetTasks(0) | Where-Object Name -eq $visibleName).Count | Should -Be 1 -Because "the set's task is visible"
            $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject($schedule)
            $rows = @(Get-DbaPfDataCollector -CollectorSet $visibleName -WarningAction SilentlyContinue)
            @($rows | ForEach-Object { Format-NativeRow $PSItem }) | Should -Be @("$env:COMPUTERNAME|$visibleName|dbatoolsci_collector")
        }
    }

    Context "A remote computer" {
        BeforeAll {
            $remoteServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
            $remoteComputer = $remoteServer.ComputerName
            # An independent read of the same computer in a session of its own: every PLA task once, each set's collector names.
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
                        "$env:COMPUTERNAME|$name|$($collector.Name)"
                    }
                }
                [pscustomobject]@{
                    Name = $env:COMPUTERNAME
                    Rows = @($rows)
                }
            }
        }

        It "reads the remote computer's collectors with its own computer name" {
            $warnings = @()
            $rows = @(Get-DbaPfDataCollector -ComputerName $remoteComputer -WarningVariable warnings -WarningAction SilentlyContinue)
            @($warnings | Where-Object { "$PSItem" -match "\[Get-DbaPfDataCollectorSet\] Failure" }).Count | Should -Be 0
            (@($rows | ForEach-Object { Format-NativeRow $PSItem } | Sort-Object -Unique) -join ";") | Should -BeExactly (@($remoteState.Rows | Sort-Object -Unique) -join ";")
            @($rows.ComputerName | Select-Object -Unique | Where-Object { $PSItem -ne $remoteState.Name }).Count | Should -Be 0
        }
    }

    Context "A computer that cannot be reached" -Tag "NativeChecklist:multi-instance-failure" {
        It "warns under Get-DbaPfDataCollectorSet and reads the next computer" {
            $warnings = @()
            $rows = @(Get-DbaPfDataCollector -ComputerName $missingComputer, $env:COMPUTERNAME -WarningVariable warnings -WarningAction SilentlyContinue)
            $failures = @($warnings | Where-Object { "$PSItem" -match "\[Get-DbaPfDataCollectorSet\]" })
            $failures.Count | Should -Be 1
            "$($failures[0])" | Should -Match "\[Get-DbaPfDataCollectorSet\] Failure \| Connecting to remote server $([regex]::Escape($missingComputer)) failed"
            $rows.Count | Should -BeGreaterThan 0
            @($rows.ComputerName | Select-Object -Unique) | Should -Be @($env:COMPUTERNAME)
        }

        It "only warns for that computer under -EnableException, as the nested set command does" -Tag "NativeChecklist:enable-exception" {
            $warnings = @()
            $failure = $null
            try {
                $rows = @(Get-DbaPfDataCollector -ComputerName $missingComputer -EnableException -WarningVariable warnings -WarningAction SilentlyContinue)
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
