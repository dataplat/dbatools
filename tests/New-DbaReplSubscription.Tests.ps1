param($ModuleName = 'dbatools')

Describe "New-DbaReplSubscription" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        Add-ReplicationLibrary
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaReplSubscription
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have SubscriberSqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SubscriberSqlInstance
        }
        It "Should have SubscriberSqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SubscriberSqlCredential
        }
        It "Should have SubscriptionDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter SubscriptionDatabase
        }
        It "Should have PublicationName parameter" {
            $CommandUnderTest | Should -HaveParameter PublicationName
        }
        It "Should have SubscriptionSqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SubscriptionSqlCredential
        }
        It "Should have Type parameter" {
            $CommandUnderTest | Should -HaveParameter Type
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
        It "Should have Confirm parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm
        }
    }
}

# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1
