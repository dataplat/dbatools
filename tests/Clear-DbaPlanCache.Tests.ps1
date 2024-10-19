param($ModuleName = 'dbatools')

Describe "Clear-DbaPlanCache" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Clear-DbaPlanCache
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Mandatory:$false
        }
        It "Should have Threshold as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Threshold -Mandatory:$false
        }
        It "Should have InputObject as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Mandatory:$false
        }
    }

    Context "Functionality" {
        It "doesn't clear plan cache when threshold is high" {
            $results = Clear-DbaPlanCache -SqlInstance $global:instance1 -Threshold 10240
            $results.Size | Should -BeOfType [dbasize]
            $results.Status | Should -Match 'below'
        }

        It "supports piping" {
            $results = Get-DbaPlanCache -SqlInstance $global:instance1 | Clear-DbaPlanCache -Threshold 10240
            $results.Size | Should -BeOfType [dbasize]
            $results.Status | Should -Match 'below'
        }
    }
}
