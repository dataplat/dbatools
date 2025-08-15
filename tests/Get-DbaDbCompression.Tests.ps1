#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbCompression",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
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
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $dbname = "dbatoolsci_test_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $null = $server.Query("Create Database [$dbname]")
        $null = $server.Query("select * into syscols from sys.all_columns
                                select * into sysallparams from sys.all_parameters
                                create clustered index CL_sysallparams on sysallparams (object_id)
                                create nonclustered index NC_syscols on syscols (precision) include (collation_name)", $dbname)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        Get-DbaProcess -SqlInstance $TestConfig.instance2 -Database $dbname | Stop-DbaProcess -WarningAction SilentlyContinue
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }
    Context "Command handles heaps and clustered indexes" {
        BeforeAll {
            $results = Get-DbaDbCompression -SqlInstance $TestConfig.instance2 -Database $dbname
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
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
            $ncResults = Get-DbaDbCompression -SqlInstance $TestConfig.instance2 -Database $dbname
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
        BeforeAll {
            $excludeResults = Get-DbaDbCompression -SqlInstance $TestConfig.instance2 -Database $dbname -ExcludeDatabase $dbname
        }

        It "Shouldn't get any results for $dbname" {
            $excludeResults.Database | Should -Not -Contain $dbname
        }
    }
}