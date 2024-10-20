param($ModuleName = 'dbatools')

Describe "Convert-DbaLSN" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Convert-DbaLSN
        }
        $parms = @(
            'LSN',
            'EnableException'
        )
        It "Has required parameter: <_>" -ForEach $parms {
            $command | Should -HaveParameter $PSItem -Mandatory
        }
    }

    Context "Converts Numeric LSN to Hex" {
        It "Should convert '00000000020000000024300001' to '00000014:000000f3:0001'" {
            $result = Convert-DbaLSN -Lsn '00000000020000000024300001'
            $result.Hexadecimal | Should -Be '00000014:000000f3:0001'
        }
    }

    Context "Converts Numeric LSN to Hex without leading 0s" {
        It "Should convert '20000000024300001' to '00000014:000000f3:0001'" {
            $result = Convert-DbaLSN -Lsn '20000000024300001'
            $result.Hexadecimal | Should -Be '00000014:000000f3:0001'
        }
    }

    Context "Converts Hex LSN to Numeric" {
        It "Should convert '00000014:000000f3:0001' to 20000000024300001" {
            $result = Convert-DbaLSN -Lsn '00000014:000000f3:0001'
            $result.Numeric | Should -Be 20000000024300001
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
