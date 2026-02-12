#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaFeature",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Verifying command works" {
        BeforeAll {
            $results = Get-DbaFeature -ComputerName ([DbaInstanceParameter]($TestConfig.InstanceSingle)).ComputerName
        }

        It "returns a result with the right computername and name is not null" {
            $firstResult = $results | Select-Object -First 1
            $firstResult.ComputerName | Should -Be ([DbaInstanceParameter]($TestConfig.InstanceSingle)).ComputerName
        }

        It "Returns output of the documented type" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $results[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProps = @("ComputerName", "Product", "Instance", "InstanceID", "Feature", "Language", "Edition", "Version", "Clustered", "Configured")
            foreach ($prop in $expectedProps) {
                $results[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}