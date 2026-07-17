#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Set-DbaDbCompression",
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
                "Table",
                "View",
                "CompressionType",
                "MaxRunTime",
                "PercentCompression",
                "ForceOfflineRebuilds",
                "SortInTempDB",
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

        $dbName = "dbatoolsci_test_$(Get-Random)"
        $indexedViewName = "dbatoolsci_syscolview"
        $indexedViewIndexName = "CL_dbatoolsci_syscolview"
        $selectionTableName = "dbatoolsci_customer"
        $selectionViewName = "dbatoolsci_customer_view"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $null = $server.Query("Create Database [$dbName]")
        $null = $server.Query("select * into syscols from sys.all_columns
                                select * into sysallparams from sys.all_parameters
                                create clustered index CL_sysallparams on sysallparams (object_id)
                                create nonclustered index NC_syscols on syscols (precision) include (collation_name)", $dbName)
        $null = $server.Query("SET ANSI_NULLS ON;
                               SET QUOTED_IDENTIFIER ON;
                               EXEC sys.sp_executesql N'CREATE VIEW dbo.[$indexedViewName]
                               WITH SCHEMABINDING
                               AS
                               SELECT object_id, column_id
                               FROM dbo.syscols'", $dbName)
        $null = $server.Query("SET ANSI_NULLS ON;
                               SET ANSI_PADDING ON;
                               SET ANSI_WARNINGS ON;
                               SET ARITHABORT ON;
                               SET CONCAT_NULL_YIELDS_NULL ON;
                               SET QUOTED_IDENTIFIER ON;
                               SET NUMERIC_ROUNDABORT OFF;
                               CREATE UNIQUE CLUSTERED INDEX [$indexedViewIndexName] ON dbo.[$indexedViewName] (object_id, column_id)", $dbName)
        $null = $server.Query("CREATE SCHEMA sales", $dbName)
        $null = $server.Query("CREATE TABLE dbo.[$selectionTableName] (CustomerId int NOT NULL);
                               CREATE UNIQUE CLUSTERED INDEX [CL_dbo_$selectionTableName] ON dbo.[$selectionTableName] (CustomerId);
                               CREATE TABLE sales.[$selectionTableName] (CustomerId int NOT NULL);
                               CREATE UNIQUE CLUSTERED INDEX [CL_sales_$selectionTableName] ON sales.[$selectionTableName] (CustomerId);", $dbName)
        $null = $server.Query("SET ANSI_NULLS ON;
                               SET QUOTED_IDENTIFIER ON;
                               EXEC sys.sp_executesql N'CREATE VIEW dbo.[$selectionViewName]
                               WITH SCHEMABINDING
                               AS
                               SELECT CustomerId
                               FROM dbo.[$selectionTableName]';
                               EXEC sys.sp_executesql N'CREATE VIEW sales.[$selectionViewName]
                               WITH SCHEMABINDING
                               AS
                               SELECT CustomerId
                               FROM sales.[$selectionTableName]'", $dbName)
        $null = $server.Query("SET ANSI_NULLS ON;
                               SET ANSI_PADDING ON;
                               SET ANSI_WARNINGS ON;
                               SET ARITHABORT ON;
                               SET CONCAT_NULL_YIELDS_NULL ON;
                               SET QUOTED_IDENTIFIER ON;
                               SET NUMERIC_ROUNDABORT OFF;
                               CREATE UNIQUE CLUSTERED INDEX [CL_dbo_$selectionViewName] ON dbo.[$selectionViewName] (CustomerId);
                               CREATE UNIQUE CLUSTERED INDEX [CL_sales_$selectionViewName] ON sales.[$selectionViewName] (CustomerId);", $dbName)

        # Get InputObject for testing
        $inputObject = Test-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Database $dbName | Stop-DbaProcess -WarningAction SilentlyContinue
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Table and indexed-view selection" {
        It "processes only the requested schema-qualified table" {
            $splatTableCompression = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $dbName
                Table           = "sales.$selectionTableName"
                CompressionType = "Row"
            }
            $results = @(Set-DbaDbCompression @splatTableCompression)

            $results | Should -HaveCount 1
            $results.Schema | Should -Be "sales"
            $results.TableName | Should -Be $selectionTableName
        }

        It "processes only the requested schema-qualified indexed view" {
            $splatViewCompression = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $dbName
                View            = "sales.$selectionViewName"
                CompressionType = "Row"
            }
            $results = @(Set-DbaDbCompression @splatViewCompression)

            $results | Should -HaveCount 1
            $results.Schema | Should -Be "sales"
            $results.TableName | Should -Be $selectionViewName
        }

        It "requires an explicit compression type for indexed views" {
            $splatRecommendedView = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $dbName
                View            = "sales.$selectionViewName"
                EnableException = $true
            }
            {
                Set-DbaDbCompression @splatRecommendedView
            } | Should -Throw "*explicit CompressionType*"
        }
    }

    Context "Command gets results" {
        BeforeAll {
            $results = Set-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName -MaxRunTime 5 -PercentCompression 0
        }

        It "Should contain objects" {
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Command handles heaps and clustered indexes" {
        BeforeAll {
            $results = Set-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName -MaxRunTime 5 -PercentCompression 0
            $heapsAndClustered = $results | Where-Object IndexId -le 1
        }

        It "Should process heap and clustered index objects" {
            foreach ($row in $heapsAndClustered) {
                $row.AlreadyProcessed | Should -Be $true
            }
        }
    }

    Context "Command handles nonclustered indexes" {
        BeforeAll {
            $results = Set-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName -MaxRunTime 5 -PercentCompression 0
            $nonClusteredIndexes = $results | Where-Object IndexId -gt 1
        }

        It "Should process nonclustered index objects" {
            foreach ($row in $nonClusteredIndexes) {
                $row.AlreadyProcessed | Should -Be $true
            }
        }
    }

    Context "Command excludes results for specified database" {
        BeforeAll {
            $server.Databases[$dbName].Tables["syscols"].PhysicalPartitions[0].DataCompression = "NONE"
            $server.Databases[$dbName].Tables["syscols"].Rebuild()
            $excludeResults = Set-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName -ExcludeDatabase $dbName -MaxRunTime 5 -PercentCompression 0
        }

        It "Shouldn't get any results for excluded database" {
            $excludeResults.Database | Should -Not -Match $dbName
        }
    }

    Context "Command can accept InputObject from Test-DbaDbCompression" {
        BeforeAll {
            $inputObjectResults = @(Set-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName -MaxRunTime 5 -PercentCompression 0 -InputObject $inputObject)
        }

        It "Should get results from InputObject" {
            $inputObjectResults | Should -Not -BeNullOrEmpty
        }

        It "Should process all objects from InputObject" {
            foreach ($row in $inputObjectResults) {
                $row.AlreadyProcessed | Should -Be $true
            }
        }
    }

    Context "Command sets compression to Row all objects" {
        BeforeAll {
            $null = Set-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName -CompressionType Row
            $rowResults = Get-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName
        }

        It "Should set all objects to Row compression" {
            foreach ($row in $rowResults) {
                $row.DataCompression | Should -Be "Row"
            }
        }
    }

    Context "Command sets compression to Page for all objects" {
        BeforeAll {
            $null = Set-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName -CompressionType Page
            $pageResults = Get-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName
        }

        It "Should set all objects to Page compression" {
            foreach ($row in $pageResults) {
                $row.DataCompression | Should -Be "Page"
            }
        }
    }

    Context "Command sets compression to None for all objects" {
        BeforeAll {
            $null = Set-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName -CompressionType None
            $noneResults = Get-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName
        }

        It "Should set all objects to no compression" {
            foreach ($row in $noneResults) {
                $row.DataCompression | Should -Be "None"
            }
        }
    }

    Context "Command returns indexed view metadata when rebuilding to None" {
        BeforeAll {
            $null = Set-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName -CompressionType Page
            $indexedViewResults = Set-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbName -CompressionType None |
                Where-Object IndexName -eq $indexedViewIndexName
        }

        It "Should return the indexed view schema and name" {
            $indexedViewResults | Should -Not -BeNullOrEmpty
            foreach ($row in $indexedViewResults) {
                $row.Schema | Should -Be "dbo"
                $row.TableName | Should -Be $indexedViewName
            }
        }
    }
}
