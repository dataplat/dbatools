#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbMasterKey",
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
                "ExcludeDatabase",
                "All",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $dbName = "dbatoolsci_removemasterkey_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbName
        $masterKeyPassword = ConvertTo-SecureString -String "dbatools.IO" -AsPlainText -Force
        $null = New-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database $dbName -SecurePassword $masterKeyPassword

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When removing a master key" {
        BeforeAll {
            $results = Remove-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database $dbName
        }

        It "Returns one result" {
            # Counts the output itself, $results.Status would skip a $null written by the command
            @($results).Count | Should -Be 1
            $results.Database | Should -Be $dbName
            $results.Status | Should -Be "Master key removed"
        }

        It "Removes the master key" {
            (Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName).MasterKey | Should -BeNullOrEmpty
        }
    }
}