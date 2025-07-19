#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Enable-DbaAgHadr" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Enable-DbaAgHadr
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "SqlInstance",
                "Credential",
                "Force",
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

Describe "Enable-DbaAgHadr" -Tag "IntegrationTests" {
    BeforeAll {
        Disable-DbaAgHadr -SqlInstance $TestConfig.instance3 -Confirm:$false -Force
    }

    Context "When enabling HADR" {
        BeforeAll {
            $results = Enable-DbaAgHadr -SqlInstance $TestConfig.instance3 -Confirm:$false -Force
        }

        It "Successfully enables HADR" {
            $results.IsHadrEnabled | Should -BeTrue
        }
    }
}
