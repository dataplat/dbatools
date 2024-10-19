param($ModuleName = 'dbatools')

Describe "Set-DbaAgListener" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaAgListener
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have AvailabilityGroup as a parameter" {
            $CommandUnderTest | Should -HaveParameter AvailabilityGroup
        }
        It "Should have Listener as a parameter" {
            $CommandUnderTest | Should -HaveParameter Listener
        }
        It "Should have Port as a parameter" {
            $CommandUnderTest | Should -HaveParameter Port
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
        It "Should have WhatIf as a parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf
        }
        It "Should have Confirm as a parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm
        }
    }
}
