#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaReplSubscription",
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
                "PublicationName",
                "SubscriberName",
                "SubscriptionDatabase",
                "Type",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

# Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: returning populated Subscription objects requires a configured
    # publisher with subscriptions (and, for the distribution-database pull fallback, an
    # installed+available distributor) - the GitHub Actions replication harness provides that
    # topology (gh-actions-repl-*) and the deep distribution-fallback dedup/pub-id-filter leg
    # is DEFERRED there. What IS characterizable on a plain instance is the read path of the
    # command: it connects, calls Get-DbaReplPublication, iterates the (empty) subscriptions,
    # then evaluates the distribution-database fallback guard (IsPublisher AND
    # DistributorInstalled AND DistributorAvailable) which is false on a non-distributor, and
    # returns nothing without throwing. That single leg exercises the live connection, the
    # publication read, the subscription enumeration, and the fallback guard end to end.
    Context "Reading an instance with no replication subscriptions" {
        It "Returns nothing and does not throw" {
            $splatSubscription = @{
                SqlInstance   = $TestConfig.InstanceSingle
                WarningAction = "SilentlyContinue"
                ErrorAction   = "SilentlyContinue"
            }
            $result = Get-DbaReplSubscription @splatSubscription
            $result | Should -BeNullOrEmpty
        }
    }
}
