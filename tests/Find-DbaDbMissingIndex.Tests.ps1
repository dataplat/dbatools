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

        # Identifier-edge-case table: the key column name contains a space, and a distinct column name
        # differs only by an underscore (a LIKE wildcard). Overlap matching is by column_id, so the
        # index on [Order Date] must be flagged, and the index on [Customer_Id] must NOT be mistaken
        # for a suggestion on a [CustomerId]-style column. This is the regression for the LIKE fix.
        $edgeSetup = @"
CREATE TABLE dbo.Sales ([Sale Id] int IDENTITY(1,1) PRIMARY KEY, [Order Date] datetime2 NOT NULL, [Customer_Id] int NOT NULL, Note char(200) NOT NULL DEFAULT 'x');
CREATE NONCLUSTERED INDEX [IX_Sales_OrderDate] ON dbo.Sales ([Order Date]);
CREATE NONCLUSTERED INDEX [IX_Sales_CustomerId] ON dbo.Sales ([Customer_Id]);
INSERT INTO dbo.Sales ([Order Date], [Customer_Id])
SELECT TOP (20000) DATEADD(MINUTE, ABS(CHECKSUM(NEWID())) % 1000000, '2020-01-01'), ABS(CHECKSUM(NEWID())) % 1000
FROM sys.all_objects a CROSS JOIN sys.all_objects b;
"@
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $db -Query $edgeSetup

        $edgeWorkload = "SELECT Note FROM dbo.Sales WHERE [Order Date] > '2020-06-01' AND 1 = (SELECT 1);"
        1..5 | ForEach-Object { $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $db -Query $edgeWorkload }

        # Low thresholds so the single-seek fixtures are not filtered out by the defaults.
        $results = Find-DbaDbMissingIndex -SqlInstance $TestConfig.InstanceSingle -Database $db -MinimumImpact 0 -MinimumSeek 1
        $suggestion = $results | Where-Object { $PSItem.EqualityColumns -match "CustomerId" } | Select-Object -First 1
        $overlapSuggestion = $results | Where-Object { $PSItem.InequalityColumns -match "OrderDate" } | Select-Object -First 1
        $edgeSuggestion = $results | Where-Object { $PSItem.Table -eq "Sales" -and $PSItem.InequalityColumns -match "Order Date" } | Select-Object -First 1

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

        It "Does not falsely flag the [Customer_Id] index (underscore is a LIKE wildcard)" {
            # The suggestion is on [Order Date], so IX_Sales_CustomerId must NOT appear; column_id
            # matching makes the _ in [Customer_Id] a literal, not a wildcard.
            $edgeSuggestion.OverlappingIndex | Should -Not -Match "IX_Sales_CustomerId"
        }
    }

    Context "Honours an explicitly piped system database" {
        It "Processes msdb and warns when piped in explicitly" {
            # Get-DbaDatabase -Database msdb | Find-DbaDbMissingIndex: the downstream -Database is not
            # set in a pipeline, so the command must treat the piped object as an explicit selection
            # and process it (with a warning), not silently return nothing.
            $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database msdb |
                Find-DbaDbMissingIndex -MinimumImpact 0 -MinimumSeek 1 -WarningVariable warnSystem 3> $null
            $warnSystem | Should -Match "msdb"
            $warnSystem | Should -Match "piped in explicitly"
        }
    }

    Context "Withholds DDL for metadata-hidden objects" {
        BeforeAll {
            # A login with VIEW SERVER STATE (so it can read the missing-index DMVs) but no access to
            # the object metadata: OBJECT_NAME/OBJECT_SCHEMA_NAME return NULL, so a CREATE statement
            # would be malformed. The command must withhold the statement and warn instead.
            $restrictedLogin = "dbatoolsci_mi_restricted_$(Get-Random)"
            $restrictedPass = "P@ssw0rd$(Get-Random)!"
            $loginSetup = @"
USE [master];
CREATE LOGIN [$restrictedLogin] WITH PASSWORD = '$restrictedPass', CHECK_POLICY = OFF;
GRANT VIEW SERVER STATE TO [$restrictedLogin];
"@
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query $loginSetup
            $restrictedCred = [PSCredential]::new($restrictedLogin, (ConvertTo-SecureString $restrictedPass -AsPlainText -Force))
        }

        AfterAll {
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query "DROP LOGIN [$restrictedLogin];" -ErrorAction SilentlyContinue
        }

        It "Returns rows without a CREATE statement when object metadata is hidden" {
            # The restricted login has no user in $db and no object access, so any suggestion it can
            # see has NULL schema/table. Either it gets no rows (no access to the DB at all) or rows
            # with a null CreateStatement and a warning - never an invalid 'ON .(...)' statement.
            $restricted = Find-DbaDbMissingIndex -SqlInstance $TestConfig.InstanceSingle -SqlCredential $restrictedCred -Database $db -MinimumImpact 0 -MinimumSeek 1 -WarningVariable warnMeta 3> $null
            foreach ($r in $restricted) {
                $r.CreateStatement | Should -Not -Match "ON \s*\.\s*\("
            }
        }
    }
}
