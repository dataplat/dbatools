#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaDbTableData",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Database",
                "DestinationDatabase",
                "Table",
                "View",
                "Query",
                "ForceExplicitMapping",
                "AutoCreateTable",
                "BatchSize",
                "NotifyAfter",
                "DestinationTable",
                "NoTableLock",
                "CheckConstraints",
                "FireTriggers",
                "KeepIdentity",
                "KeepNulls",
                "Truncate",
                "BulkCopyTimeout",
                "CommandTimeout",
                "UseDefaultFileGroup",
                "ScriptingOptionsObject",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $sourceDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb
        $destinationDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database tempdb
        $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_example (id int);
            INSERT dbo.dbatoolsci_example
            SELECT top 10 1
            FROM sys.objects")
        $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_example2 (id int)")
        $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_example3 (id int)")
        $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_example4 (id int);
            INSERT dbo.dbatoolsci_example4
            SELECT top 13 1
            FROM sys.objects")
        $null = $destinationDb.Query("CREATE TABLE dbo.dbatoolsci_example (id int)")
        $null = $destinationDb.Query("CREATE TABLE dbo.dbatoolsci_example3 (id int)")
        $null = $destinationDb.Query("CREATE TABLE dbo.dbatoolsci_example4 (id int);
            INSERT dbo.dbatoolsci_example4
            SELECT top 13 2
            FROM sys.objects")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = $sourceDb.Query("DROP TABLE dbo.dbatoolsci_example")
        $null = $sourceDb.Query("DROP TABLE dbo.dbatoolsci_example2")
        $null = $sourceDb.Query("DROP TABLE dbo.dbatoolsci_example3")
        $null = $sourceDb.Query("DROP TABLE dbo.dbatoolsci_example4")
        $null = $destinationDb.Query("DROP TABLE dbo.dbatoolsci_example3")
        $null = $destinationDb.Query("DROP TABLE dbo.dbatoolsci_example4")
        $null = $destinationDb.Query("DROP TABLE dbo.dbatoolsci_example")
        $null = $sourceDb.Query("DROP TABLE tempdb.dbo.dbatoolsci_willexist")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying table data within same instance" {
        It "copies the table data" {
            $results = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_example2
            $table1count = $sourceDb.Query("select id from dbo.dbatoolsci_example")
            $table2count = $sourceDb.Query("select id from dbo.dbatoolsci_example2")
            $table1count.Count | Should -Be $table2count.Count
            $results.SourceDatabaseID | Should -Be $sourceDb.ID
            $results.DestinationDatabaseID | Should -Be $sourceDb.ID
        }
    }

    Context "When copying table data between instances" {
        It "copies the table data to another instance" {
            $null = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Database tempdb -Table tempdb.dbo.dbatoolsci_example -DestinationTable dbatoolsci_example3
            $table1count = $sourceDb.Query("select id from dbo.dbatoolsci_example")
            $table2count = $destinationDb.Query("select id from dbo.dbatoolsci_example3")
            $table1count.Count | Should -Be $table2count.Count
        }

        It "Copy data using a query that relies on the default source database" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy2 -Database tempdb -Table dbo.dbatoolsci_example4 -Query "SELECT TOP (1) Id FROM dbo.dbatoolsci_example4 ORDER BY Id DESC" -DestinationTable dbatoolsci_example3 -Truncate
            $result.RowsCopied | Should -Be 1
        }

        It "Copy data using a query that uses a 3 part query" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy2 -Database tempdb -Table dbo.dbatoolsci_example4 -Query "SELECT TOP (1) Id FROM tempdb.dbo.dbatoolsci_example4 ORDER BY Id DESC" -DestinationTable dbatoolsci_example3 -Truncate
            $result.RowsCopied | Should -Be 1
        }
    }

    Context "When testing pipeline functionality" {
        It "supports piping" {
            $null = Get-DbaDbTable -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Table dbatoolsci_example | Copy-DbaDbTableData -DestinationTable dbatoolsci_example2 -Truncate
            $table1count = $sourceDb.Query("select id from dbo.dbatoolsci_example")
            $table2count = $sourceDb.Query("select id from dbo.dbatoolsci_example2")
            $table1count.Count | Should -Be $table2count.Count
        }

        It "supports piping more than one table" {
            $results = Get-DbaDbTable -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Table dbatoolsci_example2, dbatoolsci_example | Copy-DbaDbTableData -DestinationTable dbatoolsci_example3
            $results.Count | Should -Be 2
            $results.RowsCopied | Measure-Object -Sum | Select-Object -ExpandProperty Sum | Should -Be 20
        }

        It "opens and closes connections properly" {
            $results = Get-DbaDbTable -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Table "dbo.dbatoolsci_example", "dbo.dbatoolsci_example4" | Copy-DbaDbTableData -Destination $TestConfig.InstanceCopy2 -DestinationDatabase tempdb -KeepIdentity -KeepNulls -BatchSize 5000 -Truncate
            $results.Count | Should -Be 2
            $table1DbCount = $sourceDb.Query("select id from dbo.dbatoolsci_example")
            $table4DbCount = $destinationDb.Query("select id from dbo.dbatoolsci_example4")
            $table1Db2Count = $sourceDb.Query("select id from dbo.dbatoolsci_example")
            $table4Db2Count = $destinationDb.Query("select id from dbo.dbatoolsci_example4")
            $table1DbCount.Count | Should -Be $table1Db2Count.Count
            $table4DbCount.Count | Should -Be $table4Db2Count.Count
            $results[0].RowsCopied | Should -Be 10
            $results[1].RowsCopied | Should -Be 13
            $table4Db2Check = $destinationDb.Query("select id from dbo.dbatoolsci_example4 where id = 1")
            $table4Db2Check.Count | Should -Be 13
        }
    }

    Context "When handling edge cases" {
        It "Should return nothing if Source and Destination are same" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Table dbatoolsci_example -Truncate -WarningVariable warn -WarningAction SilentlyContinue
            $result | Should -Be $null
            $warn | Should -Match "Cannot copy .* into itself"
        }

        It "Should warn if the destinaton table doesn't exist" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_doesntexist -WarningVariable tablewarning 3> $null
            $result | Should -Be $null
            $tablewarning | Should -Match Auto
        }

        It "automatically creates the table" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Table dbatoolsci_example -DestinationTable dbatoolsci_willexist -AutoCreateTable
            $result.DestinationTable | Should -Be "dbatoolsci_willexist"
        }
    }

    Context "When destination table has computed columns" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_computed_source (Dt DATETIME)")
            $null = $sourceDb.Query("INSERT dbo.dbatoolsci_computed_source (Dt) VALUES (GETDATE()), (DATEADD(MONTH, -1, GETDATE()))")
            $null = $destinationDb.Query("CREATE TABLE dbo.dbatoolsci_computed_dest (Dt DATETIME, DtDay AS (DATEPART(DAY, Dt)), DtMonth AS (DATEPART(MONTH, Dt)), DtYear AS (DATEPART(YEAR, Dt)))")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceDb.Query("IF OBJECT_ID('dbo.dbatoolsci_computed_source', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_computed_source")
            $null = $destinationDb.Query("IF OBJECT_ID('dbo.dbatoolsci_computed_dest', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_computed_dest")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should copy data successfully when destination has computed columns" {
            $result = Copy-DbaDbTableData -SqlInstance $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Database tempdb -Table dbatoolsci_computed_source -DestinationTable dbatoolsci_computed_dest
            $result.RowsCopied | Should -Be 2
            $destCount = $destinationDb.Query("SELECT * FROM dbo.dbatoolsci_computed_dest")
            $destCount.Count | Should -Be 2
        }

        It "Should copy data using Query with ForceExplicitMapping when destination has computed columns" {
            # First truncate dest table
            $null = $destinationDb.Query("TRUNCATE TABLE dbo.dbatoolsci_computed_dest")

            # Use Query parameter with ForceExplicitMapping to enable name-based column mapping
            # This is needed when using Query with tables that have computed columns
            $splatCopy = @{
                SqlInstance          = $TestConfig.InstanceCopy1
                Destination          = $TestConfig.InstanceCopy2
                Database             = "tempdb"
                Table                = "dbatoolsci_computed_source"
                Query                = "SELECT Dt FROM dbo.dbatoolsci_computed_source"
                DestinationTable     = "dbatoolsci_computed_dest"
                ForceExplicitMapping = $true
            }
            $result = Copy-DbaDbTableData @splatCopy
            $result.RowsCopied | Should -Be 2
            $destCount = $destinationDb.Query("SELECT * FROM dbo.dbatoolsci_computed_dest")
            $destCount.Count | Should -Be 2
        }
    }

    Context "When -WhatIf is used" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_whatif_source (id int);
                INSERT dbo.dbatoolsci_whatif_source
                SELECT TOP 10 1
                FROM sys.objects")
            $null = $destinationDb.Query("CREATE TABLE dbo.dbatoolsci_whatif_dest (id int);
                INSERT dbo.dbatoolsci_whatif_dest
                SELECT TOP 3 2
                FROM sys.objects")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceDb.Query("IF OBJECT_ID('dbo.dbatoolsci_whatif_source', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_whatif_source")
            $null = $destinationDb.Query("IF OBJECT_ID('dbo.dbatoolsci_whatif_dest', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_whatif_dest")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should neither truncate nor copy, and should emit nothing" {
            $splatWhatIf = @{
                SqlInstance      = $TestConfig.InstanceCopy1
                Destination      = $TestConfig.InstanceCopy2
                Database         = "tempdb"
                Table            = "dbatoolsci_whatif_source"
                DestinationTable = "dbatoolsci_whatif_dest"
                Truncate         = $true
                WhatIf           = $true
            }
            $result = Copy-DbaDbTableData @splatWhatIf
            $result | Should -BeNullOrEmpty

            # -Truncate runs under its own gate ahead of the copy, so the three seeded rows
            # surviving proves the gate held for both side effects, not just the bulk copy.
            $afterWhatIf = $destinationDb.Query("SELECT id FROM dbo.dbatoolsci_whatif_dest")
            $afterWhatIf.Count | Should -Be 3
            @($afterWhatIf | Where-Object id -eq 2).Count | Should -Be 3
        }

        It "Should truncate and copy once -WhatIf is dropped" {
            # Without this the assertion above cannot fail: it would pass against a command that
            # never copies anything at all.
            $splatReal = @{
                SqlInstance      = $TestConfig.InstanceCopy1
                Destination      = $TestConfig.InstanceCopy2
                Database         = "tempdb"
                Table            = "dbatoolsci_whatif_source"
                DestinationTable = "dbatoolsci_whatif_dest"
                Truncate         = $true
            }
            $result = Copy-DbaDbTableData @splatReal
            $result.RowsCopied | Should -Be 10

            $afterReal = $destinationDb.Query("SELECT id FROM dbo.dbatoolsci_whatif_dest")
            $afterReal.Count | Should -Be 10
            @($afterReal | Where-Object id -eq 2).Count | Should -Be 0
        }
    }

    Context "When one call spans more than one destination or source instance" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_multi_source (id int);
                INSERT dbo.dbatoolsci_multi_source
                SELECT TOP 6 1
                FROM sys.objects")
            $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_multi_dest (id int)")
            $null = $destinationDb.Query("CREATE TABLE dbo.dbatoolsci_multi_dest (id int)")

            $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_latch_a (id int);
                INSERT dbo.dbatoolsci_latch_a
                SELECT TOP 4 1
                FROM sys.objects")
            $null = $destinationDb.Query("CREATE TABLE dbo.dbatoolsci_latch_b (id int);
                INSERT dbo.dbatoolsci_latch_b
                SELECT TOP 9 1
                FROM sys.objects")
            # Deliberately only on the first instance - the latch below sends the second record
            # here too, so a run that resolved the destination per record would find nothing.
            $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_latch_dest (id int)")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceDb.Query("IF OBJECT_ID('dbo.dbatoolsci_multi_source', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_multi_source")
            $null = $sourceDb.Query("IF OBJECT_ID('dbo.dbatoolsci_multi_dest', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_multi_dest")
            $null = $destinationDb.Query("IF OBJECT_ID('dbo.dbatoolsci_multi_dest', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_multi_dest")
            $null = $sourceDb.Query("IF OBJECT_ID('dbo.dbatoolsci_latch_a', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_latch_a")
            $null = $destinationDb.Query("IF OBJECT_ID('dbo.dbatoolsci_latch_b', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_latch_b")
            $null = $sourceDb.Query("IF OBJECT_ID('dbo.dbatoolsci_latch_dest', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_latch_dest")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should copy one table to two destination instances in a single call" {
            $splatTwoDestinations = @{
                SqlInstance      = $TestConfig.InstanceCopy1
                Destination      = $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2
                Database         = "tempdb"
                Table            = "dbatoolsci_multi_source"
                DestinationTable = "dbatoolsci_multi_dest"
            }
            $results = Copy-DbaDbTableData @splatTwoDestinations
            $results.Count | Should -Be 2
            @($results.DestinationInstance | Sort-Object -Unique).Count | Should -Be 2
            $results.RowsCopied | Should -Be @(6, 6)

            $sourceDb.Query("SELECT id FROM dbo.dbatoolsci_multi_dest").Count | Should -Be 6
            $destinationDb.Query("SELECT id FROM dbo.dbatoolsci_multi_dest").Count | Should -Be 6
        }

        It "Should send every piped record to the instance the first record settled on" {
            # Documented behaviour of the retired function rather than a design intent: -Destination
            # is only defaulted when it is still empty, so the first record's server sticks for the
            # rest of the pipeline even when a later table comes from somewhere else. Reproduced
            # deliberately; the divergence a per-record resolution would introduce is what this
            # pins.
            $splatLatchA = @{
                SqlInstance = $TestConfig.InstanceCopy1
                Database    = "tempdb"
                Table       = "dbatoolsci_latch_a"
            }
            $splatLatchB = @{
                SqlInstance = $TestConfig.InstanceCopy2
                Database    = "tempdb"
                Table       = "dbatoolsci_latch_b"
            }
            $latchTableA = Get-DbaDbTable @splatLatchA
            $latchTableB = Get-DbaDbTable @splatLatchB
            $latchTableA | Should -Not -BeNullOrEmpty
            $latchTableB | Should -Not -BeNullOrEmpty

            $results = $latchTableA, $latchTableB | Copy-DbaDbTableData -DestinationTable dbatoolsci_latch_dest
            $results.Count | Should -Be 2
            @($results.SourceInstance | Sort-Object -Unique).Count | Should -Be 2
            @($results.DestinationInstance | Sort-Object -Unique).Count | Should -Be 1
            $results[1].SourceInstance | Should -Not -Be $results[1].DestinationInstance
            $results[0].DestinationInstance | Should -Be $results[1].DestinationInstance

            $sourceDb.Query("SELECT id FROM dbo.dbatoolsci_latch_dest").Count | Should -Be 13
        }
    }

    Context "When copying view data" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_view_source (id int);
                INSERT dbo.dbatoolsci_view_source
                SELECT TOP 5 1
                FROM sys.objects")
            $null = $sourceDb.Query("CREATE VIEW dbo.dbatoolsci_view_vw AS SELECT id FROM dbo.dbatoolsci_view_source")
            $null = $destinationDb.Query("CREATE TABLE dbo.dbatoolsci_view_dest (id int)")
            $null = $destinationDb.Query("CREATE TABLE dbo.dbatoolsci_view_wrapped (id int)")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceDb.Query("IF OBJECT_ID('dbo.dbatoolsci_view_vw', 'V') IS NOT NULL DROP VIEW dbo.dbatoolsci_view_vw")
            $null = $sourceDb.Query("IF OBJECT_ID('dbo.dbatoolsci_view_source', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_view_source")
            $null = $destinationDb.Query("IF OBJECT_ID('dbo.dbatoolsci_view_dest', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_view_dest")
            $null = $destinationDb.Query("IF OBJECT_ID('dbo.dbatoolsci_view_wrapped', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_view_wrapped")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should copy from a view when -View is used instead of -Table" {
            $splatView = @{
                SqlInstance      = $TestConfig.InstanceCopy1
                Destination      = $TestConfig.InstanceCopy2
                Database         = "tempdb"
                View             = "dbo.dbatoolsci_view_vw"
                DestinationTable = "dbatoolsci_view_dest"
            }
            $result = Copy-DbaDbTableData @splatView
            $result.RowsCopied | Should -Be 5
            $result.SourceTable | Should -Be "dbatoolsci_view_vw"
            $destinationDb.Query("SELECT id FROM dbo.dbatoolsci_view_dest").Count | Should -Be 5
        }

        It "Should still be reachable from Copy-DbaDbViewData, which forwards its bound parameters" {
            # Copy-DbaDbViewData is a thin wrapper that splats straight into this command, so it is
            # the one caller that would break on a name that no longer resolves inside the module.
            $splatWrapped = @{
                SqlInstance      = $TestConfig.InstanceCopy1
                Destination      = $TestConfig.InstanceCopy2
                Database         = "tempdb"
                View             = "dbo.dbatoolsci_view_vw"
                DestinationTable = "dbatoolsci_view_wrapped"
            }
            $result = Copy-DbaDbViewData @splatWrapped
            $result.RowsCopied | Should -Be 5
            $destinationDb.Query("SELECT id FROM dbo.dbatoolsci_view_wrapped").Count | Should -Be 5
        }
    }

    Context "Regression tests" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceDb.Query("CREATE TABLE dbo.dbatoolsci_ordering_test (id INT IDENTITY(1,1) PRIMARY KEY, data_hash VARBINARY(32))")
            $null = $sourceDb.Query("INSERT INTO dbo.dbatoolsci_ordering_test (data_hash) VALUES (0x0102030405), (0x0607080910), (0x1112131415)")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceDb.Query("IF OBJECT_ID('dbo.dbatoolsci_ordering_test', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_ordering_test")
            $null = $destinationDb.Query("IF OBJECT_ID('dbo.dbatoolsci_ordering_test_dest', 'U') IS NOT NULL DROP TABLE dbo.dbatoolsci_ordering_test_dest")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should maintain correct row order when copying tables with varbinary fields (issue #9610)" {
            $splatCopy = @{
                SqlInstance      = $TestConfig.InstanceCopy1
                Destination      = $TestConfig.InstanceCopy2
                Database         = "tempdb"
                Table            = "dbatoolsci_ordering_test"
                DestinationTable = "dbatoolsci_ordering_test_dest"
                AutoCreateTable  = $true
            }
            $result = Copy-DbaDbTableData @splatCopy
            $result.RowsCopied | Should -Be 3

            $sourceData = $sourceDb.Query("SELECT id, data_hash FROM dbo.dbatoolsci_ordering_test ORDER BY id")
            $destData = $destinationDb.Query("SELECT id, data_hash FROM dbo.dbatoolsci_ordering_test_dest ORDER BY id")

            for ($i = 0; $i -lt $sourceData.Count; $i++) {
                $sourceData[$i].id | Should -Be $destData[$i].id
                $sourceData[$i].data_hash | Should -Be $destData[$i].data_hash
            }
        }
    }

    Context "When resolving the command name in a cold shell" {
        BeforeAll {
            # Every other leg runs in a session that imported dbatools long before Pester started,
            # so none of them can tell the binary cmdlet apart from the retired script function -
            # whichever got there first answers to the name. This leg starts a shell of the same
            # edition that has imported nothing, loads the module the way a consumer does, and asks
            # what the name resolves to. dbatools.psm1 is the import under test on purpose: it is
            # the loader that pulls the satellite in by path, and importing the manifest by name
            # cannot work in a dev tree because the satellites are not on PSModulePath.
            $moduleBase = @(Get-Module -Name dbatools)[0].ModuleBase
            $shellPath = (Get-Process -Id $PID).Path
            # This file is EXECUTED, so where it lives matters as much as what is in it. It goes in
            # a per-invocation directory that only its creator and the machine's administrators can
            # write to, rather than in the shared temp root, under a GUID name, and created below
            # with CreateNew rather than written over whatever is at the path.
            $probeDirectory = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatoolsci-resolve-$([guid]::NewGuid().ToString("N"))"
            # A GUID makes this unreachable in practice, but every create-directory API below
            # succeeds silently on a path that already exists and leaves its permissions alone, so
            # the one thing that must not happen is adopting somebody else's directory and
            # executing a script out of it.
            if (Test-Path -LiteralPath $probeDirectory) {
                throw "$probeDirectory already exists - this run will not execute a script out of a directory it did not create"
            }
            # Only a directory this block actually created may be deleted in AfterAll. Without the
            # flag the throw above hands the cleanup a path it just refused to touch.
            $probeDirectoryCreated = $false
            $probeDirectoryInfo = New-Object System.IO.DirectoryInfo($probeDirectory)
            if ([System.Environment]::OSVersion.Platform -eq "Win32NT") {
                # The running identity owns it, not Administrators: only an elevated run can hand
                # ownership to a group it is not in, and a descriptor that omits the creator locks
                # the creator out of the directory it just made.
                $currentSid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User
                $administratorsSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
                $systemSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
                $probeSecurity = New-Object System.Security.AccessControl.DirectorySecurity
                $probeSecurity.SetAccessRuleProtection($true, $false)
                $probeSecurity.SetOwner($currentSid)
                foreach ($trusteeSid in $currentSid, $administratorsSid, $systemSid) {
                    $probeRule = New-Object System.Security.AccessControl.FileSystemAccessRule($trusteeSid, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
                    $probeSecurity.AddAccessRule($probeRule)
                }
                # Created WITH the descriptor, never created and then secured - the gap between
                # those two calls carries inherited permissions. Which call does it differs by
                # edition: .NET Framework has DirectoryInfo.Create(DirectorySecurity), .NET moved
                # it out to FileSystemAclExtensions. Probing for the overload rather than the
                # PSEdition because it is the overload that decides.
                $probeNativeCreate = [System.IO.DirectoryInfo].GetMethod("Create", [Type[]]@([System.Security.AccessControl.DirectorySecurity]))
                if ($probeNativeCreate) {
                    $probeDirectoryInfo.Create($probeSecurity)
                } else {
                    [System.IO.FileSystemAclExtensions]::Create($probeDirectoryInfo, $probeSecurity)
                }
                $probeDirectoryCreated = $true
            } else {
                # DirectorySecurity is Windows-only and throws PlatformNotSupportedException
                # everywhere else, so the mode carries the same job there. mkdir rather than a .NET
                # call, for the exclusivity: every managed create-directory API succeeds silently
                # on a directory that already exists and leaves its permissions alone.
                $null = & /bin/mkdir -m 700 $probeDirectory
                if ($LASTEXITCODE -ne 0) {
                    throw "could not create $probeDirectory with owner-only permissions (mkdir exited $LASTEXITCODE)"
                }
                $probeDirectoryCreated = $true
            }
            $probePath = Join-Path -Path $probeDirectory -ChildPath "resolve.ps1"

            # Get-Command -All so a retired function shadowing the cmdlet shows up as a second
            # entry rather than silently winning; the count is what proves it is not there.
            $probeBody = @"
param(`$ModuleBase)
# The module path is an ARGUMENT, not interpolated text: this script is executed, and a
# path carrying a quote or a $ would otherwise close the string and run as code.
Import-Module -Name (Join-Path -Path `$ModuleBase -ChildPath "dbatools.psm1") -DisableNameChecking
`$resolved = Get-Command -Name Copy-DbaDbTableData -ErrorAction SilentlyContinue
`$splatResolveAll = @{
    Name        = "Copy-DbaDbTableData"
    All         = `$true
    ErrorAction = "SilentlyContinue"
}
`$allResolved = @(Get-Command @splatResolveAll)
`$functionCount = @(`$allResolved | Where-Object { `$PSItem.CommandType -eq "Function" }).Count
`$satelliteLoaded = [bool](Get-Module -Name dbatools.migration)
"RESOLVED|`$(`$resolved.CommandType)|`$(`$resolved.ModuleName)|`$functionCount|`$satelliteLoaded"
"@
            $probeStream = New-Object System.IO.FileStream($probePath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
            try {
                $probeBytes = [System.Text.Encoding]::UTF8.GetBytes($probeBody)
                $probeStream.Write($probeBytes, 0, $probeBytes.Length)
            } finally {
                $probeStream.Dispose()
            }

            $probeArguments = @("-NoProfile", "-NonInteractive", "-File", $probePath, $moduleBase)
            $probeOutput = & $shellPath @probeArguments 2>&1
            $probeFields = @("$(@($probeOutput | Where-Object { "$PSItem" -like "RESOLVED|*" })[0])" -split "\|")
        }

        AfterAll {
            if ($probeDirectoryCreated) {
                $splatRemoveProbeDirectory = @{
                    Path        = $probeDirectory
                    Recurse     = $true
                    Force       = $true
                    ErrorAction = "SilentlyContinue"
                }
                Remove-Item @splatRemoveProbeDirectory
            }
        }

        It "Should resolve to the binary cmdlet shipped by dbatools.migration" {
            $probeFields[1] | Should -Be "Cmdlet"
            $probeFields[2] | Should -Be "dbatools.migration"
        }

        It "Should load the satellite and leave no retired function shadowing the name" {
            $probeFields[4] | Should -Be "True"
            $probeFields[3] | Should -Be "0"
        }
    }
}
