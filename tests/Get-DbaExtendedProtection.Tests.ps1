param($ModuleName = 'dbatools')

Describe "Get-DbaExtendedProtection" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaExtendedProtection
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "Credential",
                "EnableException",
                "WhatIf",
                "Confirm"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
