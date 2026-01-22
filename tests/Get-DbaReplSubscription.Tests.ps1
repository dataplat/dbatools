#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
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

    Context "Output Validation" {
        It "Has documentation for output type" {
            $commandHelp = Get-Help $CommandName
            $commandHelp.returnValues.returnValue.type.name | Should -Contain "Microsoft.SqlServer.Replication.Subscription"
        }

        It "Has expected default display properties documented" {
            $commandHelp = Get-Help $CommandName -Full
            $outputSection = $commandHelp.returnValues.returnValue.description.text
            $outputSection | Should -BeLikeExactly "*ComputerName*"
            $outputSection | Should -BeLikeExactly "*InstanceName*"
            $outputSection | Should -BeLikeExactly "*SqlInstance*"
            $outputSection | Should -BeLikeExactly "*DatabaseName*"
            $outputSection | Should -BeLikeExactly "*PublicationName*"
            $outputSection | Should -BeLikeExactly "*Name*"
            $outputSection | Should -BeLikeExactly "*SubscriberName*"
            $outputSection | Should -BeLikeExactly "*SubscriptionDBName*"
            $outputSection | Should -BeLikeExactly "*SubscriptionType*"
        }
    }
}
<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>