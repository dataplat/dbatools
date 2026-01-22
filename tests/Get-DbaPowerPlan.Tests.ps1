#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPowerPlan",
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
                "List",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        It "Should return result for the server" {
            $results = Get-DbaPowerPlan -ComputerName $TestConfig.InstanceSingle
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaPowerPlan -ComputerName $TestConfig.InstanceSingle -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "PowerPlan"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the InstanceId property available" {
            $result.PSObject.Properties.Name | Should -Contain "InstanceId"
        }
    }

    Context "Output with -List" {
        BeforeAll {
            $result = Get-DbaPowerPlan -ComputerName $TestConfig.InstanceSingle -List -EnableException
        }

        It "Returns multiple power plans" {
            $result | Should -Not -BeNullOrEmpty
        }

        It "Includes IsActive property when -List specified" {
            $result[0].PSObject.Properties.Name | Should -Contain "IsActive"
        }

        It "Has the expected display properties with -List" {
            $expectedProps = @(
                "ComputerName",
                "PowerPlan",
                "IsActive"
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in display with -List"
            }
        }
    }
}