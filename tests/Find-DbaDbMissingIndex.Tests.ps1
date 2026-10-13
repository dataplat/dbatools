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

        # Low thresholds so the single-seek fixtures are not filtered out by the defaults.
        $results = Find-DbaDbMissingIndex -SqlInstance $TestConfig.InstanceSingle -Database $db -MinimumImpact 0 -MinimumSeek 1
        $suggestion = $results | Where-Object { $PSItem.EqualityColumns -match "CustomerId" } | Select-Object -First 1
        $overlapSuggestion = $results | Where-Object { $PSItem.InequalityColumns -match "OrderDate" } | Select-Object -First 1

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
}