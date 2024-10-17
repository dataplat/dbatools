param($ModuleName = 'dbatools')

Describe "Get-DbaReplSubscription" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        Add-ReplicationLibrary
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaReplSubscription
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[]
        }
        It "Should have PublicationName as a parameter" {
            $CommandUnderTest | Should -HaveParameter PublicationName -Type String[]
        }
        It "Should have SubscriberName as a parameter" {
            $CommandUnderTest | Should -HaveParameter SubscriberName -Type DbaInstanceParameter[]
        }
        It "Should have SubscriptionDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter SubscriptionDatabase -Type Object[]
        }
        It "Should have Type as a parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type Object[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }
}

# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1
