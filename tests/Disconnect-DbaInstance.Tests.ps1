param($ModuleName = 'dbatools')

Describe "Disconnect-DbaInstance" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Disconnect-DbaInstance
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
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

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $null = Connect-DbaInstance -SqlInstance $global:instance1
        }

        It "disconnects and returns some results" {
            $results = Get-DbaConnectedInstance | Disconnect-DbaInstance
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
