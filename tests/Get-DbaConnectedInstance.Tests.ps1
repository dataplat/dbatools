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
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
            $script:connectedInstanceResults = Get-DbaConnectedInstance
        }

        It "returns some results" {
            $script:connectedInstanceResults | Should -Not -BeNullOrEmpty
        }

        It "Returns output of the documented type" {
            $script:connectedInstanceResults | Should -Not -BeNullOrEmpty
            $script:connectedInstanceResults[0].psobject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $script:connectedInstanceResults | Should -Not -BeNullOrEmpty
            $defaultProps = $script:connectedInstanceResults[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "SqlInstance",
                "ConnectionType",
                "ConnectionObject",
                "Pooled"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}