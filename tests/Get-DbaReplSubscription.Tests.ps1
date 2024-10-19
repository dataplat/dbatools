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
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have PublicationName as a parameter" {
            $CommandUnderTest | Should -HaveParameter PublicationName
        }
        It "Should have SubscriberName as a parameter" {
            $CommandUnderTest | Should -HaveParameter SubscriberName
        }
        It "Should have SubscriptionDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter SubscriptionDatabase
        }
        It "Should have Type as a parameter" {
            $CommandUnderTest | Should -HaveParameter Type
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1
