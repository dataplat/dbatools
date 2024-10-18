param($ModuleName = 'dbatools')

Describe "Remove-DbaReplPublication" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        Add-ReplicationLibrary
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaReplPublication
        }
        It "Should have SqlInstance as a mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory
        }
        It "Should have SqlCredential as an optional parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Database as an optional parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.String[]
        }
        It "Should have Name as an optional parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type System.String[]
        }
        It "Should have InputObject as an optional parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Replication.Publication[]
        }
        It "Should have EnableException as an optional parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }
}

# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1
