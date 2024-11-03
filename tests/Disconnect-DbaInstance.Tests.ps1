#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Disconnect-DbaInstance" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Disconnect-DbaInstance
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "InputObject",
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

Describe "Disconnect-DbaInstance" -Tag "IntegrationTests" {
    BeforeAll {
        $null = Connect-DbaInstance -SqlInstance $TestConfig.Instance1
    }

    Context "When disconnecting a server" {
        BeforeAll {
            $results = Get-DbaConnectedInstance | Disconnect-DbaInstance
        }

        It "Returns results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
