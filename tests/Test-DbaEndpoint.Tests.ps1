$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    It -Skip "returns success" {
        $results = Test-DbaEndpoint -SqlInstance $script:instance2, $script:instance1
        $results | Select-Object -First 1 -ExpandProperty Connection | Should -Be 'Success'
    }
}