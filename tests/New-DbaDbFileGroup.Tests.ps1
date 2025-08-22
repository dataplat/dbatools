#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDbFileGroup",
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
                "FileGroup",
                "FileGroupType",
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
        $db1name = "dbatoolsci_filegroup_test_$random"
        $db2name = "dbatoolsci_filegroup_test2_$random"

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $newDb1 = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $db1name
        $newDb2 = New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $db2name

        $fileStreamStatus = Get-DbaFilestream -SqlInstance $TestConfig.instance2

        if ($fileStreamStatus.InstanceAccessLevel -eq 0) {
            Enable-DbaFilestream -SqlInstance $TestConfig.instance2 -Confirm:$false -Force
            $resetFileStream = $true
        } else {
            $resetFileStream = $false
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $newDb1, $newDb2 | Remove-DbaDatabase -Confirm:$false

        if ($resetFileStream) {
            Disable-DbaFilestream -SqlInstance $TestConfig.instance2 -Confirm:$false -Force
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "ensure command works" {
        It "Creates a filegroup" {
            $results = New-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup "filegroup_$random"
            $results.Parent.Name | Should -Be $db1name
            $results.Name | Should -Be "filegroup_$random"
            $results.FileGroupType | Should -Be RowsFileGroup
        }

        It "Check the validation for duplicate filegroup names" {
            $results = New-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup "filegroup_$random" -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
        }

        It "Creates a filegroup of each FileGroupType" {
            $results = New-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup "filegroup_rows_$random" -FileGroupType RowsFileGroup
            $results.Name | Should -Be "filegroup_rows_$random"
            $results.FileGroupType | Should -Be RowsFileGroup

            $results = New-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup "filegroup_filestream_$random" -FileGroupType FileStreamDataFileGroup
            $results.Name | Should -Be "filegroup_filestream_$random"
            $results.FileGroupType | Should -Be FileStreamDataFileGroup

            $results = New-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db1name -FileGroup "filegroup_memory_optimized_$random" -FileGroupType MemoryOptimizedDataFileGroup
            $results.Name | Should -Be "filegroup_memory_optimized_$random"
            $results.FileGroupType | Should -Be MemoryOptimizedDataFileGroup
        }

        It "Creates a filegroup using a database from a pipeline" {
            $results = $newDb1 | New-DbaDbFileGroup -FileGroup "filegroup_pipeline_$random"
            $results.Name | Should -Be "filegroup_pipeline_$random"
            $results.Parent.Name | Should -Be $db1name

            $results = $newDb1 | New-DbaDbFileGroup -SqlInstance $TestConfig.instance2 -Database $db2name -FileGroup "filegroup_pipeline2_$random"
            $results.Name | Should -Be "filegroup_pipeline2_$random", "filegroup_pipeline2_$random"
            $results.Parent.Name | Should -Be $db1name, $db2name
        }
    }
}