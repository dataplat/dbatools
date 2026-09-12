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
Describe $CommandName -Tag IntegrationTests {
    Context "When the publisher cannot be reached" {
        BeforeAll {
            # Lower the connection timeout so the three failing connection attempts do not stretch
            # the test to a minute and a half.
            $oldConnectionTimeout = Get-DbatoolsConfigValue -FullName sql.connection.timeout
            $null = Set-DbatoolsConfig -FullName sql.connection.timeout -Value 2
        }

        AfterAll {
            $null = Set-DbatoolsConfig -FullName sql.connection.timeout -Value $oldConnectionTimeout
        }

        It "Warns without eating an iteration of the caller's loop" {
            # The connection guards in the begin block used to run Stop-Function -Continue without an
            # enclosing loop - the continue escaped the command and consumed an iteration of this very
            # loop, so the counter fell short (#10638). The publisher name does not resolve, so every
            # iteration fails at the connection attempt without touching any instance.
            $loopCount = 0
            foreach ($i in 1..3) {
                $splatUnreachable = @{
                    SqlInstance           = "dbatoolsci-nohost"
                    SubscriberSqlInstance = "dbatoolsci-nohost2"
                    Database              = "dbatoolsci_nope"
                    PublicationName       = "dbatoolsci_nope"
                    Type                  = "Push"
                    WarningAction         = "SilentlyContinue"
                }
                $null = New-DbaReplSubscription @splatUnreachable
                $loopCount++
            }
            $loopCount | Should -Be 3
            ($WarnVar -join " ") | Should -BeLike "*Error connecting*"
        }
    }
}

<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>