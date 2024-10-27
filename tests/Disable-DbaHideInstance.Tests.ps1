#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Disable-DbaHideInstance" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Disable-DbaHideInstance
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "SqlInstance",
                "Credential",
                "EnableException",
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Disable-DbaHideInstance" -Tag "IntegrationTests" {
    Context "When disabling hide instance" {
        BeforeAll {
            $results = Disable-DbaHideInstance -SqlInstance $TestConfig.instance1 -EnableException
        }

        It "Returns result with HideInstance set to false" {
            $results.HideInstance | Should -BeFalse
        }
    }
}
