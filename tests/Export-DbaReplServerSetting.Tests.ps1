param($ModuleName = 'dbatools')

Describe "Export-DbaReplServerSetting" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        Add-ReplicationLibrary
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaReplServerSetting
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Path as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter Path -Type System.String -Mandatory:$false
        }
        It "Should have FilePath as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter FilePath -Type System.String -Mandatory:$false
        }
        It "Should have ScriptOption as a non-mandatory parameter of type System.Object[]" {
            $CommandUnderTest | Should -HaveParameter ScriptOption -Type System.Object[] -Mandatory:$false
        }
        It "Should have InputObject as a non-mandatory parameter of type System.Object[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type System.Object[] -Mandatory:$false
        }
        It "Should have Encoding as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter Encoding -Type System.String -Mandatory:$false
        }
        It "Should have Passthru as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Passthru -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have NoClobber as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoClobber -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have Append as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Append -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
    }
}

# Integration tests can be added below this line
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests for more guidance.
