param($ModuleName = 'dbatools')

Describe "New-DbaAzAccessToken" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaAzAccessToken
        }
        It "Should have Type as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Type
        }
        It "Should have Subtype as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Subtype
        }
        It "Should have Config as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Config
        }
        It "Should have Credential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have Tenant as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Tenant
        }
        It "Should have Thumbprint as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Thumbprint
        }
        It "Should have Store as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Store
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
