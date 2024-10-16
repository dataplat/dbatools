param($ModuleName = 'dbatools')

Describe "Clear-DbaWaitStatistics" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Clear-DbaWaitStatistics
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
        It "Should have Verbose as a parameter" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type SwitchParameter
        }
        It "Should have Debug as a parameter" {
            $CommandUnderTest | Should -HaveParameter Debug -Type SwitchParameter
        }
        It "Should have ErrorAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference
        }
        It "Should have WarningAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference
        }
        It "Should have InformationAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference
        }
        It "Should have ProgressAction as a parameter" {
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference
        }
        It "Should have ErrorVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String
        }
        It "Should have WarningVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String
        }
        It "Should have InformationVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String
        }
        It "Should have OutVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String
        }
        It "Should have OutBuffer as a parameter" {
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32
        }
        It "Should have PipelineVariable as a parameter" {
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String
        }
        It "Should have WhatIf as a parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf -Type SwitchParameter
        }
        It "Should have Confirm as a parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm -Type SwitchParameter
        }
    }

    Context "Command executes properly and returns proper info" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }
        BeforeAll {
            $results = Clear-DbaWaitStatistics -SqlInstance $script:instance1 -Confirm:$false
        }
        It "returns success" {
            $results.Status | Should -Be 'Success'
        }
    }
}
