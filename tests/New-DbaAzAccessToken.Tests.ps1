param($ModuleName = 'dbatools')

Describe "New-DbaAzAccessToken" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaAzAccessToken
        }

        It "has all the required parameters" {
            $params = @(
                "Type",
                "Subtype",
                "Config",
                "Credential",
                "Tenant",
                "Thumbprint",
                "Store",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
