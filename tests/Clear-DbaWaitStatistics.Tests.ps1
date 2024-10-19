param($ModuleName = 'dbatools')

Describe "Clear-DbaWaitStatistics" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Clear-DbaWaitStatistics
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
        It "Should have WhatIf as a parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf
        }
        It "Should have Confirm as a parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm
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
