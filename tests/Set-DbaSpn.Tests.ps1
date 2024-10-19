param($ModuleName = 'dbatools')

Describe "Set-DbaSpn" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaSpn
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SPN",
                "ServiceAccount",
                "Credential",
                "NoDelegation",
                "EnableException"
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

        # Add your integration tests here
        # Example:
        # It "Should do something" {
        #     # Test code here
        # }
    }
}
