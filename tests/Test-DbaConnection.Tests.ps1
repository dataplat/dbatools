$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 4
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Test-DbaConnection).Parameters.Keys
        $knownParameters = 'SqlInstance', 'Credential', 'SqlCredential', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Testing if command works" {

        $results = Test-DbaConnection -SqlInstance $script:instance1
        $whoami = whoami
        It "returns the correct port" {
            $results.TcpPort -eq 1433 | Should Be $true
        }

        It "returns the correct authtype" {
            $results.AuthType -eq 'Windows Authentication' | Should Be $true
        }

        It "returns the correct user" {
            $results.ConnectingAsUser -eq $whoami | Should Be $true
        }
    }
}