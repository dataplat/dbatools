#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbAssembly",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Name",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When getting database assemblies" {
        BeforeAll {
            $assemblyResults = Get-DbaDbAssembly -SqlInstance $TestConfig.instance2 | Where-Object { $PSItem.parent.name -eq "master" }
            $masterDatabase = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database master
        }

        It "Returns assembly objects" {
            $assemblyResults | Should -Not -BeNullOrEmpty
            $assemblyResults.DatabaseId | Should -BeExactly $masterDatabase.Id
        }

        It "Has the correct assembly name" {
            $assemblyResults.name | Should -BeExactly "Microsoft.SqlServer.Types"
        }

        It "Has the correct owner" {
            $assemblyResults.owner | Should -BeExactly "sys"
        }

        It "Has a version matching the instance" {
            $assemblyResults.Version | Should -BeExactly $masterDatabase.assemblies.Version
        }
    }
}