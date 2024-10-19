param($ModuleName = 'dbatools')

Describe "Enable-DbaAgHadr" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Enable-DbaAgHadr
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have Force as a parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $null = Disable-DbaAgHadr -SqlInstance $global:instance3 -Confirm:$false -Force
        }

        It "enables hadr" {
            $results = Enable-DbaAgHadr -SqlInstance $global:instance3 -Confirm:$false -Force
            $results.IsHadrEnabled | Should -Be $true
        }
    }
}
