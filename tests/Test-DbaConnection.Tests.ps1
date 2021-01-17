$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'Credential', 'SqlCredential', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
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