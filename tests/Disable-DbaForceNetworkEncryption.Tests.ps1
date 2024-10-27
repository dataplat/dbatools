#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Disable-DbaForceNetworkEncryption" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Disable-DbaForceNetworkEncryption
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

Describe "Disable-DbaForceNetworkEncryption" -Tag "IntegrationTests" {
    Context "When disabling force network encryption" {
        BeforeAll {
            $results = Disable-DbaForceNetworkEncryption -SqlInstance $TestConfig.instance1 -EnableException
        }

        It "Returns results with ForceEncryption set to false" {
            $results.ForceEncryption | Should -BeFalse
        }
    }
}
