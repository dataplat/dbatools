#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbccStatistic",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads statistics.

# Expected values below are as the pin measured on both editions: evidence/pin-dbccstat-20261104.txt and evidence/pin-dbccstat2-20261104.txt. Case names in comments are from those files.
# A failed connect writes one warning line naming the server, where the pin writes two (bad-plain, no-credential): an accepted difference,
# harness-edits.md, "Script-scope preferences and the one-line connect warning", points 5 to 7.

BeforeAll {
    # A statement of a fixture's setup or cleanup, never the command's. Parallel lanes share an instance and CREATE or DROP databases and logins on it, so one can be chosen as a deadlock
    # victim (6bd36cf50, result 20261104T0528149024313Z, the 2017 5.1 leg's cleanup): a bounded retry, and any other failure still fails.
    function Invoke-NativeFixtureQuery {
        param($Connection, [string]$Text)
        for ($attempt = 1; ; $attempt++) {
            try {
                return $Connection.Query($Text)
            } catch {
                if ("$($PSItem.Exception.Message)" -notlike "*deadlock victim*" -or $attempt -ge 5) { throw }
                Start-Sleep -Seconds 2
            }
        }
    }

    # A plain call in a runspace of its own, so no try of Pester's encloses it, with a next statement after it.
    function Invoke-NativeOutsideTry {
        param([hashtable]$Arguments)
        $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $outsideType = (Get-Command Get-DbaDbccStatistic -CommandType Cmdlet).ImplementingType
        $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaDbccStatistic", $outsideType, $null
        $outsideState.Commands.Add($outsideEntry)
        $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
        $outsideShell = [System.Management.Automation.PowerShell]::Create()
        $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
        $outsideStop = $null
        try {
            $outsideRunspace.Open()
            $outsideShell.Runspace = $outsideRunspace
            $null = $outsideShell.AddScript('param($Arguments) Get-DbaDbccStatistic @Arguments; "next statement"').AddArgument($Arguments)
            try {
                $null = $outsideShell.Invoke($null, $outsideOutput)
            } catch {
                # The stop leaves the runspace's script through Invoke, as a method call's exception.
                $outsideStop = $PSItem.Exception.InnerException
            }
            [pscustomobject]@{
                Rows     = @($outsideOutput | Where-Object { $null -ne $PSItem.PSObject.Properties["Cmd"] })
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

    # The record of a $db.Query that faulted, as held-plain measured it.
    function Assert-NativeQueryRecord {
        param($Record, [string]$DatabaseName)
        $listed = "Execute with results failed for Database '$DatabaseName'. "
        $inner = "Exception calling `"ExecuteWithResults`" with `"1`" argument(s): `"$listed`""
        $Record.FullyQualifiedErrorId | Should -BeLike "ScriptMethodRuntimeException*"
        "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
        $Record.CategoryInfo.Reason | Should -BeExactly "MethodInvocationException"
        $Record.TargetObject | Should -BeNullOrEmpty
        $Record.Exception | Should -BeOfType System.Management.Automation.MethodInvocationException
        $Record.Exception.Message | Should -BeExactly "Exception calling `"Query`" with `"1`" argument(s): `"$inner`""
        $Record.Exception.InnerException | Should -BeOfType System.Management.Automation.MethodInvocationException
        $Record.Exception.InnerException.Message | Should -BeExactly $inner
        $Record.Exception.InnerException.InnerException | Should -BeOfType Microsoft.SqlServer.Management.Smo.FailedOperationException
    }

    # The record of a database list that could not be read, as denied-plain measured it.
    function Assert-NativeEnumerationRecord {
        param($Record)
        $Record.FullyQualifiedErrorId | Should -BeLike "ExceptionInGetEnumerator*"
        "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
        $Record.CategoryInfo.Reason | Should -BeExactly "ExtendedTypeSystemException"
        $Record.TargetObject | Should -BeNullOrEmpty
        $Record.Exception | Should -BeOfType System.Management.Automation.ExtendedTypeSystemException
        $Record.Exception.Message | Should -BeExactly 'The following exception occurred while trying to enumerate the collection: "An exception occurred while executing a Transact-SQL statement or batch.".'
        $Record.Exception.InnerException | Should -BeOfType Microsoft.SqlServer.Management.Common.ExecutionFailureException
    }
}

Describe "Native Get-DbaDbccStatistic" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $random = Get-Random
        $dbA = "dbatoolsci_nstat_a_$random"
        $dbB = "dbatoolsci_nstat_b_$random"
        $dbHeld = "dbatoolsci_nstat_held_$random"
        $dbOff = "dbatoolsci_nstat_off_$random"
        $dbCase = "dbatoolsci_nstat_cs_$random"
        $dbTick = "dbatoolsci_nstat_tick_$random"
        $dbWide = "dbatoolsci_nstat_wide_$random"
        $dbDot = "dbatoolsci_nstat_dot_$random"
        $allDatabases = @($dbA, $dbB, $dbHeld, $dbOff, $dbCase, $dbTick, $dbWide, $dbDot)
        $wideTable = "T" + [char]0x65E5 + [char]0x672C
        $wideStatistic = "St" + [char]0x65E5 + [char]0x672C

        # The fixture's connection is never given to the command.
        $server = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
        foreach ($name in $dbA, $dbB, $dbHeld, $dbOff, $dbTick, $dbWide, $dbDot) {
            $null = Invoke-NativeFixtureQuery $server ("CREATE DATABASE [$name];")
        }
        $null = Invoke-NativeFixtureQuery $server ("CREATE DATABASE [$dbCase] COLLATE Latin1_General_CS_AS;")
        foreach ($statement in @(
                "EXEC('CREATE SCHEMA [s1]');",
                "CREATE TABLE [dbo].[T1] (id int NOT NULL CONSTRAINT [PK_T1] PRIMARY KEY); INSERT [dbo].[T1] (id) VALUES (1), (2), (3);",
                "CREATE TABLE [s1].[T1] (x int NOT NULL); INSERT [s1].[T1] (x) VALUES (1), (2); CREATE STATISTICS [St1] ON [s1].[T1] ([x]);",
                "CREATE TABLE [dbo].[T2] (a int NOT NULL, b int NOT NULL, c int NOT NULL); INSERT [dbo].[T2] (a, b, c) VALUES (1, 2, 3), (2, 3, 4), (3, 4, 5); CREATE STATISTICS [St1] ON [dbo].[T2] ([a], [b], [c]); CREATE STATISTICS [St2] ON [dbo].[T2] ([b], [a]);",
                "CREATE TABLE [dbo].[Sp ace] (a int NOT NULL); INSERT [dbo].[Sp ace] (a) VALUES (1); CREATE STATISTICS [St ace] ON [dbo].[Sp ace] ([a]);",
                "CREATE TABLE [dbo].[Hollow] (e int NOT NULL); CREATE STATISTICS [StHollow] ON [dbo].[Hollow] ([e]);",
                "CREATE TABLE [dbo].[Filt] (a int NOT NULL); INSERT [dbo].[Filt] (a) VALUES (-1), (1), (2); CREATE STATISTICS [StFilt] ON [dbo].[Filt] ([a]) WHERE a > 0;",
                "CREATE TABLE [dbo].[Str] (s varchar(20) NOT NULL); INSERT [dbo].[Str] (s) VALUES ('one'), ('two'); CREATE STATISTICS [StStr] ON [dbo].[Str] ([s]);",
                "CREATE TABLE [dbo].[Brk] (a int NOT NULL); INSERT [dbo].[Brk] (a) VALUES (1); CREATE STATISTICS [St]]X] ON [dbo].[Brk] ([a]);",
                "EXEC('CREATE VIEW [dbo].[V1] WITH SCHEMABINDING AS SELECT a, COUNT_BIG(*) AS n FROM [dbo].[T2] GROUP BY a'); CREATE UNIQUE CLUSTERED INDEX [IX_V1] ON [dbo].[V1] ([a]);"
            )) {
            $null = Invoke-NativeFixtureQuery $server ("USE [$dbA]; $statement USE [master];")
        }
        $null = Invoke-NativeFixtureQuery $server ("USE [$dbB]; CREATE TABLE [dbo].[T1] (id int NOT NULL CONSTRAINT [PK_T1B] PRIMARY KEY); INSERT [dbo].[T1] (id) VALUES (1); USE [master];")
        $null = Invoke-NativeFixtureQuery $server ("USE [$dbHeld]; CREATE TABLE [dbo].[T1] (id int NOT NULL CONSTRAINT [PK_T1S] PRIMARY KEY); INSERT [dbo].[T1] (id) VALUES (1); USE [master];")
        $null = Invoke-NativeFixtureQuery $server ("USE [$dbOff]; CREATE TABLE [dbo].[T1] (id int NOT NULL CONSTRAINT [PK_T1O] PRIMARY KEY); USE [master];")
        $null = Invoke-NativeFixtureQuery $server ("USE [$dbCase]; CREATE TABLE [dbo].[Cs] (a int NOT NULL, b int NOT NULL); INSERT [dbo].[Cs] (a, b) VALUES (1, 2); CREATE STATISTICS [Sta] ON [dbo].[Cs] ([a]); CREATE STATISTICS [sta] ON [dbo].[Cs] ([b]); USE [master];")
        $null = Invoke-NativeFixtureQuery $server ("USE [$dbTick]; CREATE TABLE [dbo].[Tick'Tab] (a int NOT NULL); INSERT [dbo].[Tick'Tab] (a) VALUES (1); CREATE STATISTICS [St'Tick] ON [dbo].[Tick'Tab] ([a]); CREATE TABLE [dbo].[T2] (a int NOT NULL); INSERT [dbo].[T2] (a) VALUES (1); CREATE STATISTICS [St1] ON [dbo].[T2] ([a]); USE [master];")
        $null = Invoke-NativeFixtureQuery $server ("USE [$dbWide]; CREATE TABLE [dbo].[$wideTable] (a int NOT NULL); INSERT [dbo].[$wideTable] (a) VALUES (1); CREATE STATISTICS [$wideStatistic] ON [dbo].[$wideTable] ([a]); USE [master];")
        $null = Invoke-NativeFixtureQuery $server ("USE [$dbDot]; CREATE TABLE [dbo].[Dot.Tab] (a int NOT NULL); INSERT [dbo].[Dot.Tab] (a) VALUES (1); CREATE STATISTICS [St.Dot] ON [dbo].[Dot.Tab] ([a]); CREATE TABLE [dbo].[Br]]ack] (a int NOT NULL); INSERT [dbo].[Br]]ack] (a) VALUES (1); CREATE STATISTICS [St]]at] ON [dbo].[Br]]ack] ([a]); USE [master];")
        $null = Invoke-NativeFixtureQuery $server ("USE [master]; ALTER DATABASE [$dbOff] SET OFFLINE WITH ROLLBACK IMMEDIATE;")

        # An independent read of a statement's rows, on the fixture's connection.
        function Read-NativeEngine {
            param([string]$DatabaseName, [string]$Statement)
            $table = $server.Databases[$DatabaseName].ExecuteWithResults($Statement).Tables[0]
            $null = $server.ConnectionContext.ExecuteNonQuery("USE [master];")
            return , $table
        }

        function Assert-NativeRows {
            param($Rows, $Engine, [string[]]$Names)
            @($Rows).Count | Should -Be $Engine.Rows.Count
            for ($row = 0; $row -lt $Engine.Rows.Count; $row++) {
                for ($ordinal = 0; $ordinal -lt $Engine.Columns.Count; $ordinal++) {
                    $value = @($Rows)[$row].($Names[$ordinal])
                    $engineValue = $Engine.Rows[$row][$ordinal]
                    $value.GetType().FullName | Should -BeExactly $engineValue.GetType().FullName -Because $Names[$ordinal]
                    "$value" | Should -BeExactly "$engineValue" -Because $Names[$ordinal]
                }
            }
        }
    }

    AfterAll {
        $server.ConnectionContext.Disconnect()
        [Microsoft.Data.SqlClient.SqlConnection]::ClearAllPools()
        $cleaner = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
        foreach ($name in $allDatabases) {
            $null = Invoke-NativeFixtureQuery $cleaner ("IF DB_ID(N'$name') IS NOT NULL BEGIN ALTER DATABASE [$name] SET ONLINE; ALTER DATABASE [$name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$name]; END;")
        }
        $cleaner.ConnectionContext.Disconnect()
    }

    Context "Output" {
        BeforeAll {
            $common = "ComputerName", "InstanceName", "SqlInstance", "Database", "Object", "Target", "Cmd"
            $inA = @{ SqlInstance = $instance; Database = $dbA; EnableException = $true }
        }

        It "returns plain objects with the pinned StatHeader properties in their order and the row's values" {
            $names = "Name", "Updated", "Rows", "RowsSampled", "Steps", "Density", "AverageKeyLength", "StringIndex", "FilterExpression", "UnfilteredRows", "PersistedSamplePercent"
            $result = @(Get-DbaDbccStatistic @inA -Object dbo.T2 -Target St1)
            $result.Count | Should -Be 1
            $result[0].PSObject.TypeNames[0] | Should -BeExactly "System.Management.Automation.PSCustomObject"
            $result[0].PSObject.Properties.Name | Should -BeExactly ($common + $names)
            $result[0].ComputerName | Should -BeExactly $server.ComputerName
            $result[0].InstanceName | Should -BeExactly $server.ServiceName
            $result[0].SqlInstance | Should -BeExactly $server.DomainInstanceName
            $result[0].Database | Should -BeExactly $dbA
            $result[0].Object | Should -BeExactly "dbo.T2"
            $result[0].Target | Should -BeExactly "St1"
            $result[0].Cmd | Should -BeExactly "DBCC SHOW_STATISTICS('dbo.T2', 'St1') WITH NO_INFOMSGS, STAT_HEADER"
            Assert-NativeRows -Rows $result -Engine (Read-NativeEngine $dbA $result[0].Cmd) -Names $names
        }

        It "returns the DensityVector rows, with AllDensity as the row's text" {
            $result = @(Get-DbaDbccStatistic @inA -Object dbo.T2 -Target St1 -Option DensityVector)
            $engine = Read-NativeEngine $dbA "DBCC SHOW_STATISTICS('dbo.T2', 'St1') WITH NO_INFOMSGS, DENSITY_VECTOR"
            $result.Count | Should -Be 3
            $result.Count | Should -Be $engine.Rows.Count
            $result[0].PSObject.Properties.Name | Should -BeExactly ($common + @("AllDensity", "AverageLength", "Columns"))
            $result[0].Cmd | Should -BeExactly "DBCC SHOW_STATISTICS('dbo.T2', 'St1') WITH NO_INFOMSGS, DENSITY_VECTOR"
            for ($row = 0; $row -lt $result.Count; $row++) {
                $result[$row].AllDensity | Should -BeOfType [string]
                $result[$row].AllDensity | Should -BeExactly $engine.Rows[$row][0].ToString()
                $result[$row].Columns | Should -BeExactly $engine.Rows[$row][2]
            }
        }

        It "returns the Histogram rows" {
            $names = "RangeHiKey", "RangeRows", "EqualRows", "DistinctRangeRows", "AverageRangeRows"
            $result = @(Get-DbaDbccStatistic @inA -Object dbo.T2 -Target St1 -Option Histogram)
            $result[0].PSObject.Properties.Name | Should -BeExactly ($common + $names)
            $result[0].Cmd | Should -BeExactly "DBCC SHOW_STATISTICS('dbo.T2', 'St1') WITH NO_INFOMSGS, HISTOGRAM"
            $result.Count | Should -BeGreaterThan 0
            Assert-NativeRows -Rows $result -Engine (Read-NativeEngine $dbA $result[0].Cmd) -Names $names
        }

        It "returns the StatsStream row, with the bytes as an array" {
            $names = "StatsStream", "Rows", "DataPages"
            $result = @(Get-DbaDbccStatistic @inA -Object dbo.T2 -Target St1 -Option StatsStream)
            $result.Count | Should -Be 1
            $result[0].PSObject.Properties.Name | Should -BeExactly ($common + $names)
            $result[0].Cmd | Should -BeExactly "DBCC SHOW_STATISTICS('dbo.T2', 'St1') WITH NO_INFOMSGS, STATS_STREAM"
            $result[0].StatsStream.GetType().FullName | Should -BeExactly "System.Byte[]"
            $result[0].StatsStream.Length | Should -BeGreaterThan 0
            $result[0].Rows -is [System.DBNull] | Should -BeTrue
            $result[0].DataPages -is [System.DBNull] | Should -BeTrue
            # The bytes are not compared with an independent read: on SQL Server 2019 two reads of one statistic differ (a11e7216, result 20261104T0432355925031Z).
            $engine = Read-NativeEngine $dbA $result[0].Cmd
            $engine.Rows.Count | Should -Be 1
            $engine.Rows[0][0].GetType().FullName | Should -BeExactly "System.Byte[]"
        }

        # shape-hollow-*: Microsoft Learn: with no data read, the statistics blob is not created.
        It "reads statistics on an empty table as the server leaves them" {
            $header = @(Get-DbaDbccStatistic @inA -Object dbo.Hollow -Target StHollow)
            $header.Count | Should -Be 1
            $header[0].Name | Should -BeExactly "StHollow"
            $header[0].Updated -is [System.DBNull] | Should -BeTrue
            $header[0].Rows -is [System.DBNull] | Should -BeTrue
            @(Get-DbaDbccStatistic @inA -Object dbo.Hollow -Target StHollow -Option DensityVector).Count | Should -Be 0
            @(Get-DbaDbccStatistic @inA -Object dbo.Hollow -Target StHollow -Option Histogram).Count | Should -Be 0
            @(Get-DbaDbccStatistic @inA -Object dbo.Hollow -Target StHollow -Option StatsStream).Count | Should -Be 1
        }

        # shape-filtered, shape-string.
        It "reads the filter expression and the string index" {
            $filtered = @(Get-DbaDbccStatistic @inA -Object dbo.Filt -Target StFilt)
            "$($filtered[0].FilterExpression)" | Should -Match "a"
            "$($filtered[0].FilterExpression)" | Should -Match ">"
            $filtered[0].UnfilteredRows | Should -BeOfType [long]
            $filtered[0].UnfilteredRows | Should -Be 3
            $text = @(Get-DbaDbccStatistic @inA -Object dbo.Str -Target StStr)
            "$($text[0].StringIndex)" | Should -Match "^YES"
            $plain = @(Get-DbaDbccStatistic @inA -Object dbo.T2 -Target St1)
            "$($plain[0].StringIndex)" | Should -Match "^NO"
            $plain[0].FilterExpression -is [System.DBNull] | Should -BeTrue
        }

        # option-lower.
        It "takes -Option in any case and writes the same statement" {
            $result = @(Get-DbaDbccStatistic @inA -Object dbo.T2 -Target St1 -Option histogram)
            $result[0].Cmd | Should -BeExactly "DBCC SHOW_STATISTICS('dbo.T2', 'St1') WITH NO_INFOMSGS, HISTOGRAM"
            $result[0].PSObject.Properties.Name | Should -Contain "RangeHiKey"
        }

        # option-invalid.
        It "refuses a value outside the pinned set at the binder" {
            $caught = $null
            try {
                $null = Get-DbaDbccStatistic -SqlInstance $instance -Option Nope
            } catch {
                $caught = $PSItem
            }
            $caught.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationError,*"
        }

        # all-one-database: one row per statistic, in the order of the list.
        It "runs the statement of each statistic of the database, in the order of the list" {
            $list = Read-NativeEngine $dbA "SELECT Object, Target, name FROM ( SELECT SCHEMA_NAME(o.schema_id) + '.' + o.name AS Object, st.name AS Target, o.name FROM sys.stats st INNER JOIN sys.objects o ON o.object_id = st.object_id WHERE o.type IN ('U', 'V') ) a"
            $list.Rows.Count | Should -BeGreaterThan 9
            $warnings = $null
            $result = @(Get-DbaDbccStatistic -SqlInstance $instance -Database $dbA -WarningVariable warnings -WarningAction SilentlyContinue)
            @($warnings).Count | Should -Be 0
            $result.Count | Should -Be $list.Rows.Count
            for ($row = 0; $row -lt $result.Count; $row++) {
                $result[$row].Object | Should -BeExactly $list.Rows[$row]["Object"]
                $result[$row].Target | Should -BeExactly $list.Rows[$row]["Target"]
                $result[$row].Name | Should -BeExactly $list.Rows[$row]["Target"]
            }
        }

        # noinfo-true, noinfo-false: the statement always says NO_INFOMSGS.
        It "does not change the statement or the rows with -NoInformationalMessages" {
            $plain = @(Get-DbaDbccStatistic @inA -Object dbo.T2 -Target St1)
            foreach ($switch in $true, $false) {
                $result = @(Get-DbaDbccStatistic @inA -Object dbo.T2 -Target St1 -NoInformationalMessages:$switch)
                $result.Count | Should -Be 1
                $result[0].Cmd | Should -BeExactly $plain[0].Cmd
            }
        }

        # all-one-database, offline-named.
        It "writes the pinned verbose lines" {
            $verbose = @(Get-DbaDbccStatistic @inA -Object dbo.T2 -Target St2 -Verbose 4>&1 | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message })
            @($verbose | Where-Object { $PSItem -like "*Processing ``[$dbA``] on *" }).Count | Should -Be 1
            @($verbose | Where-Object { $PSItem -like "*Running statement DBCC SHOW_STATISTICS('dbo.T2', 'St2') WITH NO_INFOMSGS, STAT_HEADER" }).Count | Should -Be 1
            @($verbose | Where-Object { $PSItem -like "*Query to execute:*" }).Count | Should -Be 0
        }

        It "writes the list query in a verbose line with -Object" {
            $verbose = @(Get-DbaDbccStatistic @inA -Object dbo.T2 -Verbose 4>&1 | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message })
            $query = @($verbose | Where-Object { $PSItem -like "*Query to execute: SELECT Object, Target, name FROM*" })
            $query.Count | Should -Be 1
            $query[0] | Should -BeLike "* WHERE (Object = 'dbo.T2' or name = 'dbo.T2')"
        }
    }

    Context "Selecting the databases" {
        # database-two.
        It "reads each database named, and only those" {
            $result = @(Get-DbaDbccStatistic -SqlInstance $instance -Database $dbB, $dbTick -Object dbo.T1 -EnableException)
            @($result.Database | Select-Object -Unique) | Should -BeExactly @($dbB)
            $both = @(Get-DbaDbccStatistic -SqlInstance $instance -Database $dbB, $dbCase -EnableException)
            @($both.Database | Sort-Object -Unique) | Should -BeExactly @(@($dbB, $dbCase) | Sort-Object)
        }

        # database-case.
        It "matches a database name whatever its case" {
            $result = @(Get-DbaDbccStatistic -SqlInstance $instance -Database $dbB.ToUpperInvariant() -EnableException)
            $result.Count | Should -Be 1
            $result[0].Database | Should -BeExactly $dbB
        }

        # database-wildcard, database-missing, database-two-empties.
        It "selects nothing for a value that names no database" {
            foreach ($value in @("dbatoolsci_nstat_b_*", "dbatoolsci_nstat_nope_$random", @("", ""))) {
                $warnings = $null
                $result = @(Get-DbaDbccStatistic -SqlInstance $instance -Database $value -WarningVariable warnings -WarningAction SilentlyContinue)
                $result.Count | Should -Be 0
                @($warnings).Count | Should -Be 0
            }
        }

        # database-null-element.
        It "ignores a null element beside a name" {
            $result = @(Get-DbaDbccStatistic -SqlInstance $instance -Database @($null, $dbB) -EnableException)
            $result.Count | Should -Be 1
            $result[0].Database | Should -BeExactly $dbB
        }

        # database-empty, database-empty-array, database-null: an empty value is false, so every database is read.
        It "reads every database for an empty or null -Database" {
            foreach ($value in @{ V = "" }, @{ V = @() }, @{ V = $null }) {
                $warnings = $null
                $result = @(Get-DbaDbccStatistic -SqlInstance $instance -Database $value.V -Object dbo.T1 -Target PK_T1B -WarningVariable warnings -WarningAction SilentlyContinue)
                @($result.Database) | Should -Contain $dbB
                # The target exists only in that database and each other accessible one warns; the offline one is reported apart.
                @($warnings | Where-Object { "$PSItem" -like "*Failed during execution*" }).Count | Should -BeGreaterThan 0
                @($warnings | Where-Object { "$PSItem" -like "*The database ``[$dbOff``] is not accessible. Skipping." }).Count | Should -Be 1
            }
        }
    }

    Context "-Object alone" {
        BeforeAll {
            $inA = @{ SqlInstance = $instance; Database = $dbA; EnableException = $true }
        }

        # object-two-part.
        It "reads every statistic of a two-part name" {
            $result = @(Get-DbaDbccStatistic @inA -Object dbo.T2)
            @($result.Target | Sort-Object) | Should -BeExactly @("St1", "St2")
            @($result.Object | Select-Object -Unique) | Should -BeExactly @("dbo.T2")
            @($result.Cmd) | Should -Contain "DBCC SHOW_STATISTICS('dbo.T2', 'St1') WITH NO_INFOMSGS, STAT_HEADER"
        }

        # object-name, object-name-two-schemas.
        It "reads the table of that name in every schema, given a one-part name" {
            $result = @(Get-DbaDbccStatistic @inA -Object T1)
            @($result.Object | Sort-Object) | Should -BeExactly @("dbo.T1", "s1.T1")
            @($result.Target | Sort-Object) | Should -BeExactly @("PK_T1", "St1")
        }

        # object-view, object-space.
        It "reads an indexed view and a name holding a space" {
            @((Get-DbaDbccStatistic @inA -Object dbo.V1).Target) | Should -BeExactly @("IX_V1")
            @((Get-DbaDbccStatistic @inA -Object "dbo.Sp ace").Target) | Should -BeExactly @("St ace")
        }

        # object-case, object-case-sensitive-db, object-case-sensitive-both: the database's collation decides.
        It "matches the name as the database's collation does" {
            @(Get-DbaDbccStatistic @inA -Object DBO.T2).Count | Should -Be 2
            @(Get-DbaDbccStatistic -SqlInstance $instance -Database $dbCase -Object DBO.CS -EnableException).Count | Should -Be 0
            $targets = @((Get-DbaDbccStatistic -SqlInstance $instance -Database $dbCase -Object dbo.Cs -EnableException).Target)
            $targets.Count | Should -Be 2
            $targets -ccontains "Sta" | Should -BeTrue
            $targets -ccontains "sta" | Should -BeTrue
        }

        # object-bracket, object-missing, object-empty, object-null, object-wildcard: the list holds plain names.
        It "returns nothing and no warning for a text the list does not hold" {
            foreach ($value in "[dbo].[T2]", "dbo.Nope", "", $null, "dbo.T*") {
                $warnings = $null
                $result = @(Get-DbaDbccStatistic -SqlInstance $instance -Database $dbA -Object $value -WarningVariable warnings -WarningAction SilentlyContinue)
                $result.Count | Should -Be 0
                @($warnings).Count | Should -Be 0
            }
        }
    }

    Context "-Object and -Target" {
        BeforeAll {
            $inA = @{ SqlInstance = $instance; Database = $dbA; WarningAction = "SilentlyContinue" }
        }

        # pair-valid, pair-index, pair-view, pair-bare-name, pair-object-bracket: the server reads the object's name and the row keeps the caller's text.
        It "reads a statistic, an index and a view's index, in the forms the server accepts" {
            foreach ($form in @(
                    @{ O = "dbo.T2"; T = "St1"; N = "St1" },
                    @{ O = "dbo.T1"; T = "PK_T1"; N = "PK_T1" },
                    @{ O = "dbo.V1"; T = "IX_V1"; N = "IX_V1" },
                    @{ O = "T2"; T = "St1"; N = "St1" },
                    @{ O = "[dbo].[T2]"; T = "St1"; N = "St1" }
                )) {
                $warnings = $null
                $result = @(Get-DbaDbccStatistic @inA -Object $form.O -Target $form.T -WarningVariable warnings)
                $result.Count | Should -Be 1
                @($warnings).Count | Should -Be 0
                $result[0].Name | Should -BeExactly $form.N
                $result[0].Object | Should -BeExactly $form.O
                $result[0].Target | Should -BeExactly $form.T
                $result[0].Cmd | Should -BeExactly "DBCC SHOW_STATISTICS('$($form.O)', '$($form.T)') WITH NO_INFOMSGS, STAT_HEADER"
            }
        }

        # pair-column, pair-target-missing, pair-target-empty, pair-target-null, pair-object-missing, pair-object-empty, pair-object-null.
        It "warns with the server's message under the nested command's name, and returns nothing" {
            foreach ($form in @(
                    @{ O = "dbo.T2"; T = "b"; M = "Could not locate statistics 'b' in the system catalogs." },
                    @{ O = "dbo.T2"; T = "Nope"; M = "Could not locate statistics 'Nope' in the system catalogs." },
                    @{ O = "dbo.T2"; T = ""; M = "Could not locate statistics '' in the system catalogs." },
                    @{ O = "dbo.T2"; T = $null; M = "Could not locate statistics '' in the system catalogs." },
                    @{ O = "dbo.Nope"; T = "St1"; M = "Cannot find a table or object with the name ""dbo.Nope"". Check the system catalog." },
                    @{ O = ""; T = "St1"; M = "Cannot find a table or object with the name """". Check the system catalog." },
                    @{ O = $null; T = "St1"; M = "Cannot find a table or object with the name """". Check the system catalog." }
                )) {
                $warnings = $null
                $captured = @()
                $result = @(Get-DbaDbccStatistic @inA -Object $form.O -Target $form.T -WarningVariable warnings -ErrorVariable captured)
                $result.Count | Should -Be 0
                @($warnings).Count | Should -Be 1
                "$($warnings[0])" | Should -BeLike "*``[Invoke-DbaQuery``] ``[*``] Failed during execution | $($form.M)"

                # The caller's -ErrorVariable holds the nested Invoke-DbaQuery Stop-Function record, as the pinned nested call puts it
                # there (watchman 22dc72e0, central CaptureErrorVariable). The pin's also holds the records of the nested query's own
                # caught calls and blank entries: accepted difference omitted-consequential-records.
                $captured = @($captured)
                $captured.Count | Should -Be 1
                $captured[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $captured[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Invoke-DbaQuery*"
                $captured[0].Exception.Message | Should -BeExactly $form.M
            }
        }

        # pair-target-missing-ee, pair-target-missing-stop, pair-target-missing-try: the nested query is given no -EnableException and no stop.
        It "stays a warning under -EnableException and -ErrorAction Stop, and in a caller's try" -Tag "NativeChecklist:enable-exception" {
            foreach ($splat in @{ EnableException = $true }, @{ ErrorAction = "Stop" }, @{ }) {
                $warnings = $null
                $captured = @()
                $failure = $null
                $after = $false
                try {
                    $result = @(Get-DbaDbccStatistic @inA @splat -Object dbo.T2 -Target Nope -WarningVariable warnings -ErrorVariable captured)
                    $after = $true
                } catch {
                    $failure = $PSItem
                }
                $failure | Should -BeNullOrEmpty
                $after | Should -BeTrue
                $result.Count | Should -Be 0
                @($warnings).Count | Should -Be 1
                @($captured).Count | Should -Be 1
                @($captured)[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Invoke-DbaQuery*"
            }
        }

        # pair-target-missing-SilentlyContinue, pair-target-missing-Ignore: Resolve-SqlError in the nested query drops the failure.
        It "drops the warning under -ErrorAction SilentlyContinue and Ignore" {
            foreach ($action in "SilentlyContinue", "Ignore") {
                $warnings = $null
                $captured = @()
                $result = @(Get-DbaDbccStatistic -SqlInstance $instance -Database $dbA -Object dbo.T2 -Target Nope -ErrorAction $action -WarningVariable warnings -WarningAction SilentlyContinue -ErrorVariable captured)
                $result.Count | Should -Be 0
                @($warnings).Count | Should -Be 0
                # No nested Stop-Function runs, so nothing reaches -ErrorVariable either.
                @($captured).Count | Should -Be 0
            }
        }
    }

    # Correction quoted-names. The cases hold no fixture of the other tests, so only these see the quote.
    Context "Names holding a quote, and text that would leave its literal" {
        BeforeAll {
            $inTick = @{ SqlInstance = $instance; Database = $dbTick; WarningAction = "SilentlyContinue" }
        }

        It "reads a table and a statistic whose names hold a quote, given by -Object and -Target" {
            $warnings = $null
            $result = @(Get-DbaDbccStatistic @inTick -Object "dbo.Tick'Tab" -Target "St'Tick" -WarningVariable warnings)
            @($warnings).Count | Should -Be 0
            $result.Count | Should -Be 1
            $result[0].Name | Should -BeExactly "St'Tick"
            $result[0].Object | Should -BeExactly "dbo.Tick'Tab"
            $result[0].Target | Should -BeExactly "St'Tick"
            $result[0].Cmd | Should -BeExactly "DBCC SHOW_STATISTICS('dbo.Tick''Tab', 'St''Tick') WITH NO_INFOMSGS, STAT_HEADER"
        }

        It "finds a table whose name holds a quote with -Object alone" {
            foreach ($value in "dbo.Tick'Tab", "Tick'Tab") {
                $warnings = $null
                $result = @(Get-DbaDbccStatistic @inTick -Object $value -WarningVariable warnings -EnableException)
                @($warnings).Count | Should -Be 0
                $result.Count | Should -Be 1
                $result[0].Name | Should -BeExactly "St'Tick"
            }
        }

        It "reads the statistic of a table whose name holds a quote when it comes from the list" {
            $warnings = $null
            $result = @(Get-DbaDbccStatistic @inTick -WarningVariable warnings)
            @($warnings).Count | Should -Be 0
            @($result.Object) | Should -Contain "dbo.Tick'Tab"
            @($result.Name) | Should -Contain "St'Tick"
        }

        It "reports a -Target holding a quote as a statistic that does not exist" {
            $warnings = $null
            $result = @(Get-DbaDbccStatistic @inTick -Object dbo.T2 -Target "St'1" -WarningVariable warnings)
            $result.Count | Should -Be 0
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -BeLike "*Could not locate statistics 'St'1' in the system catalogs."
        }

        It "runs no second statement from -Object" {
            $text = "dbo.T2', 'St1') WITH NO_INFOMSGS, STAT_HEADER; SELECT 11 AS injected, 22 AS second --"
            $warnings = $null
            $result = @(Get-DbaDbccStatistic @inTick -Object $text -Target x -WarningVariable warnings)
            $result.Count | Should -Be 0
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -BeLike "*Failed during execution | *"
        }

        It "runs no second statement from -Target" {
            $text = "St1') WITH NO_INFOMSGS, STAT_HEADER; SELECT 33 AS injected, 44 AS second --"
            $warnings = $null
            $result = @(Get-DbaDbccStatistic @inTick -Object dbo.T2 -Target $text -WarningVariable warnings)
            $result.Count | Should -Be 0
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -BeLike "*Could not locate statistics*"
        }

        It "turns no printed line into a row" {
            $text = "St1') WITH NO_INFOMSGS, STAT_HEADER; PRINT 'printed' --"
            $warnings = $null
            $result = @(Get-DbaDbccStatistic @inTick -Object dbo.T2 -Target $text -WarningVariable warnings)
            $result.Count | Should -Be 0
            @($warnings).Count | Should -Be 1
        }

        It "does not widen the list from -Object" {
            $warnings = $null
            $result = @(Get-DbaDbccStatistic @inTick -Object "x' OR 1=1 OR Object = 'y" -WarningVariable warnings)
            $result.Count | Should -Be 0
            @($warnings).Count | Should -Be 0
        }
    }

    # Correction name-outside-code-page. Its own database, so only these see such a name. The characters come from their codes: 5.1 reads this file in the system's code page.
    Context "Names outside the database's code page" {
        BeforeAll {
            $inWide = @{ SqlInstance = $instance; Database = $dbWide; WarningAction = "SilentlyContinue" }
        }

        It "reads a statistic whose name is outside the code page, from the list" {
            $warnings = $null
            $result = @(Get-DbaDbccStatistic @inWide -WarningVariable warnings)
            @($warnings).Count | Should -Be 0
            $result.Count | Should -Be 1
            $result[0].Name | Should -BeExactly $wideStatistic
            $result[0].Object | Should -BeExactly "dbo.$wideTable"
        }

        It "finds a table whose name is outside the code page with -Object alone" {
            foreach ($value in "dbo.$wideTable", $wideTable) {
                $warnings = $null
                $result = @(Get-DbaDbccStatistic @inWide -Object $value -WarningVariable warnings)
                @($warnings).Count | Should -Be 0
                $result.Count | Should -Be 1
                $result[0].Name | Should -BeExactly $wideStatistic
            }
        }

        It "reads a statistic whose name is outside the code page, given by -Object and -Target" {
            $warnings = $null
            $result = @(Get-DbaDbccStatistic @inWide -Object "dbo.$wideTable" -Target $wideStatistic -WarningVariable warnings)
            @($warnings).Count | Should -Be 0
            $result.Count | Should -Be 1
            $result[0].Name | Should -BeExactly $wideStatistic
            $result[0].Cmd | Should -BeExactly "DBCC SHOW_STATISTICS(N'dbo.$wideTable', N'$wideStatistic') WITH NO_INFOMSGS, STAT_HEADER"
        }
    }

    # Correction list-names-the-server-splits. Its own database, so only these see such a name. dot-list, dot-object: the server read the plain text as database.schema.table and warned of a database dbo.
    Context "Tables the list names with a dot or a bracket" {
        BeforeAll {
            $inDot = @{ SqlInstance = $instance; Database = $dbDot; WarningAction = "SilentlyContinue" }
        }

        It "reads the statistics of those tables from the list" {
            $warnings = $null
            $result = @(Get-DbaDbccStatistic @inDot -WarningVariable warnings)
            @($warnings).Count | Should -Be 0
            $result.Count | Should -Be 2
            @($result.Object | Sort-Object) | Should -BeExactly @("dbo.Br]ack", "dbo.Dot.Tab")
            @($result.Name | Sort-Object) | Should -BeExactly @("St.Dot", "St]at")
            @($result.Cmd) | Should -Contain "DBCC SHOW_STATISTICS('[dbo].[Dot.Tab]', 'St.Dot') WITH NO_INFOMSGS, STAT_HEADER"
            @($result.Cmd) | Should -Contain "DBCC SHOW_STATISTICS('[dbo].[Br]]ack]', 'St]at') WITH NO_INFOMSGS, STAT_HEADER"
        }

        It "reads the statistic of a table named with a dot, with -Object alone" {
            $warnings = $null
            $result = @(Get-DbaDbccStatistic @inDot -Object dbo.Dot.Tab -WarningVariable warnings)
            @($warnings).Count | Should -Be 0
            $result.Count | Should -Be 1
            $result[0].Name | Should -BeExactly "St.Dot"
            $result[0].Object | Should -BeExactly "dbo.Dot.Tab"
        }
    }

    # dot-pair, dot-pair-brackets, bracket-pair, bracket-pair-brackets: given both names, the statement holds the caller's text and the server reads it.
    Context "A dot or a bracket in the caller's -Object" {
        BeforeAll {
            $inDot = @{ SqlInstance = $instance; Database = $dbDot; WarningAction = "SilentlyContinue" }
        }

        It "warns for the plain text and reads the bracketed text" {
            $warnings = $null
            @(Get-DbaDbccStatistic @inDot -Object dbo.Dot.Tab -Target St.Dot -WarningVariable warnings).Count | Should -Be 0
            "$($warnings[0])" | Should -BeLike "*Could not find database 'dbo'*"
            $warnings = $null
            @(Get-DbaDbccStatistic @inDot -Object "dbo.Br]ack" -Target "St]at" -WarningVariable warnings).Count | Should -Be 0
            "$($warnings[0])" | Should -BeLike "*Cannot find a table or object with the name `"dbo.Br]ack`"*"
            @((Get-DbaDbccStatistic @inDot -Object "[dbo].[Dot.Tab]" -Target St.Dot).Name) | Should -BeExactly @("St.Dot")
            @((Get-DbaDbccStatistic @inDot -Object "[dbo].[Br]]ack]" -Target "St]at").Name) | Should -BeExactly @("St]at")
        }
    }

    # Correction target-enclosed. Microsoft Learn's DBCC SHOW_STATISTICS page and the pinned help: target is enclosed in brackets, single quotes, double quotes, or no quotes.
    Context "A -Target enclosed as its help documents" {
        BeforeAll {
            $inA = @{ SqlInstance = $instance; Database = $dbA; WarningAction = "SilentlyContinue" }
        }

        It "reads a -Target in brackets, in double quotes and in single quotes" {
            foreach ($form in '[St1]', '"St1"', "'St1'") {
                $warnings = $null
                $result = @(Get-DbaDbccStatistic @inA -Object dbo.T2 -Target $form -WarningVariable warnings)
                @($warnings).Count | Should -Be 0
                $result.Count | Should -Be 1
                $result[0].Name | Should -BeExactly "St1"
                $result[0].Target | Should -BeExactly $form
                $result[0].Cmd | Should -BeExactly "DBCC SHOW_STATISTICS('dbo.T2', 'St1') WITH NO_INFOMSGS, STAT_HEADER"
            }
        }

        It "reads a -Target in brackets whose name holds an escaped bracket" {
            $warnings = $null
            $result = @(Get-DbaDbccStatistic @inA -Object dbo.Brk -Target "[St]]X]" -WarningVariable warnings)
            @($warnings).Count | Should -Be 0
            $result.Count | Should -Be 1
            $result[0].Name | Should -BeExactly "St]X"
        }
    }

    # Correction target-alone.
    Context "-Target without -Object" {
        BeforeAll {
            $inA = @{ SqlInstance = $instance; Database = $dbA; WarningAction = "SilentlyContinue" }
        }

        It "reads only the statistics of that name, on every table" {
            $warnings = $null
            $result = @(Get-DbaDbccStatistic @inA -Target St1 -WarningVariable warnings)
            @($warnings).Count | Should -Be 0
            @($result.Object | Sort-Object) | Should -BeExactly @("dbo.T2", "s1.T1")
            @($result.Name | Select-Object -Unique) | Should -BeExactly @("St1")
        }

        It "takes the enclosed forms there too" {
            foreach ($form in '[St2]', '"St2"', "'St2'") {
                $result = @(Get-DbaDbccStatistic @inA -Target $form)
                $result.Count | Should -Be 1
                $result[0].Object | Should -BeExactly "dbo.T2"
                $result[0].Target | Should -BeExactly "St2"
            }
        }

        It "returns nothing and no warning for a name no statistic has" {
            $warnings = $null
            $result = @(Get-DbaDbccStatistic @inA -Target Nope -WarningVariable warnings)
            $result.Count | Should -Be 0
            @($warnings).Count | Should -Be 0
        }
    }

    Context "A database that is not accessible" {
        # offline-named, offline-try.
        It "warns for it and reads the next, in a caller's try too" {
            $warnings = $null
            $result = @(Get-DbaDbccStatistic -SqlInstance $instance -Database $dbOff, $dbB -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 1
            $result[0].Database | Should -BeExactly $dbB
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -BeLike "*The database ``[$dbOff``] is not accessible. Skipping."
        }

        # offline-ee.
        It "throws under -EnableException" -Tag "NativeChecklist:enable-exception" {
            { Get-DbaDbccStatistic -SqlInstance $instance -Database $dbOff -EnableException -WarningAction SilentlyContinue } | Should -Throw -ExpectedMessage "The database ``[$dbOff``] is not accessible. Skipping." -ErrorId "dbatools_Get-DbaDbccStatistic*"
        }
    }

    Context "A database whose statistics cannot be listed" {
        BeforeAll {
            # A separate session holds the database in single-user mode. A connection that read the databases first still calls them accessible, so its list query faults.
            $holder = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
            function New-NativeReader {
                $reader = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
                foreach ($name in $dbB, $dbHeld) {
                    $null = $reader.Databases[$name].IsAccessible
                }
                return $reader
            }
            # Built before the hold: each test takes a connection that has read what the command then finds.
            $readers = New-Object System.Collections.ArrayList
            foreach ($slot in 1..11) {
                $null = $readers.Add((New-NativeReader))
            }
            $readerQueue = New-Object System.Collections.Queue
            foreach ($reader in $readers) {
                $readerQueue.Enqueue($reader)
            }
            function Get-NativeReader {
                return $readerQueue.Dequeue()
            }
            $null = $holder.ConnectionContext.ExecuteNonQuery("USE [$dbHeld]; ALTER DATABASE [$dbHeld] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;")
            $both = @($dbB, $dbHeld)
        }

        AfterAll {
            foreach ($reader in $readers) {
                $reader.ConnectionContext.Disconnect()
            }
            $null = $holder.ConnectionContext.ExecuteNonQuery("USE [master]; ALTER DATABASE [$dbHeld] SET MULTI_USER;")
            $holder.ConnectionContext.Disconnect()
        }

        # held-plain.
        It "outside any try, writes the pinned record and goes on" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = (Get-NativeReader); Database = $both }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeQueryRecord -Record $outside.Errors[0] -DatabaseName $dbHeld
            $outside.Next | Should -BeTrue
        }

        # Correction stale-list: held-plain, held-object and held-silent ran the statements of the database before it against this one.
        It "runs no statement of the database before it, reading the whole list" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = (Get-NativeReader); Database = $both }
            $outside.Warnings.Count | Should -Be 0
            $outside.Rows.Count | Should -Be 1
            $outside.Rows[0].Database | Should -BeExactly $dbB
        }

        It "runs no statement of the database before it, reading by -Object" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = (Get-NativeReader); Database = $both; Object = "dbo.T1" }
            $outside.Errors.Count | Should -Be 1
            $outside.Warnings.Count | Should -Be 0
            $outside.Rows.Count | Should -Be 1
            $outside.Rows[0].Database | Should -BeExactly $dbB
        }

        It "runs no statement of the database before it, under -ErrorAction SilentlyContinue" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = (Get-NativeReader); Database = $both; ErrorAction = "SilentlyContinue" }
            $outside.Errors.Count | Should -Be 0
            $outside.Warnings.Count | Should -Be 0
            $outside.Rows.Count | Should -Be 1
            $outside.Next | Should -BeTrue
        }

        # held-ee: the pin writes the record and goes on; an accepted difference, the keep-going section's point 3.
        It "outside any try, -EnableException ends the command at the record and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = (Get-NativeReader); Database = $both; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeQueryRecord -Record $outside.Errors[0] -DatabaseName $dbHeld
            $outside.Rows.Count | Should -Be 1
            $outside.Next | Should -BeTrue
        }

        # held-stop: an accepted difference, the stop PowerShell gives WriteError.
        It "outside any try, -ErrorAction Stop turns the record into the stop PowerShell gives WriteError" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = (Get-NativeReader); Database = $both; ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outside.Rows.Count | Should -Be 1
            $outside.Next | Should -BeFalse
        }

        # held-try, held-object-try, held-ee-try.
        It "inside a caller's try, the catch receives the record and the command does not go on" {
            foreach ($splat in @{ }, @{ EnableException = $true }) {
                $failure = $null
                $after = $false
                $rows = New-Object System.Collections.ArrayList
                try {
                    Get-DbaDbccStatistic -SqlInstance (Get-NativeReader) -Database $both @splat | ForEach-Object { $null = $rows.Add($PSItem) }
                    $after = $true
                } catch {
                    $failure = $PSItem
                }
                Assert-NativeQueryRecord -Record $failure -DatabaseName $dbHeld
                $after | Should -BeFalse
                $rows.Count | Should -Be 1
                $rows[0].Database | Should -BeExactly $dbB
            }
        }

        # held-pair: with both names no list is read, so the nested query's connection meets the hold.
        It "with -Object and -Target, warns under both nested names and goes on, under -EnableException too" -Tag "NativeChecklist:enable-exception" {
            foreach ($splat in @{ }, @{ EnableException = $true }) {
                $warnings = $null
                $captured = @()
                $result = @(Get-DbaDbccStatistic -SqlInstance (Get-NativeReader) -Database $both -Object dbo.T1 -Target PK_T1B -WarningVariable warnings -WarningAction SilentlyContinue -ErrorVariable captured @splat)
                $result.Count | Should -Be 1
                $result[0].Database | Should -BeExactly $dbB
                @($warnings).Count | Should -Be 2
                "$($warnings[0])" | Should -BeLike "*``[Connect-DbaInstance``] Failure | Error connecting to ``[*``]: *"
                "$($warnings[1])" | Should -BeLike "*``[Invoke-DbaQuery``] Failure | *"

                # The caller's -ErrorVariable holds both nested Stop-Function records, the connection's and the query's, in the order
                # the warnings show them (watchman 22dc72e0); the pin's other entries are omitted (omitted-consequential-records).
                $captured = @($captured)
                $captured.Count | Should -Be 2
                $captured[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $captured[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Connect-DbaInstance*"
                $captured[1] | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $captured[1].FullyQualifiedErrorId | Should -BeLike "dbatools_Invoke-DbaQuery*"
            }
        }

        # held-named: a fresh connection reads the database as not accessible.
        It "on a fresh connection, reports the database as not accessible" {
            $warnings = $null
            $result = @(Get-DbaDbccStatistic -SqlInstance $instance -Database $both -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 1
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -BeLike "*The database ``[$dbHeld``] is not accessible. Skipping."
        }
    }

    # downstream-throw, downstream-throw-ee, downstream-throw-try, downstream-throw-ee-try: the pin's try around the statements catches what the downstream command throws.
    Context "A downstream command that throws" {
        It "reports the failure as the pinned capture error" {
            $warnings = $null
            $seen = 0
            $after = $false
            Get-DbaDbccStatistic -SqlInstance $instance -Database $dbB -Object dbo.T1 -WarningVariable warnings -WarningAction SilentlyContinue | ForEach-Object { $seen++; throw "dbatoolsci downstream throw" }
            $after = $true
            $after | Should -BeTrue
            $seen | Should -Be 1
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -BeLike "*``[Get-DbaDbccStatistic``] Error capturing data on ``[$dbB``] | dbatoolsci downstream throw"
        }

        It "throws that capture error under -EnableException" -Tag "NativeChecklist:enable-exception" {
            { Get-DbaDbccStatistic -SqlInstance $instance -Database $dbB -Object dbo.T1 -EnableException -WarningAction SilentlyContinue | ForEach-Object { throw "dbatoolsci downstream throw" } } | Should -Throw -ExpectedMessage "*dbatoolsci downstream throw*"
        }
    }

    Context "Instances" {
        It "reads each piped instance" -Tag "NativeChecklist:pipeline-multiple" {
            $result = @($instance, $instance | Get-DbaDbccStatistic -Database $dbB -EnableException)
            $result.Count | Should -Be 2
        }

        # named-twice.
        It "reads each instance of an array" {
            $result = @(Get-DbaDbccStatistic -SqlInstance $instance, $instance -Database $dbB -EnableException)
            $result.Count | Should -Be 2
        }

        It "reads through a server object" {
            $own = Connect-DbaInstance -SqlInstance $instance -EnableException
            $result = @($own | Get-DbaDbccStatistic -Database $dbB -EnableException)
            $result.Count | Should -Be 1
            $result[0].SqlInstance | Should -BeExactly $own.DomainInstanceName
        }

        # A connection already in the database keeps it: the nested query does not open its own.
        It "leaves a caller's connection in its database" {
            $own = Connect-DbaInstance -SqlInstance $instance -Database $dbB -NonPooledConnection -EnableException
            try {
                $result = @(Get-DbaDbccStatistic -SqlInstance $own -Database $dbB -EnableException)
                $result.Count | Should -Be 1
                $own.ConnectionContext.CurrentDatabase | Should -BeExactly $dbB
            } finally {
                $own.ConnectionContext.Disconnect()
            }
        }

        # A connection in another database is put back after the list.
        It "puts a caller's connection back in its database after reading another" {
            $own = Connect-DbaInstance -SqlInstance $instance -Database $dbTick -NonPooledConnection -EnableException
            try {
                $result = @(Get-DbaDbccStatistic -SqlInstance $own -Database $dbB -EnableException)
                $result.Count | Should -Be 1
                $own.ConnectionContext.CurrentDatabase | Should -BeExactly $dbTick
            } finally {
                $own.ConnectionContext.Disconnect()
            }
        }
    }

    # bad-plain, bad-between, bad-ee, bad-try: a listener that never answers, so the connect fails fast.
    Context "An instance that cannot be reached" {
        BeforeAll {
            $savedTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
            $listener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
            $listener.Start()
            $badInstance = "127.0.0.1," + $listener.LocalEndpoint.Port
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
        }

        AfterAll {
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $savedTimeout
            $listener.Stop()
        }

        It "warns in one line naming the server and goes on to the next instance" -Tag "NativeChecklist:multi-instance-failure" {
            $warnings = $null
            $result = @(Get-DbaDbccStatistic -SqlInstance $badInstance, $instance -Database $dbB -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 1
            $result[0].Database | Should -BeExactly $dbB
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -BeLike "*``[Get-DbaDbccStatistic``] Failure | Error connecting to ``[*$badInstance``]: *"
        }

        It "warns and goes on under -EnableException:`$false" -Tag "NativeChecklist:switch-false" {
            $warnings = $null
            $result = @(Get-DbaDbccStatistic -SqlInstance $badInstance, $instance -Database $dbB -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 1
            @($warnings).Count | Should -Be 1
        }

        It "throws the connection failure under -EnableException, before the next instance" -Tag "NativeChecklist:enable-exception" {
            $failure = $null
            $rows = New-Object System.Collections.ArrayList
            try {
                Get-DbaDbccStatistic -SqlInstance $badInstance, $instance -Database $dbB -EnableException -WarningAction SilentlyContinue | ForEach-Object { $null = $rows.Add($PSItem) }
            } catch {
                $failure = $PSItem
            }
            $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbccStatistic*"
            "$($failure.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            $rows.Count | Should -Be 0
        }
    }

    # In a runspace of its own, where Streams.Warning can be read and nothing else sets a preference. Points 5 and 6 of the section named above.
    Context "The warning stream of a failed connect" {
        BeforeAll {
            $missingInstance = "nativedbccstat$(Get-Random)"
            $streamLine = "\[Get-DbaDbccStatistic\] Failure \| Error connecting to \[$missingInstance\]: "
            $streamState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $streamRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($streamState)
            $streamRunspace.Open()
            $streamShell = [System.Management.Automation.PowerShell]::Create()
            $streamShell.Runspace = $streamRunspace
            $streamModulePath = (Get-Module dbatools | Where-Object ModuleType -eq Script | Select-Object -First 1).Path
            $null = $streamShell.AddCommand("Import-Module").AddParameter("Name", $streamModulePath).AddParameter("ErrorAction", "Stop").Invoke()

            function NativeDbccStatisticStreamCall {
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
            $call = NativeDbccStatisticStreamCall -Script 'param($Target) Get-DbaDbccStatistic -SqlInstance $Target; "next statement"'
            $call.Warnings.Count | Should -Be 1
            $call.Warnings[0] | Should -Match $streamLine
            $call.Lines | Should -Contain "next statement"
        }

        It "merges the one line under 3>&1 on a plain call" {
            $call = NativeDbccStatisticStreamCall -Script 'param($Target) Get-DbaDbccStatistic -SqlInstance $Target 3>&1; "next statement"'
            $call.Merged.Count | Should -Be 1
            $call.Merged[0] | Should -Match $streamLine
            $call.Warnings.Count | Should -Be 0
            $call.Lines | Should -Contain "next statement"
        }

        It "displays nothing under -EnableException, and -WarningVariable holds the one line" -Tag "NativeChecklist:enable-exception" {
            $call = NativeDbccStatisticStreamCall -Script 'param($Target) try { Get-DbaDbccStatistic -SqlInstance $Target -EnableException -WarningVariable held 3>&1 } catch { "caught " + $PSItem.FullyQualifiedErrorId }; "held " + @($held).Count; foreach ($line in $held) { "line " + $line }'
            $call.Merged.Count | Should -Be 0
            $call.Warnings.Count | Should -Be 0
            @($call.Lines | Where-Object { $PSItem -like "caught dbatools_Get-DbaDbccStatistic*" }).Count | Should -Be 1
            $call.Lines | Should -Contain "held 1"
            @($call.Lines | Where-Object { $PSItem -like "line *" -and $PSItem -match $streamLine }).Count | Should -Be 1
        }

        It "leaves the warning stream empty under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $call = NativeDbccStatisticStreamCall -Script 'param($Target) try { Get-DbaDbccStatistic -SqlInstance $Target -EnableException } catch { "caught " + $PSItem.FullyQualifiedErrorId }'
            $call.Warnings.Count | Should -Be 0
            @($call.Lines | Where-Object { $PSItem -like "caught dbatools_Get-DbaDbccStatistic*" }).Count | Should -Be 1
        }
    }

    Context "A null or empty -SqlInstance" {
        # named-null-element, piped-null: the command's own binder refuses it.
        It "refuses <Name> at the binder, with no warning and no output" -ForEach @(
            @{ Name = "a null element"; Value = @($null, "unused"); Id = "ParameterArgumentValidationErrorNullNotAllowed"; Reason = "is null" }
            @{ Name = "a null value"; Value = $null; Id = "ParameterArgumentValidationErrorNullNotAllowed"; Reason = "is null" }
            @{ Name = "an empty array"; Value = @(); Id = "ParameterArgumentValidationErrorEmptyArrayNotAllowed"; Reason = "is an empty array" }
        ) {
            $caught = $null
            $warnings = $null
            $collected = $null
            try {
                $null = Get-DbaDbccStatistic -SqlInstance $Value -OutVariable collected -WarningVariable warnings -WarningAction SilentlyContinue
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

Describe "Native Get-DbaDbccStatistic over SQL authentication" -Tag IntegrationTests {
    BeforeAll {
        $loginInstance = $TestConfig.InstanceSqlLogin
        $loginCred = $TestConfig.SqlLoginCred
        $random = Get-Random
        $dbA = "dbatoolsci_nstatl_a_$random"
        $dbB = "dbatoolsci_nstatl_b_$random"
        $dbNone = "dbatoolsci_nstatl_none_$random"
        $dbHome = "dbatoolsci_nstatl_home_$random"
        $allDatabases = @($dbA, $dbB, $dbNone, $dbHome)
        $lowName = "dbatoolsci_nstatl_low_$random"
        $lowPassword = "Nstat-$([guid]::NewGuid().ToString('N'))"
        $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)

        $fixture = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -NonPooledConnection -EnableException
        foreach ($name in $allDatabases) {
            $null = Invoke-NativeFixtureQuery $fixture ("CREATE DATABASE [$name];")
        }
        $null = Invoke-NativeFixtureQuery $fixture ("USE [master]; CREATE LOGIN [$lowName] WITH PASSWORD = '$lowPassword', CHECK_POLICY = OFF;")
        $null = Invoke-NativeFixtureQuery $fixture ("USE [$dbA]; CREATE TABLE [dbo].[T1] (id int NOT NULL CONSTRAINT [PK_T1] PRIMARY KEY); INSERT [dbo].[T1] (id) VALUES (1); CREATE TABLE [dbo].[T2] (a int NOT NULL); INSERT [dbo].[T2] (a) VALUES (1); CREATE STATISTICS [St1] ON [dbo].[T2] ([a]); CREATE USER [$lowName] FOR LOGIN [$lowName]; GRANT SELECT ON [dbo].[T2] TO [$lowName]; USE [master];")
        $null = Invoke-NativeFixtureQuery $fixture ("USE [$dbB]; CREATE TABLE [dbo].[T1] (id int NOT NULL CONSTRAINT [PK_T1B] PRIMARY KEY); INSERT [dbo].[T1] (id) VALUES (1); CREATE USER [$lowName] FOR LOGIN [$lowName]; USE [master];")
        $null = Invoke-NativeFixtureQuery $fixture ("USE [$dbHome]; CREATE USER [$lowName] FOR LOGIN [$lowName]; USE [master];")

        # A connection of the low login in its home database, with CONNECT then denied there. -ReadList reads the database list first.
        function New-NativeDenied {
            param([switch]$ReadList)
            $null = Invoke-NativeFixtureQuery $fixture ("USE [$dbHome]; GRANT CONNECT TO [$lowName]; USE [master];")
            $caller = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $lowCred -Database $dbHome -NonPooledConnection -EnableException
            $null = $caller.ConnectionContext.ExecuteScalar("SELECT 1;")
            if ($ReadList) {
                foreach ($database in $caller.Databases) {
                    $null = $database.Name
                }
            }
            $null = Invoke-NativeFixtureQuery $fixture ("USE [$dbHome]; DENY CONNECT TO [$lowName]; USE [master];")
            return $caller
        }
    }

    AfterAll {
        [Microsoft.Data.SqlClient.SqlConnection]::ClearAllPools()
        $null = Invoke-NativeFixtureQuery $fixture ("USE [master];")
        foreach ($row in @(Invoke-NativeFixtureQuery $fixture ("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$lowName';") | Where-Object { $null -ne $PSItem })) {
            $null = Invoke-NativeFixtureQuery $fixture ("KILL $($row.session_id);")
        }
        foreach ($name in $allDatabases) {
            $null = Invoke-NativeFixtureQuery $fixture ("IF DB_ID(N'$name') IS NOT NULL BEGIN ALTER DATABASE [$name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$name]; END;")
        }
        $null = Invoke-NativeFixtureQuery $fixture ("IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];")
        $fixture.ConnectionContext.Disconnect()
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        It "works with -SqlCredential" {
            $result = @(Get-DbaDbccStatistic -SqlInstance $loginInstance -SqlCredential $loginCred -Database $dbA -Object dbo.T2 -EnableException)
            $result.Count | Should -Be 1
            $result[0].Name | Should -BeExactly "St1"
        }

        It "fails cleanly without the credential: one warning line and no output" {
            $warnings = $null
            $result = Get-DbaDbccStatistic -SqlInstance $loginInstance -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match ("\[Get-DbaDbccStatistic\] Failure \| Error connecting to \[" + [regex]::Escape($loginInstance) + "\]: Login failed")
        }

        It "throws the connection failure under -EnableException" {
            { Get-DbaDbccStatistic -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue } | Should -Throw -ExpectedMessage "*Login failed*" -ErrorId "dbatools_Get-DbaDbccStatistic*"
        }
    }

    Context "A login with little access" {
        # low-no-user.
        It "reports a database it has no user in as not accessible" {
            $warnings = $null
            $result = @(Get-DbaDbccStatistic -SqlInstance $loginInstance -SqlCredential $lowCred -Database $dbNone -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 0
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -BeLike "*The database ``[$dbNone``] is not accessible. Skipping."
        }

        # low-no-permission, low-select-ee.
        It "warns of the server's refusal of a table it may not read, under -EnableException too" -Tag "NativeChecklist:enable-exception" {
            foreach ($splat in @{ }, @{ EnableException = $true }) {
                $warnings = $null
                $result = @(Get-DbaDbccStatistic -SqlInstance $loginInstance -SqlCredential $lowCred -Database $dbB -Object dbo.T1 -Target PK_T1B -WarningVariable warnings -WarningAction SilentlyContinue @splat)
                $result.Count | Should -Be 0
                @($warnings).Count | Should -Be 1
                "$($warnings[0])" | Should -BeLike "*``[Invoke-DbaQuery``] ``[*``] Failed during execution | The SELECT permission was denied on the object 'T1', database '$dbB', schema 'dbo'.*"
            }
        }

        # low-no-permission-list: the list shows it nothing.
        It "returns nothing and no warning for a database whose tables it cannot see" {
            $warnings = $null
            $result = @(Get-DbaDbccStatistic -SqlInstance $loginInstance -SqlCredential $lowCred -Database $dbB -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 0
            @($warnings).Count | Should -Be 0
        }

        # low-select.
        It "reads a table it may read" {
            $result = @(Get-DbaDbccStatistic -SqlInstance $loginInstance -SqlCredential $lowCred -Database $dbA -Object dbo.T2 -Target St1 -EnableException)
            $result.Count | Should -Be 1
            $result[0].Name | Should -BeExactly "St1"
        }
    }

    Context "A connection that cannot read the database list" {
        # denied-plain: the filter and the foreach each fault.
        It "outside any try, writes a record for each walk of the list with -Database" {
            $caller = New-NativeDenied
            try {
                $outside = Invoke-NativeOutsideTry @{ SqlInstance = $caller; Database = $dbB; Object = "dbo.T1"; Target = "PK_T1B" }
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Errors.Count | Should -Be 2
                foreach ($record in $outside.Errors) {
                    Assert-NativeEnumerationRecord -Record $record
                }
                $outside.Rows.Count | Should -Be 0
                $outside.Next | Should -BeTrue
            } finally {
                $caller.ConnectionContext.Disconnect()
            }
        }

        # denied-no-filter.
        It "outside any try, writes one record without -Database" {
            $caller = New-NativeDenied
            try {
                $outside = Invoke-NativeOutsideTry @{ SqlInstance = $caller }
                $outside.Errors.Count | Should -Be 1
                Assert-NativeEnumerationRecord -Record $outside.Errors[0]
                $outside.Rows.Count | Should -Be 0
                $outside.Next | Should -BeTrue
            } finally {
                $caller.ConnectionContext.Disconnect()
            }
        }

        # denied-ee: the pin writes both and goes on; an accepted difference, the keep-going section's point 3.
        It "outside any try, -EnableException ends the command at the first record" -Tag "NativeChecklist:enable-exception" {
            $caller = New-NativeDenied
            try {
                $outside = Invoke-NativeOutsideTry @{ SqlInstance = $caller; Database = $dbB; EnableException = $true }
                $outside.Errors.Count | Should -Be 1
                Assert-NativeEnumerationRecord -Record $outside.Errors[0]
                $outside.Next | Should -BeTrue
            } finally {
                $caller.ConnectionContext.Disconnect()
            }
        }

        # denied-try.
        It "inside a caller's try, the catch receives the record" {
            $caller = New-NativeDenied
            try {
                $failure = $null
                $after = $false
                try {
                    $null = Get-DbaDbccStatistic -SqlInstance $caller -Database $dbB
                    $after = $true
                } catch {
                    $failure = $PSItem
                }
                Assert-NativeEnumerationRecord -Record $failure
                $after | Should -BeFalse
            } finally {
                $caller.ConnectionContext.Disconnect()
            }
        }

        # denied-read-plain: the list was read first, and no list query runs.
        It "with the list read first, warns of the server's refusal with -Object and -Target" {
            $caller = New-NativeDenied -ReadList
            try {
                $warnings = $null
                $result = @(Get-DbaDbccStatistic -SqlInstance $caller -Database $dbB -Object dbo.T1 -Target PK_T1B -WarningVariable warnings -WarningAction SilentlyContinue)
                $result.Count | Should -Be 0
                @($warnings).Count | Should -Be 1 -Because ($warnings -join " / ")
                "$($warnings[0])" | Should -BeLike "*The SELECT permission was denied*"
            } finally {
                $caller.ConnectionContext.Disconnect()
            }
        }

        # denied-read-list, denied-read-ee: the list query runs and the way back to the home database is refused.
        It "with the list read first, warns that the context could not be restored, also under -EnableException" -Tag "NativeChecklist:enable-exception" {
            foreach ($splat in @{ }, @{ EnableException = $true }) {
                $caller = New-NativeDenied -ReadList
                try {
                    $warnings = $null
                    $result = @(Get-DbaDbccStatistic -SqlInstance $caller -Database $dbB -WarningVariable warnings -WarningAction SilentlyContinue @splat)
                    $result.Count | Should -Be 0
                    @($warnings).Count | Should -Be 1
                    "$($warnings[0])" | Should -BeExactly "The database context could not be restored to [$dbHome]: Exception calling `"ExecuteNonQuery`" with `"1`" argument(s): `"An exception occurred while executing a Transact-SQL statement or batch.`""
                } finally {
                    $caller.ConnectionContext.Disconnect()
                }
            }
        }
    }
}

Describe "Native Get-DbaDbccStatistic on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $azureDatabase = $TestConfig.AzureSqlDbName
        $azureTable = "dbatoolsci_nstat_$(Get-Random)"
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
        $azureFixture = Connect-DbaInstance @splatAzureConnection -NonPooledConnection
        $null = $azureFixture.ConnectionContext.ExecuteNonQuery("CREATE TABLE [dbo].[$azureTable] (a int NOT NULL); INSERT [dbo].[$azureTable] (a) VALUES (1), (2); CREATE STATISTICS [StAzure] ON [dbo].[$azureTable] ([a]);")
    }

    AfterAll {
        if ($azureFixture) {
            $null = $azureFixture.ConnectionContext.ExecuteNonQuery("IF OBJECT_ID(N'dbo.$azureTable') IS NOT NULL DROP TABLE [dbo].[$azureTable];")
            $azureFixture.ConnectionContext.Disconnect()
        }
    }

    # azure-connection-object, azure-shape-*: the instance name is null there.
    It "reads a statistic through -Object on a connection to the database, and leaves it there" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $warnings = $null
        $result = @(Get-DbaDbccStatistic -SqlInstance $azureServer -Object "dbo.$azureTable" -WarningVariable warnings -WarningAction SilentlyContinue)
        @($warnings).Count | Should -Be 0
        $result.Count | Should -Be 1
        $result[0].Name | Should -BeExactly "StAzure"
        $result[0].Database | Should -BeExactly $azureDatabase
        $result[0].ComputerName | Should -BeExactly $azureServer.ComputerName
        $result[0].SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
        $result[0].InstanceName | Should -BeNullOrEmpty
        $azureServer.ConnectionContext.CurrentDatabase | Should -BeExactly $azureDatabase
    }

    It "returns each -Option's rows with the pinned properties" -Tag "NativeChecklist:azure-sqldb" {
        $last = @{ StatHeader = "PersistedSamplePercent"; DensityVector = "Columns"; Histogram = "AverageRangeRows"; StatsStream = "DataPages" }
        foreach ($option in $last.Keys) {
            $warnings = $null
            $result = @(Get-DbaDbccStatistic -SqlInstance $azureServer -Object "dbo.$azureTable" -Target StAzure -Option $option -WarningVariable warnings -WarningAction SilentlyContinue)
            @($warnings).Count | Should -Be 0
            $result.Count | Should -BeGreaterThan 0
            @($result[0].PSObject.Properties.Name)[-1] | Should -BeExactly $last[$option]
        }
    }

    # azure-by-name, azure-by-name-database: on a connection by name master is read too.
    It "reads the database on a connection by name, and master without -Database" -Tag "NativeChecklist:azure-sqldb" {
        $splatByName = @{ SqlInstance = $TestConfig.AzureSqlDbServer; SqlCredential = $TestConfig.AzureSqlDbCred; WarningAction = "SilentlyContinue" }
        $warnings = $null
        $result = @(Get-DbaDbccStatistic @splatByName -Database $azureDatabase -Object "dbo.$azureTable" -Target StAzure -WarningVariable warnings)
        @($warnings).Count | Should -Be 0
        $result.Count | Should -Be 1
        $result[0].Database | Should -BeExactly $azureDatabase
        # Other lanes' tables come and go, so only the databases are asserted.
        $all = @(Get-DbaDbccStatistic @splatByName)
        @($all.Database) | Should -Contain "master"
        @($all.Database) | Should -Contain $azureDatabase
    }
}
