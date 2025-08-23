#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Install-DbaWhoIsActive",
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
                "LocalFile",
                "Database",
                "EnableException",
                "Force"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $dbName = "WhoIsActive-$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $dbName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbName

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Should install sp_WhoIsActive" {
        It "Should output correct results" {
            $installResults = Install-DbaWhoIsActive -SqlInstance $TestConfig.instance1 -Database $dbName
            $installResults.Database | Should -Be $dbName
            $installResults.Name | Should -Be "sp_WhoisActive"
            $installResults.Status | Should -Be "Installed"
        }
    }

    Context "Should update sp_WhoIsActive" {
        It "Should output correct results" {
            $updateResults = Install-DbaWhoIsActive -SqlInstance $TestConfig.instance1 -Database $dbName
            $updateResults.Database | Should -Be $dbName
            $updateResults.Name | Should -Be "sp_WhoisActive"
            $updateResults.Status | Should -Be "Updated"
        }
    }
}