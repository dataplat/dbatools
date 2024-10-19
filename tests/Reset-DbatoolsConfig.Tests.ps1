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
        It "has all the required parameters" {
            $requiredParameters = @(
                "ConfigurationItem",
                "FullName",
                "Module",
                "Name",
                "EnableException",
                "WhatIf",
                "Confirm"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }
}

# Integration tests can be added here
# Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests for more guidance
