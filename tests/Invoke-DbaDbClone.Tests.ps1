#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbClone",
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
                "InputObject",
                "CloneDatabase",
                "ExcludeStatistics",
                "ExcludeQueryStore",
                "UpdateStatistics",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command functions as expected" {
        BeforeAll {
            $dbname = "dbatoolsci_clonetest"
            $clonedb = "dbatoolsci_clonetest_CLONE"
            $clonedb2 = "dbatoolsci_clonetest_CLONE2"

            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $server.Query("CREATE DATABASE $dbname")
        }

        AfterAll {
            Get-DbaDatabase -SqlInstance $server -Database $dbname, $clonedb, $clonedb2 | Remove-DbaDatabase
        }

        It "warns if destination database already exists" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.InstanceSingle -Database $dbname -CloneDatabase tempdb -WarningAction SilentlyContinue
            $WarnVar | Should -Match "exists"
        }

        It "warns if a system db is specified to clone" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.InstanceSingle -Database master -CloneDatabase $clonedb -WarningAction SilentlyContinue
            $WarnVar | Should -Match "user database"
        }

        It "returns 1 result" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.InstanceSingle -Database $dbname -CloneDatabase $clonedb
            $WarnVar | Should -BeNullOrEmpty
            $results | Should -HaveCount 1
            $results.Name | Should -Be $clonedb
        }
    }

    Context "Database names that need quoting" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # A quote and a closing bracket break a name that is not escaped, and the omega is missing from the code
            # page of the usual collations, so a name that is not passed as Unicode loses it.
            $random = Get-Random
            $omega = [char]0x03A9
            $quotedDbName = "dbatoolsci_clone'source]$($omega)_$random"
            $quotedCloneName = "dbatoolsci_clone'target]$($omega)_$random"
            $quotedServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $null = $quotedServer.Query("CREATE DATABASE [$($quotedDbName.Replace("]", "]]"))]")

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Matched by the random suffix, so that a clone created under a mangled name is removed as well.
            $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -like "dbatoolsci_clone*_$random" | Remove-DbaDatabase

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "clones a database whose name and clone name need quoting" {
            $results = Invoke-DbaDbClone -SqlInstance $TestConfig.InstanceSingle -Database $quotedDbName -CloneDatabase $quotedCloneName
            $WarnVar | Should -BeNullOrEmpty
            @($results).Count | Should -Be 1
            $results.Name | Should -BeExactly $quotedCloneName
        }
    }

    Context "Column store statistics" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $columnstoreDbName = "dbatoolsci_clonecs_$(Get-Random)"
            $columnstoreCloneName = "$($columnstoreDbName)_clone"
            $columnstoreServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $null = New-DbaDatabase -SqlInstance $columnstoreServer -Name $columnstoreDbName

            # Less than 102400 rows are not compressed, so they stay in the delta store.
            $createQuery = @"
CREATE TABLE dbo.cci (id INT NOT NULL, v INT NOT NULL);
CREATE CLUSTERED COLUMNSTORE INDEX cci_idx ON dbo.cci;
INSERT dbo.cci SELECT TOP (1000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), 1 FROM sys.all_columns AS a CROSS JOIN sys.all_columns AS b;
"@
            $splatCreate = @{
                SqlInstance = $columnstoreServer
                Database    = $columnstoreDbName
                Query       = $createQuery
            }
            $null = Invoke-DbaQuery @splatCreate

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $columnstoreDbName, $columnstoreCloneName -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "leaves the row count of the source intact with -UpdateStatistics" {
            if ($columnstoreServer.VersionMajor -lt 15) {
                Set-ItResult -Skipped -Because "the statistics are written back to the source before SQL Server 2019"
            }

            $splatClone = @{
                SqlInstance      = $TestConfig.InstanceSingle
                Database         = $columnstoreDbName
                CloneDatabase    = $columnstoreCloneName
                UpdateStatistics = $true
            }
            $results = Invoke-DbaDbClone @splatClone
            $WarnVar | Should -BeNullOrEmpty
            $results.Name | Should -Be $columnstoreCloneName

            $rowCountQuery = @"
SELECT SUM(row_count) AS TableRows
FROM sys.dm_db_partition_stats
WHERE object_id = OBJECT_ID(N'dbo.cci') AND index_id IN (0, 1)
"@
            $splatRowCount = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $columnstoreDbName
                Query       = $rowCountQuery
            }
            (Invoke-DbaQuery @splatRowCount).TableRows | Should -Be 1000

            # DBCC CLONEDATABASE captures the statistics of the column store index for the clone itself.
            $statsQuery = @"
SELECT sp.last_updated AS LastUpdated
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS sp
WHERE s.object_id = OBJECT_ID(N'dbo.cci') AND s.name = N'cci_idx'
"@
            $splatStats = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $columnstoreCloneName
                Query       = $statsQuery
            }
            (Invoke-DbaQuery @splatStats).LastUpdated | Should -Not -BeNullOrEmpty
        }
    }
}