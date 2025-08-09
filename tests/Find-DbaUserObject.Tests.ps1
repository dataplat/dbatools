#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaUserObject",
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
                "Pattern",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command finds User Objects for SA" {
        BeforeAll {
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true
            $null = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name "dbatoolsci_userObject" -Owner "sa"
            $PSDefaultParameterValues.Remove('*-Dba*:EnableException')

            $results = Find-DbaUserObject -SqlInstance $TestConfig.instance2 -Pattern "sa"
        }

        AfterAll {
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database "dbatoolsci_userObject" -Confirm:$false
        }

        It "Should find a specific Database Owned by sa" {
            $results.Where( { $PSItem.name -eq "dbatoolsci_userobject" }).Type | Should -Be "Database"
        }

        It "Should find more than 10 objects Owned by sa" {
            $results.Count | Should -BeGreaterThan 10
        }
    }

    Context "Command finds User Objects" {
        BeforeAll {
            $results = Find-DbaUserObject -SqlInstance $TestConfig.instance2
        }

        It "Should find results" {
            $results | Should -Not -BeNull
        }
    }
}