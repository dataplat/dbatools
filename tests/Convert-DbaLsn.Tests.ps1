param($ModuleName = 'dbatools')

Describe "Convert-DbaLSN" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Convert-DbaLSN
        }
        $params = @(
            "LSN",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Converts Numeric LSN to Hex" {
        It "Should convert to 00000014:000000f3:0001" {
            $LSN = '00000000020000000024300001'
            $result = Convert-DbaLSN -Lsn $Lsn
            $result.Hexadecimal | Should -Be '00000014:000000f3:0001'
        }
    }

    Context "Converts Numeric LSN to Hex without leading 0s" {
        It "Should convert to 00000014:000000f3:0001" {
            $LSN = '20000000024300001'
            $result = Convert-DbaLSN -Lsn $Lsn
            $result.Hexadecimal | Should -Be '00000014:000000f3:0001'
        }
    }

    Context "Converts Hex LSN to Numeric" {
        It "Should convert to 20000000024300001" {
            $LSN = '00000014:000000f3:0001'
            $result = Convert-DbaLSN -Lsn $Lsn
            $result.Numeric | Should -Be 20000000024300001
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
