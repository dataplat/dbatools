$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        $knownParameters = 'LSN', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
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