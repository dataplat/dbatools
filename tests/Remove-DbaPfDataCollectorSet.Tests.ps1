#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaPfDataCollectorSet",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "CollectorSet",
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

        # Set up the data collector set for testing
        $null = Get-DbaPfDataCollectorSetTemplate -Template "Long Running Queries" | Import-DbaPfDataCollectorSetTemplate

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up any remaining data collector sets
        $null = Remove-DbaPfDataCollectorSet -CollectorSet "Long Running Queries" -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Verifying command return the proper results" {
        BeforeEach {
            # Ensure the data collector set exists before each test
            $existing = Get-DbaPfDataCollectorSet -CollectorSet "Long Running Queries" -ErrorAction SilentlyContinue
            if (-not $existing) {
                $null = Get-DbaPfDataCollectorSetTemplate -Template "Long Running Queries" | Import-DbaPfDataCollectorSetTemplate
            }
        }

        It "removes the data collector set" {
            $results = Get-DbaPfDataCollectorSet -CollectorSet "Long Running Queries" | Remove-DbaPfDataCollectorSet -Confirm:$false
            $results.Name | Should -Be "Long Running Queries"
            $results.Status | Should -Be "Removed"
        }

        It "returns a result" {
            $results = Get-DbaPfDataCollectorSet -CollectorSet "Long Running Queries"
            $results.Name | Should -Be "Long Running Queries"
        }

        It "returns no results" {
            $null = Remove-DbaPfDataCollectorSet -CollectorSet "Long Running Queries" -Confirm:$false
            $results = Get-DbaPfDataCollectorSet -CollectorSet "Long Running Queries"
            $results.Name | Should -Be $null
        }
    }
}