#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaAgentJobCategory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Set up test category for the integration tests
        $null = New-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category "dbatoolsci test category"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created categories
        $null = Remove-DbaAgentJobCategory -SqlInstance $TestConfig.instance2 -Category "dbatoolsci test category" -Confirm:$false
        $null = Remove-DbaAgentJobCategory -SqlInstance $TestConfig.instance3 -Category "dbatoolsci test category" -Confirm:$false

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "CategoryType",
                "JobCategory",
                "AgentCategory",
                "OperatorCategory",
                "Force",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "When copying job categories" {
        It "Returns successful results" {
            $splatCopyCategory = @{
                Source      = $TestConfig.instance2
                Destination = $TestConfig.instance3
                JobCategory = "dbatoolsci test category"
            }

            $results = Copy-DbaAgentJobCategory @splatCopyCategory
            $results.Name | Should -Be "dbatoolsci test category"
            $results.Status | Should -Be "Successful"
        }

        It "Does not overwrite existing categories" {
            $splatSecondCopy = @{
                Source      = $TestConfig.instance2
                Destination = $TestConfig.instance3
                JobCategory = "dbatoolsci test category"
            }

            $secondCopyResults = Copy-DbaAgentJobCategory @splatSecondCopy
            $secondCopyResults.Name | Should -Be "dbatoolsci test category"
            $secondCopyResults.Status | Should -Be "Skipped"
        }
    }
}