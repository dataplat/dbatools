param($ModuleName = 'dbatools')

Describe "Add-DbaReplArticle" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Add-DbaReplArticle
        }

        It "has all the required parameters" {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Publication",
                "Schema",
                "Name",
                "Filter",
                "CreationScriptOptions",
                "EnableException",
                "WhatIf",
                "Confirm"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }
}

# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1
