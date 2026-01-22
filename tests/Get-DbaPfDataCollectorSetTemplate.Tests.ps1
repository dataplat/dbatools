#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPfDataCollectorSetTemplate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "Pattern",
                "Template",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Verifying command returns all the required results" {
        BeforeAll {
            $allResults = @(Get-DbaPfDataCollectorSetTemplate)
            $templateResults = @(Get-DbaPfDataCollectorSetTemplate -Template "Long Running Queries")
        }

        It "Returns not null values for required fields" {
            foreach ($result in $allResults) {
                $result.Name | Should -Not -BeNullOrEmpty
                $result.Source | Should -Not -BeNullOrEmpty
                $result.Description | Should -Not -BeNullOrEmpty
            }
        }

        It "Returns only one (and the proper) template" {
            $templateResults.Name | Should -Be "Long Running Queries"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaPfDataCollectorSetTemplate -EnableException
        }

        It "Returns PSCustomObject" {
            $result[0].PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "Name",
                "Source",
                "UserAccount",
                "Description"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has additional properties accessible via Select-Object" {
            $result = Get-DbaPfDataCollectorSetTemplate -EnableException | Select-Object -First 1 *
            $result.PSObject.Properties.Name | Should -Contain "Path"
            $result.PSObject.Properties.Name | Should -Contain "File"
        }
    }
}