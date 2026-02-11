#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbCompression",
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

        $dbname = "dbatoolsci_test_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $null = $server.Query("Create Database [$dbname]")
        $null = $server.Query("select * into syscols from sys.all_columns
                                select * into sysallparams from sys.all_parameters
                                create clustered index CL_sysallparams on sysallparams (object_id)
                                create nonclustered index NC_syscols on syscols (precision) include (collation_name)", $dbname)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Stop-DbaProcess -WarningAction SilentlyContinue
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    Context "Command handles heaps and clustered indexes" {
        BeforeAll {
            $results = Get-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbname
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
            $results.Database | Get-Unique | Should -Be $dbname
            $results.DatabaseId | Get-Unique | Should -Be $server.Query("SELECT database_id FROM sys.databases WHERE name = '$dbname'").database_id
        }
        It "Should return compression level for heaps and clustered indexes" {
            $heapAndClusteredResults = $results | Where-Object { $PSItem.IndexId -le 1 }
            foreach ($row in $heapAndClusteredResults) {
                $row.DataCompression | Should -BeIn @("None", "Row", "Page")
            }
        }
    }
    Context "Command handles nonclustered indexes" {
        BeforeAll {
            $ncResults = Get-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbname
        }

        It "Gets results" {
            $ncResults | Should -Not -BeNullOrEmpty
        }

        It "Should return compression level for nonclustered indexes" {
            $nonclustered = $ncResults | Where-Object { $PSItem.IndexId -gt 1 }
            foreach ($row in $nonclustered) {
                $row.DataCompression | Should -BeIn @("None", "Row", "Page")
            }
        }
    }

    Context "Command excludes results for specified database" {
        It "Shouldn't get any results for $dbname" {
            $excludeResults = Get-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbname -ExcludeDatabase $dbname
            $excludeResults.Database | Should -Not -Contain $dbname
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Get-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbname
        }

        It "Returns output of the expected type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "DatabaseId",
                "Schema",
                "TableName",
                "IndexName",
                "Partition",
                "IndexID",
                "IndexType",
                "DataCompression",
                "SizeCurrent",
                "RowCount"
            )
            foreach ($prop in $expectedProperties) {
                $result[0].PSObject.Properties[$prop].Name | Should -Be $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}