param($ModuleName = 'dbatools')

Describe "Set-DbaCmConnection" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaCmConnection
        }
        It "Should have ComputerName parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have Credential parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have UseWindowsCredentials parameter" {
            $CommandUnderTest | Should -HaveParameter UseWindowsCredentials
        }
        It "Should have OverrideExplicitCredential parameter" {
            $CommandUnderTest | Should -HaveParameter OverrideExplicitCredential
        }
        It "Should have OverrideConnectionPolicy parameter" {
            $CommandUnderTest | Should -HaveParameter OverrideConnectionPolicy
        }
        It "Should have DisabledConnectionTypes parameter" {
            $CommandUnderTest | Should -HaveParameter DisabledConnectionTypes
        }
        It "Should have DisableBadCredentialCache parameter" {
            $CommandUnderTest | Should -HaveParameter DisableBadCredentialCache
        }
        It "Should have DisableCimPersistence parameter" {
            $CommandUnderTest | Should -HaveParameter DisableCimPersistence
        }
        It "Should have DisableCredentialAutoRegister parameter" {
            $CommandUnderTest | Should -HaveParameter DisableCredentialAutoRegister
        }
        It "Should have EnableCredentialFailover parameter" {
            $CommandUnderTest | Should -HaveParameter EnableCredentialFailover
        }
        It "Should have WindowsCredentialsAreBad parameter" {
            $CommandUnderTest | Should -HaveParameter WindowsCredentialsAreBad
        }
        It "Should have CimWinRMOptions parameter" {
            $CommandUnderTest | Should -HaveParameter CimWinRMOptions
        }
        It "Should have CimDCOMOptions parameter" {
            $CommandUnderTest | Should -HaveParameter CimDCOMOptions
        }
        It "Should have AddBadCredential parameter" {
            $CommandUnderTest | Should -HaveParameter AddBadCredential
        }
        It "Should have RemoveBadCredential parameter" {
            $CommandUnderTest | Should -HaveParameter RemoveBadCredential
        }
        It "Should have ClearBadCredential parameter" {
            $CommandUnderTest | Should -HaveParameter ClearBadCredential
        }
        It "Should have ClearCredential parameter" {
            $CommandUnderTest | Should -HaveParameter ClearCredential
        }
        It "Should have ResetCredential parameter" {
            $CommandUnderTest | Should -HaveParameter ResetCredential
        }
        It "Should have ResetConnectionStatus parameter" {
            $CommandUnderTest | Should -HaveParameter ResetConnectionStatus
        }
        It "Should have ResetConfiguration parameter" {
            $CommandUnderTest | Should -HaveParameter ResetConfiguration
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
