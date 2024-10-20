$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        # fake tests, no parameters to validate
        It "Should only contain our specific parameters" {
            $null | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance1
    }
    Context "gets connected objects" {
        It "returns some results" {
            $results = Get-DbaConnectedInstance
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
