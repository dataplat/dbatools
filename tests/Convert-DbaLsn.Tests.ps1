#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Convert-DbaLSN" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Convert-DbaLSN
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "LSN",
                "EnableException"
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

    Context "Converts Numeric LSN to Hex" {
        BeforeAll {
            $LSN = '00000000020000000024300001'
            $result = Convert-DbaLSN -Lsn $LSN
        }

        It "Should convert to 00000014:000000f3:0001" {
            $result.Hexadecimal | Should -Be '00000014:000000f3:0001'
        }
    }

    Context "Converts Numeric LSN to Hex without leading 0s" {
        BeforeAll {
            $LSN = '20000000024300001'
            $result = Convert-DbaLSN -Lsn $LSN
        }

        It "Should convert to 00000014:000000f3:0001" {
            $result.Hexadecimal | Should -Be '00000014:000000f3:0001'
        }
    }

    Context "Converts Hex LSN to Numeric" {
        BeforeAll {
            $LSN = '00000014:000000f3:0001'
            $result = Convert-DbaLSN -Lsn $LSN
        }

        It "Should convert to 20000000024300001" {
            $result.Numeric | Should -Be 20000000024300001
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
