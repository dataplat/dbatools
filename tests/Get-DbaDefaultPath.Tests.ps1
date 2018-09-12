$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    Context "returns proper information" {
        $results = Get-DbaDefaultPath -SqlInstance $script:instance1
        It "Data returns a value that contains :\" {
            $results.Data -match "\:\\"
        }
        It "Log returns a value that contains :\" {
            $results.Log -match "\:\\"
        }
        It "Backup returns a value that contains :\" {
            $results.Backup -match "\:\\"
        }
        It "ErrorLog returns a value that contains :\" {
            $results.ErrorLog -match "\:\\"
        }
    }
}