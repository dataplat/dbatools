#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaServerRole",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

<#
    The below statement stays in for every test you build.
#>
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

<#
    Unit test is required for any command added
#>
Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "ServerRole",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Set variables. They are available in all the It blocks.
        $testInstance = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $testRoleExecutor = "serverExecuter"
        $null = New-DbaServerRole -SqlInstance $testInstance -ServerRole $testRoleExecutor

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaServerRole -SqlInstance $testInstance -ServerRole $testRoleExecutor -Confirm:$false

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Command actually works" {
        It "It returns info about server-role removed" {
            $results = Remove-DbaServerRole -SqlInstance $testInstance -ServerRole $testRoleExecutor -Confirm:$false
            $results.ServerRole | Should -Be $testRoleExecutor
        }

        It "Should not return server-role" {
            $results = Get-DbaServerRole -SqlInstance $testInstance -ServerRole $testRoleExecutor
            $results | Should -Be $null
        }
    }
}
