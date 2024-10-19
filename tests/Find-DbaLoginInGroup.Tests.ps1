param($ModuleName = 'dbatools')

Describe "Find-DbaLoginInGroup" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaLoginInGroup
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Login",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }
}

# Integration tests
Describe "Find-DbaLoginInGroup Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        # Add any necessary setup code here
    }

    Context "Command executes properly" {
        It "Should execute without throwing" {
            { Find-DbaLoginInGroup -SqlInstance $global:instance1 } | Should -Not -Throw
        }
    }

    # Add more integration tests as needed
}
