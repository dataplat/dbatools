param($ModuleName = 'dbatools')

Describe "Save-DbaCommunitySoftware" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Save-DbaCommunitySoftware
        }

        It "has all the required parameters" {
            $params = @(
                "Software",
                "Branch",
                "LocalFile",
                "Url",
                "LocalDirectory",
                "EnableException",
                "WhatIf",
                "Confirm"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    # Add more contexts and tests as needed
}
