$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'IgnoreUptime', 'InputObject', 'EnableException', 'Seeks', 'Scans', 'Lookups'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Verify basics of the Find-DbaDbUnusedIndex command" {
        BeforeAll {
            Write-Message -Level Warning -Message "Find-DbaDbUnusedIndex testing connection to $script:instance2"
            Test-DbaConnection -SqlInstance $script:instance2

            $server = Connect-DbaInstance -SqlInstance $script:instance2

            $random = Get-Random
            $dbName = "dbatoolsci_$random"

            Write-Message -Level Warning -Message "Find-DbaDbUnusedIndex setting up the new database $dbName"
            Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbName -Confirm:$false
            New-DbaDatabase -SqlInstance $script:instance2 -Name $dbName

            $indexName = "dbatoolsci_index_$random"
            $tableName = "dbatoolsci_table_$random"
            $sql = "USE $dbName;
                    CREATE TABLE $tableName (ID INTEGER);
                    CREATE INDEX $indexName ON $tableName (ID);
                    INSERT INTO $tableName (ID) VALUES (1);
                    SELECT ID FROM $tableName;
                    WAITFOR DELAY '00:00:05'; -- for slower systems allow the query optimizer engine to catch up and update sys.dm_db_index_usage_stats"

            $null = $server.Query($sql)
        }

        AfterAll {
            Write-Message -Level Warning -Message "Find-DbaDbUnusedIndex removing the database $dbName"
            Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbName -Confirm:$false
        }

        It "Should find the 'unused' index on each test sql instance" {
            $results = Find-DbaDbUnusedIndex -SqlInstance $script:instance2 -Database $dbName -IgnoreUptime -Seeks 10 -Scans 10 -Lookups 10

            $testSQLinstance = $false

            foreach ($row in $results) {
                if ($row["IndexName"] -eq $indexName) {
                    Write-Message -Level Debug -Message "$($indexName) was found on $($script:instance2) in database $($dbName)"
                    $testSQLinstance = $true
                } else {
                    Write-Message -Level Warning -Message "$($indexName) was not found on $($script:instance2) in database $($dbName)"
                }
            }

            $testSQLinstance | Should -Be $true
        }


        It "Should return the expected columns on each test sql instance" {
            [object[]]$expectedColumnArray = 'CompressionDescription', 'ComputerName', 'Database', 'IndexId', 'IndexName', 'IndexSizeMB', 'InstanceName', 'LastSystemLookup', 'LastSystemScan', 'LastSystemSeek', 'LastSystemUpdate', 'LastUserLookup', 'LastUserScan', 'LastUserSeek', 'LastUserUpdate', 'ObjectId', 'RowCount', 'Schema', 'SqlInstance', 'SystemLookup', 'SystemScans', 'SystemSeeks', 'SystemUpdates', 'Table', 'TypeDesc', 'UserLookups', 'UserScans', 'UserSeeks', 'UserUpdates'

            $testSQLinstance = $false

            $results = Find-DbaDbUnusedIndex -SqlInstance $script:instance2 -Database $dbName -IgnoreUptime -Seeks 10 -Scans 10 -Lookups 10

            if ( ($null -ne $results) ) {
                $row = $null
                # if one row is returned $results will be a System.Data.DataRow, otherwise it will be an object[] of System.Data.DataRow
                if ($results -is [System.Data.DataRow]) {
                    $row = $results
                } elseif ($results -is [Object[]] -and $results.Count -gt 0) {
                    $row = $results[0]
                } else {
                    Write-Message -Level Warning -Message "Unexpected results returned from $($SqlInstance): $($results)"
                    $testSQLinstance = $false
                }

                if ($null -ne $row) {
                    [object[]]$columnNamesReturned = @($row | Get-Member -MemberType Property | Select-Object -Property Name | ForEach-Object { $_.Name })

                    if ( @(Compare-Object -ReferenceObject $expectedColumnArray -DifferenceObject $columnNamesReturned).Count -eq 0 ) {
                        Write-Message -Level Debug -Message "Columns matched on $($script:instance2)"
                        $testSQLinstance = $true
                    } else {
                        Write-Message -Level Warning -Message "The columns specified in the expectedColumnList variable do not match these returned columns from $($script:instance2): $($columnNamesReturned)"
                    }
                }
            }

            $testSQLinstance | Should -Be $true
        }
    }
}