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
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $script:instance3 = [Environment]::GetEnvironmentVariable('instance3')
        }

        AfterAll {
            Enable-DbaAgHadr -SqlInstance $script:instance3 -Confirm:$false -Force
        }

        It "disables hadr" {
            $results = Disable-DbaAgHadr -SqlInstance $script:instance3 -Confirm:$false -Force
            $results.IsHadrEnabled | Should -Be $false
        }
    }
}
