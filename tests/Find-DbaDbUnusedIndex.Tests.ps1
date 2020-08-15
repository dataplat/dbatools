$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        It "Should only contain our specific parameters" {
            [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
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


Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Verify basics of the Find-DbaDbUnusedIndex command" {
        BeforeAll {
            try {
                Write-Message -Level Debug -Message "Connecting to $script:instance3"

                try {
                    $connectionResults = Test-DbaConnection -SqlInstance $script:instance3 -EnableException

                    Write-Message -Level Warning -Message "Connection result for $script:instance3 was: $($connectionResults.ConnectSuccess)"
                } catch {
                    Write-Message -Level Warning -Message "$($_) : $($_.ScriptStackTrace)"
                }

                $server3 = Connect-DbaInstance -SqlInstance $script:instance3

                $random = Get-Random
                $dbName = "dbatoolsci_$random"

                Write-Message -Level Debug -Message "Setting up the new database $dbName"
                Remove-DbaDatabase -SqlInstance $script:instance3 -Database $dbName -Confirm:$false
                New-DbaDatabase -SqlInstance $script:instance3 -Name $dbName

                $indexName = "dbatoolsci_index_$random"
                $tableName = "dbatoolsci_table_$random"
                $sql = "USE $dbName;
                        CREATE TABLE $tableName (ID INTEGER);
                        CREATE INDEX $indexName ON $tableName (ID);
                        INSERT INTO $tableName (ID) VALUES (1);
                        SELECT ID FROM $tableName;
                        WAITFOR DELAY '00:00:05'; -- for slower systems allow the query optimizer engine to catch up and update sys.dm_db_index_usage_stats"

                $null = $server3.Query($sql)
            } catch {
                Write-Message -Level Warning -Message "$($_): $($_.ScriptStackTrace)"
            }
        }
        AfterAll {
            try {
                Remove-DbaDatabase -SqlInstance $script:instance3 -Database $dbName -Confirm:$false -EnableException
            } catch {
                Write-Message -Level Warning -Message "Unable to drop database $dbName due to $($_): $($_.ScriptStackTrace)"
            }
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
                        Write-Message -Level Debug -Message "$($IndexNameToCheck) was found on $($SqlInstance) in database $($Database)"
                        return $true
                    }
                }

                Write-Message -Level Warning -Message "$($IndexNameToCheck) was not found on $($SqlInstance) in database $($Database)"

                return $false
            }

            $testSQLInstance3 = $false

            try {
                $testSQLInstance3 = checkIfIndexIsReturned $script:instance3 $dbName $indexName 10
            } catch {
                Write-Message -Level Warning -Message "$($_): $($_.ScriptStackTrace)"
            }

            $testSQLInstance3 | Should -Be $true
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
                        Write-Message -Level Warning -Message "Unexpected results returned from $($SqlInstance): $($results)"
                        return $false
                    }

                    [object[]]$columnNamesReturned = @($row | Get-Member -MemberType Property | Select-Object -Property Name | ForEach-Object { $_.Name })

                    if ( @(Compare-Object -ReferenceObject $ExpectedColumnArray -DifferenceObject $columnNamesReturned).Count -eq 0 ) {
                        Write-Message -Level Debug -Message "Columns matched on $($SqlInstance)"
                        return $true
                    } else {
                        Write-Message -Level Warning -Message "The columns specified in the expectedColumnList variable do not match these returned columns from $($SqlInstance): $($columnNamesReturned)"
                    }
                } else {
                    Write-Message -Level Warning -Message "No results were returned from $($SqlInstance)"
                }

                return $false
            }

            $testSQLInstance3 = $false

            try {
                $testSQLInstance3 = checkReturnedColumns $script:instance3 $dbName $expectedColumnArray 10
            } catch {
                Write-Message -Level Warning -Message "$($_): $($_.ScriptStackTrace)"
            }

            $testSQLInstance3 | Should -Be $true
        }
    }
}