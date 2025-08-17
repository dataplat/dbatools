#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaConnectedInstance",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        # fake tests, no parameters to validate
        It "Should only contain our specific parameters" {
            $null | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "gets connected objects" {
        It "returns some results" {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.instance1
            $results = Get-DbaConnectedInstance
            $results | Should -Not -BeNullOrEmpty
        }
    }
}