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

    Context "Output Validation" {
        BeforeAll {
            $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle
            $result = Get-DbaConnectedInstance | Select-Object -First 1
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'SqlInstance',
                'ConnectionType',
                'ConnectionObject',
                'Pooled'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the ConnectionString property available" {
            $result.PSObject.Properties.Name | Should -Contain 'ConnectionString' -Because "ConnectionString is available via Select-Object *"
        }
    }
}