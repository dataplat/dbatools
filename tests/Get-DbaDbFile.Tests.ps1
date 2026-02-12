#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbFile",
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
                "FileGroup",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Ensure array" {
        It "Returns disks as an array" {
            $results = Get-Command -Name Get-DbaDbFile | Select-Object -ExpandProperty ScriptBlock
            $results -match '\$disks \= \@\(' | Should -Be $true
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Should return file information" {
        It "Returns information about tempdb files" {
            $results = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle
            $results.Database -contains "tempdb" | Should -Be $true
        }
    }

    Context "Should return file information for only tempdb" {
        It "Returns only tempdb files" {
            $results = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database tempdb
            foreach ($result in $results) {
                $result.Database | Should -Be "tempdb"
            }
        }
    }

    Context "Should return file information for only tempdb primary filegroup" {
        It "Returns only tempdb files that are in Primary filegroup" {
            $results = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database tempdb -FileGroup Primary
            foreach ($result in $results) {
                $result.Database | Should -Be "tempdb"
                $result.FileGroupName | Should -Be "Primary"
            }
        }
    }

    Context "Physical name is populated" {
        BeforeAll {
            $script:dbFileResults = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database master
        }

        It "Master returns proper results" {
            $result = $script:dbFileResults | Where-Object LogicalName -eq "master"
            $result.PhysicalName -match "master.mdf" | Should -Be $true
            $result = $script:dbFileResults | Where-Object LogicalName -eq "mastlog"
            $result.PhysicalName -match "mastlog.ldf" | Should -Be $true
        }

        It "Returns output of the documented type" {
            $script:dbFileResults | Should -Not -BeNullOrEmpty
            $script:dbFileResults[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $script:dbFileResults | Should -Not -BeNullOrEmpty
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "DatabaseID",
                "FileGroupName",
                "ID",
                "Type",
                "TypeDescription",
                "LogicalName",
                "PhysicalName",
                "State",
                "MaxSize",
                "Growth",
                "GrowthType",
                "NextGrowthEventSize",
                "Size",
                "UsedSpace",
                "AvailableSpace",
                "IsOffline",
                "IsReadOnly",
                "IsReadOnlyMedia",
                "IsSparse",
                "NumberOfDiskWrites",
                "NumberOfDiskReads",
                "ReadFromDisk",
                "WrittenToDisk",
                "VolumeFreeSpace",
                "FileGroupDataSpaceId",
                "FileGroupType",
                "FileGroupTypeDescription",
                "FileGroupDefault",
                "FileGroupReadOnly"
            )
            foreach ($prop in $expectedProps) {
                $script:dbFileResults[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }
    }

    Context "Database ID is populated" {
        It "Returns proper results for the master db" {
            $results = Get-DbaDbFile -SqlInstance $TestConfig.InstanceSingle -Database master
            $results.DatabaseID | Get-Unique | Should -Be (Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database master).ID
        }

        It "Uses a pipeline input and returns proper results for the tempdb" {
            $tempDB = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database tempdb
            $results = $tempDB | Get-DbaDbFile
            $results.DatabaseID | Get-Unique | Should -Be $tempDB.ID
        }
    }

}