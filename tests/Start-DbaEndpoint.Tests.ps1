$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        Get-DbaEndpoint -SqlInstance $script:instance2 -Endpoint 'TSQL Default TCP' | Stop-DbaEndpoint
    }
    
    It "starts the endpoint" {
        $endpoint = Get-DbaEndpoint -SqlInstance $script:instance2 -Endpoint 'TSQL Default TCP'
        $results = $endpoint | Start-DbaEndpoint -Confirm:$false
        $results.EndpointState | Should -Be 'Started'
    }
}