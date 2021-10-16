$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'Credential', 'SqlCredential', 'SkipPSRemoting', 'EnableException'

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
            $results.TcpPort | Should Be 1433
        }

        It "returns the correct authtype" {
            $results.AuthType | Should Be 'Windows Authentication'
        }

        It "returns the correct user" {
            $results.ConnectingAsUser | Should Be $whoami
        }
    }
}