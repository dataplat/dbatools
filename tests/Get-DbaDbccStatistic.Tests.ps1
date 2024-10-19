param($ModuleName = 'dbatools')

Describe "Get-DbaDbccStatistic" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbccStatistic
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Object",
                "Target",
                "Option",
                "NoInformationalMessages",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeAll {
            . (Join-Path $PSScriptRoot 'constants.ps1')
            $server = Connect-DbaInstance -SqlInstance $global:instance2
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
        }

        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $global:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
        }

        Context "Validate standard output for StatHeader option" {
            BeforeAll {
                $result = Get-DbaDbccStatistic -SqlInstance $global:instance2 -Database $dbname -Option StatHeader
            }

            It "returns correct number of results" {
                $result.Count | Should -Be 3
            }

            It "returns expected properties" {
                $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Object', 'Target', 'Cmd', 'Name', 'Updated', 'Rows', 'RowsSampled', 'Steps', 'Density', 'AverageKeyLength', 'StringIndex', 'FilterExpression', 'UnfilteredRows', 'PersistedSamplePercent'
                $result[0].PSObject.Properties.Name | Should -Contain $props
            }
        }

        Context "Validate standard output for DensityVector option" {
            BeforeAll {
                $result = Get-DbaDbccStatistic -SqlInstance $global:instance2 -Database $dbname -Option DensityVector
            }

            It "returns results" {
                $result.Count | Should -BeGreaterThan 0
            }

            It "returns expected properties" {
                $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Object', 'Target', 'Cmd', 'AllDensity', 'AverageLength', 'Columns'
                $result[0].PSObject.Properties.Name | Should -Contain $props
            }
        }

        Context "Validate standard output for Histogram option" {
            BeforeAll {
                $result = Get-DbaDbccStatistic -SqlInstance $global:instance2 -Database $dbname -Option Histogram
            }

            It "returns results" {
                $result.Count | Should -BeGreaterThan 0
            }

            It "returns expected properties" {
                $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Object', 'Target', 'Cmd', 'RangeHiKey', 'RangeRows', 'EqualRows', 'DistinctRangeRows', 'AverageRangeRows'
                $result[0].PSObject.Properties.Name | Should -Contain $props
            }
        }

        Context "Validate standard output for StatsStream option" {
            BeforeAll {
                $result = Get-DbaDbccStatistic -SqlInstance $global:instance2 -Database $dbname -Option StatsStream
            }

            It "returns results" {
                $result.Count | Should -BeGreaterThan 0
            }

            It "returns expected properties" {
                $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Object', 'Target', 'Cmd', 'StatsStream', 'Rows', 'DataPages'
                $result[0].PSObject.Properties.Name | Should -Contain $props
            }
        }

        Context "Validate returns results for single Object" {
            BeforeAll {
                $result = Get-DbaDbccStatistic -SqlInstance $global:instance2 -Database $dbname -Object $tableName2 -Option StatsStream
            }

            It "returns results" {
                $result.Count | Should -BeGreaterThan 0
            }
        }

        Context "Validate returns results for single Object and Target" {
            BeforeAll {
                $result = Get-DbaDbccStatistic -SqlInstance $global:instance2 -Database $dbname -Object $tableName2 -Target 'TestStat2' -Option DensityVector
            }

            It "returns results" {
                $result.Count | Should -BeGreaterThan 0
            }
        }
    }
}
