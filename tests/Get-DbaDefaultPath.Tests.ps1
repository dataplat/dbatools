$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
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