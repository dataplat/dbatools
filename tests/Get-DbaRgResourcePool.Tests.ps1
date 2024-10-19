param($ModuleName = 'dbatools')

Describe "Get-DbaRgResourcePool" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRgResourcePool
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type ResourceGovernor[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaRgResourcePool -SqlInstance $global:instance2
        }
        It "Gets Results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Command actually works using -Type" {
        BeforeAll {
            $results = Get-DbaRgResourcePool -SqlInstance $global:instance2 -Type Internal
        }
        It "Gets Results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
