param($ModuleName = 'dbatools')

Describe "New-DbaCmConnection" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaCmConnection
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaCmConnectionParameter[]
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have UseWindowsCredentials as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter UseWindowsCredentials -Type switch
        }
        It "Should have OverrideExplicitCredential as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter OverrideExplicitCredential -Type switch
        }
        It "Should have DisabledConnectionTypes as a parameter" {
            $CommandUnderTest | Should -HaveParameter DisabledConnectionTypes -Type Dataplat.Dbatools.Connection.ManagementConnectionType
        }
        It "Should have DisableBadCredentialCache as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DisableBadCredentialCache -Type switch
        }
        It "Should have DisableCimPersistence as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DisableCimPersistence -Type switch
        }
        It "Should have DisableCredentialAutoRegister as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DisableCredentialAutoRegister -Type switch
        }
        It "Should have EnableCredentialFailover as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableCredentialFailover -Type switch
        }
        It "Should have WindowsCredentialsAreBad as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter WindowsCredentialsAreBad -Type switch
        }
        It "Should have CimWinRMOptions as a parameter" {
            $CommandUnderTest | Should -HaveParameter CimWinRMOptions -Type WSManSessionOptions
        }
        It "Should have CimDCOMOptions as a parameter" {
            $CommandUnderTest | Should -HaveParameter CimDCOMOptions -Type DComSessionOptions
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch
        }
    }
}

# Integration tests can be added below this line
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests for more guidance
