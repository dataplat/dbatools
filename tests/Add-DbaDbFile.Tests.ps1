#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaDbFile",
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
                "FileName",
                "Path",
                "Size",
                "Growth",
                "MaxSize",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $dbName = "dbatoolsci_addfile_test_$random"
        $fgName = "filegroup_$random"
        $fgMemName = "filegroup_mem_$random"

        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbName
        $null = New-DbaDbFileGroup -SqlInstance $TestConfig.InstanceSingle -Database $dbName -FileGroup $fgName
        $null = New-DbaDbFileGroup -SqlInstance $TestConfig.InstanceSingle -Database $dbName -FileGroup $fgMemName -FileGroupType MemoryOptimizedDataFileGroup

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Adds a file to a filegroup" {
        It "Adds a file with auto-generated name" {
            $splatAddFile = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                FileGroup   = $fgName
            }
            $result = Add-DbaDbFile @splatAddFile
            $result.Name | Should -Not -BeNullOrEmpty
            $result.Parent.Name | Should -Be $fgName
        }

        It "Adds a file with a custom name" {
            $customFileName = "customfile_$random"
            $splatAddFile = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                FileGroup   = $fgName
                FileName    = $customFileName
            }
            $result = Add-DbaDbFile @splatAddFile
            $result.Name | Should -Be $customFileName
            $result.Parent.Name | Should -Be $fgName
        }

        It "Adds a file with custom size and growth" {
            $splatAddFile = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                FileGroup   = $fgName
                FileName    = "customsize_$random"
                Size        = 256
                Growth      = 128
                MaxSize     = 10240
            }
            $result = Add-DbaDbFile @splatAddFile
            $result.Name | Should -Be "customsize_$random"
            $result.Size | Should -Be 262144
            $result.Growth | Should -Be 131072
            $result.MaxSize | Should -Be 10485760
        }

        It "Adds a file to a memory-optimized filegroup" {
            $splatAddFile = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                FileGroup   = $fgMemName
                FileName    = "memfile_$random"
            }
            $result = Add-DbaDbFile @splatAddFile
            $result.Name | Should -Be "memfile_$random"
            $result.Parent.Name | Should -Be $fgMemName
            $result.Parent.FileGroupType | Should -Be MemoryOptimizedDataFileGroup
        }

        It "Validates that duplicate file names are rejected" {
            $duplicateName = "duplicate_$random"
            $splatAddFile = @{
                SqlInstance      = $TestConfig.InstanceSingle
                Database         = $dbName
                FileGroup        = $fgName
                FileName         = $duplicateName
                WarningAction    = "SilentlyContinue"
            }
            $null = Add-DbaDbFile @splatAddFile

            $result = Add-DbaDbFile @splatAddFile
            $result | Should -BeNullOrEmpty
        }

        It "Validates that non-existent filegroup is rejected" {
            $splatAddFile = @{
                SqlInstance      = $TestConfig.InstanceSingle
                Database         = $dbName
                FileGroup        = "nonexistent_$random"
                WarningAction    = "SilentlyContinue"
            }
            $result = Add-DbaDbFile @splatAddFile
            $result | Should -BeNullOrEmpty
        }

        It "Works with pipeline input" {
            $splatGetDb = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
            }
            $result = Get-DbaDatabase @splatGetDb | Add-DbaDbFile -FileGroup $fgName -FileName "pipelinefile_$random"
            $result.Name | Should -Be "pipelinefile_$random"
            $result.Parent.Name | Should -Be $fgName
        }
    }
}
