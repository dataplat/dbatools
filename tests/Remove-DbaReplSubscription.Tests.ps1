param($ModuleName = 'dbatools')

Describe "Remove-DbaReplSubscription" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        Add-ReplicationLibrary
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaReplSubscription
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String
        }
        It "Should have PublicationName parameter" {
            $CommandUnderTest | Should -HaveParameter PublicationName -Type String
        }
        It "Should have SubscriberSqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SubscriberSqlInstance -Type DbaInstanceParameter
        }
        It "Should have SubscriberSqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SubscriberSqlCredential -Type PSCredential
        }
        It "Should have SubscriptionDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter SubscriptionDatabase -Type String
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
        It "Should have WhatIf parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf -Type Switch
        }
        It "Should have Confirm parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm -Type Switch
        }
    }
}

# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1
