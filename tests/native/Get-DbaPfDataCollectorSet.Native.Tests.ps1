#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaPfDataCollectorSet",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads collector sets.
# NativeChecklist: azure-sqldb N/A -- The command never opens a SQL Server connection on any code path, parameter set or pipeline input: it reads the Windows Performance Logs and Alerts collector sets of computers through the Task Scheduler and Pla.DataCollectorSet COM objects (https://learn.microsoft.com/windows/win32/api/pla/nn-pla-idatacollectorset), locally or over PowerShell remoting.
# NativeChecklist: sql-login N/A -- The pinned function declares no SqlCredential and never connects to SQL Server.
# NativeChecklist: platform windows-only -- windows-binary: the Task Scheduler (Schedule.Service) and Performance Logs and Alerts (Pla.DataCollectorSet) COM servers of Windows, read in this process for the local computer and in a remote session otherwise.

Describe "Native Get-DbaPfDataCollectorSet" -Tag IntegrationTests {
    BeforeAll {
        $columns = "ComputerName", "Name", "DisplayName", "Description", "State", "Duration", "OutputLocation", "LatestOutputLocation", "RootPath", "SchedulesEnabled", "Segment", "SegmentMaxDuration", "SegmentMaxSize", "SerialNumber", "Server", "StopOnCompletion", "Subdirectory", "SubdirectoryFormat", "SubdirectoryFormatPattern", "Task", "TaskArguments", "TaskRunAsSelf", "TaskUserTextArguments", "UserAccount"
        $properties = "ComputerName", "Name", "LatestOutputLocation", "OutputLocation", "RemoteOutputLocation", "RemoteLatestOutputLocation", "RootPath", "Duration", "Description", "DescriptionUnresolved", "DisplayName", "DisplayNameUnresolved", "Keywords", "Segment", "SegmentMaxDuration", "SegmentMaxSize", "SerialNumber", "Server", "Status", "Subdirectory", "SubdirectoryFormat", "SubdirectoryFormatPattern", "Task", "TaskRunAsSelf", "TaskArguments", "TaskUserTextArguments", "Schedules", "SchedulesEnabled", "UserAccount", "Xml", "Security", "StopOnCompletion", "State", "DataCollectorSetObject", "TaskObject", "Credential"
        $states = "Unknown", "Disabled", "Queued", "Ready", "Running"
        $missingComputer = "dbatoolsci-nohost-$(Get-Random)"

        # Two user-defined collector sets of this test: the first has run (PLA keeps its LatestOutputLocation, which the user may set:
        # Microsoft Learn, IDataCollectorSet::put_LatestOutputLocation), the second never has.
        $prefix = "dbatoolsci_pfset_$(Get-Random)"
        $ranName = "$($prefix)_a"
        $newName = "$($prefix)_b"
        $ranLatest = "C:\PerfLogs\Admin\$ranName\dbatoolsci_ran_000001"

        # The XML of a small set, with one performance counter collector.
        function Get-NativeSetXml {
            param([string]$Name, [string]$Latest)
            $latestElement = if ($Latest) { "<LatestOutputLocation>$Latest</LatestOutputLocation>" } else { "" }
            "<DataCollectorSet><Name>$Name</Name><DisplayName>$Name</DisplayName><Description>dbatools native test set</Description><RootPath>%systemdrive%\PerfLogs\Admin\$Name</RootPath>$latestElement<PerformanceCounterDataCollector><Name>dbatoolsci_collector</Name><SampleInterval>15</SampleInterval><Counter>\Processor(_Total)\% Processor Time</Counter></PerformanceCounterDataCollector></DataCollectorSet>"
        }

        function New-NativeLocalSet {
            param([string]$Name, [string]$Latest)
            $set = New-Object -ComObject Pla.DataCollectorSet
            $set.SetXml((Get-NativeSetXml -Name $Name -Latest $Latest))
            if ($Latest) {
                $set.LatestOutputLocation = $Latest
            }
            $null = $set.Commit("Service\$Name", $null, 0x0003)
        }

        function Remove-NativeLocalSet {
            param([string]$Name)
            try {
                $cleanup = New-Object -ComObject Pla.DataCollectorSet
                $cleanup.Query("Service\$Name", $null)
                $cleanup.Delete()
            } catch {
                Write-Warning "Could not remove the test collector set $($Name): $PSItem"
            }
        }

        # The PLA task names of this computer, read independently: every task once (TASK_ENUM_HIDDEN lists the hidden and the
        # visible tasks). The sets that native tests on this computer make for a while are left out.
        function Get-NativeLocalSetName {
            $schedule = New-Object -ComObject "Schedule.Service"
            $schedule.Connect()
            $folder = $schedule.GetFolder("Microsoft\Windows\PLA")
            $names = @($folder.GetTasks(1) | ForEach-Object { $PSItem.Name } | Where-Object { $PSItem -notlike "dbatoolsci_*" })
            $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject($schedule)
            , $names
        }

        # A read through the command. The legs read this computer's collector sets at the same time and make and remove their own
        # test sets: when Pla.DataCollectorSet refuses a Query the set script warns "Issue with getting Collector Set ..." and leaves
        # the set out, and when another leg removes its set while this one lists the tasks, reading the removed task's Name fails
        # the whole read ("Failure | The system cannot find the file specified."), as both do in the pin. A read with any warning
        # is made again, at most three times. Every warning is kept for the assertion messages.
        function Invoke-NativeRead {
            param([hashtable]$Arguments = @{ })
            $allWarnings = @()
            $rows = @()
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                $readWarnings = @()
                $rows = @(Get-DbaPfDataCollectorSet @Arguments -WarningVariable readWarnings -WarningAction SilentlyContinue)
                $allWarnings += @($readWarnings | ForEach-Object { "attempt $($attempt): $PSItem" })
                if (@($readWarnings).Count -eq 0) {
                    break
                }
            }
            [pscustomobject]@{
                Rows     = $rows
                Warnings = "warnings: " + ($allWarnings -join " / ")
                Last     = @($readWarnings | ForEach-Object { "$PSItem" })
            }
        }

        # The pin's RemoteOutputLocation and RemoteLatestOutputLocation as its set script intends them, for a row read on $Computer.
        function Get-NativeRemoteLocation {
            param($Row, [string]$Computer)
            [pscustomobject]@{
                Output = if ($Row.OutputLocation) { "\\$Computer\" + (Split-Path $Row.OutputLocation).Replace(':', '$') } else { $null }
                Latest = if ($Row.LatestOutputLocation) { "\\$Computer\" + ($Row.LatestOutputLocation).Replace(':', '$') } else { $null }
            }
        }

        # The pin passes the script block's rows through Select-Object -Property * -ExcludeProperty PSComputerName, RunspaceId,
        # PSShowComputerName (Invoke-Command2): the type names that gives a [PSCustomObject] row.
        $localTypeNames = ([pscustomobject]@{ Name = "x" } | Select-Object -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName).PSObject.TypeNames -join ";"

        New-NativeLocalSet -Name $ranName -Latest $ranLatest
        New-NativeLocalSet -Name $newName
    }

    AfterAll {
        Remove-NativeLocalSet -Name $ranName
        Remove-NativeLocalSet -Name $newName
    }

    Context "The local computer" {
        It "returns every collector set once, with the pinned properties, type names and 24 shown by default" {
            $expected = Get-NativeLocalSetName
            $read = Invoke-NativeRead
            $rows = @($read.Rows | Where-Object Name -notlike "dbatoolsci_*")
            $expected.Count | Should -BeGreaterThan 0
            (@($rows.Name | Sort-Object) -join ";") | Should -BeExactly (@($expected | Sort-Object) -join ";") -Because $read.Warnings
            $first = $rows[0]
            (@($first.PSObject.Properties.Name) -join ",") | Should -BeExactly ($properties -join ",")
            (@($first.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) -join ",") | Should -BeExactly ($columns -join ",")
            ($first.PSObject.TypeNames -join ";") | Should -BeExactly $localTypeNames
            @($rows.ComputerName | Select-Object -Unique) | Should -Be @($env:COMPUTERNAME)
            @($rows | Where-Object DataCollectorSetObject -ne $true).Count | Should -Be 0
            @($rows | Where-Object { $PSItem.TaskObject.Name -ne $PSItem.Name }).Count | Should -Be 0
        }

        It "reads a set's values as Pla.DataCollectorSet and its task report them" {
            $read = Invoke-NativeRead -Arguments @{ CollectorSet = $ranName }
            $read.Rows.Count | Should -Be 1 -Because $read.Warnings
            $row = $read.Rows[0]
            $query = New-Object -ComObject Pla.DataCollectorSet
            $query.Query($ranName, $null)
            foreach ($name in "LatestOutputLocation", "OutputLocation", "RootPath", "Duration", "Description", "DescriptionUnresolved", "DisplayName", "DisplayNameUnresolved", "Segment", "SegmentMaxDuration", "SegmentMaxSize", "SerialNumber", "Server", "Status", "Subdirectory", "SubdirectoryFormat", "SubdirectoryFormatPattern", "Task", "TaskRunAsSelf", "TaskArguments", "TaskUserTextArguments", "SchedulesEnabled", "UserAccount", "Xml", "Security", "StopOnCompletion") {
                "$name=$($row.$name)" | Should -BeExactly "$name=$($query.$name)"
            }
            $row.Name | Should -BeExactly $ranName
            $row.Description | Should -BeExactly "dbatools native test set"
            $row.State | Should -BeExactly $states[$row.TaskObject.State]
            $row.Credential | Should -BeNullOrEmpty
        }

        It "carries -Credential in each row" {
            $password = ConvertTo-SecureString "dbatoolsci-$(Get-Random)" -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential ("dbatoolsci_user", $password)
            $read = Invoke-NativeRead -Arguments @{ CollectorSet = $ranName; Credential = $credential }
            $read.Rows.Count | Should -Be 1 -Because $read.Warnings
            $read.Rows[0].Credential | Should -BeOfType [System.Management.Automation.PSCredential]
            $read.Rows[0].Credential.UserName | Should -BeExactly "dbatoolsci_user"
            $read.Rows[0].Credential.GetNetworkCredential().Password | Should -BeExactly $credential.GetNetworkCredential().Password
        }

        It "returns the set named by -CollectorSet, ignoring case" {
            $read = Invoke-NativeRead -Arguments @{ CollectorSet = $ranName.ToUpper() }
            @($read.Rows.Name) | Should -Be @($ranName) -Because $read.Warnings
        }

        It "matches -CollectorSet wildcards, as the help describes" {
            $read = Invoke-NativeRead -Arguments @{ CollectorSet = "$prefix*" }
            @($read.Rows.Name | Sort-Object) | Should -Be @($ranName, $newName) -Because $read.Warnings
        }

        It "returns nothing and warns of nothing for a collector set that does not exist" {
            $read = Invoke-NativeRead -Arguments @{ CollectorSet = "dbatoolsci-noset-$(Get-Random)" }
            $read.Rows.Count | Should -Be 0
            $read.Last.Count | Should -Be 0 -Because $read.Warnings
        }

        It "reads each computer name piped in" -Tag "NativeChecklist:pipeline-multiple" {
            # Read again while a read warns, at most three times (see Invoke-NativeRead).
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                $warnings = @()
                $rows = @($env:COMPUTERNAME, $env:COMPUTERNAME | Get-DbaPfDataCollectorSet -CollectorSet $ranName -WarningVariable warnings -WarningAction SilentlyContinue)
                if ($warnings.Count -eq 0) {
                    break
                }
            }
            @($rows.Name) | Should -Be @($ranName, $ranName) -Because "warnings: $($warnings -join ' / ')"
        }
    }

    Context "Remote output locations" {
        It "reports the RemoteOutputLocation of a set that has not run, and no RemoteLatestOutputLocation" {
            $read = Invoke-NativeRead -Arguments @{ CollectorSet = $newName }
            $read.Rows.Count | Should -Be 1 -Because $read.Warnings
            $row = $read.Rows[0]
            $row.OutputLocation | Should -Not -BeNullOrEmpty
            $row.LatestOutputLocation | Should -BeNullOrEmpty
            $row.RemoteOutputLocation | Should -BeExactly (Get-NativeRemoteLocation -Row $row -Computer $env:COMPUTERNAME).Output
            $row.RemoteLatestOutputLocation | Should -BeNullOrEmpty
        }

        It "reports each set's own remote locations when a set that has not run is read after one that has" {
            $read = Invoke-NativeRead -Arguments @{ CollectorSet = $ranName, $newName }
            @($read.Rows.Name | Sort-Object) | Should -Be @($ranName, $newName) -Because $read.Warnings
            ($read.Rows | Where-Object Name -eq $ranName).LatestOutputLocation | Should -BeExactly $ranLatest
            foreach ($row in $read.Rows) {
                $expected = Get-NativeRemoteLocation -Row $row -Computer $env:COMPUTERNAME
                "$($row.Name) $($row.RemoteOutputLocation)|$($row.RemoteLatestOutputLocation)" | Should -BeExactly "$($row.Name) $($expected.Output)|$($expected.Latest)"
            }
        }
    }

    Context "A set with a visible task" {
        BeforeAll {
            # A set of its own, whose task a user has un-hidden: PLA makes a set's task hidden and Task Scheduler lets a user clear
            # Hidden. GetTasks(0) (visible tasks) and GetTasks(1) (TASK_ENUM_HIDDEN, hidden and visible tasks) then both list it.
            $visibleName = "$($prefix)_v"
            New-NativeLocalSet -Name $visibleName
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
            Remove-NativeLocalSet -Name $visibleName
        }

        It "lists a set whose task is visible once" {
            $schedule = New-Object -ComObject "Schedule.Service"
            $schedule.Connect()
            $folder = $schedule.GetFolder("Microsoft\Windows\PLA")
            @($folder.GetTasks(0) | Where-Object Name -eq $visibleName).Count | Should -Be 1 -Because "the set's task is visible"
            $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject($schedule)
            $read = Invoke-NativeRead -Arguments @{ CollectorSet = $visibleName }
            @($read.Rows.Name) | Should -Be @($visibleName) -Because $read.Warnings
        }
    }

    Context "A remote computer" {
        BeforeAll {
            $remoteServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
            $remoteComputer = $remoteServer.ComputerName
            $remoteNewName = "$($prefix)_remote"
            $remoteXml = Get-NativeSetXml -Name $remoteNewName
            # A set that has never run on the remote computer, and an independent read of that computer's PLA task names.
            $remoteState = Invoke-Command -ComputerName $remoteComputer -ArgumentList $remoteNewName, $remoteXml -ScriptBlock {
                param($Name, $Xml)
                $set = New-Object -ComObject Pla.DataCollectorSet
                $set.SetXml($Xml)
                $null = $set.Commit("Service\$Name", $null, 0x0003)
                $schedule = New-Object -ComObject "Schedule.Service"
                $schedule.Connect()
                $folder = $schedule.GetFolder("Microsoft\Windows\PLA")
                $names = @($folder.GetTasks(1) | ForEach-Object { $PSItem.Name } | Where-Object { $PSItem -notlike "dbatoolsci_*" })
                $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject($schedule)
                [pscustomobject]@{
                    Name  = $env:COMPUTERNAME
                    Names = $names
                }
            }
            $remoteTypeNames = (Invoke-Command -ComputerName $remoteComputer -ScriptBlock { [pscustomobject]@{ Name = "x" } } | Select-Object -Property * -ExcludeProperty PSComputerName, RunspaceId, PSShowComputerName).PSObject.TypeNames -join ";"
        }

        AfterAll {
            Invoke-Command -ComputerName $remoteComputer -ArgumentList $remoteNewName -ScriptBlock {
                param($Name)
                $cleanup = New-Object -ComObject Pla.DataCollectorSet
                $cleanup.Query("Service\$Name", $null)
                $cleanup.Delete()
            }
        }

        It "reads the remote computer's sets with its own computer name and the pinned properties and type names" {
            $read = Invoke-NativeRead -Arguments @{ ComputerName = $remoteComputer }
            $rows = @($read.Rows | Where-Object Name -notlike "dbatoolsci_*")
            @($read.Last | Where-Object { $PSItem -match "\[Get-DbaPfDataCollectorSet\] Failure" }).Count | Should -Be 0 -Because $read.Warnings
            (@($rows.Name | Sort-Object) -join ";") | Should -BeExactly (@($remoteState.Names | Sort-Object) -join ";") -Because $read.Warnings
            @($rows.ComputerName | Select-Object -Unique) | Should -Be @($remoteState.Name)
            $first = $rows[0]
            (@($first.PSObject.Properties.Name) -join ",") | Should -BeExactly ($properties -join ",")
            (@($first.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) -join ",") | Should -BeExactly ($columns -join ",")
            ($first.PSObject.TypeNames -join ";") | Should -BeExactly $remoteTypeNames
            $first.DataCollectorSetObject | Should -BeTrue
        }

        It "reports the remote RemoteOutputLocation of a set that has not run, and no RemoteLatestOutputLocation" {
            $read = Invoke-NativeRead -Arguments @{ ComputerName = $remoteComputer; CollectorSet = $remoteNewName }
            $rows = @($read.Rows)
            $rows.Count | Should -Be 1 -Because $read.Warnings
            $row = $rows[0]
            $row.OutputLocation | Should -Not -BeNullOrEmpty
            $row.RemoteOutputLocation | Should -BeExactly (Get-NativeRemoteLocation -Row $row -Computer $remoteState.Name).Output
            $row.RemoteLatestOutputLocation | Should -BeNullOrEmpty
        }
    }

    Context "A computer that cannot be reached" -Tag "NativeChecklist:multi-instance-failure" {
        BeforeAll {
            $missingLine = "\[Get-DbaPfDataCollectorSet\] Failure \| Connecting to remote server $([regex]::Escape($missingComputer)) failed"

            # The missing computer, then this one, at most three times while the read of this computer warns as well (another
            # leg removing its set while this one lists the tasks, see Invoke-NativeRead).
            function Invoke-NativeMissingRead {
                param([hashtable]$Arguments = @{ })
                for ($attempt = 1; $attempt -le 3; $attempt++) {
                    $missingWarnings = @()
                    $missingRows = @(Get-DbaPfDataCollectorSet -ComputerName $missingComputer, $env:COMPUTERNAME -CollectorSet $ranName @Arguments -WarningVariable missingWarnings -WarningAction SilentlyContinue)
                    if (@($missingWarnings | Where-Object { "$PSItem" -notmatch $missingLine }).Count -eq 0) {
                        break
                    }
                }
                [pscustomobject]@{
                    Rows     = $missingRows
                    Warnings = @($missingWarnings | ForEach-Object { "$PSItem" })
                }
            }
        }

        It "warns Failure for that computer and reads the next one" {
            $read = Invoke-NativeMissingRead
            $failures = @($read.Warnings | Where-Object { $PSItem -match "\[Get-DbaPfDataCollectorSet\] Failure" })
            $failures.Count | Should -Be 1 -Because "warnings: $($read.Warnings -join ' / ')"
            $failures[0] | Should -Match $missingLine
            @($read.Rows.Name) | Should -Be @($ranName)
        }

        It "warns and goes on under -EnableException:`$false" -Tag "NativeChecklist:switch-false" {
            $read = Invoke-NativeMissingRead -Arguments @{ EnableException = $false }
            @($read.Warnings | Where-Object { $PSItem -match "\[Get-DbaPfDataCollectorSet\] Failure" }).Count | Should -Be 1 -Because "warnings: $($read.Warnings -join ' / ')"
            @($read.Rows.Name) | Should -Be @($ranName)
        }

        It "throws for that computer under -EnableException, after the rows already read" -Tag "NativeChecklist:enable-exception" {
            # A stop for this computer itself (see Invoke-NativeRead) is a reason to read again, at most three times.
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                $rows = @()
                $failure = $null
                try {
                    Get-DbaPfDataCollectorSet -ComputerName $env:COMPUTERNAME, $missingComputer, $env:COMPUTERNAME -CollectorSet $ranName -EnableException -WarningAction SilentlyContinue | ForEach-Object { $rows += $PSItem }
                } catch {
                    $failure = $PSItem
                }
                if ("$failure" -match "Connecting to remote server") {
                    break
                }
            }
            $failure | Should -Not -BeNullOrEmpty
            "$failure" | Should -Match "Connecting to remote server $([regex]::Escape($missingComputer)) failed"
            @($rows.Name) | Should -Be @($ranName)
        }
    }
}
