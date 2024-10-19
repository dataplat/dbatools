param($ModuleName = 'dbatools')

Describe "Clear-DbaWaitStatistics" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Clear-DbaWaitStatistics
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
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }
        BeforeAll {
            $results = Clear-DbaWaitStatistics -SqlInstance $global:instance1
        }
        It "returns success" {
            $results.Status | Should -Be 'Success'
        }
    }
}
