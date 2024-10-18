param($ModuleName = 'dbatools')

Describe "New-DbaReplPublication" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        Add-ReplicationLibrary
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaReplPublication
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.String
        }
        It "Should have Name parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type System.String
        }
        It "Should have Type parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type System.String
        }
        It "Should have LogReaderAgentCredential parameter" {
            $CommandUnderTest | Should -HaveParameter LogReaderAgentCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }
}

# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1
