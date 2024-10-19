param($ModuleName = 'dbatools')

Describe "Disconnect-DbaInstance" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Disconnect-DbaInstance
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "InputObject",
                "EnableException",
                "WhatIf",
                "Confirm"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
