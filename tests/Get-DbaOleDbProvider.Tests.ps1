param($ModuleName = 'dbatools')

Describe "Get-DbaOleDbProvider" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaOleDbProvider
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Provider as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Provider
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        It "Returns output when executed against <_>" -ForEach $global:instance1, $global:instance2 {
            $result = Get-DbaOleDbProvider -SqlInstance $_
            $result | Should -Not -BeNullOrEmpty
        }
    }
}
