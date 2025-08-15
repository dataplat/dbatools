#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaPfDataCollectorSetTemplate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "CollectorSet",
                "Path",
                "FilePath",
                "InputObject",
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

        # Set up collector set for testing
        $null = Get-DbaPfDataCollectorSetTemplate -Template "Long Running Queries" | Import-DbaPfDataCollectorSetTemplate

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup
        $null = Get-DbaPfDataCollectorSet -CollectorSet "Long Running Queries" | Remove-DbaPfDataCollectorSet -Confirm:$false

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Verifying command returns all the required results" {
        It "returns a file system object using piped input" {
            $results = Get-DbaPfDataCollectorSet -CollectorSet "Long Running Queries" | Export-DbaPfDataCollectorSetTemplate
            $results.BaseName | Should -Be "Long Running Queries"
        }

        It "returns a file system object using direct parameter" {
            $results = Export-DbaPfDataCollectorSetTemplate -CollectorSet "Long Running Queries"
            $results.BaseName | Should -Be "Long Running Queries"
        }
    }
}