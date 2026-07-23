#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaReplSubscription",
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
                "SubscriberSqlInstance",
                "SubscriberSqlCredential",
                "SubscriptionDatabase",
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
    # NOTE ON COVERAGE: removing a subscription needs a configured publisher/publication and a live
    # subscription, which the GitHub Actions replication harness provides (gh-actions-repl-*) - the
    # live TransSubscription/MergeSubscription .Remove() leg is DEFERRED-TO-REPL-HARNESS. What IS
    # characterizable on a plain instance is the begin-block branch the source takes when the named
    # publication is not found: it connects, Get-DbaReplPublication returns nothing, and it warns
    # "Didn't find a subscription to the <publication> publication". -WhatIf is belt-and-braces so
    # the per-subscriber RMO removal is never reached even if a publication were found. Target is a
    # standalone instance with no replication configured.
    Context "Warning when the publication is not found" {
        It "Warns that no subscription was found and removes nothing" {
            $splatRemove = @{
                SqlInstance           = $TestConfig.InstanceMulti1
                Database              = "master"
                PublicationName       = "dbatoolsci_nopub"
                SubscriberSqlInstance = $TestConfig.InstanceMulti1
                SubscriptionDatabase  = "dbatoolsci_nosub"
                WarningVariable       = "subWarn"
                WarningAction         = "SilentlyContinue"
                WhatIf                = $true
            }
            $result = Remove-DbaReplSubscription @splatRemove
            $result | Should -BeNullOrEmpty
            ($subWarn -join "`n") | Should -Match "Didn't find a subscription to the dbatoolsci_nopub publication"
        }
    }
}