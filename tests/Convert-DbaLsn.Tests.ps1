$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 2
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Convert-DbaLSN).Parameters.Keys
        $knownParameters = 'LSN', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }

    Context "Converts Numeric LSN to Hex" {
        $LSN = '00000000020000000024300001'
        It "Should convert to 00000014:000000f3:0001" {
            (Convert-DbaLSN -Lsn $Lsn).Hexadecimal | Should -Be '00000014:000000f3:0001'
        }
    }

    Context "Converts Numeric LSN to Hex without leading 0s" {
        $LSN = '20000000024300001'
        It "Should convert to 00000014:000000f3:0001" {
            (Convert-DbaLSN -Lsn $Lsn).Hexadecimal | Should -Be '00000014:000000f3:0001'
        }
    }

    Context "Converts Hex LSN to Numeric" {
        $LSN = '00000014:000000f3:0001'
        It "Should convert to 20000000024300001" {
            (Convert-DbaLSN -Lsn $Lsn).Numeric | Should -Be 20000000024300001
        }
    }


}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>