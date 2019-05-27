$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Object', 'Target', 'Option', 'NoInformationalMessages', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
Describe "$commandname Integration Test" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
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
        $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
    }

    Context "Validate standard output for StatHeader option " {
        $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Object', 'Target', 'Cmd', 'Name', 'Updated', 'Rows', 'RowsSampled', 'Steps', 'Density', 'AverageKeyLength', 'StringIndex', 'FilterExpression', 'UnfilteredRows', 'PersistedSamplePercent'
        $result = Get-DbaDbccStatistic -SqlInstance $script:instance2 -Database $dbname -Option StatHeader

        It "returns correct results" {
            $result.Count -eq 3 | Should Be $true
        }

        foreach ($prop in $props) {
            $p = $result[0].PSObject.Properties[$prop]
            It "Should return property: $prop" {
                $p.Name | Should Be $prop
            }
        }
    }

    Context "Validate standard output for DensityVector option " {
        $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Object', 'Target', 'Cmd', 'AllDensity', 'AverageLength', 'Columns'
        $result = Get-DbaDbccStatistic -SqlInstance $script:instance2 -Database $dbname -Option DensityVector

        It "returns results" {
            $result.Count -gt 0 | Should Be $true
        }

        foreach ($prop in $props) {
            $p = $result[0].PSObject.Properties[$prop]
            It "Should return property: $prop" {
                $p.Name | Should Be $prop
            }

        }
    }

    Context "Validate standard output for Histogram option " {
        $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Object', 'Target', 'Cmd', 'RangeHiKey', 'RangeRows', 'EqualRows', 'DistinctRangeRows', 'AverageRangeRows'
        $result = Get-DbaDbccStatistic -SqlInstance $script:instance2 -Database $dbname -Option Histogram

        It "returns results" {
            $result.Count -gt 0 | Should Be $true
        }

        foreach ($prop in $props) {
            $p = $result[0].PSObject.Properties[$prop]
            It "Should return property: $prop" {
                $p.Name | Should Be $prop
            }

        }
    }

    Context "Validate standard output for StatsStream option " {
        $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Object', 'Target', 'Cmd', 'StatsStream', 'Rows', 'DataPages'
        $result = Get-DbaDbccStatistic -SqlInstance $script:instance2 -Database $dbname -Option StatsStream

        It "returns results" {
            $result.Count -gt 0 | Should Be $true
        }

        foreach ($prop in $props) {
            $p = $result[0].PSObject.Properties[$prop]
            It "Should return property: $prop" {
                $p.Name | Should Be $prop
            }

        }
    }

    Context "Validate returns results for single Object " {
        $result = Get-DbaDbccStatistic -SqlInstance $script:instance2 -Database $dbname -Object $tableName2 -Option StatsStream

        It "returns results" {
            $result.Count -gt 0 | Should Be $true
        }
    }

    Context "Validate returns results for single Object and Target " {
        $result = Get-DbaDbccStatistic -SqlInstance $script:instance2 -Database $dbname -Object $tableName2 -Target 'TestStat2'  -Option DensityVector

        It "returns results" {
            $result.Count -gt 0 | Should Be $true
        }
    }
}