param($ModuleName = 'dbatools')

Describe "Disable-DbaHideInstance" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Disable-DbaHideInstance
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

    Context "Integration Tests" {
        BeforeAll {
            $results = Disable-DbaHideInstance -SqlInstance $global:instance1 -EnableException
        }

        It "Returns false for HideInstance" {
            $results.HideInstance | Should -Be $false
        }
    }
}
