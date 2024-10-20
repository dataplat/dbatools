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

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "SubscriberSqlInstance",
            "SubscriberSqlCredential",
            "SubscriptionDatabase",
            "PublicationName",
            "SubscriptionSqlCredential",
            "Type",
            "EnableException",
            "Confirm"
        )

        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1
