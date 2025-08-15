#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaConnectedInstance",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Validate parameters" {
        # fake tests, no parameters to validate
        It "Should only contain our specific parameters" {
            $null | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
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