param($ModuleName = 'dbatools')

Describe "Clear-DbaPlanCache" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Clear-DbaPlanCache
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Threshold as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter Threshold -Type Int32 -Not -Mandatory
        }
        It "Should have InputObject as a non-mandatory parameter of type Object[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[] -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
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
