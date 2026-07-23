#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaReplSubscription",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "SubscriberSqlInstance",
                "SubscriberSqlCredential",
                "SubscriptionDatabase",
                "PublicationName",
                "SubscriptionSqlCredential",
                "Type",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: creating a subscription requires a configured publisher/distributor and a
    # live publication, which the GitHub Actions replication harness provides (gh-actions-repl-*) -
    # the live TransSubscription/MergeSubscription .Create() leg is DEFERRED-TO-GATE. The source
    # has no pre-connection guard: both mutating actions (creating the subscription database and
    # creating the subscription) are gated by ShouldProcess. What IS characterizable on a plain
    # instance is that -WhatIf routes through the module hop to the real cmdlet, so the connect and
    # publication lookup run, but neither the subscription database nor the subscription is created
    # and nothing is emitted. That leg exercises the hop, the live publisher connection, the
    # Get-DbaReplServer / Get-DbaReplPublication lookups, and the ShouldProcess wiring while
    # asserting the side effect did not happen. Target is a standalone instance not configured for
    # replication.
    Context "Honoring -WhatIf" {
        It "Skips the subscription-database creation and emits nothing under -WhatIf" {
            $splatSubscription = @{
                SqlInstance           = $TestConfig.InstanceMulti1
                Database              = "master"
                SubscriberSqlInstance = $TestConfig.InstanceMulti1
                SubscriptionDatabase  = "dbatoolsci_subwhatif"
                PublicationName       = "dbatoolsci_nopub"
                Type                  = "Push"
                WhatIf                = $true
            }
            $result = New-DbaReplSubscription @splatSubscription
            $result | Should -BeNullOrEmpty
            (Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database "dbatoolsci_subwhatif" -WarningAction SilentlyContinue) | Should -BeNullOrEmpty
        }
    }
}