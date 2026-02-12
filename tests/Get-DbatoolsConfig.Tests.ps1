#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbatoolsConfig",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "FullName",
                "Name",
                "Module",
                "Force"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When retrieving configuration values" {
        It "Should return a value that is an int" {
            $results = Get-DbatoolsConfig -FullName sql.connection.timeout
            $results.Value | Should -BeOfType [int]
        }

        It "Returns output of the documented type" {
            $results | Should -Not -BeNullOrEmpty
            $results[0].psobject.TypeNames | Should -Contain "Dataplat.Dbatools.Configuration.Config"
        }

        It "Has the expected properties" {
            $results[0].psobject.Properties.Name | Should -Contain "Module"
            $results[0].psobject.Properties.Name | Should -Contain "Name"
            $results[0].psobject.Properties.Name | Should -Contain "Value"
            $results[0].psobject.Properties.Name | Should -Contain "Description"
            $results[0].psobject.Properties.Name | Should -Contain "Hidden"
        }
    }
}