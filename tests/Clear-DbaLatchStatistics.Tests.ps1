param($ModuleName = 'dbatools')

Describe "Clear-DbaLatchStatistics" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Clear-DbaLatchStatistics
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "EnableException",
                "WhatIf",
                "Confirm"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command executes properly and returns proper info" {
        BeforeDiscovery {
            . "$PSScriptRoot\constants.ps1"
        }
        BeforeAll {
            $results = Clear-DbaLatchStatistics -SqlInstance $global:instance1 -Confirm:$false
        }
        It "returns success" {
            $results.Status | Should -Be 'Success'
        }
    }
}
