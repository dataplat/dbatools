#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbExtentDiff",
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
        $dbname = "dbatoolsci_test_$(Get-Random)"

        # Create the objects.
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $server.Query("Create Database [$dbname]")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created object.
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Gets Changed Extents for Multiple Databases" {
        BeforeAll {
            $multiDbResults = Get-DbaDbExtentDiff -SqlInstance $TestConfig.InstanceSingle
        }

        It "Gets results" {
            $multiDbResults | Should -Not -BeNullOrEmpty
        }

        It "Should have extents for each database" {
            foreach ($row in $multiDbResults) {
                $row.ExtentsTotal | Should -BeGreaterThan 0
            }
        }

        It "Should have extents changed for each database" {
            foreach ($row in $multiDbResults) {
                $row.ExtentsChanged | Should -BeGreaterOrEqual 0
            }
        }
    }

    Context "Gets Changed Extents for Single Database" {
        BeforeAll {
            $singleDbResults = Get-DbaDbExtentDiff -SqlInstance $TestConfig.InstanceSingle -Database $dbname
        }

        It "Gets results" {
            $singleDbResults | Should -Not -BeNullOrEmpty
        }

        It "Should have extents for $dbname" {
            $singleDbResults.ExtentsTotal | Should -BeGreaterThan 0
        }

        It "Should have extents changed for $dbname" {
            $singleDbResults.ExtentsChanged | Should -BeGreaterOrEqual 0
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outputResult = Get-DbaDbExtentDiff -SqlInstance $TestConfig.InstanceSingle -Database master
        }

        It "Returns output as PSCustomObject" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $outputResult | Should -Not -BeNullOrEmpty
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "DatabaseName",
                "ExtentsTotal",
                "ExtentsChanged",
                "ChangedPerc"
            )
            foreach ($prop in $expectedProperties) {
                $outputResult[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}