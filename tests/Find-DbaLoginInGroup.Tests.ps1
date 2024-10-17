param($ModuleName = 'dbatools')

Describe "Find-DbaLoginInGroup" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaLoginInGroup
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Login as a parameter" {
            $CommandUnderTest | Should -HaveParameter Login -Type String[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
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
