param($ModuleName = 'dbatools')

Describe "Test-DbaDbCompatibility" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaDbCompatibility
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        It "Should return a result" {
            $results = Test-DbaDbCompatibility -SqlInstance $global:instance2
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return a result for a database" {
            $results = Test-DbaDbCompatibility -Database Master -SqlInstance $global:instance2
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return a result excluding one database" {
            $results = Test-DbaDbCompatibility -ExcludeDatabase Master -SqlInstance $global:instance2
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
