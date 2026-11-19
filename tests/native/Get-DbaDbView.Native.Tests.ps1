#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbView",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads views.

# Expected values below are as the pin measured on both editions: evidence/pin-view-20261104.txt. The case names in the comments are that file's.
# The two editions order the views of a database differently (vw*star), so names are compared sorted unless a test is about order. The accepted differences are in the corrections record.

BeforeAll {
    function Format-NativeViewNames {
        param($Views)
        $names = [string[]]@($Views | ForEach-Object { "$($PSItem.Schema).$($PSItem.Name)" })
        [array]::Sort($names, [System.StringComparer]::Ordinal)
        $names -join ","
    }

    # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
    function Invoke-NativeOutsideTry {
        param([hashtable]$Arguments, [object[]]$Values, [switch]$Piped)
        $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $outsideType = (Get-Command Get-DbaDbView -CommandType Cmdlet).ImplementingType
        $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaDbView", $outsideType, $null
        $outsideState.Commands.Add($outsideEntry)
        $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
        $outsideShell = [System.Management.Automation.PowerShell]::Create()
        $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
        $outsideStop = $null
        try {
            $outsideRunspace.Open()
            $outsideShell.Runspace = $outsideRunspace
            $null = $outsideShell.AddScript('param($Arguments, $Values, $Piped) if ($Piped) { $Values | Get-DbaDbView @Arguments } else { Get-DbaDbView @Arguments }; "next statement"').AddArgument($Arguments).AddArgument($Values).AddArgument([bool]$Piped)
            try {
                $null = $outsideShell.Invoke($null, $outsideOutput)
            } catch {
                # The stop leaves the runspace's script through Invoke, as a method call's exception.
                $outsideStop = $PSItem.Exception.InnerException
            }
            [pscustomobject]@{
                Output   = @($outsideOutput)
                Rows     = @($outsideOutput | Where-Object { $PSItem -isnot [string] })
                Errors   = @($outsideShell.Streams.Error)
                Warnings = @($outsideShell.Streams.Warning | ForEach-Object { $PSItem.Message })
                Stop     = $outsideStop
            }
        } finally {
            $outsideShell.Dispose()
            $outsideRunspace.Dispose()
        }
    }

    function Read-NativeVerboseLines {
        param([hashtable]$Arguments)
        @(Get-DbaDbView @Arguments -Verbose 4>&1 | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message })
    }

    function Assert-NativeEnumerationRecord {
        param($Record, [string]$InnerMessage)
        $Record.FullyQualifiedErrorId | Should -BeLike "ExceptionInGetEnumerator,*"
        "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
        $Record.CategoryInfo.Reason | Should -BeExactly "ExtendedTypeSystemException"
        $Record.TargetObject | Should -BeNullOrEmpty
        $Record.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.ExtendedTypeSystemException"
        $Record.Exception.Message | Should -BeExactly 'The following exception occurred while trying to enumerate the collection: "An exception occurred while executing a Transact-SQL statement or batch.".'
        $Record.Exception.InnerException.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Common.ExecutionFailureException"
        $Record.Exception.InnerException.InnerException.GetType().Name | Should -BeExactly "SqlException"
        $Record.Exception.InnerException.InnerException.Message | Should -BeLike $InnerMessage
    }
}

Describe "Native Get-DbaDbView" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $stamp = Get-Random
        $dbA = "dbatoolsci_ndv_a_$stamp"
        $dbB = "dbatoolsci_ndv_b_$stamp"
        $dbOff = "dbatoolsci_ndv_off_$stamp"
        $dbCase = "dbatoolsci_ndv_cs_$stamp"
        $allDatabases = @($dbA, $dbB, $dbOff, $dbCase)
        $missingInstance = "nativedbview$(Get-Random)"
        $allViewsA = "dbo.vw*star,dbo.vw.dot,dbo.vw_one,dbo.vw_two,other.vw_one"
        $offlineText = "*Database '$dbOff' cannot be opened because it is offline."

        # The reader of the independent values and the fixture's own connection; never given to the command unless a test says so.
        $server = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
        $null = $server.Query("CREATE DATABASE [$dbA]; CREATE DATABASE [$dbB]; CREATE DATABASE [$dbOff];")
        $null = $server.Query("CREATE DATABASE [$dbCase] COLLATE Latin1_General_CS_AS;")
        $null = $server.Query("USE [$dbA]; EXEC('CREATE SCHEMA [other]'); EXEC('CREATE VIEW [dbo].[vw_one] AS SELECT 1 AS col1'); EXEC('CREATE VIEW [other].[vw_one] AS SELECT 2 AS col1'); EXEC('CREATE VIEW [dbo].[vw_two] AS SELECT 3 AS col1'); EXEC('CREATE VIEW [dbo].[vw*star] AS SELECT 4 AS col1'); EXEC('CREATE VIEW [dbo].[vw.dot] AS SELECT 5 AS col1'); USE [master];")
        $null = $server.Query("USE [$dbB]; EXEC('CREATE VIEW [dbo].[vw_one] AS SELECT 1 AS col1'); USE [master];")
        $null = $server.Query("USE [$dbCase]; EXEC('CREATE VIEW [dbo].[VwCase] AS SELECT 1 AS col1'); EXEC('CREATE VIEW [dbo].[vwcase] AS SELECT 2 AS col1'); USE [master];")
        $null = $server.Query("ALTER DATABASE [$dbOff] SET OFFLINE WITH ROLLBACK IMMEDIATE;")

        # Database objects for -InputObject, on a connection of their own.
        $objects = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
        $objectA = $objects.Databases[$dbA]
        $objectB = $objects.Databases[$dbB]
        $objectOff = $objects.Databases[$dbOff]
    }

    AfterAll {
        $objects.ConnectionContext.Disconnect()
        $null = $server.Query("USE [master];")
        foreach ($name in $allDatabases) {
            $null = $server.Query("IF DB_ID(N'$name') IS NOT NULL BEGIN ALTER DATABASE [$name] SET ONLINE; ALTER DATABASE [$name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$name]; END;")
        }
        $server.ConnectionContext.Disconnect()
    }

    Context "Output" {
        # shape
        It "returns the SMO view, with the pinned notes, view and values" {
            $result = @(Get-DbaDbView -SqlInstance $instance -Database $dbA -View vw_two -EnableException)
            $result.Count | Should -Be 1
            $result[0].PSObject.BaseObject.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Smo.View"
            $result[0].PSObject.TypeNames[0] | Should -BeExactly "Microsoft.SqlServer.Management.Smo.View"
            @($result[0].PSObject.Properties | Where-Object MemberType -eq NoteProperty | ForEach-Object { $PSItem.Name }) | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance", "Database")
            $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "CreateDate", "DateLastModified", "Name")
            $result[0].ComputerName | Should -BeExactly $server.ComputerName
            $result[0].InstanceName | Should -BeExactly $server.ServiceName
            $result[0].SqlInstance | Should -BeExactly $server.DomainInstanceName
            $result[0].Database | Should -BeExactly $dbA
            $result[0].Schema | Should -BeExactly "dbo"
            $result[0].Name | Should -BeExactly "vw_two"
            $result[0].IsSystemObject | Should -BeFalse
            $result[0].CreateDate | Should -BeOfType [datetime]
            $result[0].DateLastModified | Should -BeOfType [datetime]
        }

        # shape; the three notes the shared selection helper gives the parent, an accepted difference from the pin's eight.
        It "gives the parent database its instance notes when it selects the database" {
            $result = @(Get-DbaDbView -SqlInstance $instance -Database $dbA -View vw_two -EnableException)
            $result[0].Parent.Name | Should -BeExactly $dbA
            $result[0].Parent.ComputerName | Should -BeExactly $server.ComputerName
            $result[0].Parent.SqlInstance | Should -BeExactly $server.DomainInstanceName
        }

        # shape
        It "keeps four notes on a second call over the same connection" {
            $null = Get-DbaDbView -SqlInstance $objects -Database $dbA -View vw_two -EnableException
            $result = @(Get-DbaDbView -SqlInstance $objects -Database $dbA -View vw_two -EnableException)
            @($result[0].PSObject.Properties | Where-Object MemberType -eq NoteProperty).Count | Should -Be 4
        }

        # named-one-database: the system views come too.
        It "reads every view of a database, the system views included" {
            $engine = @($server.Query("SELECT s.name + N'.' + v.name AS shown FROM [$dbA].sys.views AS v INNER JOIN [$dbA].sys.schemas AS s ON s.schema_id = v.schema_id;") | ForEach-Object { $PSItem.shown })
            $result = @(Get-DbaDbView -SqlInstance $instance -Database $dbA -EnableException)
            $user = @($result | Where-Object { -not $PSItem.IsSystemObject })
            Format-NativeViewNames -Views $user | Should -BeExactly $allViewsA
            @($result | Where-Object { $PSItem.IsSystemObject }).Count | Should -BeGreaterThan 100
            foreach ($shown in $engine) {
                @($user | Where-Object { "$($PSItem.Schema).$($PSItem.Name)" -ceq $shown }).Count | Should -Be 1
            }
        }

        # case-sensitive-database, case-sensitive-any-case
        It "reads both views whose names differ only in case, and -View matches them in any case" {
            Format-NativeViewNames -Views @(Get-DbaDbView -SqlInstance $instance -Database $dbCase -ExcludeSystemView -EnableException) | Should -BeExactly "dbo.VwCase,dbo.vwcase"
            Format-NativeViewNames -Views @(Get-DbaDbView -SqlInstance $instance -Database $dbCase -View VWCASE -EnableException) | Should -BeExactly "dbo.VwCase,dbo.vwcase"
        }
    }

    Context "System views" {
        # exclude-system
        It "drops the system views with -ExcludeSystemView" {
            Format-NativeViewNames -Views @(Get-DbaDbView -SqlInstance $instance -Database $dbA -ExcludeSystemView -EnableException) | Should -BeExactly $allViewsA
        }

        # Correction exclude-system-false: exclude-system-false drops them on the pin, whose Test-Bound reads the switch set to false as the switch.
        It "keeps the system views when -ExcludeSystemView is set to false" -Tag "NativeChecklist:switch-false" {
            $result = @(Get-DbaDbView -SqlInstance $instance -Database $dbA -ExcludeSystemView:$false -EnableException)
            @($result | Where-Object { $PSItem.IsSystemObject }).Count | Should -BeGreaterThan 100
            Format-NativeViewNames -Views @($result | Where-Object { -not $PSItem.IsSystemObject }) | Should -BeExactly $allViewsA
        }

        # named-system, exclude-system-named-system
        It "reads a system view by name, and -ExcludeSystemView drops it" {
            $named = @(Get-DbaDbView -SqlInstance $instance -Database master -View sys.objects -EnableException)
            $named.Count | Should -Be 1
            $named[0].IsSystemObject | Should -BeTrue
            @(Get-DbaDbView -SqlInstance $instance -Database master -View sys.objects -ExcludeSystemView -EnableException).Count | Should -Be 0
        }
    }

    Context "View and schema filters" {
        It "reads <Name>" -ForEach @(
            @{ Name = "one schema (schema-one)"; Extra = @{ Schema = "other" }; Expected = "other.vw_one" }
            @{ Name = "a schema in any case (schema-any-case)"; Extra = @{ Schema = "OTHER" }; Expected = "other.vw_one" }
            @{ Name = "no view for a schema wildcard (schema-wildcard)"; Extra = @{ Schema = "oth*" }; Expected = "" }
            @{ Name = "no view for an absent schema (schema-absent)"; Extra = @{ Schema = "absent" }; Expected = "" }
            @{ Name = "every view for an empty schema name (schema-empty-string)"; Extra = @{ Schema = ""; ExcludeSystemView = $true }; Expected = "dbo.vw*star,dbo.vw.dot,dbo.vw_one,dbo.vw_two,other.vw_one" }
            @{ Name = "every view for an empty schema array (schema-empty-array)"; Extra = @{ Schema = @(); ExcludeSystemView = $true }; Expected = "dbo.vw*star,dbo.vw.dot,dbo.vw_one,dbo.vw_two,other.vw_one" }
            @{ Name = "every view for a null schema (schema-null)"; Extra = @{ Schema = $null; ExcludeSystemView = $true }; Expected = "dbo.vw*star,dbo.vw.dot,dbo.vw_one,dbo.vw_two,other.vw_one" }
            @{ Name = "the schema beside a null element (schema-null-and-name)"; Extra = @{ Schema = @($null, "other"); ExcludeSystemView = $true }; Expected = "other.vw_one" }
            @{ Name = "the views of -View in -Schema (schema-and-view)"; Extra = @{ Schema = "other"; View = "vw_one", "vw_two" }; Expected = "other.vw_one" }
            @{ Name = "none when -Schema refuses the schema of -View (schema-against-view-schema)"; Extra = @{ Schema = "other"; View = "dbo.vw_one" }; Expected = "" }
            @{ Name = "a view by name (view-name)"; Extra = @{ View = "vw_two" }; Expected = "dbo.vw_two" }
            @{ Name = "the same name in two schemas (view-same-name-two-schemas)"; Extra = @{ View = "vw_one" }; Expected = "dbo.vw_one,other.vw_one" }
            @{ Name = "a view by schema and name (view-schema-name)"; Extra = @{ View = "other.vw_one" }; Expected = "other.vw_one" }
            @{ Name = "bracketed parts (view-brackets)"; Extra = @{ View = "[other].[vw_one]" }; Expected = "other.vw_one" }
            @{ Name = "a dot inside brackets (view-bracket-dot)"; Extra = @{ View = "[dbo].[vw.dot]" }; Expected = "dbo.vw.dot" }
            @{ Name = "no view for a bare dot, which splits (view-bare-dot)"; Extra = @{ View = "vw.dot" }; Expected = "" }
            @{ Name = "a view in any case (view-any-case)"; Extra = @{ View = "VW_TWO" }; Expected = "dbo.vw_two" }
            @{ Name = "no view for a wildcard (view-wildcard)"; Extra = @{ View = "vw_*" }; Expected = "" }
            @{ Name = "a literal star (view-literal-star)"; Extra = @{ View = "vw*star" }; Expected = "dbo.vw*star" }
            @{ Name = "no view for an absent name (view-absent)"; Extra = @{ View = "absent" }; Expected = "" }
            @{ Name = "no view for an unclosed bracket, which parses (view-bad-unclosed)"; Extra = @{ View = "[unclosed" }; Expected = "" }
            @{ Name = "every view for an empty name (view-empty-string)"; Extra = @{ View = ""; ExcludeSystemView = $true }; Expected = "dbo.vw*star,dbo.vw.dot,dbo.vw_one,dbo.vw_two,other.vw_one" }
            @{ Name = "every view for an empty array (view-empty-array)"; Extra = @{ View = @(); ExcludeSystemView = $true }; Expected = "dbo.vw*star,dbo.vw.dot,dbo.vw_one,dbo.vw_two,other.vw_one" }
            @{ Name = "every view for a null (view-null)"; Extra = @{ View = $null; ExcludeSystemView = $true }; Expected = "dbo.vw*star,dbo.vw.dot,dbo.vw_one,dbo.vw_two,other.vw_one" }
        ) {
            $warnings = $null
            $result = @(Get-DbaDbView -SqlInstance $instance -Database $dbA @Extra -WarningVariable warnings -EnableException)
            Format-NativeViewNames -Views $result | Should -BeExactly $Expected
            @($warnings).Count | Should -Be 0
        }

        # view-twice, view-and-schema-form, view-order-given: in the order given, each name adding its own.
        It "reads the names in the order given, a repeated name twice: <Name>" -ForEach @(
            @{ Name = "the same name"; Views = @("vw_two", "vw_two"); Expected = "dbo.vw_two,dbo.vw_two" }
            @{ Name = "two forms of one name"; Views = @("vw_two", "dbo.vw_two"); Expected = "dbo.vw_two,dbo.vw_two" }
            @{ Name = "two names"; Views = @("vw_two", "other.vw_one"); Expected = "dbo.vw_two,other.vw_one" }
            @{ Name = "two names reversed"; Views = @("other.vw_one", "vw_two"); Expected = "other.vw_one,dbo.vw_two" }
        ) {
            $result = @(Get-DbaDbView -SqlInstance $instance -Database $dbA -View $Views -EnableException)
            (@($result | ForEach-Object { "$($PSItem.Schema).$($PSItem.Name)" }) -join ",") | Should -BeExactly $Expected
        }

        # view-three-part, view-three-part-any-case, view-two-dots, view-three-part-other-database
        It "reads a three-part name only in its database" {
            $scan = @(Get-DbaDbView -SqlInstance $instance -Database $dbB, $dbA -View "$dbA.other.vw_one" -EnableException)
            ($scan.Database -join ",") | Should -BeExactly $dbA
            Format-NativeViewNames -Views $scan | Should -BeExactly "other.vw_one"
            Format-NativeViewNames -Views @(Get-DbaDbView -SqlInstance $instance -Database $dbA -View "$($dbA.ToUpperInvariant()).OTHER.VW_ONE" -EnableException) | Should -BeExactly "other.vw_one"
            Format-NativeViewNames -Views @(Get-DbaDbView -SqlInstance $instance -Database $dbA -View "$dbA..vw_one" -EnableException) | Should -BeExactly "dbo.vw_one,other.vw_one"
            @(Get-DbaDbView -SqlInstance $instance -Database $dbB -View "$dbA.dbo.vw_one" -EnableException).Count | Should -Be 0
        }

        It "writes the pinned verbose lines for a name it cannot find" {
            $on = $server.DomainInstanceName
            $verbose = Read-NativeVerboseLines @{ SqlInstance = $instance; Database = $dbA; View = "absent"; EnableException = $true }
            @($verbose | Where-Object { $PSItem.EndsWith("processing [$dbA]", [System.StringComparison]::Ordinal) }).Count | Should -Be 1
            @($verbose | Where-Object { $PSItem.EndsWith("Could not find view absent in [$dbA] on $on", [System.StringComparison]::Ordinal) }).Count | Should -Be 1
            @($verbose | Where-Object { $PSItem.EndsWith("No views exist in the [$dbA] database on $on", [System.StringComparison]::Ordinal) }).Count | Should -Be 1
        }

        # view-three-part-other-database: the name is skipped before the search, so only the last line is written.
        It "writes only the no-views line for a three-part name in another database" {
            $verbose = Read-NativeVerboseLines @{ SqlInstance = $instance; Database = $dbB; View = "$dbA.dbo.vw_one"; EnableException = $true }
            @($verbose | Where-Object { $PSItem -like "*Could not find view*" }).Count | Should -Be 0
            @($verbose | Where-Object { $PSItem -like "*No views exist in the ``[$dbB``] database on *" }).Count | Should -Be 1
        }

        It "writes no no-views line for a database read whole" {
            $verbose = Read-NativeVerboseLines @{ SqlInstance = $instance; Database = $dbB; Schema = "absent"; EnableException = $true }
            @($verbose | Where-Object { $PSItem -like "*No views exist*" }).Count | Should -Be 0
        }
    }

    Context "A name that does not parse" {
        BeforeAll {
            $parseLine = "[Get-DbaDbView] Please check you are using proper three-part names. If your search value contains special characters you must use [ ] to wrap the name. The value  could not be parsed as a valid name."
        }

        # view-bad-four-parts
        It "warns, then says no valid view was given, and reads nothing" {
            $warnings = $null
            $result = @(Get-DbaDbView -SqlInstance $instance -Database $dbA -View "a.b.c.d" -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 0
            @($warnings).Count | Should -Be 2
            "$($warnings[0])".EndsWith($parseLine, [System.StringComparison]::Ordinal) | Should -BeTrue
            "$($warnings[1])".EndsWith("[Get-DbaDbView] No Valid View specified", [System.StringComparison]::Ordinal) | Should -BeTrue
        }

        # view-bad-piped-twice
        It "warns once for every piped instance" {
            $warnings = $null
            $result = @($instance, $instance | Get-DbaDbView -Database $dbA -View "a.b.c.d" -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 0
            @($warnings).Count | Should -Be 2
        }

        # view-bad-and-good, view-null-and-name
        It "warns and goes on with the names that parse: <Name>" -ForEach @(
            @{ Name = "four parts"; Views = @("a.b.c.d", "vw_two") }
            @{ Name = "a null element"; Views = @($null, "vw_two") }
        ) {
            $warnings = $null
            $result = @(Get-DbaDbView -SqlInstance $instance -Database $dbA -View $Views -WarningVariable warnings -WarningAction SilentlyContinue)
            Format-NativeViewNames -Views $result | Should -BeExactly "dbo.vw_two"
            @($warnings).Count | Should -Be 1
            "$($warnings[0])".EndsWith($parseLine, [System.StringComparison]::Ordinal) | Should -BeTrue
        }

        # view-bad-ee, view-bad-ee-try
        It "throws under -EnableException, and the parse warning still shows" -Tag "NativeChecklist:enable-exception" {
            $record = $null
            $warnings = $null
            try {
                $null = Get-DbaDbView -SqlInstance $instance -Database $dbA -View "a.b.c.d" -EnableException -WarningVariable warnings -WarningAction SilentlyContinue
            } catch {
                $record = $PSItem
            }
            $record.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbView*"
            "$($record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
            $record.TargetObject | Should -BeNullOrEmpty
            $record.Exception.Message | Should -BeExactly "No Valid View specified"
            "$($warnings[0])".EndsWith($parseLine, [System.StringComparison]::Ordinal) | Should -BeTrue
        }
    }

    Context "Database filters" {
        # two-databases-reversed
        It "reads the named databases in the order of the rows, not the order given" {
            $result = @(Get-DbaDbView -SqlInstance $instance -Database $dbB, $dbA -View dbo.vw_one -EnableException)
            ($result.Database -join ",") | Should -BeExactly "$dbA,$dbB"
        }

        # instance-wide. The pin selects from the rows of sys.databases; SMO's own collection is sorted, which would put model before tempdb. Offline databases write a record here.
        It "reads an instance-wide call in the order of the rows of sys.databases" {
            $rows = @($server.Query("SELECT name, state, SUSER_SNAME(owner_sid) AS [Owner], is_cdc_enabled FROM sys.databases") | ForEach-Object { $PSItem.name })
            $outside = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = $instance; View = "sys.objects" }
            $shown = @($outside.Rows | ForEach-Object { $PSItem.Database })
            $shown | Should -Contain $dbA
            $shown | Should -Not -Contain $dbOff
            ($shown -join ",") | Should -BeExactly (@($rows | Where-Object { $PSItem -in $shown }) -join ",")
            [array]::IndexOf($shown, "tempdb") | Should -BeLessThan ([array]::IndexOf($shown, "model"))
        }

        # wildcard-database: the help documents no wildcard here.
        It "reads nothing for a wildcard in -Database" {
            @(Get-DbaDbView -SqlInstance $instance -Database "dbatoolsci_ndv_?_$stamp" -View dbo.vw_one -EnableException).Count | Should -Be 0
        }

        # wildcard-exclude-database
        It "keeps a wildcard in -ExcludeDatabase literal, so it excludes nothing" {
            $result = @(Get-DbaDbView -SqlInstance $instance -Database $dbA, $dbB -ExcludeDatabase "dbatoolsci_ndv_b*" -View dbo.vw_one -EnableException)
            ($result.Database -join ",") | Should -BeExactly "$dbA,$dbB"
        }

        # database-any-case, database-absent, database-null-element, database-and-exclude
        It "reads a database named in any case" {
            $result = @(Get-DbaDbView -SqlInstance $instance -Database $dbB.ToUpperInvariant() -View dbo.vw_one -EnableException)
            ($result.Database -join ",") | Should -BeExactly $dbB
        }

        It "reads nothing for an absent database, with no warning" {
            $warnings = $null
            $result = @(Get-DbaDbView -SqlInstance $instance -Database "dbatoolsci_ndv_absent_$stamp" -WarningVariable warnings -EnableException)
            $result.Count | Should -Be 0
            @($warnings).Count | Should -Be 0
        }

        It "reads the name beside a null element" {
            $result = @(Get-DbaDbView -SqlInstance $instance -Database @($null, $dbB) -View dbo.vw_one -EnableException)
            ($result.Database -join ",") | Should -BeExactly $dbB
        }

        It "excludes a database named in any case" {
            $result = @(Get-DbaDbView -SqlInstance $instance -Database $dbA, $dbB -ExcludeDatabase $dbB.ToUpperInvariant() -View dbo.vw_one -EnableException)
            ($result.Database -join ",") | Should -BeExactly $dbA
        }

        # database-empty-string, exclude-empty-string: every database, the offline one's fault included.
        It "reads every database for an empty name: <Name>" -ForEach @(
            @{ Name = "-Database"; Extra = @{ Database = "" } }
            @{ Name = "-ExcludeDatabase"; Extra = @{ ExcludeDatabase = "" } }
        ) {
            $outside = Invoke-NativeOutsideTry -Arguments (@{ SqlInstance = $instance; View = "vw_two" } + $Extra)
            ($outside.Rows.Database -join ",") | Should -BeExactly $dbA
            @($outside.Warnings | Where-Object { $PSItem -like "*Database ``[$dbOff``] is not accessible. Skipping" }).Count | Should -Be 1
        }
    }

    Context "An offline database" {
        # offline-plain, offline-schema: the accessibility check comes before the statements that enumerate.
        It "warns and goes on, with no record: <Name>" -ForEach @(
            @{ Name = "-ExcludeSystemView"; Extra = @{ ExcludeSystemView = $true } }
            @{ Name = "-Schema"; Extra = @{ Schema = "dbo" } }
        ) {
            $outside = Invoke-NativeOutsideTry -Arguments (@{ SqlInstance = $instance; Database = @($dbOff, $dbB) } + $Extra)
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 0
            $outside.Warnings.Count | Should -Be 1
            $outside.Warnings[0] | Should -BeLike "*Get-DbaDbView*Database ``[$dbOff``] is not accessible. Skipping"
            Format-NativeViewNames -Views $outside.Rows | Should -BeExactly "dbo.vw_one"
        }

        # offline-view: the name's search enumerates first, so it writes the record and then the warning.
        It "with -View writes the record, warns and goes on" {
            $outside = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = $instance; Database = @($dbOff, $dbB); View = "vw_one" }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeEnumerationRecord -Record $outside.Errors[0] -InnerMessage $offlineText
            $outside.Warnings.Count | Should -Be 1
            @($outside.Rows.Database) | Should -BeExactly @($dbB)
            $outside.Output[-1] | Should -BeExactly "next statement"
        }

        # Accepted difference, keep-going: offline-ee goes on where the port stops. The rows come first, so the database before it was read.
        It "with -View, -EnableException ends the command at the record and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = $instance; Database = @($dbOff, $dbB); View = "vw_one"; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeEnumerationRecord -Record $outside.Errors[0] -InnerMessage $offlineText
            @($outside.Rows.Database) | Should -BeExactly @($dbB)
            $outside.Output[-1] | Should -BeExactly "next statement"
        }

        # offline-stop: the rows of the database before it, then the stop PowerShell gives WriteError (accepted difference, keep-going).
        It "with -View, -ErrorAction Stop turns the record into the stop" {
            $outside = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = $instance; Database = @($dbOff, $dbB); View = "vw_one"; ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeEnumerationRecord -Record $outside.Stop.ErrorRecord -InnerMessage $offlineText
            @($outside.Output | Where-Object { $PSItem -is [string] }).Count | Should -Be 0
        }

        # offline-try, offline-ee-try
        It "with -View, the caller's catch receives the record: <Name>" -ForEach @(
            @{ Name = "plain"; Extra = @{ } }
            @{ Name = "-EnableException"; Extra = @{ EnableException = $true } }
        ) {
            $streamed = New-Object System.Collections.ArrayList
            $failure = $null
            $after = $false
            try {
                Get-DbaDbView -SqlInstance $instance -Database $dbOff, $dbB -View vw_one @Extra | ForEach-Object { $null = $streamed.Add($PSItem) }
                $after = $true
            } catch {
                $failure = $PSItem
            }
            Assert-NativeEnumerationRecord -Record $failure -InnerMessage $offlineText
            $after | Should -BeFalse
            @($streamed | ForEach-Object { $PSItem.Database }) | Should -BeExactly @($dbB)
        }

        # input-offline
        It "piped first, writes the record and the warning and goes on to the next object" {
            $outside = Invoke-NativeOutsideTry -Arguments @{ View = "vw_one" } -Values @($objectOff, $objectB) -Piped
            $outside.Errors.Count | Should -Be 1
            Assert-NativeEnumerationRecord -Record $outside.Errors[0] -InnerMessage $offlineText
            $outside.Warnings.Count | Should -Be 1
            @($outside.Rows.Database) | Should -BeExactly @($dbB)
        }
    }

    Context "Input" {
        # no-parameters, view-only: -SqlInstance is not mandatory here.
        It "reads nothing, with no message, when given nothing to read" {
            $warnings = $null
            @(Get-DbaDbView -WarningVariable warnings -EnableException).Count | Should -Be 0
            @(Get-DbaDbView -View vw_one -WarningVariable warnings -EnableException).Count | Should -Be 0
            @($warnings).Count | Should -Be 0
        }

        # piped-instance-twice
        It "reads each piped instance" -Tag "NativeChecklist:pipeline-multiple" {
            $results = @($instance, $instance | Get-DbaDbView -Database $dbB -View dbo.vw_one -EnableException)
            $results.Count | Should -Be 2
            $results[0].SqlInstance | Should -BeExactly $server.DomainInstanceName
            $results[1].SqlInstance | Should -BeExactly $server.DomainInstanceName
        }

        # named-instance-twice
        It "reads each instance of an array" {
            @(Get-DbaDbView -SqlInstance $instance, $instance -Database $dbB -View dbo.vw_one -EnableException).Count | Should -Be 2
        }

        # server-piped
        It "reads through a piped server object" {
            $result = @($objects | Get-DbaDbView -Database $dbB -View dbo.vw_one -EnableException)
            $result.Count | Should -Be 1
            $result[0].Database | Should -BeExactly $dbB
        }

        # input-piped-one, input-piped-two: in the order piped.
        It "reads piped database objects in the order piped" {
            $result = @($objectB, $objectA | Get-DbaDbView -View dbo.vw_one -EnableException)
            ($result.Database -join ",") | Should -BeExactly "$dbB,$dbA"
            $result[0].SqlInstance | Should -BeExactly $server.DomainInstanceName
        }

        # input-named
        It "reads named database objects" {
            $result = @(Get-DbaDbView -InputObject $objectB, $objectA -View vw_two -EnableException)
            ($result.Database -join ",") | Should -BeExactly $dbA
        }

        # input-null, input-empty
        It "reads nothing for <Name>" -ForEach @(
            @{ Name = "a null"; Value = $null }
            @{ Name = "an empty array"; Value = @() }
        ) {
            $warnings = $null
            @(Get-DbaDbView -InputObject $Value -WarningVariable warnings -EnableException).Count | Should -Be 0
            @($warnings).Count | Should -Be 0
        }

        # input-null-element, input-null-element-view
        It "warns of a null element as a database with no name, and writes the pinned verbose lines" {
            $warnings = $null
            $result = @(Get-DbaDbView -InputObject @($null) -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 0
            @($warnings).Count | Should -Be 1
            "$($warnings[0])".EndsWith("[Get-DbaDbView] Database  is not accessible. Skipping", [System.StringComparison]::Ordinal) | Should -BeTrue
            $verbose = Read-NativeVerboseLines @{ InputObject = @($null); View = "vw_one"; WarningAction = "SilentlyContinue" }
            @($verbose | Where-Object { $PSItem.EndsWith("ClearAndInitialize failed: You cannot call a method on a null-valued expression.", [System.StringComparison]::Ordinal) }).Count | Should -Be 1
            @($verbose | Where-Object { $PSItem.EndsWith("Could not find view vw_one in  on ", [System.StringComparison]::Ordinal) }).Count | Should -Be 1
        }

        # input-null-then-database
        It "goes on past a null element" {
            $warnings = $null
            $result = @(Get-DbaDbView -InputObject @($null, $objectB) -View dbo.vw_one -WarningVariable warnings -WarningAction SilentlyContinue)
            ($result.Database -join ",") | Should -BeExactly $dbB
            @($warnings).Count | Should -Be 1
        }

        # input-ignores-database, input-and-instance
        It "ignores the database filters for piped objects, and -InputObject when -SqlInstance is given" {
            $piped = @($objectB | Get-DbaDbView -Database $dbA -ExcludeDatabase $dbB -View dbo.vw_one -EnableException)
            ($piped.Database -join ",") | Should -BeExactly $dbB
            $named = @(Get-DbaDbView -SqlInstance $instance -Database $dbA -InputObject $objectB -View dbo.vw_one -EnableException)
            ($named.Database -join ",") | Should -BeExactly $dbA
        }

        # input-then-instance-piped
        It "reads a piped object, then a piped instance" {
            $outside = Invoke-NativeOutsideTry -Arguments @{ Database = $dbA; View = "dbo.vw_one" } -Values @($objectB, $instance) -Piped
            $outside.Errors.Count | Should -Be 0
            ($outside.Rows.Database -join ",") | Should -BeExactly "$dbB,$dbA"
        }

        # instance-then-input-piped: Test-Bound stays true on the second record, whose -SqlInstance is null.
        It "reads a piped instance, then writes the nested binder's record and reads the piped object" {
            $outside = Invoke-NativeOutsideTry -Arguments @{ Database = $dbA; View = "dbo.vw_one" } -Values @($instance, $objectB) -Piped
            $outside.Errors.Count | Should -Be 1
            $outside.Errors[0].FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
            ($outside.Rows.Database -join ",") | Should -BeExactly "$dbA,$dbB"
        }
    }

    Context "A null or empty -SqlInstance, which reaches the nested Get-DbaDatabase's binder" {
        BeforeAll {
            function Assert-NativeBinderRecord {
                param($Record, [string]$Id, [string]$Reason, [string]$Activity)
                $Record.FullyQualifiedErrorId | Should -BeLike "$Id,*"
                "$($Record.CategoryInfo.Category)" | Should -BeExactly "InvalidData"
                $Record.CategoryInfo.Reason | Should -BeExactly "ParameterBindingValidationException"
                $Record.CategoryInfo.Activity | Should -BeExactly $Activity
                $Record.TargetObject | Should -BeNullOrEmpty
                $Record.Exception | Should -BeOfType System.Management.Automation.ParameterBindingException
                $Record.Exception.Message | Should -BeExactly "Cannot bind argument to parameter 'SqlInstance' because it $Reason."
            }
        }

        # instance-null-plain, instance-empty-plain, instance-null-element-plain
        It "a plain call writes the record, reads nothing and goes on: <Name>" -ForEach @(
            @{ Name = "a null"; Value = $null; Id = "ParameterArgumentValidationErrorNullNotAllowed"; Reason = "is null" }
            @{ Name = "an empty array"; Value = @(); Id = "ParameterArgumentValidationErrorEmptyArrayNotAllowed"; Reason = "is an empty array" }
            @{ Name = "a null element"; Value = @("unused", $null); Id = "ParameterArgumentValidationErrorNullNotAllowed"; Reason = "is null" }
        ) {
            $outside = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = $Value }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeBinderRecord -Record $outside.Errors[0] -Id $Id -Reason $Reason -Activity "Get-DbaDatabase"
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        # pipe-null, pipe-null-then-instance
        It "a piped null writes the record, and the next record reads its instance" {
            $outside = Invoke-NativeOutsideTry -Arguments @{ Database = $dbB; View = "dbo.vw_one" } -Values @($null, $instance) -Piped
            $outside.Errors.Count | Should -Be 1
            Assert-NativeBinderRecord -Record $outside.Errors[0] -Id "ParameterArgumentValidationErrorNullNotAllowed" -Reason "is null" -Activity "Get-DbaDatabase"
            ($outside.Rows.Database -join ",") | Should -BeExactly $dbB
        }

        # Accepted difference, keep-going: instance-null-ee goes on where the port stops.
        It "-EnableException ends the command at the record and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = $null; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeBinderRecord -Record $outside.Errors[0] -Id "ParameterArgumentValidationErrorNullNotAllowed" -Reason "is null" -Activity "Get-DbaDatabase"
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        # Accepted difference, keep-going: instance-null-stop ends the function's statement only.
        It "-ErrorAction Stop turns the record into the stop PowerShell gives WriteError" {
            $outside = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = $null; ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeBinderRecord -Record $outside.Stop.ErrorRecord -Id "ParameterArgumentValidationErrorNullNotAllowed" -Reason "is null" -Activity "Get-DbaDbView"
            $outside.Output.Count | Should -Be 0
        }

        # instance-null-try, instance-null-ee-try, instance-null-stop-try
        It "the catch receives the record: <Name>" -ForEach @(
            @{ Name = "plain"; Extra = @{ } }
            @{ Name = "-EnableException"; Extra = @{ EnableException = $true } }
            @{ Name = "-ErrorAction Stop"; Extra = @{ ErrorAction = "Stop" } }
        ) {
            $failure = $null
            $after = $false
            try {
                $null = Get-DbaDbView -SqlInstance $null @Extra
                $after = $true
            } catch {
                $failure = $PSItem
            }
            Assert-NativeBinderRecord -Record $failure -Id "ParameterArgumentValidationErrorNullNotAllowed" -Reason "is null" -Activity "Get-DbaDbView"
            $after | Should -BeFalse
        }
    }

    Context "An instance that cannot be reached" {
        # bad-between, bad-ee: the nested Get-DbaDatabase warns, and it gets no -EnableException. The one line is the shared selection helper's: an accepted difference in the corrections record.
        It "warns and goes on to the next instance: <Name>" -Tag "NativeChecklist:multi-instance-failure" -ForEach @(
            @{ Name = "plain"; Extra = @{ } }
            @{ Name = "-EnableException"; Extra = @{ EnableException = $true } }
            @{ Name = "-ErrorAction Stop"; Extra = @{ ErrorAction = "Stop" } }
        ) {
            $warnings = $null
            $results = @(Get-DbaDbView -SqlInstance $missingInstance, $instance -Database $dbB -View dbo.vw_one @Extra -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 1
            @($warnings | Where-Object { "$PSItem" -like "*Get-DbaDatabase*Failure*" }).Count | Should -Be 1
        }

        It "warns and goes on under -EnableException:`$false" -Tag "NativeChecklist:switch-false" {
            $warnings = $null
            $results = @(Get-DbaDbView -SqlInstance $missingInstance, $instance -Database $dbB -View dbo.vw_one -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 1
            @($warnings | Where-Object { "$PSItem" -like "*Get-DbaDatabase*Failure*" }).Count | Should -Be 1
        }
    }
}

Describe "Native Get-DbaDbView on Azure SQL Database" -Tag IntegrationTests {
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
    }

    # azure-shape, azure-view: read-only, and the instance name is empty there.
    It "reads a view by name on its connection, with the pinned shape" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $warnings = $null
        $result = @(Get-DbaDbView -SqlInstance $azureServer -View sys.objects -WarningVariable warnings -WarningAction SilentlyContinue)
        @($warnings).Count | Should -Be 0
        $result.Count | Should -Be 1
        $result[0].PSObject.BaseObject.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Smo.View"
        $result[0].Database | Should -BeExactly $azureDatabase
        $result[0].ComputerName | Should -BeExactly $azureServer.ComputerName
        $result[0].InstanceName | Should -BeNullOrEmpty
        $result[0].SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
    }

    # azure-connection, azure-exclude-system
    It "reads the system views of its database, which -ExcludeSystemView drops" -Tag "NativeChecklist:azure-sqldb" {
        $all = @(Get-DbaDbView -SqlInstance $azureServer -EnableException)
        @($all | Where-Object { $PSItem.IsSystemObject }).Count | Should -BeGreaterThan 100
        @($all.Database | Select-Object -Unique) | Should -BeExactly @($azureDatabase)
        @(Get-DbaDbView -SqlInstance $azureServer -ExcludeSystemView -EnableException).Count | Should -Be 0
    }

    # azure-by-name: the order of the rows, master first, where SMO's collection is sorted.
    It "reads by name master and then the database, in the order of the rows" -Tag "NativeChecklist:azure-sqldb" {
        $result = @(Get-DbaDbView -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -View sys.objects -EnableException)
        ($result.Database -join ",") | Should -BeExactly "master,$azureDatabase"
    }

    # azure-by-name-database
    It "reads by name the one database asked for" -Tag "NativeChecklist:azure-sqldb" {
        $result = @(Get-DbaDbView -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -Database $azureDatabase -View sys.objects -EnableException)
        ($result.Database -join ",") | Should -BeExactly $azureDatabase
    }

    # azure-input-piped
    It "reads a piped database object" -Tag "NativeChecklist:azure-sqldb" {
        $result = @($azureServer.Databases[$azureDatabase] | Get-DbaDbView -View sys.objects -EnableException)
        ($result.Database -join ",") | Should -BeExactly $azureDatabase
    }
}

Describe "Native Get-DbaDbView over SQL authentication" -Tag IntegrationTests {
    BeforeAll {
        $loginInstance = $TestConfig.InstanceSqlLogin
        $loginCred = $TestConfig.SqlLoginCred
        # Unique per leg and run: the instance is shared. The second database comes before the held one in the rows, as the stale view needs.
        $stamp = Get-Random
        $dbB = "dbatoolsci_ndvl_b_$stamp"
        $dbHeld = "dbatoolsci_ndvl_held_$stamp"
        $dbNone = "dbatoolsci_ndvl_none_$stamp"
        $dbLow = "dbatoolsci_ndvl_low_$stamp"
        $allDatabases = @($dbB, $dbHeld, $dbNone, $dbLow)
        $lowName = "dbatoolsci_ndvl_low_$stamp"
        $lowPassword = "Ndv-$([guid]::NewGuid().ToString('N'))"
        $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
        $heldText = "*Database '$dbHeld' is already open and can only have one user at a time."

        $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -NonPooledConnection -EnableException
        $null = $loginServer.Query("CREATE LOGIN [$lowName] WITH PASSWORD = '$lowPassword', CHECK_POLICY = OFF;")
        foreach ($name in $allDatabases) {
            $null = $loginServer.Query("CREATE DATABASE [$name];")
            $null = $loginServer.Query("USE [$name]; EXEC('CREATE VIEW [dbo].[vw_one] AS SELECT 1 AS col1'); USE [master];")
        }
        $null = $loginServer.Query("USE [$dbLow]; CREATE USER [$lowName] FOR LOGIN [$lowName]; USE [master];")

        # The connection the held cases pass: it has read both databases' properties, but not their views, and so keeps reading the held one as accessible (read after the hold).
        $measured = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -NonPooledConnection -EnableException
        $null = $measured.Databases[$dbHeld].IsAccessible
        $null = $measured.Databases[$dbB].IsAccessible
        $holder = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -NonPooledConnection -EnableException
        $holder.ConnectionContext.ExecuteNonQuery("USE [$dbHeld]; ALTER DATABASE [$dbHeld] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;")
        $held = @{ SqlInstance = $measured; Database = @($dbHeld, $dbB) }
        $fresh = @{ SqlInstance = $loginInstance; SqlCredential = $loginCred; Database = @($dbHeld, $dbB) }
    }

    AfterAll {
        foreach ($connection in @($measured, $holder)) {
            $connection.ConnectionContext.Disconnect()
        }
        foreach ($name in $allDatabases) {
            $null = $loginServer.Query("IF DB_ID(N'$name') IS NOT NULL BEGIN ALTER DATABASE [$name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$name]; END;")
        }
        # A query with no rows must not read as one null row.
        foreach ($row in @($loginServer.Query("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$lowName';") | Where-Object { $null -ne $PSItem })) {
            $null = $loginServer.Query("KILL $($row.session_id);")
        }
        $null = $loginServer.Query("IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];")
        $loginServer.ConnectionContext.Disconnect()
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        It "works with -SqlCredential" {
            $result = @(Get-DbaDbView -SqlInstance $loginInstance -SqlCredential $loginCred -Database $dbB -View dbo.vw_one -EnableException)
            $result.Count | Should -Be 1
            $result[0].Database | Should -BeExactly $dbB
            $result[0].SqlInstance | Should -BeExactly $loginServer.DomainInstanceName
        }

        # no-credential, no-credential-ee: the nested Get-DbaDatabase warns under either, since it gets no -EnableException.
        It "fails cleanly without the credential: a warning and no output: <Name>" -ForEach @(
            @{ Name = "plain"; Extra = @{ } }
            @{ Name = "-EnableException"; Extra = @{ EnableException = $true } }
        ) {
            $warnings = $null
            $result = Get-DbaDbView -SqlInstance $loginInstance @Extra -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            @($warnings | Where-Object { "$PSItem" -like "*Get-DbaDatabase*Failure*Login failed*" }).Count | Should -Be 1
        }
    }

    Context "A login with little access" {
        # low-no-user, low-no-user-ee: the warning shows under -EnableException too, and nothing stops.
        It "warns of a database it has no user in, and reads nothing: <Name>" -ForEach @(
            @{ Name = "plain"; Extra = @{ } }
            @{ Name = "-EnableException"; Extra = @{ EnableException = $true } }
        ) {
            $warnings = $null
            $result = @(Get-DbaDbView -SqlInstance $loginInstance -SqlCredential $lowCred -Database $dbNone @Extra -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 0
            @($warnings).Count | Should -Be 1
            "$($warnings[0])".EndsWith("[Get-DbaDbView] Database [$dbNone] is not accessible. Skipping", [System.StringComparison]::Ordinal) | Should -BeTrue
        }

        # low-no-user-view
        It "with -View, writes the record and then the warning" {
            $outside = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = $loginInstance; SqlCredential = $lowCred; Database = $dbNone; View = "vw_one" }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeEnumerationRecord -Record $outside.Errors[0] -InnerMessage "The server principal ""$lowName"" is not able to access the database ""$dbNone"" under the current security context."
            $outside.Warnings.Count | Should -Be 1
            $outside.Rows.Count | Should -Be 0
        }

        # low-user-no-permission, low-user-no-permission-view: it sees the system views and not the view it has no permission on.
        It "reads only the system views in a database it has a user in" {
            $result = @(Get-DbaDbView -SqlInstance $loginInstance -SqlCredential $lowCred -Database $dbLow -EnableException)
            @($result | Where-Object { $PSItem.IsSystemObject }).Count | Should -BeGreaterThan 100
            @($result | Where-Object { -not $PSItem.IsSystemObject }).Count | Should -Be 0
            @(Get-DbaDbView -SqlInstance $loginInstance -SqlCredential $lowCred -Database $dbLow -View vw_one -EnableException).Count | Should -Be 0
        }

        # low-master
        It "reads the system views of master as guest" {
            $result = @(Get-DbaDbView -SqlInstance $loginInstance -SqlCredential $lowCred -Database master -EnableException)
            @($result | Where-Object { $PSItem.IsSystemObject }).Count | Should -BeGreaterThan 100
        }
    }

    Context "A database held in single-user mode, on a connection that has not read it yet" {
        # held-fresh-plain: such a connection reads the database as not accessible.
        It "warns and goes on, with no record" {
            $outside = Invoke-NativeOutsideTry -Arguments ($fresh + @{ ExcludeSystemView = $true })
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 0
            $outside.Warnings.Count | Should -Be 1
            $outside.Warnings[0] | Should -BeLike "*Database ``[$dbHeld``] is not accessible. Skipping"
            ($outside.Rows.Database -join ",") | Should -BeExactly $dbB
        }

        # held-fresh-view
        It "with -View, writes the record, warns and goes on" {
            $outside = Invoke-NativeOutsideTry -Arguments ($fresh + @{ View = "vw_one" })
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeEnumerationRecord -Record $outside.Errors[0] -InnerMessage $heldText
            $outside.Warnings.Count | Should -Be 1
            ($outside.Rows.Database -join ",") | Should -BeExactly $dbB
        }
    }

    Context "A database held in single-user mode, on a connection that read it before, outside any try" {
        # held-plain, held-two-views, held-schema, held-exclude-system, held-schema-and-exclude, held-view-schema-exclude: one record for each statement that enumerates the views.
        It "a plain call writes <Records> record(s) and goes on: <Name>" -ForEach @(
            @{ Name = "no filter"; Extra = @{ }; Records = 1 }
            @{ Name = "-View"; Extra = @{ View = "vw_one" }; Records = 1 }
            @{ Name = "two names"; Extra = @{ View = "vw_one", "dbo.vw_one" }; Records = 2 }
            @{ Name = "-Schema"; Extra = @{ Schema = "dbo" }; Records = 2 }
            @{ Name = "-ExcludeSystemView"; Extra = @{ ExcludeSystemView = $true }; Records = 2 }
            @{ Name = "-Schema and -ExcludeSystemView"; Extra = @{ Schema = "dbo"; ExcludeSystemView = $true }; Records = 3 }
            @{ Name = "-View, -Schema and -ExcludeSystemView"; Extra = @{ View = "vw_one"; Schema = "dbo"; ExcludeSystemView = $true }; Records = 1 }
        ) {
            $outside = Invoke-NativeOutsideTry -Arguments ($held + $Extra)
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be $Records
            foreach ($record in $outside.Errors) {
                Assert-NativeEnumerationRecord -Record $record -InnerMessage $heldText
            }
            $outside.Warnings.Count | Should -Be 0
            @($outside.Rows | ForEach-Object { $PSItem.Parent.Name } | Select-Object -Unique) | Should -BeExactly @($dbB)
            $outside.Output[-1] | Should -BeExactly "next statement"
        }

        # Correction stale-view-row: held-view writes the second database's view again on the pin, under the held database's name, because the fault leaves $vw as it was.
        It "writes no row for a database whose view read faults" {
            $outside = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = $measured; Database = @($dbHeld, $dbB); View = "vw_one" }
            $outside.Errors.Count | Should -Be 1
            @($outside.Rows | Where-Object { $PSItem.Database -eq $dbHeld }).Count | Should -Be 0
            $outside.Rows.Count | Should -Be 1
            $outside.Rows[0].Database | Should -BeExactly $dbB
            $outside.Rows[0].Parent.Name | Should -BeExactly $dbB
        }

        # held-silent
        It "-ErrorAction SilentlyContinue writes no record and goes on" {
            $outside = Invoke-NativeOutsideTry -Arguments ($held + @{ View = "vw_one"; ErrorAction = "SilentlyContinue" })
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 0
            @($outside.Rows | ForEach-Object { $PSItem.Parent.Name } | Select-Object -Unique) | Should -BeExactly @($dbB)
            $outside.Output[-1] | Should -BeExactly "next statement"
        }

        # Accepted difference, keep-going: held-ee goes on where the port stops.
        It "-EnableException ends the command at the record and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOutsideTry -Arguments ($held + @{ EnableException = $true })
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeEnumerationRecord -Record $outside.Errors[0] -InnerMessage $heldText
            @($outside.Rows.Database | Select-Object -Unique) | Should -BeExactly @($dbB)
            $outside.Output[-1] | Should -BeExactly "next statement"
        }

        # Accepted difference, keep-going: held-stop ends the function's statement only.
        It "-ErrorAction Stop turns the record into the stop PowerShell gives WriteError" {
            $outside = Invoke-NativeOutsideTry -Arguments ($held + @{ View = "vw_one"; ErrorAction = "Stop" })
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeEnumerationRecord -Record $outside.Stop.ErrorRecord -InnerMessage $heldText
            ($outside.Rows.Database -join ",") | Should -BeExactly $dbB
            @($outside.Output | Where-Object { $PSItem -is [string] }).Count | Should -Be 0
        }

        # held-input-piped: the held object first, so nothing is stale; the verbose lines are the pinned ones.
        It "piped, writes the record and goes on to the next object" {
            $outside = Invoke-NativeOutsideTry -Arguments @{ View = "vw_one" } -Values @($measured.Databases[$dbHeld], $measured.Databases[$dbB]) -Piped
            $outside.Errors.Count | Should -Be 1
            Assert-NativeEnumerationRecord -Record $outside.Errors[0] -InnerMessage $heldText
            ($outside.Rows.Database -join ",") | Should -BeExactly $dbB
        }
    }

    Context "A database held in single-user mode, on a connection that read it before, inside a caller's try" {
        # held-try, held-view-try, held-ee-try, held-stop-try
        It "the catch receives the record after the rows before it: <Name>" -ForEach @(
            @{ Name = "plain"; Extra = @{ } }
            @{ Name = "-View"; Extra = @{ View = "vw_one" } }
            @{ Name = "-EnableException"; Extra = @{ EnableException = $true } }
            @{ Name = "-ErrorAction Stop"; Extra = @{ ErrorAction = "Stop" } }
        ) {
            $streamed = New-Object System.Collections.ArrayList
            $failure = $null
            $after = $false
            try {
                Get-DbaDbView @held @Extra | ForEach-Object { $null = $streamed.Add($PSItem) }
                $after = $true
            } catch {
                $failure = $PSItem
            }
            Assert-NativeEnumerationRecord -Record $failure -InnerMessage $heldText
            $after | Should -BeFalse
            @($streamed | ForEach-Object { $PSItem.Database } | Select-Object -Unique) | Should -BeExactly @($dbB)
        }

        # held-input-piped-try
        It "piped, the held object first, the catch receives the record before any row" {
            $streamed = New-Object System.Collections.ArrayList
            $failure = $null
            try {
                $measured.Databases[$dbHeld], $measured.Databases[$dbB] | Get-DbaDbView -View vw_one | ForEach-Object { $null = $streamed.Add($PSItem) }
            } catch {
                $failure = $PSItem
            }
            Assert-NativeEnumerationRecord -Record $failure -InnerMessage $heldText
            $streamed.Count | Should -Be 0
        }
    }
}
