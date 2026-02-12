#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Enable-DbaHideInstance",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $testInstance = $TestConfig.InstanceSingle
        $results = Enable-DbaHideInstance -SqlInstance $testInstance

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Disable-DbaHideInstance -SqlInstance $testInstance -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "Returns an object with HideInstance property set to true" {
        $results | Should -Not -BeNullOrEmpty
        $results.HideInstance | Should -BeTrue
    }

    It "Returns output of the documented type" {
        $results | Should -Not -BeNullOrEmpty
        $results[0] | Should -BeOfType PSCustomObject
    }

    It "Has the expected properties" {
        $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "HideInstance")
        foreach ($prop in $expectedProps) {
            $results[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
        }
    }
}