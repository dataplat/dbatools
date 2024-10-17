param($ModuleName = 'dbatools')

Describe "Test-DbaDbCompatibility" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaDbCompatibility
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        It "Should return a result" {
            $results = Test-DbaDbCompatibility -SqlInstance $script:instance2
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return a result for a database" {
            $results = Test-DbaDbCompatibility -Database Master -SqlInstance $script:instance2
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return a result excluding one database" {
            $results = Test-DbaDbCompatibility -ExcludeDatabase Master -SqlInstance $script:instance2
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
