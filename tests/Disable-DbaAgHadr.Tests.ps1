param($ModuleName = 'dbatools')

Describe "Disable-DbaAgHadr" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Disable-DbaAgHadr
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        AfterAll {
            Enable-DbaAgHadr -SqlInstance $global:instance3 -Confirm:$false -Force
        }

        It "disables hadr" {
            $results = Disable-DbaAgHadr -SqlInstance $global:instance3 -Confirm:$false -Force
            $results.IsHadrEnabled | Should -Be $false
        }
    }
}
