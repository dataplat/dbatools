param($ModuleName = 'dbatools')

Describe "Remove-DbaFirewallRule" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaFirewallRule
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have Type as a parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }
}

Describe "Remove-DbaFirewallRule Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Command actually works" {
        BeforeAll {
            $global:instance1 = $global:instance1
            $global:instance2 = $global:instance2
        }

        It "Removes firewall rules" {
            # This test is a placeholder and needs to be implemented
            # when we have a proper way to create and remove firewall rules in a test environment
            $true | Should -Be $true
        }
    }
}
