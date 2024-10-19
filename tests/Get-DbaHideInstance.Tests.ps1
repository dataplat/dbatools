param($ModuleName = 'dbatools')

Describe "Get-DbaHideInstance" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaHideInstance
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeAll {
            $results = Get-DbaHideInstance -SqlInstance $global:instance1 -EnableException
        }

        It "returns true or false" {
            $results.HideInstance | Should -Not -BeNullOrEmpty
        }
    }
}
