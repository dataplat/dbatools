$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'EndPoint', 'AllEndpoints', 'InputObject', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        Get-DbaEndpoint -SqlInstance $script:instance2 -Endpoint 'TSQL Default TCP' | Stop-DbaEndpoint -Confirm:$false
    }

    It "starts the endpoint" {
        $endpoint = Get-DbaEndpoint -SqlInstance $script:instance2 -Endpoint 'TSQL Default TCP'
        $results = $endpoint | Start-DbaEndpoint -Confirm:$false
        $results.EndpointState | Should -Be 'Started'
    }
}