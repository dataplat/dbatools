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
            $requiredParameters = @(
                "Type",
                "Subtype",
                "Config",
                "Credential",
                "Tenant",
                "Thumbprint",
                "Store",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
