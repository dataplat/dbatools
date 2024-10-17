param($ModuleName = 'dbatools')

Describe "New-DbaServiceMasterKey" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaServiceMasterKey
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential
        }
        It "Should have SecurePassword as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecurePassword -Type SecureString
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
        It "Should have common parameters" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type Switch
            $CommandUnderTest | Should -HaveParameter Debug -Type Switch
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String
            $CommandUnderTest | Should -HaveParameter WhatIf -Type Switch
            $CommandUnderTest | Should -HaveParameter Confirm -Type Switch
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
