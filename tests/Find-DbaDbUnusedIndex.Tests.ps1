$script:UnusedIndexCommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$script:UnusedIndexCommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        It "Should only contain our specific parameters" {
            [object[]]$params = (Get-Command $script:UnusedIndexCommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
            [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'IgnoreUptime', 'InputObject', 'EnableException', 'UserSeeksLessThan', 'UserScansLessThan', 'UserLookupsLessThan'
            $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters

            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should -Be 0
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>


Describe "$script:UnusedIndexCommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Verify basics of the Find-DbaDbUnusedIndex command" {
        BeforeAll {
            $server1 = Connect-DbaInstance -SqlInstance $script:instance1
            $server2 = Connect-DbaInstance -SqlInstance $script:instance2
            $server3 = Connect-DbaInstance -SqlInstance $script:instance3
            $random = Get-Random
            $indexName = "dbatoolsci_index_$random"
            $tableName = "dbatoolsci_table_$random"
            $sql = "CREATE TABLE $tableName (ID INTEGER);
                    CREATE INDEX $indexName ON $tableName (ID);
                    INSERT INTO $tableName (ID) VALUES (1);
                    SELECT ID FROM $tableName;"
            $null = $server1.Query($sql, 'tempdb')
            $null = $server2.Query($sql, 'tempdb')
            $null = $server3.Query($sql, 'tempdb')
        }
        AfterAll {
            $sql = "DROP TABLE $tableName;"
            $null = $server1.Query($sql, 'tempdb')
            $null = $server2.Query($sql, 'tempdb')
            $null = $server3.Query($sql, 'tempdb')
        }

        It "Should find the 'unused' index on each test sql instance" {
            Function checkIfIndexIsReturned {
                param(
                    [string]$SqlInstance,
                    [string]$Database,
                    [string]$IndexNameToCheck,
                    [int]$Threshold
                )

                $results = Find-DbaDbUnusedIndex -SqlInstance $SqlInstance -Database $Database -IgnoreUptime -UserSeeksLessThan $Threshold -UserScansLessThan $Threshold -UserLookupsLessThan $Threshold

                foreach ($row in $results) {
                    if ($row["IndexName"] -eq $IndexNameToCheck) {
                        Write-Host "$($IndexNameToCheck) was found on $($SqlInstance)"
                        return $true
                    }
                }

                Write-Host "$($IndexNameToCheck) was not found on $($SqlInstance)"

                return $false
            }

            $testSQLInstance1 = checkIfIndexIsReturned $script:instance1 tempdb $indexName 10
            $testSQLInstance2 = checkIfIndexIsReturned $script:instance2 tempdb $indexName 10
            $testSQLInstance3 = checkIfIndexIsReturned $script:instance3 tempdb $indexName 10

            ($testSQLInstance1 -and $testSQLInstance2 -and $testSQLInstance3) | Should -Be $true
        }

        It "Should return the expected columns on each test sql instance" {

            [object[]]$expectedColumnArray = 'CompressionDescription', 'ComputerName', 'Database', 'IndexId', 'IndexName', 'IndexSizeMB', 'InstanceName', 'LastSystemLookup', 'LastSystemScan', 'LastSystemSeek', 'LastSystemUpdate', 'LastUserLookup', 'LastUserScan', 'LastUserSeek', 'LastUserUpdate', 'ObjectId', 'RowCount', 'Schema', 'SqlInstance', 'SystemLookup', 'SystemScans', 'SystemSeeks', 'SystemUpdates', 'Table', 'TypeDesc', 'UserLookups', 'UserScans', 'UserSeeks', 'UserUpdates'

            Function checkReturnedColumns {
                param(
                    [string]$SqlInstance,
                    [string]$Database,
                    [object[]]$ExpectedColumnArray,
                    [int]$Threshold
                )

                $results = Find-DbaDbUnusedIndex -SqlInstance $SqlInstance -Database $Database -IgnoreUptime -UserSeeksLessThan $Threshold -UserScansLessThan $Threshold -UserLookupsLessThan $Threshold

                if ( ($null -ne $results) ) {
                    $row = $null
                    # if one row is returned $results will be a System.Data.DataRow, otherwise it will be an object[] of System.Data.DataRow
                    if ($results -is [System.Data.DataRow]) {
                        $row = $results
                    } elseif ($results -is [Object[]] -and $results.Count -gt 0) {
                        $row = $results[0]
                    } else {
                        Write-Host "Unexpected results returned from $($SqlInstance): $($results)"
                        return $false
                    }

                    [object[]]$columnNamesReturned = @($row | Get-Member -MemberType Property | Select-Object -Property Name | ForEach-Object { $_.Name })

                    if ( @(Compare-Object -ReferenceObject $ExpectedColumnArray -DifferenceObject $columnNamesReturned).Count -eq 0 ) {
                        Write-Host "Columns matched on $($SqlInstance)"
                        return $true
                    } else {
                        Write-Host "The columns specified in the expectedColumnList variable do not match these returned columns from $($SqlInstance): $($columnNamesReturned)"
                    }
                } else {
                    Write-Host "No results were returned from $($SqlInstance)"
                }

                return $false
            }

            $testSQLInstance1 = checkReturnedColumns $script:instance1 tempdb $expectedColumnArray 10
            $testSQLInstance2 = checkReturnedColumns $script:instance2 tempdb $expectedColumnArray 10
            $testSQLInstance3 = checkReturnedColumns $script:instance3 tempdb $expectedColumnArray 10

            ($testSQLInstance1 -and $testSQLInstance2 -and $testSQLInstance3) | Should -Be $true
        }
    }
}