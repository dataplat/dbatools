#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Enable-DbaHideInstance" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Enable-DbaHideInstance
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

Describe "Enable-DbaHideInstance" -Tag "IntegrationTests" {
    BeforeAll {
        $instance = $TestConfig.instance1
        $results = Enable-DbaHideInstance -SqlInstance $instance -EnableException
    }

    AfterAll {
        $null = Disable-DbaHideInstance -SqlInstance $instance
    }

    It "Returns an object with HideInstance property set to true" {
        $results | Should -Not -BeNullOrEmpty
        $results.HideInstance | Should -BeTrue
    }
}
