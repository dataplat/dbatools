param($ModuleName = 'dbatools')

Describe "Get-DbaExtendedProtection" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaExtendedProtection
        }

        $params = @(
            "SqlInstance",
            "Credential",
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
            $results = Get-DbaExtendedProtection -SqlInstance $global:instance1 -EnableException
        }

        It "returns a value" {
            $results.ExtendedProtection | Should -Not -BeNullOrEmpty
        }
    }
}
