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
        It "Should have Verbose parameter" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type Switch
        }
        It "Should have Debug parameter" {
            $CommandUnderTest | Should -HaveParameter Debug -Type Switch
        }
        It "Should have ErrorAction parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference
        }
        It "Should have WarningAction parameter" {
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference
        }
        It "Should have InformationAction parameter" {
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference
        }
        It "Should have ProgressAction parameter" {
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference
        }
        It "Should have ErrorVariable parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String
        }
        It "Should have WarningVariable parameter" {
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String
        }
        It "Should have InformationVariable parameter" {
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String
        }
        It "Should have OutVariable parameter" {
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String
        }
        It "Should have OutBuffer parameter" {
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32
        }
        It "Should have PipelineVariable parameter" {
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String
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
