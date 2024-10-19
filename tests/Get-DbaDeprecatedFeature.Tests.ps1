param($ModuleName = 'dbatools')

Describe "Get-DbaDeprecatedFeature" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDeprecatedFeature
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Gets Deprecated Features" {
        BeforeAll {
            $results = Get-DbaDeprecatedFeature -SqlInstance $global:instance1
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
