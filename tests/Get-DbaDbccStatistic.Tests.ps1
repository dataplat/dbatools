#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbccStatistic",
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
                "Object",
                "Target",
                "Option",
                "NoInformationalMessages",
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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $random = Get-Random
        $tableName = "dbatools_getdbtbl1"
        $tableName2 = "dbatools_getdbtbl2"

        $dbname = "dbatoolsci_dbccstat$random"
        $null = $server.Query("CREATE DATABASE $dbname")
        $null = $server.Query("CREATE TABLE $tableName (idTbl1 INT PRIMARY KEY)", $dbname)
        $null = $server.Query("CREATE TABLE $tableName2 (idTbl2 INT, idTbl1 INT, id3 INT)", $dbname)

        $null = $server.Query("INSERT $tableName(idTbl1) SELECT object_id FROM sys.objects", $dbname)
        $null = $server.Query("INSERT $tableName2(idTbl2, idTbl1, id3) SELECT object_id, parent_object_id, schema_id from sys.all_objects", $dbname)

        $null = $server.Query("CREATE STATISTICS [TestStat1] ON $tableName2([idTbl2], [idTbl1], [id3])", $dbname)
        $null = $server.Query("CREATE STATISTICS [TestStat2] ON $tableName2([idTbl1], [idTbl2])", $dbname)
        $null = $server.Query("UPDATE STATISTICS $tableName", $dbname)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Remove-DbaDatabase

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Validate standard output for StatHeader option" {
        BeforeAll {
            $props = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Object",
                "Target",
                "Cmd",
                "Name",
                "Updated",
                "Rows",
                "RowsSampled",
                "Steps",
                "Density",
                "AverageKeyLength",
                "StringIndex",
                "FilterExpression",
                "UnfilteredRows",
                "PersistedSamplePercent"
            )
            $result = Get-DbaDbccStatistic -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Option StatHeader -OutVariable "global:dbatoolsciOutput"
        }

        It "returns correct results" {
            $result.Count | Should -BeExactly 3
        }

        It "Should return all expected properties" {
            foreach ($prop in $props) {
                $result[0].PSObject.Properties[$prop].Name | Should -Be $prop
            }
        }
    }

    Context "Validate standard output for DensityVector option" {
        BeforeAll {
            $props = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Object",
                "Target",
                "Cmd",
                "AllDensity",
                "AverageLength",
                "Columns"
            )
            $result = Get-DbaDbccStatistic -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Option DensityVector
        }

        It "returns results" {
            $result.Count | Should -BeGreaterThan 0
        }

        It "Should return all expected properties" {
            foreach ($prop in $props) {
                $result[0].PSObject.Properties[$prop].Name | Should -Be $prop
            }
        }
    }

    Context "Validate standard output for Histogram option" {
        BeforeAll {
            $props = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Object",
                "Target",
                "Cmd",
                "RangeHiKey",
                "RangeRows",
                "EqualRows",
                "DistinctRangeRows",
                "AverageRangeRows"
            )
            $result = Get-DbaDbccStatistic -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Option Histogram
        }

        It "returns results" {
            $result.Count | Should -BeGreaterThan 0
        }

        It "Should return all expected properties" {
            foreach ($prop in $props) {
                $result[0].PSObject.Properties[$prop].Name | Should -Be $prop
            }
        }
    }

    Context "Validate standard output for StatsStream option" {
        BeforeAll {
            $props = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Object",
                "Target",
                "Cmd",
                "StatsStream",
                "Rows",
                "DataPages"
            )
            $result = Get-DbaDbccStatistic -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Option StatsStream
        }

        It "returns results" {
            $result.Count | Should -BeGreaterThan 0
        }

        It "Should return all expected properties" {
            foreach ($prop in $props) {
                $result[0].PSObject.Properties[$prop].Name | Should -Be $prop
            }
        }
    }

    Context "Validate returns results for single Object" {
        It "returns results" {
            $result = Get-DbaDbccStatistic -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Object $tableName2 -Option StatsStream
            $result.Count | Should -BeGreaterThan 0
        }
    }

    Context "Validate returns results for single Object and Target" {
        It "returns results" {
            $result = Get-DbaDbccStatistic -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Object $tableName2 -Target "TestStat2" -Option DensityVector
            $result.Count | Should -BeGreaterThan 0
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties for StatHeader" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Object",
                "Target",
                "Cmd",
                "Name",
                "Updated",
                "Rows",
                "RowsSampled",
                "Steps",
                "Density",
                "AverageKeyLength",
                "StringIndex",
                "FilterExpression",
                "UnfilteredRows",
                "PersistedSamplePercent"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}