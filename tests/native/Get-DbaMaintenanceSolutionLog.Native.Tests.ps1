#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: whatif-confirm N/A -- the pinned command declares [CmdletBinding()] without SupportsShouldProcess and only reads files, so it has no -WhatIf or -Confirm.
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaMaintenanceSolutionLog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# The fixtures are IndexOptimize text logs written into one folder tree with a unique name on $TestConfig.Temp, the share every lab
# instance and this host reach, removed in AfterAll. -Path takes a UNC path as it is, so no admin share and no instance log folder
# is touched. The lines follow what the bundled MaintenanceSolution (bin/maintenancesolution: IndexOptimize.sql and
# CommandExecute.sql) writes through sqlcmd: a block of "key: value" lines, then a line holding one tab.
Describe "Native Get-DbaMaintenanceSolutionLog" -Tag IntegrationTests {
    BeforeAll {
        $logInstance = $TestConfig.InstanceSingle
        $logComputer = ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$logInstance).ComputerName
        $logBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $logRoot = "$($TestConfig.Temp)\$CommandName-native-" + [guid]::NewGuid().ToString("N").Substring(0, 12)
        $tab = "`t"

        # The format the pin's patterns read: three-part names, a lock timeout, a partition, an error line.
        $legacyLines = @(
            "Date and time: 2018-03-01 02:00:00", "Database: [dbatoolsci_mslog]", "Status: ONLINE", "Standby: No", "Updateability: READ_WRITE",
            "User access: MULTI_USER", "Is accessible: Yes", "Recovery model: FULL", $tab,
            "Date and time: 2018-03-01 02:00:01",
            "Command: SET LOCK_TIMEOUT 60000; ALTER INDEX [IX_Part] ON [dbatoolsci_mslog].[dbo].[Sales] REBUILD PARTITION = 3 WITH (SORT_IN_TEMPDB = OFF, MAXDOP = 1)",
            "Comment: ObjectType: Table, IndexType: NonClustered, ImageText: No, NewLOB: No, FileStream: No, ColumnStore: No, AllowPageLocks: Yes, PageCount: 2048, Fragmentation: 61.2",
            "Outcome: Succeeded", "Duration: 00:01:05", "Date and time: 2018-03-01 02:01:06", $tab,
            "Date and time: 2018-03-01 02:01:07", "Command: UPDATE STATISTICS [dbatoolsci_mslog].[dbo].[Sales] [ST_Sales_Region] WITH FULLSCAN",
            "Comment: ObjectType: Table, IndexType: N/A", "Outcome: Failed", "Duration: 1.02:03:04", "Msg 1222, Lock request time out period exceeded.",
            "Date and time: 2018-03-02 04:04:11", $tab
        )
        # The whole log of the bundled version: the header, the parameter listing, a database, two operations, the closing date.
        $currentLines = @(
            "Date and time: 2024-05-01 01:00:00", "Server: SQL01", "Version: 16.0.1000.6", "Edition: Developer Edition (64-bit)", "Platform: Windows",
            "Database: [master]", "Procedure: [dbo].[IndexOptimize]", "Version: 2022-12-03 17:23:44", "Source: https://ola.hallengren.com", $tab,
            "Command:", "EXECUTE [dbo].[IndexOptimize]", "@Databases = 'USER_DATABASES',", "@LogToTable = 'N'", $tab,
            "Date and time: 2024-05-01 01:00:01", "Database: [dbatoolsci_mslog]", "State: ONLINE", "Standby: No", "Updateability: READ_WRITE",
            "User access: MULTI_USER", "Recovery model: FULL", "Is accessible: Yes", $tab,
            "Date and time: 2024-05-01 01:00:02", "Database context: [dbatoolsci_mslog]",
            "Command: ALTER INDEX [PK_Widget] ON [dbo].[Widget] REBUILD WITH (SORT_IN_TEMPDB = OFF, ONLINE = OFF)",
            "Comment: ObjectType: Table, IndexType: Clustered, ImageText: No, NewLOB: No, FileStream: No, ColumnStore: No, AllowPageLocks: Yes, PageCount: 1200, Fragmentation: 45.5",
            "Outcome: Succeeded", "Duration: 00:00:03", "Date and time: 2024-05-01 01:00:05", $tab,
            "Date and time: 2024-05-01 01:00:06", "Database context: [dbatoolsci_mslog]", "Command: UPDATE STATISTICS [dbo].[Widget] [ST_Widget_Name]",
            "Comment: ObjectType: Table, StatisticsType: Column, Incremental: No, RowCount: 500, ModificationCounter: 20",
            "Outcome: Succeeded", "Duration: 00:00:01", "Date and time: 2024-05-01 01:00:07", $tab,
            "Date and time: 2024-05-01 01:00:11", $tab
        )
        # The operations of the bundled version alone: two-part names, a resumed index, and a command neither pattern reads.
        $twoPartLines = @(
            "Date and time: 2024-05-01 01:00:01", "Database: [dbatoolsci_mslog]", "State: ONLINE", $tab,
            "Date and time: 2024-05-01 01:00:02", "Database context: [dbatoolsci_mslog]",
            "Command: SET LOCK_TIMEOUT 30000; ALTER INDEX [PK_Widget] ON [dbo].[Widget] REBUILD WITH (SORT_IN_TEMPDB = OFF, ONLINE = OFF)",
            "Comment: ObjectType: Table, IndexType: Clustered, AllowPageLocks: Yes, PageCount: 1200, Fragmentation: 45.5",
            "Outcome: Succeeded", "Duration: 00:00:03", "Date and time: 2024-05-01 01:00:05", $tab,
            "Date and time: 2024-05-01 01:00:06", "Database context: [dbatoolsci_mslog]", "Command: UPDATE STATISTICS [dbo].[Widget] [ST_Widget_Name]",
            "Comment: ObjectType: Table, StatisticsType: Column, Incremental: No, RowCount: 500, ModificationCounter: 20",
            "Outcome: Succeeded", "Duration: 00:00:01", "Date and time: 2024-05-01 01:00:07", $tab,
            "Date and time: 2024-05-01 01:00:08", "Database context: [dbatoolsci_mslog]", "Command: ALTER INDEX [IX_Widget_Size] ON [dbo].[Widget] RESUME",
            "Comment: ObjectType: Table, IndexType: NonClustered, AllowPageLocks: Yes, PageCount: 300, Fragmentation: 12.5",
            "Outcome: Succeeded", "Duration: 00:00:02", "Date and time: 2024-05-01 01:00:10", $tab,
            "Date and time: 2024-05-01 01:00:11", "Database context: [dbatoolsci_mslog]", "Command: ALTER INDEX ALL ON [dbo].[Widget] REORGANIZE",
            "Outcome: Succeeded", "Duration: 00:00:01", "Date and time: 2024-05-01 01:00:12", $tab
        )
        # The legacy log with empty separator lines in place of the tab lines.
        $emptyLines = @($legacyLines | ForEach-Object { if ($PSItem -eq $tab) { "" } else { $PSItem } })

        function New-NativeLogFolder {
            param([string]$Name, [hashtable]$Files)
            $folder = "$logRoot\$Name"
            $null = New-Item -Path $folder -ItemType Directory -Force
            foreach ($fileName in $Files.Keys) {
                [System.IO.File]::WriteAllText("$folder\$fileName", (($Files[$fileName] -join "`r`n") + "`r`n"))
            }
            $folder
        }

        $legacyFolder = New-NativeLogFolder -Name "legacy" -Files @{ "IndexOptimize_legacy.txt" = $legacyLines }
        $currentFolder = New-NativeLogFolder -Name "current" -Files @{ "IndexOptimize_current.txt" = $currentLines }
        $twoPartFolder = New-NativeLogFolder -Name "twopart" -Files @{ "IndexOptimize_twopart.txt" = $twoPartLines }
        $emptyLineFolder = New-NativeLogFolder -Name "emptylines" -Files @{ "IndexOptimize_emptylines.txt" = $emptyLines }
        $sinceFolder = New-NativeLogFolder -Name "since" -Files @{ "IndexOptimize_old.txt" = $legacyLines; "IndexOptimize_new.txt" = $twoPartLines; "DatabaseBackup_new.txt" = $legacyLines }
        (Get-Item -Path "$sinceFolder\IndexOptimize_old.txt").CreationTime = New-Object DateTime -ArgumentList 2020, 1, 1
        $emptyFolder = New-NativeLogFolder -Name "empty" -Files @{ "DatabaseBackup_only.txt" = $legacyLines }
        # An operation block with no "Date and time" line, whose StartTime ParseExact faults.
        $noDateLines = @(
            "Command: ALTER INDEX [IX_Part] ON [dbatoolsci_mslog].[dbo].[Sales] REBUILD WITH (MAXDOP = 1)",
            "Comment: ObjectType: Table, IndexType: NonClustered", "Outcome: Succeeded", "Duration: 00:00:01", $tab
        )
        $noDateFolder = New-NativeLogFolder -Name "nodate" -Files @{ "IndexOptimize_nodate.txt" = $noDateLines }
        # A log the test holds open with no sharing, so the command's StreamReader cannot open it.
        $lockedFolder = New-NativeLogFolder -Name "locked" -Files @{ "IndexOptimize_locked.txt" = $legacyLines }
        $lockedFile = "$lockedFolder\IndexOptimize_locked.txt"
        # A file named as -Path: Test-Path passes, and the directory enumeration of a file faults.
        $fileAsPath = "$legacyFolder\IndexOptimize_legacy.txt"

        # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
        function Invoke-NativeOutsideTry {
            param([hashtable]$Arguments)
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command -Name "Get-DbaMaintenanceSolutionLog" -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaMaintenanceSolutionLog", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $outsideStop = $null
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                $null = $outsideShell.AddScript('param($Arguments) Get-DbaMaintenanceSolutionLog @Arguments; "next statement"').AddArgument($Arguments)
                try {
                    $null = $outsideShell.Invoke($null, $outsideOutput)
                } catch {
                    # The stop leaves the runspace's script through Invoke, as a method call's exception.
                    $outsideStop = $PSItem.Exception.InnerException
                }
                [PSCustomObject]@{
                    Rows     = @($outsideOutput | Where-Object { "$($PSItem.PSObject.BaseObject)" -cne "next statement" })
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
    }

    AfterAll {
        if ($logRoot -and (Test-Path -Path $logRoot)) {
            Remove-Item -Path $logRoot -Recurse -Force
        }
    }

    Context "Reading IndexOptimize logs" {
        It "reads each operation of a log in the format the pinned patterns parse" {
            $rows = @(Get-DbaMaintenanceSolutionLog -SqlInstance $logInstance -Path $legacyFolder -EnableException)
            $rows.Count | Should -Be 2

            $rebuild = $rows[0]
            $rebuild.Database | Should -BeExactly "dbatoolsci_mslog"
            $rebuild.Status | Should -BeExactly "ONLINE"
            $rebuild.StartTime | Should -BeOfType [Dataplat.Dbatools.Utility.DbaDateTime]
            ([datetime]$rebuild.StartTime).ToString("yyyy-MM-dd HH:mm:ss") | Should -BeExactly "2018-03-01 02:00:01"
            $rebuild.Duration | Should -BeOfType [timespan]
            $rebuild.Duration | Should -Be (New-Object TimeSpan -ArgumentList 0, 1, 5)
            $rebuild.Index | Should -BeExactly "IX_Part"
            $rebuild.Statistics | Should -BeNullOrEmpty
            $rebuild.Schema | Should -BeExactly "dbo"
            $rebuild.Table | Should -BeExactly "Sales"
            $rebuild.Action | Should -BeExactly "REBUILD"
            $rebuild.Options | Should -BeExactly "SORT_IN_TEMPDB = OFF, MAXDOP = 1"
            $rebuild.Timeout | Should -BeExactly "60000"
            $rebuild.Partition | Should -BeExactly "3"
            $rebuild.ObjectType | Should -BeExactly "Table"
            $rebuild.IndexType | Should -BeExactly "NonClustered"
            $rebuild.ImageText | Should -BeExactly "No"
            $rebuild.NewLOB | Should -BeExactly "No"
            $rebuild.FileStream | Should -BeExactly "No"
            $rebuild.ColumnStore | Should -BeExactly "No"
            $rebuild.AllowPageLocks | Should -BeExactly "Yes"
            $rebuild.PageCount | Should -BeExactly "2048"
            $rebuild.Fragmentation | Should -BeExactly "61.2"
            $rebuild.Outcome | Should -BeExactly "Succeeded"
            $rebuild.Error | Should -BeNullOrEmpty
            $rebuild.PSObject.Properties.Name | Should -Not -Contain "Command"
            $rebuild.PSObject.Properties.Name | Should -Not -Contain "Date and time"

            $statistics = $rows[1]
            ([datetime]$statistics.StartTime).ToString("yyyy-MM-dd HH:mm:ss") | Should -BeExactly "2018-03-01 02:01:07"
            $statistics.Duration | Should -Be (New-Object TimeSpan -ArgumentList 1, 2, 3, 4)
            $statistics.Index | Should -BeNullOrEmpty
            $statistics.Statistics | Should -BeExactly "ST_Sales_Region"
            $statistics.Schema | Should -BeExactly "dbo"
            $statistics.Table | Should -BeExactly "Sales"
            $statistics.Action | Should -BeNullOrEmpty
            $statistics.Options | Should -BeNullOrEmpty
            $statistics.Timeout | Should -BeNullOrEmpty
            $statistics.Partition | Should -BeNullOrEmpty
            $statistics.ObjectType | Should -BeExactly "Table"
            $statistics.IndexType | Should -BeExactly "N/A"
            $statistics.PageCount | Should -BeNullOrEmpty
            $statistics.Outcome | Should -BeExactly "Failed"
            $statistics.Error | Should -BeExactly "Msg 1222, Lock request time out period exceeded."
        }

        It "keeps only the IndexOptimize files later than -Since, by creation time when the name holds no date" {
            @(Get-DbaMaintenanceSolutionLog -SqlInstance $logInstance -Path $sinceFolder -EnableException).Count | Should -Be 6
            $recent = @(Get-DbaMaintenanceSolutionLog -SqlInstance $logInstance -Path $sinceFolder -Since (New-Object DateTime -ArgumentList 2021, 1, 1) -EnableException)
            $recent.Count | Should -Be 4
            $recent.Database | Select-Object -Unique | Should -BeExactly "dbatoolsci_mslog"
            foreach ($row in $recent) {
                $row.PSObject.Properties.Name | Should -Not -Contain "Status"
            }
        }

        It "warns that a directory it cannot reach is not accessible" {
            $missing = "$logRoot\missing"
            $warnings = @()
            @(Get-DbaMaintenanceSolutionLog -SqlInstance $logInstance -Path $missing -WarningVariable warnings -WarningAction SilentlyContinue).Count | Should -Be 0
            $warnings.Count | Should -Be 1
            $warnings[0].Message | Should -Match ([regex]::Escape("Directory $missing is not accessible") + '$')
        }

        It "warns when the directory holds no IndexOptimize log" {
            $warnings = @()
            @(Get-DbaMaintenanceSolutionLog -SqlInstance $logInstance -Path $emptyFolder -WarningVariable warnings -WarningAction SilentlyContinue).Count | Should -Be 0
            $warnings.Count | Should -Be 1
            $warnings[0].Message | Should -Match ([regex]::Escape("No log files returned from $logComputer") + '$')
        }

        It "warns that a LogType list holding another type is not supported, with the whole list" {
            $warnings = @()
            @(Get-DbaMaintenanceSolutionLog -SqlInstance $logInstance -LogType IndexOptimize, DatabaseBackup -Path $legacyFolder -WarningVariable warnings -WarningAction SilentlyContinue).Count | Should -Be 0
            $warnings.Count | Should -Be 1
            $warnings[0].Message | Should -Match ([regex]::Escape("Parsing IndexOptimize DatabaseBackup is not supported at the moment") + '$')
        }

        It "reads each piped instance" -Tag "NativeChecklist:pipeline-multiple" {
            @($logInstance, $logInstance | Get-DbaMaintenanceSolutionLog -Path $legacyFolder -EnableException).Count | Should -Be 4
        }

        It "warns and goes on past an instance it cannot reach" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false", "NativeChecklist:pipeline-multiple" {
            $warnings = @()
            $rows = @(@($logBadInstance, $logInstance) | Get-DbaMaintenanceSolutionLog -Path $legacyFolder -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
            $rows.Count | Should -Be 2
            $warnings.Count | Should -Be 1
            $warnings[0].Message | Should -BeLike "*Failure*"
        }

        It "throws the connection failure under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $connectFailure = $null
            try {
                $null = Get-DbaMaintenanceSolutionLog -SqlInstance $logBadInstance -Path $legacyFolder -EnableException
            } catch {
                $connectFailure = $PSItem
            }
            $connectFailure | Should -Not -BeNullOrEmpty
            $connectFailure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaMaintenanceSolutionLog*"
            "$($connectFailure.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
        }
    }

    Context "Upstream corrections" {
        # Correction empty-line-stop: the pin's while ($line = $text.ReadLine()) ends at the first empty line, so a log separated by
        # empty lines gives nothing; the port reads to the end and treats an empty line as a block separator, like a tab line.
        It "reads past an empty line, as a separator like a tab line" {
            $rows = @(Get-DbaMaintenanceSolutionLog -SqlInstance $logInstance -Path $emptyLineFolder -EnableException)
            $rows.Count | Should -Be 2
            $rows[0].Index | Should -BeExactly "IX_Part"
            $rows[1].Statistics | Should -BeExactly "ST_Sales_Region"
        }

        # Correction operation-blocks: the pin reads the parameter listing and the closing date of every bundled-version log as
        # operations, a first object holding only the listing (and a ParseExact fault for its missing date) and a last object
        # repeating the previous operation; the port writes one object per operation (a block with a Command line).
        It "writes one object per operation of a whole log, and nothing for its header, parameter listing or closing date" {
            $errors = @()
            $rows = @(Get-DbaMaintenanceSolutionLog -SqlInstance $logInstance -Path $currentFolder -ErrorVariable errors)
            $errors.Count | Should -Be 0
            $rows.Count | Should -Be 2
            ([datetime]$rows[0].StartTime).ToString("yyyy-MM-dd HH:mm:ss") | Should -BeExactly "2024-05-01 01:00:02"
            ([datetime]$rows[1].StartTime).ToString("yyyy-MM-dd HH:mm:ss") | Should -BeExactly "2024-05-01 01:00:06"
            foreach ($row in $rows) {
                $row.Error | Should -BeNullOrEmpty
            }
        }

        # Correction operation-names: the pin's patterns read only three-part names, which the bundled version no longer writes, so
        # its objects carry no Index, Statistics, Schema, Table, Action or Options; the port reads two-part names too, a REBUILD or
        # RESUME without a WITH clause, and leaves the names null for a command neither pattern reads instead of repeating the last.
        It "reads the names of the two-part commands the bundled version writes" {
            $rows = @(Get-DbaMaintenanceSolutionLog -SqlInstance $logInstance -Path $twoPartFolder -EnableException)
            $rows.Count | Should -Be 4

            $rows[0].Index | Should -BeExactly "PK_Widget"
            $rows[0].Statistics | Should -BeNullOrEmpty
            $rows[0].Schema | Should -BeExactly "dbo"
            $rows[0].Table | Should -BeExactly "Widget"
            $rows[0].Action | Should -BeExactly "REBUILD"
            $rows[0].Options | Should -BeExactly "SORT_IN_TEMPDB = OFF, ONLINE = OFF"
            $rows[0].Timeout | Should -BeExactly "30000"
            $rows[0].'Database context' | Should -BeExactly "[dbatoolsci_mslog]"

            $rows[1].Index | Should -BeNullOrEmpty
            $rows[1].Statistics | Should -BeExactly "ST_Widget_Name"
            $rows[1].Schema | Should -BeExactly "dbo"
            $rows[1].Table | Should -BeExactly "Widget"
            $rows[1].Timeout | Should -BeNullOrEmpty

            $rows[2].Index | Should -BeExactly "IX_Widget_Size"
            $rows[2].Table | Should -BeExactly "Widget"
            $rows[2].Action | Should -BeExactly "RESUME"
            $rows[2].Options | Should -BeNullOrEmpty

            foreach ($name in "Index", "Statistics", "Schema", "Table", "Action", "Options", "Timeout", "Partition") {
                $rows[3].PSObject.Properties.Name | Should -Contain $name
                $rows[3].$name | Should -BeNullOrEmpty
            }
        }

        # Correction instance-properties: the pin builds ComputerName, InstanceName and SqlInstance and never adds them, so objects
        # read from several instances cannot be told apart; the port puts them first, as its help lists them.
        It "names the instance each object comes from" {
            $server = Connect-DbaInstance -SqlInstance $logInstance -EnableException
            $rows = @(Get-DbaMaintenanceSolutionLog -SqlInstance $logInstance -Path $legacyFolder -EnableException)
            $rows.Count | Should -Be 2
            foreach ($row in $rows) {
                @($row.PSObject.Properties.Name)[0..2] | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance")
                $row.ComputerName | Should -BeExactly $server.ComputerName
                $row.InstanceName | Should -BeExactly $server.ServiceName
                $row.SqlInstance | Should -BeExactly $server.DomainInstanceName
            }
        }
    }

    # The pin's .NET calls run with no try, so a fault is a statement fault: written, and the pin goes on with its next statement
    # (the directory listing leaves no file and warns that none was returned; a reader that cannot open reads nothing; a missing
    # start date leaves StartTime unset and the object is still written). A caller's try catches it. The port surfaces each through
    # StatementFault.Surface and stops under -EnableException (the keep-going section's accepted difference).
    Context "Statement faults of the file reads" {
        It "outside any try, a plain call writes the record of <Site> and goes on" -ForEach @(
            @{ Site = "EnumerateFiles"; Fault = [System.IO.IOException]; Rows = 0; Warnings = 1 }
            @{ Site = "StreamReader"; Fault = [System.IO.IOException]; Rows = 0; Warnings = 0 }
            @{ Site = "ParseExact"; Fault = [System.FormatException]; Rows = 1; Warnings = 0 }
        ) {
            $paths = @{ EnumerateFiles = $fileAsPath; StreamReader = $lockedFolder; ParseExact = $noDateFolder }
            $lock = $null
            if ($Site -eq "StreamReader") { $lock = [System.IO.File]::Open($lockedFile, "Open", "Read", "None") }
            try {
                $outside = Invoke-NativeOutsideTry @{ SqlInstance = $logInstance; Path = $paths[$Site] }
            } finally {
                if ($lock) { $lock.Dispose() }
            }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            $outside.Errors[0].Exception.GetBaseException() | Should -BeOfType $Fault
            $outside.Rows.Count | Should -Be $Rows
            $outside.Warnings.Count | Should -Be $Warnings
            $outside.Next | Should -BeTrue
        }

        It "outside any try, -EnableException stops at the record of <Site>" -Tag "NativeChecklist:enable-exception" -ForEach @(
            @{ Site = "EnumerateFiles"; Fault = [System.IO.IOException] }
            @{ Site = "StreamReader"; Fault = [System.IO.IOException] }
            @{ Site = "ParseExact"; Fault = [System.FormatException] }
        ) {
            $paths = @{ EnumerateFiles = $fileAsPath; StreamReader = $lockedFolder; ParseExact = $noDateFolder }
            $lock = $null
            if ($Site -eq "StreamReader") { $lock = [System.IO.File]::Open($lockedFile, "Open", "Read", "None") }
            try {
                $outside = Invoke-NativeOutsideTry @{ SqlInstance = $logInstance; Path = $paths[$Site]; EnableException = $true }
            } finally {
                if ($lock) { $lock.Dispose() }
            }
            $outside.Errors.Count | Should -Be 1
            $outside.Errors[0].Exception.GetBaseException() | Should -BeOfType $Fault
            $outside.Rows.Count | Should -Be 0
            $outside.Warnings.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        It "outside any try, -ErrorAction Stop turns the record of <Site> into the stop PowerShell gives WriteError" -ForEach @(
            @{ Site = "EnumerateFiles"; Fault = [System.IO.IOException] }
            @{ Site = "StreamReader"; Fault = [System.IO.IOException] }
            @{ Site = "ParseExact"; Fault = [System.FormatException] }
        ) {
            $paths = @{ EnumerateFiles = $fileAsPath; StreamReader = $lockedFolder; ParseExact = $noDateFolder }
            $lock = $null
            if ($Site -eq "StreamReader") { $lock = [System.IO.File]::Open($lockedFile, "Open", "Read", "None") }
            try {
                $outside = Invoke-NativeOutsideTry @{ SqlInstance = $logInstance; Path = $paths[$Site]; ErrorAction = "Stop" }
            } finally {
                if ($lock) { $lock.Dispose() }
            }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outside.Stop.ErrorRecord.Exception.GetBaseException() | Should -BeOfType $Fault
            $outside.Rows.Count | Should -Be 0
            $outside.Next | Should -BeFalse
        }

        It "inside a caller's try, the catch receives the record of <Site> and the command does not go on" -ForEach @(
            @{ Site = "EnumerateFiles"; Fault = [System.IO.IOException] }
            @{ Site = "StreamReader"; Fault = [System.IO.IOException] }
            @{ Site = "ParseExact"; Fault = [System.FormatException] }
        ) {
            $paths = @{ EnumerateFiles = $fileAsPath; StreamReader = $lockedFolder; ParseExact = $noDateFolder }
            $lock = $null
            if ($Site -eq "StreamReader") { $lock = [System.IO.File]::Open($lockedFile, "Open", "Read", "None") }
            $failure = $null
            $after = $false
            $tryRows = @()
            try {
                $tryRows = @(Get-DbaMaintenanceSolutionLog -SqlInstance $logInstance -Path $paths[$Site] -WarningAction SilentlyContinue)
                $after = $true
            } catch {
                $failure = $PSItem
            } finally {
                if ($lock) { $lock.Dispose() }
            }
            $failure.Exception.GetBaseException() | Should -BeOfType $Fault
            $after | Should -BeFalse
            $tryRows.Count | Should -Be 0
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
        }

        It "works with -SqlCredential" {
            $rows = @(Get-DbaMaintenanceSolutionLog -SqlInstance $loginInstance -SqlCredential $loginCred -Path $legacyFolder -EnableException)
            $rows.Count | Should -Be 2
            $rows[0].Index | Should -BeExactly "IX_Part"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = @()
            @(Get-DbaMaintenanceSolutionLog -SqlInstance $loginInstance -Path $legacyFolder -WarningVariable warnings -WarningAction SilentlyContinue).Count | Should -Be 0
            $warnings.Count | Should -Be 1
            $warnings[0].Message | Should -BeLike "*Failure*"
        }

        # The pinned function catches the connection failure and calls Stop-Function, which throws under -EnableException.
        It "throws without the credential under -EnableException, as the pinned Stop-Function does" {
            { Get-DbaMaintenanceSolutionLog -SqlInstance $loginInstance -Path $legacyFolder -EnableException -WarningAction SilentlyContinue } | Should -Throw
        }
    }

    Context "Azure SQL Database" -Tag NativeChecklist:azure-sqldb {
        BeforeAll {
            # The command reads text logs that sqlcmd wrote. Azure SQL Database has no Agent, so the bundled solution for it
            # (bin/maintenancesolution/MaintenanceSolutionAzureSQLDatabase.sql) runs through sqlcmd from another machine, whose
            # output files -Path names; the connection is only checked and named, so the command works there with -Path.
            $azure = $null
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
                    break
                } catch {
                    $azureError = $PSItem.Exception
                    $isResuming = $false
                    while ($azureError) {
                        if ($azureError.Number -in 40613, -2 -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                        if ($azureError -is [System.ComponentModel.Win32Exception] -and $azureError.NativeErrorCode -eq 258) { $isResuming = $true }
                        if ($azureError.Message -like "*The wait operation timed out*") { $isResuming = $true }
                        $azureError = $azureError.InnerException
                    }
                    if (-not $isResuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
        }

        AfterAll {
            if ($azure) { $azure.ConnectionContext.Disconnect() }
        }

        It "reads the logs of a -Path folder over an Azure SQL Database connection" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $azureWarnings = @()
            $azureErrors = @()
            $rows = @(Get-DbaMaintenanceSolutionLog -SqlInstance $azure -Path $legacyFolder -WarningAction SilentlyContinue -WarningVariable azureWarnings -ErrorVariable azureErrors)
            $azureWarnings.Count | Should -Be 0
            $azureErrors.Count | Should -Be 0
            $rows.Count | Should -Be 2
            $rows[0].Index | Should -BeExactly "IX_Part"
            $rows[1].Statistics | Should -BeExactly "ST_Sales_Region"
        }

        # Without -Path the pin passes $server.errorlogpath, null on Azure SQL Database, to Join-AdminUnc, whose [ValidateNotNullOrEmpty()]
        # -Filepath binder writes its record; $logDir stays null and the pin warns "No log directory returned from <instance>". The pinned
        # record, measured on both editions (items/Get-DbaMaintenanceSolutionLog/evidence/pin-mslog-r2-20261107.txt, A1 to A3), has this
        # message, the stem ParameterArgumentValidationError, InvalidData, the reason ParameterBindingValidationException and no target;
        # its activity is Join-AdminUnc outside a caller try and the pinned command inside one. The port writes the public
        # ParameterBindingException with those fields (harness-edits.md, "Get-DbaMaintenanceSolutionLog: the Join-AdminUnc binder record
        # on Azure SQL Database").
        Context "Without -Path, where the server reports no error log path" {
            BeforeAll {
                $pinnedBinderMessage = "Cannot validate argument on parameter 'filepath'. The argument is null or empty. Provide an argument that is not null or empty, and then try the command again."
                $pinnedWarning = "No log directory returned from " + ([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$azure).ToString()

                function Assert-NativeBinderRecord {
                    param($Record, [string]$Activity)
                    $Record | Should -BeOfType System.Management.Automation.ErrorRecord
                    $Record.Exception | Should -BeOfType System.Management.Automation.ParameterBindingException
                    $Record.Exception.Message | Should -BeExactly $pinnedBinderMessage
                    $Record.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationError,*"
                    "$($Record.CategoryInfo.Category)" | Should -BeExactly "InvalidData"
                    $Record.CategoryInfo.Reason | Should -BeExactly "ParameterBindingValidationException"
                    $Record.CategoryInfo.Activity | Should -BeExactly $Activity
                    $Record.TargetObject | Should -BeNullOrEmpty
                }
            }

            It "outside any try, a plain call writes the binder record, then the pinned warning, and goes on" {
                $azure.ErrorLogPath | Should -BeNullOrEmpty
                $outside = Invoke-NativeOutsideTry @{ SqlInstance = $azure }
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Rows.Count | Should -Be 0
                $outside.Errors.Count | Should -Be 1
                Assert-NativeBinderRecord -Record $outside.Errors[0] -Activity "Join-AdminUnc"
                $outside.Warnings.Count | Should -Be 1
                $outside.Warnings[0].Message | Should -BeLike "*$pinnedWarning"
                $outside.Next | Should -BeTrue
            }

            It "outside any try, -ErrorAction Stop turns the binder record into the stop PowerShell gives WriteError" {
                $outside = Invoke-NativeOutsideTry @{ SqlInstance = $azure; ErrorAction = "Stop" }
                $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
                Assert-NativeBinderRecord -Record $outside.Stop.ErrorRecord -Activity "Get-DbaMaintenanceSolutionLog"
                $outside.Rows.Count | Should -Be 0
                $outside.Warnings.Count | Should -Be 0
                $outside.Next | Should -BeFalse
            }

            It "inside a caller's try, the catch receives the binder record, with no warning and no row" {
                $failure = $null
                $after = $false
                $tryWarnings = @()
                $tryRows = @()
                try {
                    $tryRows = @(Get-DbaMaintenanceSolutionLog -SqlInstance $azure -WarningVariable tryWarnings -WarningAction SilentlyContinue)
                    $after = $true
                } catch {
                    $failure = $PSItem
                }
                Assert-NativeBinderRecord -Record $failure -Activity "Get-DbaMaintenanceSolutionLog"
                $after | Should -BeFalse
                $tryWarnings.Count | Should -Be 0
                $tryRows.Count | Should -Be 0
            }

            It "stops with the binder record under -EnableException" -Tag "NativeChecklist:enable-exception" {
                $outside = Invoke-NativeOutsideTry @{ SqlInstance = $azure; EnableException = $true }
                $outside.Rows.Count | Should -Be 0
                $outside.Errors.Count | Should -Be 1
                Assert-NativeBinderRecord -Record $outside.Errors[0] -Activity "Join-AdminUnc"
                $outside.Warnings.Count | Should -Be 0
                $outside.Next | Should -BeTrue

                $failure = $null
                $eeErrors = @()
                try {
                    $null = Get-DbaMaintenanceSolutionLog -SqlInstance $azure -EnableException -ErrorVariable eeErrors -WarningAction SilentlyContinue
                } catch {
                    $failure = $PSItem
                }
                Assert-NativeBinderRecord -Record $failure -Activity "Get-DbaMaintenanceSolutionLog"
                $eeErrors.Count | Should -Be 1
                $eeErrors[0] | Should -BeOfType System.Management.Automation.CmdletInvocationException
                Assert-NativeBinderRecord -Record $eeErrors[0].ErrorRecord -Activity "Get-DbaMaintenanceSolutionLog"
            }
        }
    }
}
