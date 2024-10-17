param($ModuleName = 'dbatools')

Describe "Test-DbaDeprecatedFeature" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        . "$PSScriptRoot\..\public\Test-DbaDeprecatedFeature.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaDeprecatedFeature
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Command actually works" {
        It "Should return a result" {
            $results = Test-DbaDeprecatedFeature -SqlInstance $script:instance2
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return a result for a database" {
            $results = Test-DbaDeprecatedFeature -SqlInstance $script:instance2 -Database Master
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
