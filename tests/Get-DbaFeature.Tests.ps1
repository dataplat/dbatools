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
        It "returns a result with the right computername and name is not null" {
            $results = Get-DbaFeature -ComputerName ([DbaInstanceParameter]($TestConfig.InstanceSingle)).ComputerName | Select-Object -First 1
            $results.ComputerName | Should -Be ([DbaInstanceParameter]($TestConfig.InstanceSingle)).ComputerName
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaFeature -ComputerName ([DbaInstanceParameter]($TestConfig.InstanceSingle)).ComputerName -EnableException | Select-Object -First 1
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected output properties" {
            $expectedProps = @(
                "ComputerName",
                "Product",
                "Instance",
                "InstanceID",
                "Feature",
                "Language",
                "Edition",
                "Version",
                "Clustered",
                "Configured"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in output"
            }
        }
    }
}