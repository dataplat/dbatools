param($ModuleName = 'dbatools')

Describe "Reset-DbatoolsConfig" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Reset-DbatoolsConfig
        }
        It "Should have ConfigurationItem as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ConfigurationItem
        }
        It "Should have FullName as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter FullName
        }
        It "Should have Module as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Module
        }
        It "Should have Name as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Name
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
        It "Should have WhatIf as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf
        }
        It "Should have Confirm as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm
        }
    }
}

# Integration tests can be added here
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests for more guidance
