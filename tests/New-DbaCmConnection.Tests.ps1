param($ModuleName = 'dbatools')

Describe "New-DbaCmConnection" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaCmConnection
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have UseWindowsCredentials as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter UseWindowsCredentials
        }
        It "Should have OverrideExplicitCredential as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter OverrideExplicitCredential
        }
        It "Should have DisabledConnectionTypes as a parameter" {
            $CommandUnderTest | Should -HaveParameter DisabledConnectionTypes
        }
        It "Should have DisableBadCredentialCache as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DisableBadCredentialCache
        }
        It "Should have DisableCimPersistence as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DisableCimPersistence
        }
        It "Should have DisableCredentialAutoRegister as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DisableCredentialAutoRegister
        }
        It "Should have EnableCredentialFailover as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableCredentialFailover
        }
        It "Should have WindowsCredentialsAreBad as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter WindowsCredentialsAreBad
        }
        It "Should have CimWinRMOptions as a parameter" {
            $CommandUnderTest | Should -HaveParameter CimWinRMOptions
        }
        It "Should have CimDCOMOptions as a parameter" {
            $CommandUnderTest | Should -HaveParameter CimDCOMOptions
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

# Integration tests can be added below this line
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests for more guidance
