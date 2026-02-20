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
        BeforeAll {
            $script:outputForValidation = Get-DbatoolsConfig -FullName sql.connection.timeout
        }

        It "Should return a value that is an int" {
            $script:outputForValidation.Value | Should -BeOfType [int]
        }

        It "Returns output of the documented type" {
            $script:outputForValidation | Should -Not -BeNullOrEmpty
            $script:outputForValidation[0].psobject.TypeNames | Should -Contain "Dataplat.Dbatools.Configuration.Config"
        }

        It "Has the expected properties" {
            $script:outputForValidation[0].psobject.Properties.Name | Should -Contain "Module"
            $script:outputForValidation[0].psobject.Properties.Name | Should -Contain "Name"
            $script:outputForValidation[0].psobject.Properties.Name | Should -Contain "Value"
            $script:outputForValidation[0].psobject.Properties.Name | Should -Contain "Description"
            $script:outputForValidation[0].psobject.Properties.Name | Should -Contain "Hidden"
        }
    }
}