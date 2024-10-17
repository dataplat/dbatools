param($ModuleName = 'dbatools')

Describe "Set-DbaCmConnection" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaCmConnection
        }
        It "Should have ComputerName parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaCmConnectionParameter[] -Not -Mandatory
        }
        It "Should have Credential parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Not -Mandatory
        }
        It "Should have UseWindowsCredentials parameter" {
            $CommandUnderTest | Should -HaveParameter UseWindowsCredentials -Type Switch -Not -Mandatory
        }
        It "Should have OverrideExplicitCredential parameter" {
            $CommandUnderTest | Should -HaveParameter OverrideExplicitCredential -Type Switch -Not -Mandatory
        }
        It "Should have OverrideConnectionPolicy parameter" {
            $CommandUnderTest | Should -HaveParameter OverrideConnectionPolicy -Type Switch -Not -Mandatory
        }
        It "Should have DisabledConnectionTypes parameter" {
            $CommandUnderTest | Should -HaveParameter DisabledConnectionTypes -Type ManagementConnectionType -Not -Mandatory
        }
        It "Should have DisableBadCredentialCache parameter" {
            $CommandUnderTest | Should -HaveParameter DisableBadCredentialCache -Type Switch -Not -Mandatory
        }
        It "Should have DisableCimPersistence parameter" {
            $CommandUnderTest | Should -HaveParameter DisableCimPersistence -Type Switch -Not -Mandatory
        }
        It "Should have DisableCredentialAutoRegister parameter" {
            $CommandUnderTest | Should -HaveParameter DisableCredentialAutoRegister -Type Switch -Not -Mandatory
        }
        It "Should have EnableCredentialFailover parameter" {
            $CommandUnderTest | Should -HaveParameter EnableCredentialFailover -Type Switch -Not -Mandatory
        }
        It "Should have WindowsCredentialsAreBad parameter" {
            $CommandUnderTest | Should -HaveParameter WindowsCredentialsAreBad -Type Switch -Not -Mandatory
        }
        It "Should have CimWinRMOptions parameter" {
            $CommandUnderTest | Should -HaveParameter CimWinRMOptions -Type WSManSessionOptions -Not -Mandatory
        }
        It "Should have CimDCOMOptions parameter" {
            $CommandUnderTest | Should -HaveParameter CimDCOMOptions -Type DComSessionOptions -Not -Mandatory
        }
        It "Should have AddBadCredential parameter" {
            $CommandUnderTest | Should -HaveParameter AddBadCredential -Type PSCredential[] -Not -Mandatory
        }
        It "Should have RemoveBadCredential parameter" {
            $CommandUnderTest | Should -HaveParameter RemoveBadCredential -Type PSCredential[] -Not -Mandatory
        }
        It "Should have ClearBadCredential parameter" {
            $CommandUnderTest | Should -HaveParameter ClearBadCredential -Type Switch -Not -Mandatory
        }
        It "Should have ClearCredential parameter" {
            $CommandUnderTest | Should -HaveParameter ClearCredential -Type Switch -Not -Mandatory
        }
        It "Should have ResetCredential parameter" {
            $CommandUnderTest | Should -HaveParameter ResetCredential -Type Switch -Not -Mandatory
        }
        It "Should have ResetConnectionStatus parameter" {
            $CommandUnderTest | Should -HaveParameter ResetConnectionStatus -Type Switch -Not -Mandatory
        }
        It "Should have ResetConfiguration parameter" {
            $CommandUnderTest | Should -HaveParameter ResetConfiguration -Type Switch -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
