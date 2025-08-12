#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbSchema",
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
                "Schema",
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

        $random = Get-Random
        $server1 = Connect-DbaInstance -SqlInstance $TestConfig.instance1
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $null = Get-DbaProcess -SqlInstance $server1, $server2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
        $newDbName = "dbatoolsci_newdb_$random"
        $newDbs = New-DbaDatabase -SqlInstance $server1, $server2 -Name $newDbName

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = $newDbs | Remove-DbaDatabase -Confirm:$false

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When removing database schemas" {

        It "Should drop the schema" {
            $schema = New-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema TestSchema1
            $schema.Status.Count | Should -Be 1
            $schema.Name | Should -Be TestSchema1
            $schema.Parent.Name | Should -Be $newDbName

            Remove-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema TestSchema1 -Confirm:$false

            (Get-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema TestSchema1) | Should -BeNullOrEmpty

            $schemas = New-DbaDbSchema -SqlInstance $server1, $server2 -Database $newDbName -Schema TestSchema2, TestSchema3
            $schemas.Status.Count | Should -Be 4
            $schemas.Name | Should -Be TestSchema2, TestSchema3, TestSchema2, TestSchema3
            $schemas.Parent.Name | Should -Be $newDbName, $newDbName, $newDbName, $newDbName

            Remove-DbaDbSchema -SqlInstance $server1, $server2 -Database $newDbName -Schema TestSchema2, TestSchema3 -Confirm:$false

            (Get-DbaDbSchema -SqlInstance $server1, $server2 -Database $newDbName -Schema TestSchema2, TestSchema3) | Should -BeNullOrEmpty
        }

        It "Should support piping databases" {
            $schema = New-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema TestSchema1
            $schema.Status.Count | Should -Be 1
            $schema.Name | Should -Be TestSchema1
            $schema.Parent.Name | Should -Be $newDbName

            Get-DbaDatabase -SqlInstance $server1 -Database $newDbName | Remove-DbaDbSchema -Schema TestSchema1 -Confirm:$false

            (Get-DbaDbSchema -SqlInstance $server1 -Database $newDbName -Schema TestSchema1) | Should -BeNullOrEmpty
        }
    }
}