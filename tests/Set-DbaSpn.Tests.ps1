param($ModuleName = 'dbatools')

Describe "Set-DbaSpn" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaSpn
        }
        It "Should have SPN as a parameter" {
            $CommandUnderTest | Should -HaveParameter SPN
        }
        It "Should have ServiceAccount as a parameter" {
            $CommandUnderTest | Should -HaveParameter ServiceAccount
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have NoDelegation as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoDelegation
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        # Add your integration tests here
        # Example:
        # It "Should do something" {
        #     # Test code here
        # }
    }
}
