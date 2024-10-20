param($ModuleName = 'dbatools')

Describe "Copy-DbaXESession" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaXESession
        }

        $params = @(
            "Source",
            "Destination",
            "SourceSqlCredential",
            "DestinationSqlCredential",
            "XeSession",
            "ExcludeXeSession",
            "Force",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeAll {
            # Add any necessary setup code here
        }

        It "Example test" {
            # Add actual tests here
            $true | Should -Be $true
        }
    }
}

<#
    Integration tests should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>
