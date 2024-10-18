param($ModuleName = 'dbatools')

Describe "Set-DbaCmConnection" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaCmConnection
        }
        It "Should have ComputerName parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type Dataplat.Dbatools.Parameter.DbaCmConnectionParameter[] -Mandatory:$false
        }
        It "Should have Credential parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have UseWindowsCredentials parameter" {
            $CommandUnderTest | Should -HaveParameter UseWindowsCredentials -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have OverrideExplicitCredential parameter" {
            $CommandUnderTest | Should -HaveParameter OverrideExplicitCredential -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have OverrideConnectionPolicy parameter" {
            $CommandUnderTest | Should -HaveParameter OverrideConnectionPolicy -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have DisabledConnectionTypes parameter" {
            $CommandUnderTest | Should -HaveParameter DisabledConnectionTypes -Type Dataplat.Dbatools.Connection.ManagementConnectionType -Mandatory:$false
        }
        It "Should have DisableBadCredentialCache parameter" {
            $CommandUnderTest | Should -HaveParameter DisableBadCredentialCache -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have DisableCimPersistence parameter" {
            $CommandUnderTest | Should -HaveParameter DisableCimPersistence -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have DisableCredentialAutoRegister parameter" {
            $CommandUnderTest | Should -HaveParameter DisableCredentialAutoRegister -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have EnableCredentialFailover parameter" {
            $CommandUnderTest | Should -HaveParameter EnableCredentialFailover -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have WindowsCredentialsAreBad parameter" {
            $CommandUnderTest | Should -HaveParameter WindowsCredentialsAreBad -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have CimWinRMOptions parameter" {
            $CommandUnderTest | Should -HaveParameter CimWinRMOptions -Type Microsoft.Management.Infrastructure.Options.WSManSessionOptions -Mandatory:$false
        }
        It "Should have CimDCOMOptions parameter" {
            $CommandUnderTest | Should -HaveParameter CimDCOMOptions -Type Microsoft.Management.Infrastructure.Options.DComSessionOptions -Mandatory:$false
        }
        It "Should have AddBadCredential parameter" {
            $CommandUnderTest | Should -HaveParameter AddBadCredential -Type System.Management.Automation.PSCredential[] -Mandatory:$false
        }
        It "Should have RemoveBadCredential parameter" {
            $CommandUnderTest | Should -HaveParameter RemoveBadCredential -Type System.Management.Automation.PSCredential[] -Mandatory:$false
        }
        It "Should have ClearBadCredential parameter" {
            $CommandUnderTest | Should -HaveParameter ClearBadCredential -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have ClearCredential parameter" {
            $CommandUnderTest | Should -HaveParameter ClearCredential -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have ResetCredential parameter" {
            $CommandUnderTest | Should -HaveParameter ResetCredential -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have ResetConnectionStatus parameter" {
            $CommandUnderTest | Should -HaveParameter ResetConnectionStatus -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have ResetConfiguration parameter" {
            $CommandUnderTest | Should -HaveParameter ResetConfiguration -Type System.Management.Automation.SwitchParameter -Mandatory:$false
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
