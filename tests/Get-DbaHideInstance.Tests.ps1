#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaHideInstance",
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
        $hideInstanceResults = Get-DbaHideInstance -SqlInstance $TestConfig.InstanceSingle
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "Returns true or false" {
        $hideInstanceResults.HideInstance | Should -Not -BeNullOrEmpty
    }

    It "Returns output of the expected type" {
        if (-not $hideInstanceResults) { Set-ItResult -Skipped -Because "no result to validate" }
        $hideInstanceResults[0] | Should -BeOfType PSCustomObject
    }

    It "Has the expected properties" {
        if (-not $hideInstanceResults) { Set-ItResult -Skipped -Because "no result to validate" }
        $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "HideInstance")
        foreach ($prop in $expectedProperties) {
            $hideInstanceResults[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
        }
    }
}