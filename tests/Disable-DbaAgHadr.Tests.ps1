#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Disable-DbaAgHadr" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Disable-DbaAgHadr
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

Describe "Disable-DbaAgHadr" -Tag "IntegrationTests" {
    AfterAll {
        Enable-DbaAgHadr -SqlInstance $TestConfig.instance3 -Confirm:$false -Force
    }

    Context "When disabling HADR" {
        BeforeAll {
            $results = Disable-DbaAgHadr -SqlInstance $TestConfig.instance3 -Confirm:$false -Force
        }

        It "Successfully disables HADR" {
            $results.IsHadrEnabled | Should -BeFalse
        }
    }
}
