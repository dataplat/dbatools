param($ModuleName = 'dbatools')

Describe "Get-DbaPbmObjectSet" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPbmObjectSet
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have ObjectSet as a parameter" {
            $CommandUnderTest | Should -HaveParameter ObjectSet -Type System.String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type System.Management.Automation.PSObject[]
        }
        It "Should have IncludeSystemObject as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemObject -Type System.Management.Automation.SwitchParameter
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        # Add your integration tests here
        # Example:
        # It "Should return object sets" {
        #     $results = Get-DbaPbmObjectSet -SqlInstance $global:instance1
        #     $results | Should -Not -BeNullOrEmpty
        # }
    }
}
