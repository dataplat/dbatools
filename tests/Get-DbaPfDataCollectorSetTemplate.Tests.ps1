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

    Context "Output validation" {
        BeforeAll {
            $result = @(Get-DbaPfDataCollectorSetTemplate | Select-Object -First 1)
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected default display properties" {
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("Name", "Source", "UserAccount", "Description")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has the expected excluded properties available" {
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $excludedProps = @("File", "Path")
            foreach ($prop in $excludedProps) {
                $defaultProps | Should -Not -Contain $prop -Because "property '$prop' should be excluded from the default display set"
            }
            $result[0].psobject.Properties["Path"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["File"] | Should -Not -BeNullOrEmpty
        }
    }
}