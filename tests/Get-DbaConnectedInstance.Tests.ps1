$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

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
        $null = Get-DbaDatabase -SqlInstance $script:instance1
    }
    Context "gets connected objects" {
        It "returns some results" {
            $results = Get-DbaConnectedInstance
            $results.Count | Should -BeGreaterThan 0
        }
    }
}