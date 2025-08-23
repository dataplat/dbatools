#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbSpace",
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
                "IncludeSystemDBs",
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

        # Set variables. They are available in all the It blocks.
        $dbName = "dbatoolsci_test_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $null = $server.Query("Create Database [$dbName]")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }


    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbName

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }


    #Skipping these tests as internals of Get-DbaDbSpace seems to be unreliable in CI
    Context "Gets DbSpace" {
        BeforeAll {
            $allResults = @(Get-DbaDbSpace -SqlInstance $TestConfig.instance2 | Where-Object Database -eq $dbName)
        }

        It "Gets results" {
            $allResults | Should -Not -BeNullOrEmpty
        }

        It "Should retrieve space for $dbName" {
            $allResults[0].Database | Should -Be $dbName
            $allResults[0].UsedSpace | Should -Not -BeNullOrEmpty
        }

        It "Should have a physical path for $dbName" {
            $allResults[0].PhysicalName | Should -Not -BeNullOrEmpty
        }
    }

    #Skipping these tests as internals of Get-DbaDbSpace seems to be unreliable in CI
    Context "Gets DbSpace when using -Database" {
        BeforeAll {
            $databaseResults = @(Get-DbaDbSpace -SqlInstance $TestConfig.instance2 -Database $dbName)
        }

        It "Gets results" {
            $databaseResults | Should -Not -BeNullOrEmpty
        }

        It "Should retrieve space for $dbName" {
            $databaseResults[0].Database | Should -Be $dbName
            $databaseResults[0].UsedSpace | Should -Not -BeNullOrEmpty
        }

        It "Should have a physical path for $dbName" {
            $databaseResults[0].PhysicalName | Should -Not -BeNullOrEmpty
        }
    }

    Context "Gets no DbSpace for specific database when using -ExcludeDatabase" {
        It "Gets no results for excluded database" {
            $excludeResults = @(Get-DbaDbSpace -SqlInstance $TestConfig.instance2 -ExcludeDatabase $dbName)
            $excludeResults.Database | Should -Not -Contain $dbName
        }
    }
}