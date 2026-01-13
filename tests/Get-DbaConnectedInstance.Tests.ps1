#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaConnectedInstance",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        # fake tests, no parameters to validate
        It "Should have the expected parameters" {
            $null | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "gets connected objects" {
        It "returns some results" {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
            $results = Get-DbaConnectedInstance
            $results | Should -Not -BeNullOrEmpty
        }
    }
}