param($ModuleName = 'dbatools')

Describe "Get-DbaReplArticleColumn" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        Add-ReplicationLibrary
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaReplArticleColumn
        }
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Database as a non-mandatory parameter of type System.Object[]" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.Object[] -Mandatory:$false
        }
        It "Should have Publication as a non-mandatory parameter of type System.Object[]" {
            $CommandUnderTest | Should -HaveParameter Publication -Type System.Object[] -Mandatory:$false
        }
        It "Should have Article as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter Article -Type System.String[] -Mandatory:$false
        }
        It "Should have Column as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter Column -Type System.String[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }
}

# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1
