#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaDbMissingIndex",
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
                "Database",
                "ExcludeDatabase",
                "InputObject",
                "MinimumImpact",
                "MinimumSeek",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $db = "dbatoolsci_missingindex_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $db

        # A clustered PK only, then enough rows that a predicate on an unindexed column produces a
        # missing-index suggestion. A trivial plan never generates one, so AND 1 = (SELECT 1) forces
        # the predicate to full optimization (the behaviour the maintainer confirmed in #10770).
        $setup = @"
CREATE TABLE dbo.Orders (OrderId int IDENTITY(1,1) PRIMARY KEY, CustomerId int, Amount money, Filler char(200) DEFAULT 'x');
INSERT INTO dbo.Orders (CustomerId, Amount)
SELECT TOP (20000) ABS(CHECKSUM(NEWID())) % 1000, ABS(CHECKSUM(NEWID())) % 10000
FROM sys.all_objects a CROSS JOIN sys.all_objects b;
"@
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $db -Query $setup

        $runWorkload = "SELECT OrderId, Amount FROM dbo.Orders WHERE CustomerId = 42 AND 1 = (SELECT 1);"
        1..5 | ForEach-Object { $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $db -Query $runWorkload }

        # Second table for the overlap case: an index already leads on OrderDate, and a range query
        # over OrderDate (projecting another column) produces an INEQUALITY-ONLY suggestion keyed on
        # OrderDate. The command should then report that existing index in OverlappingIndex - this is
        # the range-only overlap that the first fixture (equality-only, no secondary index) can't cover.
        $overlapSetup = @"
CREATE TABLE dbo.Events (EventId int IDENTITY(1,1) PRIMARY KEY, OrderDate datetime2 NOT NULL, Payload char(200) NOT NULL DEFAULT 'x');
CREATE NONCLUSTERED INDEX IX_Events_OrderDate ON dbo.Events (OrderDate);
INSERT INTO dbo.Events (OrderDate)
SELECT TOP (20000) DATEADD(MINUTE, ABS(CHECKSUM(NEWID())) % 1000000, '2020-01-01')
FROM sys.all_objects a CROSS JOIN sys.all_objects b;
"@
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $db -Query $overlapSetup

        # Range predicate on OrderDate + project Payload -> inequality-only suggestion on OrderDate.
        $overlapWorkload = "SELECT Payload FROM dbo.Events WHERE OrderDate > '2020-06-01' AND 1 = (SELECT 1);"
        1..5 | ForEach-Object { $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $db -Query $overlapWorkload }

        # Identifier-edge-case table. Two things the OLD text/LIKE matching got wrong, that column_id
        # matching must get right:
        #   1. Space: a suggestion on [Order Date] against an index leading on [Order Date] (the old
        #      code stripped spaces, so it could confuse this with a different column).
        #   2. Underscore wildcard: an index leads on [Customer_d], and the workload filters on
        #      [CustomerId], producing a suggestion on [CustomerId]. Under the old LIKE, the _ in
        #      [Customer_d] is a single-character wildcard, so 'Customer_d' would FALSELY match
        #      'CustomerId'. With column_id matching it must NOT, because they are different columns.
        $edgeSetup = @"
CREATE TABLE dbo.Sales ([Sale Id] int IDENTITY(1,1) PRIMARY KEY, [Order Date] datetime2 NOT NULL, CustomerId int NOT NULL, [Customer_d] int NOT NULL, Note char(200) NOT NULL DEFAULT 'x');
CREATE NONCLUSTERED INDEX [IX_Sales_OrderDate] ON dbo.Sales ([Order Date]);
CREATE NONCLUSTERED INDEX [IX_Sales_Customer_d] ON dbo.Sales ([Customer_d]);
INSERT INTO dbo.Sales ([Order Date], CustomerId, [Customer_d])
SELECT TOP (20000) DATEADD(MINUTE, ABS(CHECKSUM(NEWID())) % 1000000, '2020-01-01'), ABS(CHECKSUM(NEWID())) % 1000, ABS(CHECKSUM(NEWID())) % 1000
FROM sys.all_objects a CROSS JOIN sys.all_objects b;
"@
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $db -Query $edgeSetup

        # Range on [Order Date] -> inequality suggestion on the spaced column.
        $edgeWorkload = "SELECT Note FROM dbo.Sales WHERE [Order Date] > '2020-06-01' AND 1 = (SELECT 1);"
        1..5 | ForEach-Object { $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $db -Query $edgeWorkload }

        # Equality on CustomerId -> suggestion on [CustomerId]; the existing index on [Customer_d]
        # must NOT be reported as overlapping (it would be, under the old _-as-wildcard LIKE).
        $wildcardWorkload = "SELECT Note FROM dbo.Sales WHERE CustomerId = 42 AND 1 = (SELECT 1);"
        1..5 | ForEach-Object { $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $db -Query $wildcardWorkload }

        # Low thresholds so the single-seek fixtures are not filtered out by the defaults.
        $results = Find-DbaDbMissingIndex -SqlInstance $TestConfig.InstanceSingle -Database $db -MinimumImpact 0 -MinimumSeek 1
        $suggestion = $results | Where-Object { $PSItem.Table -eq "Orders" -and $PSItem.EqualityColumns -match "CustomerId" } | Select-Object -First 1
        $overlapSuggestion = $results | Where-Object { $PSItem.InequalityColumns -match "OrderDate" } | Select-Object -First 1
        $edgeSuggestion = $results | Where-Object { $PSItem.Table -eq "Sales" -and $PSItem.InequalityColumns -match "Order Date" } | Select-Object -First 1
        $wildcardSuggestion = $results | Where-Object { $PSItem.Table -eq "Sales" -and $PSItem.EqualityColumns -match "CustomerId" } | Select-Object -First 1

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $db -ErrorAction SilentlyContinue
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Finds a seeded missing index" {
        It "Returns a suggestion keyed on CustomerId" {
            $suggestion | Should -Not -BeNullOrEmpty
        }

        It "Generates the exact CREATE statement for the fixture" {
            # Assert the complete statement. The index name carries the index_handle (a per-table
            # integer), so that one segment is matched as \d+. The optimizer may or may not add
            # [Amount] as an included column for this small fixture, so the INCLUDE clause is
            # optional; everything else - verb, name shape, schema, table and the single key
            # column - must match exactly, which is what catches a malformed statement.
            $suggestion.CreateStatement | Should -Match "^CREATE NONCLUSTERED INDEX \[IX_Orders_CustomerId_\d+\] ON \[dbo\]\.\[Orders\] \(\[CustomerId\]\)( INCLUDE \(\[Amount\]\))?;$"
        }

        It "Does not emit an empty key list or empty INCLUDE" {
            $suggestion.CreateStatement | Should -Not -Match "\(\s*\)"
            $suggestion.CreateStatement | Should -Not -Match ",\s*\)"
        }

        It "Returns the impact-score inputs as properties" {
            $suggestion.PSObject.Properties.Name | Should -Contain "AvgTotalUserCost"
            $suggestion.PSObject.Properties.Name | Should -Contain "AvgUserImpact"
            $suggestion.PSObject.Properties.Name | Should -Contain "ImpactScore"
        }

        It "Leaves the caller's connection in its original database" {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $before = $server.ConnectionContext.CurrentDatabase
            $null = $server | Find-DbaDbMissingIndex -Database $db -MinimumImpact 0 -MinimumSeek 1
            $server.ConnectionContext.CurrentDatabase | Should -Be $before
        }
    }

    Context "Flags an overlapping index for an inequality-only suggestion" {
        It "Returns an inequality-only suggestion keyed on OrderDate" {
            $overlapSuggestion | Should -Not -BeNullOrEmpty
            $overlapSuggestion.InequalityColumns | Should -Match "OrderDate"
            $overlapSuggestion.EqualityColumns | Should -BeNullOrEmpty
        }

        It "Names the existing OrderDate index in OverlappingIndex" {
            # This is the regression for the overlap-matching fix: the final (here, only) key column
            # of a range-only suggestion must still match an existing index leading on that column.
            $overlapSuggestion.OverlappingIndex | Should -Match "IX_Events_OrderDate"
        }
    }

    Context "Matches overlaps by column id, not identifier text" {
        It "Returns the inequality suggestion on the spaced column" {
            $edgeSuggestion | Should -Not -BeNullOrEmpty
        }

        It "Flags the index on the spaced column [Order Date]" {
            # A space in the identifier must not break the match (the old text approach stripped spaces).
            $edgeSuggestion.OverlappingIndex | Should -Match "IX_Sales_OrderDate"
        }

        It "Returns the equality suggestion on CustomerId" {
            $wildcardSuggestion | Should -Not -BeNullOrEmpty
        }

        It "Does not falsely flag the [Customer_d] index for a [CustomerId] suggestion" {
            # Under the OLD LIKE matching, the _ in 'Customer_d' is a single-char wildcard, so an index
            # leading on [Customer_d] would FALSELY match a suggestion on [CustomerId]. column_id
            # matching compares real columns, so IX_Sales_Customer_d must NOT be reported here.
            $wildcardSuggestion.OverlappingIndex | Should -Not -Match "IX_Sales_Customer_d"
        }
    }

    Context "Honours an explicitly piped system database" {
        It "Processes msdb without warning when piped in explicitly" {
            # Get-DbaDatabase -Database msdb | Find-DbaDbMissingIndex: the downstream -Database is not
            # set in a pipeline, so the command must treat the piped object as an explicit selection
            # and process it, not silently return nothing. The caller chose msdb, so there is no
            # warning (that would be noise); the processing note is verbose only. This runs without
            # throwing, which proves msdb was not rejected.
            { Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database msdb |
                Find-DbaDbMissingIndex -MinimumImpact 0 -MinimumSeek 1 -WarningVariable warnSystem 3> $null } |
                Should -Not -Throw
            $warnSystem | Should -BeNullOrEmpty
        }
    }

    Context "Withholds DDL for metadata-hidden objects" {
        BeforeAll {
            # The split we need: the login CAN read the missing-index DMV (a server-scoped view) but
            # CANNOT see the object's metadata, so OBJECT_NAME / OBJECT_SCHEMA_NAME return NULL and a
            # generated CREATE statement would be malformed. The command must return the row but
            # withhold the statement, and warn. To produce that split:
            #   - grant the server-level DMV permission. SQL 2022+ renamed it to VIEW SERVER
            #     PERFORMANCE STATE; earlier versions use VIEW SERVER STATE. Grant whichever the
            #     instance supports (try the new name, fall back to the old) so the DMV returns rows.
            #   - add a database user (so Get-DbaDatabase -OnlyAccessible does not drop the database
            #     before analysis - without the user the login can't open the DB and gets zero rows,
            #     which is exactly the vacuous pass this test must avoid), but grant it NO permission
            #     on dbo.Orders, so the object metadata stays hidden.
            $restrictedLogin = "dbatoolsci_mi_restricted_$(Get-Random)"
            $restrictedPass = "P@ssw0rd$(Get-Random)!"
            $server2022Plus = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle).VersionMajor -ge 16
            $dmvGrant = if ($server2022Plus) { "VIEW SERVER PERFORMANCE STATE" } else { "VIEW SERVER STATE" }
            $loginSetup = @"
USE [master];
CREATE LOGIN [$restrictedLogin] WITH PASSWORD = '$restrictedPass', CHECK_POLICY = OFF;
GRANT $dmvGrant TO [$restrictedLogin];
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query $loginSetup
            $null = New-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database $db -Login $restrictedLogin
            $restrictedSecure = ConvertTo-SecureString $restrictedPass -AsPlainText -Force
            $restrictedCred = New-Object System.Management.Automation.PSCredential($restrictedLogin, $restrictedSecure)

            # Generate a fresh suggestion so the DMV has a row for this table.
            $hiddenWorkload = "SELECT Amount FROM dbo.Orders WHERE CustomerId = 77 AND 1 = (SELECT 1);"
            1..5 | ForEach-Object { $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $db -Query $hiddenWorkload }

            $restricted = Find-DbaDbMissingIndex -SqlInstance $TestConfig.InstanceSingle -SqlCredential $restrictedCred -Database $db -MinimumImpact 0 -MinimumSeek 1 -WarningVariable warnMeta 3> $null
        }

        AfterAll {
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query "DROP LOGIN [$restrictedLogin];" -ErrorAction SilentlyContinue
        }

        It "Returns at least one row for the restricted login" {
            $restricted | Should -Not -BeNullOrEmpty
        }

        It "Withholds the CREATE statement (null, never an invalid 'ON .(...)')" {
            $hidden = $restricted | Select-Object -First 1
            $hidden.CreateStatement | Should -BeNullOrEmpty
            foreach ($r in $restricted) { $r.CreateStatement | Should -Not -Match "ON \s*\.\s*\(" }
        }

        It "Warns that object metadata is not visible" {
            $warnMeta | Should -Match "not visible to this login"
        }
    }

    # Azure SQL Database boundary. CI has no Azure SQL DB, so Get-TestConfig leaves AzureSqlDbServer
    # empty and this context skips; a lab that configures AzureSqlDbServer/Name/Cred runs it for real
    # (pattern from tests/CLAUDE.md, "The other boundary CI does not have"). The first It asserts the
    # engine, so pointed at anything but Azure SQL DB the whole context fails rather than passing
    # vacuously - every other engine simply takes the USE that Azure rejects with error 40508.
    Context "Azure SQL Database" -Skip:(-not $TestConfig.AzureSqlDbServer) {
        BeforeAll {
            $azCred = $TestConfig.AzureSqlDbCred
            $azServer = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $azCred -Database $TestConfig.AzureSqlDbName
            $azTable = "dbatoolsci_mi_$(Get-Random)"
            $azSetup = @"
CREATE TABLE dbo.[$azTable] (Id int IDENTITY(1,1) PRIMARY KEY, CustomerId int NOT NULL, Amount money NOT NULL, Filler char(200) NOT NULL DEFAULT 'x');
INSERT INTO dbo.[$azTable] (CustomerId, Amount)
SELECT TOP (20000) ABS(CHECKSUM(NEWID())) % 1000, ABS(CHECKSUM(NEWID())) % 10000
FROM sys.all_objects a CROSS JOIN sys.all_objects b;
"@
            $null = Invoke-DbaQuery -SqlInstance $azServer -Query $azSetup
            $azWorkload = "SELECT Amount FROM dbo.[$azTable] WHERE CustomerId = 42 AND 1 = (SELECT 1);"
            1..5 | ForEach-Object { $null = Invoke-DbaQuery -SqlInstance $azServer -Query $azWorkload }

            $azResults = Find-DbaDbMissingIndex -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $azCred -Database $TestConfig.AzureSqlDbName -MinimumImpact 0 -MinimumSeek 1 -WarningVariable azWarn 3> $null
        }

        AfterAll {
            if ($azServer) { $null = Invoke-DbaQuery -SqlInstance $azServer -Query "DROP TABLE IF EXISTS dbo.[$azTable];" -ErrorAction SilentlyContinue }
        }

        It "Is actually an Azure SQL Database" {
            $azServer.DatabaseEngineEdition | Should -Be "SqlDatabase"
        }

        It "Runs without hitting error 40508 (cross-database USE)" {
            $azWarn | Should -Not -Match "40508"
            $azWarn | Should -Not -Match "USE statement is not supported"
        }

        It "Returns a seeded suggestion on CustomerId" {
            ($azResults | Where-Object { $PSItem.EqualityColumns -match "CustomerId" }) | Should -Not -BeNullOrEmpty
        }
    }
}
