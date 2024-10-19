param($ModuleName = 'dbatools')

Describe "Clear-DbaLatchStatistics" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Clear-DbaLatchStatistics
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
