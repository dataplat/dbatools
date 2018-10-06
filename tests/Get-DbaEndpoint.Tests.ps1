$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    It "gets some endpoints" {
        $results = Get-DbaEndpoint -SqlInstance $script:instance2
        $results.Count | Should -BeGreaterThan 1
        $results.Name | Should -Contain 'TSQL Default TCP'
    }
    It "gets one endpoint" {
        $results = Get-DbaEndpoint -SqlInstance $script:instance2 -Endpoint 'TSQL Default TCP'
        $results.Name | Should -Be 'TSQL Default TCP'
        $results.Count | Should -Be 1
    }
}