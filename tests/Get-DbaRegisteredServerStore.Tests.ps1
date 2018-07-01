$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Components are properly retreived" {
        It "Should return the right values" {
            $results = Get-DbaRegisteredServerStore -SqlInstance $script:instance2
            $results.InstanceName | Should -Not -Be $null
            $results.DisplayName | Should -Be "Central Management Servers"
        }
    }
}