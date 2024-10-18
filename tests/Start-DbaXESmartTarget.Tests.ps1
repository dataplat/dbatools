param($ModuleName = 'dbatools')

Describe "Start-DbaXESmartTarget" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Start-DbaXESmartTarget
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.String -Mandatory:$false
        }
        It "Should have Session parameter" {
            $CommandUnderTest | Should -HaveParameter Session -Type System.String -Mandatory:$false
        }
        It "Should have FailOnProcessingError parameter" {
            $CommandUnderTest | Should -HaveParameter FailOnProcessingError -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have Responder parameter" {
            $CommandUnderTest | Should -HaveParameter Responder -Type System.Object[] -Mandatory:$false
        }
        It "Should have Template parameter" {
            $CommandUnderTest | Should -HaveParameter Template -Type System.String[] -Mandatory:$false
        }
        It "Should have NotAsJob parameter" {
            $CommandUnderTest | Should -HaveParameter NotAsJob -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
