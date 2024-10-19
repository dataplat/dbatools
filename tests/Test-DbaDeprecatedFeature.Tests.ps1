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
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command actually works" {
        It "Should return a result" {
            $results = Test-DbaDeprecatedFeature -SqlInstance $global:instance2
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should return a result for a database" {
            $results = Test-DbaDeprecatedFeature -SqlInstance $global:instance2 -Database Master
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
