param($ModuleName = 'dbatools')

Describe "Get-DbaInstanceUserOption" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaInstanceUserOption
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Gets UserOptions for the Instance" {
        BeforeAll {
            $results = Get-DbaInstanceUserOption -SqlInstance $global:instance2 | Where-Object {$_.name -eq 'AnsiNullDefaultOff'}
        }
        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should return AnsiNullDefaultOff UserOption" {
            $results.Name | Should -Be 'AnsiNullDefaultOff'
        }
        It "Should be set to false" {
            $results.Value | Should -BeFalse
        }
    }
}
