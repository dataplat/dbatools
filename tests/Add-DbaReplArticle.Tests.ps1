#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaReplArticle",
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
                "Publication",
                "Schema",
                "Name",
                "Filter",
                "CreationScriptOptions",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When the filter includes WHERE" {
        It "Warns without eating an iteration of the caller's loop" {
            # The validation guards used to run Stop-Function -Continue before the instance loop -
            # the continue escaped the command and consumed an iteration of this very loop, so the
            # counter fell short (#10638). The guard fires before any connection is made, so the
            # instance name is never contacted.
            $loopCount = 0
            foreach ($i in 1..3) {
                $splatWhereFilter = @{
                    SqlInstance   = "dbatoolsci-nohost"
                    Database      = "dbatoolsci_nope"
                    Publication   = "dbatoolsci_nope"
                    Name          = "dbatoolsci_nope"
                    Filter        = "WHERE 1 = 1"
                    WarningAction = "SilentlyContinue"
                }
                $null = Add-DbaReplArticle @splatWhereFilter
                $loopCount++
            }
            $loopCount | Should -Be 3
            $WarnVar | Should -BeLike "*Filter should not include the word WHERE*"
        }
    }
}

<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>