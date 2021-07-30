$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $null = Get-DbaDatabase -SqlInstance $script:instance1
    }
    Context "gets connected objects" {
        It "returns some results" {
            $results = Get-DbaConnectedInstance
            $results.Count | Should -BeGreaterThan 0
        }
    }
}