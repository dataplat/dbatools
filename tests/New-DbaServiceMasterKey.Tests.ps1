param($ModuleName = 'dbatools')

Describe "New-DbaServiceMasterKey" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaServiceMasterKey
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Credential",
            "SecurePassword",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
