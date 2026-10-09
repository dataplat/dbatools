#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Find-DbaDbMissingIndex" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeDiscovery {
            [object[]]$knownParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "InputObject",
                "MinimumImpact",
                "MinimumSeek",
                "EnableException"
            )
        }

        It "Has parameter: <_>" -ForEach $knownParameters {
            (Get-Command Find-DbaDbMissingIndex).Parameters.Keys | Should -Contain $PSItem
        }

        It "Should have exactly the expected parameters" {
            $hasParams = (Get-Command Find-DbaDbMissingIndex).Parameters.Values.Name
            $commonParameters = [System.Management.Automation.PSCmdlet]::CommonParameters
            $comparison = Compare-Object -ReferenceObject $knownParameters -DifferenceObject ($hasParams | Where-Object { $PSItem -notin $commonParameters })
            $comparison | Should -BeNullOrEmpty
        }
    }
}

Describe "Find-DbaDbMissingIndex" -Tag "IntegrationTests" {
    BeforeAll {
        $db = "dbatoolsci_missingindex_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $null = $server.Query("CREATE DATABASE [$db]")

        # 20k rows, clustered PK only, so a non-trivial query produces a missing-index suggestion.
        # A trivial plan never generates one, so the predicate is forced to full optimization
        # with AND 1 = (SELECT 1), per the behavior confirmed in the maintainer's lab.
        $setup = @"
USE [$db];
CREATE TABLE dbo.Orders (OrderId int IDENTITY(1,1) PRIMARY KEY, CustomerId int, Amount money, Filler char(200) DEFAULT 'x');
INSERT INTO dbo.Orders (CustomerId, Amount)
SELECT TOP (20000) ABS(CHECKSUM(NEWID())) % 1000, ABS(CHECKSUM(NEWID())) % 10000
FROM sys.all_objects a CROSS JOIN sys.all_objects b;
"@
        $null = $server.Query($setup)

        $runWorkload = "USE [$db]; SELECT OrderId, Amount FROM dbo.Orders WHERE CustomerId = 42 AND 1 = (SELECT 1);"
        1..5 | ForEach-Object { $null = $server.Query($runWorkload) }
    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $db -Confirm:$false
    }

    Context "Finds a seeded missing index" {
        BeforeAll {
            # Low thresholds so the single-seek fixture is not filtered out by the defaults.
            $results = Find-DbaDbMissingIndex -SqlInstance $TestConfig.instance2 -Database $db -MinimumImpact 0 -MinimumSeek 1
        }

        It "Returns at least one suggestion" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Suggests an index keyed on CustomerId" {
            ($results | Where-Object { $PSItem.EqualityColumns -match "CustomerId" }) | Should -Not -BeNullOrEmpty
        }

        It "Generates a CREATE NONCLUSTERED INDEX statement" {
            $results[0].CreateStatement | Should -Match "CREATE NONCLUSTERED INDEX"
        }

        It "Returns the impact-score inputs as properties" {
            $results[0].PSObject.Properties.Name | Should -Contain "AvgTotalUserCost"
            $results[0].PSObject.Properties.Name | Should -Contain "AvgUserImpact"
            $results[0].PSObject.Properties.Name | Should -Contain "ImpactScore"
        }
    }
}
