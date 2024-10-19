param($ModuleName = 'dbatools')

Describe "Test-DbaAgSpn" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaAgSpn
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Credential parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have AvailabilityGroup parameter" {
            $CommandUnderTest | Should -HaveParameter AvailabilityGroup
        }
        It "Should have Listener parameter" {
            $CommandUnderTest | Should -HaveParameter Listener
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    # Add more contexts and tests as needed for the specific functionality of Test-DbaAgSpn
}
