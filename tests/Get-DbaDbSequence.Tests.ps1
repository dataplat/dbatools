#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbSequence",
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
                "Sequence",
                "Schema",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {

    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $newDbName = "dbatoolsci_newdb_$random"
        $newDbName2 = "dbatoolsci_newdb2_$random"
        $newDb, $newDb2 = New-DbaDatabase -SqlInstance $server -Name $newDbName, $newDbName2

        $sequence = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence1_$random" -Schema "Schema_$random"
        $sequence2 = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence2_$random" -Schema "Schema2_$random"
        $sequence3 = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence1_$random" -Schema "Schema2_$random"
        $sequence4 = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence2_$random" -Schema "Schema_$random"
        $sequence5 = New-DbaDbSequence -SqlInstance $server -Database $newDbName2 -Sequence "Sequence1_$random" -Schema "Schema_$random"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = $newDb, $newDb2 | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "commands work as expected" {
        It "finds a sequence on an instance" {
            $sequence = Get-DbaDbSequence -SqlInstance $server
            $sequence.Count | Should -BeGreaterOrEqual 5
        }

        It "finds a sequence in a single database" {
            $sequence = Get-DbaDbSequence -SqlInstance $server -Database $newDbName
            $sequence.Parent.Name | Select-Object -Unique | Should -Be $newDbName
            $sequence.Count | Should -Be 4
        }

        It "finds a sequence in a single database by schema only" {
            $sequence = Get-DbaDbSequence -SqlInstance $server -Database $newDbName -Schema "Schema2_$random"
            $sequence.Parent.Name | Select-Object -Unique | Should -Be $newDbName
            $sequence.Schema | Select-Object -Unique | Should -Be "Schema2_$random"
            $sequence.Count | Should -Be 2
        }

        It "finds a sequence in a single database by schema and by name" {
            $sequence = Get-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence1_$random" -Schema "Schema_$random"
            $sequence.Parent.Name | Select-Object -Unique | Should -Be $newDbName
            $sequence.Name | Select-Object -Unique | Should -Be "Sequence1_$random"
            $sequence.Schema | Select-Object -Unique | Should -Be "Schema_$random"
            $sequence.Count | Should -Be 1
        }

        It "finds a sequence on an instance by name only" {
            $sequence = Get-DbaDbSequence -SqlInstance $server -Sequence "Sequence1_$random"
            $sequence.Name | Select-Object -Unique | Should -Be "Sequence1_$random"
            $sequence.Count | Should -Be 3
        }

        It "finds a sequence on an instance by schema only" {
            $sequence = Get-DbaDbSequence -SqlInstance $server -Schema "Schema2_$random"
            $sequence.Schema | Select-Object -Unique | Should -Be "Schema2_$random"
            $sequence.Count | Should -Be 2
        }

        It "finds a sequence on an instance by schema and name" {
            $sequence = Get-DbaDbSequence -SqlInstance $server -Schema "Schema_$random" -Sequence "Sequence1_$random"
            $sequence.Schema | Select-Object -Unique | Should -Be "Schema_$random"
            $sequence.Name | Select-Object -Unique | Should -Be "Sequence1_$random"
            $sequence.Count | Should -Be 2
        }

        It "supports piping databases" {
            $sequence = Get-DbaDatabase -SqlInstance $server -Database $newDbName | Get-DbaDbSequence -Sequence "Sequence1_$random" -Schema "Schema_$random"
            $sequence.Name | Should -Be "Sequence1_$random"
            $sequence.Schema | Should -Be "Schema_$random"
            $sequence.Parent.Name | Should -Be $newDbName
        }
    }
}