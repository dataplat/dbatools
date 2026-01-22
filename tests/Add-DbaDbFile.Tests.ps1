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

    Context "Output Validation" {
        BeforeAll {
            $splatAddFile = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                FileGroup   = $fgName
                FileName    = "outputtest_$random"
            }
            $result = Add-DbaDbFile @splatAddFile
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.DataFile]
        }

        It "Has the expected dbatools-controlled properties for standard data files" {
            $expectedProps = @(
                'Name',
                'FileName',
                'Size',
                'Growth',
                'GrowthType',
                'MaxSize',
                'Parent',
                'IsPrimaryFile',
                'IsReadOnly',
                'IsOffline'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be available"
            }
        }

        It "Sets Size, Growth, and MaxSize correctly for standard data files" {
            $result.Size | Should -Be 131072 -Because "Size should be 128MB (default) * 1024 = 131072KB"
            $result.Growth | Should -Be 65536 -Because "Growth should be 64MB (default) * 1024 = 65536KB"
            $result.GrowthType | Should -Be "KB" -Because "GrowthType should be set to KB for standard files"
            $result.MaxSize | Should -Be -1 -Because "MaxSize should be -1 (unlimited) by default"
        }

        It "Returns the correct Parent FileGroup object" {
            $result.Parent.Name | Should -Be $fgName
            $result.Parent | Should -BeOfType [Microsoft.SqlServer.Management.Smo.FileGroup]
        }
    }

    Context "Output Validation for Memory-Optimized FileGroup" {
        BeforeAll {
            $splatAddMemFile = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                FileGroup   = $fgMemName
                FileName    = "outputtest_mem_$random"
            }
            $result = Add-DbaDbFile @splatAddMemFile
        }

        It "Returns DataFile type for memory-optimized filegroup" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.DataFile]
        }

        It "Has Name and FileName properties" {
            $result.Name | Should -Be "outputtest_mem_$random"
            $result.FileName | Should -Not -BeNullOrEmpty
        }

        It "Returns the correct Parent FileGroup with MemoryOptimizedDataFileGroup type" {
            $result.Parent.Name | Should -Be $fgMemName
            $result.Parent.FileGroupType | Should -Be MemoryOptimizedDataFileGroup
        }
    }
}
