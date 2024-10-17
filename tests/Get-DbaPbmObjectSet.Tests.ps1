param($ModuleName = 'dbatools')

Describe "Get-DbaPbmObjectSet" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPbmObjectSet
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have ObjectSet as a parameter" {
            $CommandUnderTest | Should -HaveParameter ObjectSet -Type String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type PSObject[]
        }
        It "Should have IncludeSystemObject as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemObject -Type Switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
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
        #     $results = Get-DbaPbmObjectSet -SqlInstance $env:instance1
        #     $results | Should -Not -BeNullOrEmpty
        # }
    }
}
