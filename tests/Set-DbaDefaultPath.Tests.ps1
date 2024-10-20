param($ModuleName = 'dbatools')

Describe "Set-DbaDefaultPath" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaDefaultPath
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Type",
            "Path",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $results = Set-DbaDefaultPath -SqlInstance $global:instance1 -Type Backup -Path C:\temp
        }
        It "Data returns a value that contains :\" {
            $results.Data | Should -Match "\:\\"
        }
        It "Log returns a value that contains :\" {
            $results.Log | Should -Match "\:\\"
        }
        It "Backup returns a value that contains :\" {
            $results.Backup | Should -Match "\:\\"
        }
        It "ErrorLog returns a value that contains :\" {
            $results.ErrorLog | Should -Match "\:\\"
        }
    }
}
