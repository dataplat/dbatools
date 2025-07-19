#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Enable-DbaFilestream" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Enable-DbaFilestream
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "SqlInstance",
                "SqlCredential",
                "Credential",
                "FileStreamLevel",
                "ShareName",
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

Describe "Enable-DbaFilestream" -Tag "IntegrationTests" {
    BeforeAll {
        $global:OriginalFileStream = Get-DbaFilestream -SqlInstance $TestConfig.instance1
    }

    AfterAll {
        if ($global:OriginalFileStream.InstanceAccessLevel -eq 0) {
            Disable-DbaFilestream -SqlInstance $TestConfig.instance1 -Confirm:$false -WarningAction SilentlyContinue
        } else {
            Enable-DbaFilestream -SqlInstance $TestConfig.instance1 -FileStreamLevel $global:OriginalFileStream.InstanceAccessLevel -Confirm:$false -WarningAction SilentlyContinue
        }
    }

    Context "When changing FileStream Level" {
        BeforeAll {
            $NewLevel = ($global:OriginalFileStream.InstanceAccessLevel + 1) % 3 #Move it on one, but keep it less than 4 with modulo division
            $results = Enable-DbaFilestream -SqlInstance $TestConfig.instance1 -FileStreamLevel $NewLevel -Confirm:$false -WarningAction SilentlyContinue
        }

        It "Should change the FileStream Level to the new value" {
            $results.InstanceAccessLevel | Should -Be $NewLevel
        }
    }
}
