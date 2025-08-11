#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaProductKey",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "SqlCredential",
                "Credential",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Gets ProductKey for SQL Server instances" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Get product key from the test instances
            $allResults = @()
            foreach ($instance in $TestConfig.Instances) {
                try {
                    $computerName = ($instance -split "\\|,")[0]
                    $result = Get-DbaProductKey -ComputerName $computerName
                    if ($result) {
                        $allResults += $result
                    }
                } catch {
                    # Some instances may not be accessible for product key retrieval
                    Write-Warning "Could not get product key for $instance`: $($_.Exception.Message)"
                }
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Gets results from at least one instance" {
            $allResults | Should -Not -BeNullOrEmpty
        }

        It "Should have Version for all results" {
            foreach ($result in $allResults) {
                $result.Version | Should -Not -BeNullOrEmpty
            }
        }

        It "Should have Edition for all results" {
            foreach ($result in $allResults) {
                $result.Edition | Should -Not -BeNullOrEmpty
            }
        }

        It "Should have Key for all results" {
            foreach ($result in $allResults) {
                $result.Key | Should -Not -BeNullOrEmpty
            }
        }
    }
}