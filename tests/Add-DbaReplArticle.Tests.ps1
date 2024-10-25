#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param($ModuleName = "dbatools")
$global:TestConfig = Get-TestConfig

Describe "Add-DbaReplArticle" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Add-DbaReplArticle
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
                "EnableException",
                "WhatIf",
                "Confirm"
            )
        }

        It "Has parameter: <_>" -ForEach $expectedParameters {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $command.Parameters.Keys | Should -BeNullOrEmpty
        }
    }
}

<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>
