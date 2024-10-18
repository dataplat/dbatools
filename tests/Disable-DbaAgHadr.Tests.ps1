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
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type System.Management.Automation.PSCredential
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type System.Management.Automation.SwitchParameter
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
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
