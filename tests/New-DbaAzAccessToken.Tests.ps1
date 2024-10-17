param($ModuleName = 'dbatools')

Describe "New-DbaAzAccessToken" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaAzAccessToken
        }
        It "Should have Type as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type String -Not -Mandatory
        }
        It "Should have Subtype as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Subtype -Type String -Not -Mandatory
        }
        It "Should have Config as a non-mandatory Object parameter" {
            $CommandUnderTest | Should -HaveParameter Config -Type Object -Not -Mandatory
        }
        It "Should have Credential as a non-mandatory PSCredential parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Not -Mandatory
        }
        It "Should have Tenant as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Tenant -Type String -Not -Mandatory
        }
        It "Should have Thumbprint as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Thumbprint -Type String -Not -Mandatory
        }
        It "Should have Store as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Store -Type String -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
