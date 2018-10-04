$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        Get-DbaEndpoint -SqlInstance $script:instance2 -Endpoint 'TSQL Default TCP' | Start-DbaEndpoint
    }
    
    It "stops the endpoint" {
        $endpoint = Get-DbaEndpoint -SqlInstance $script:instance2 -Endpoint 'TSQL Default TCP'
        $results = $endpoint | Stop-DbaEndpoint -Confirm:$false
        $results.EndpointState | Should -Be 'Stopped'
    }
}