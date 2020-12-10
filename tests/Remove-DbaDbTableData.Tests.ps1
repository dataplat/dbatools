$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'BatchSize', 'Table', 'FromSql', 'WhereSql', 'InputObject', 'LogBackupPath', 'LogBackupTimeStampFormat', 'AzureBaseUrl', 'AzureCredential', 'EnableException'
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $server2 = Connect-DbaInstance -SqlInstance $script:instance3

        # scenario for testing with a db in the simple recovery model
        $dbnameSimpleModel = "dbatoolsci_$(Get-Random)"
        $newDbSimpleModel = New-DbaDatabase -SqlInstance $server -Name $dbnameSimpleModel -RecoveryModel Simple

        # scenario for testing with a db in the full recovery model
        $dbnameFullModel = "dbatoolsci_$(Get-Random)"
        $newDbFullModel = New-DbaDatabase -SqlInstance $server -Name $dbnameFullModel -RecoveryModel Full

        # scenario for testing with a db in the bulk_logged recovery model
        $dbnameBulkLoggedModel = "dbatoolsci_$(Get-Random)"
        $newDbBulkLoggedModel = New-DbaDatabase -SqlInstance $server -Name $dbnameBulkLoggedModel -RecoveryModel BulkLogged

        # additional server pipeline testing
        $newDbSimpleModelServer2 = New-DbaDatabase -SqlInstance $server2 -Name $dbnameSimpleModel -RecoveryModel Simple

        # add the sample tables to each of the databases
        $newDbSimpleModel, $newDbFullModel, $newDbBulkLoggedModel, $newDbSimpleModelServer2 | Invoke-DbaQuery -Query "CREATE TABLE dbo.Test (Id INTEGER); CREATE TABLE dbo.Test2 (Id INTEGER)"

        # do a full backup so that log backups can be done
        $backupDbFull = Backup-DbaDatabase -SqlInstance $server -Database $dbnameFullModel
        $backupDbBulkLogged = Backup-DbaDatabase -SqlInstance $server -Database $dbnameBulkLoggedModel
        $logBackupPath = $backupDbFull.BackupFolder

        # SQL to populate some data for testing
        $sqlAddRows = "
                TRUNCATE TABLE dbo.Test;

                DECLARE
                    @loopCounter INTEGER = 0;

                WHILE @loopCounter < 100
                BEGIN
                    INSERT INTO dbo.Test VALUES (@loopCounter);
                    SET @loopCounter = @loopCounter + 1;
                END;"
    }
    AfterAll {
        $newDbSimpleModel, $newDbFullModel, $newDbBulkLoggedModel, $newDbSimpleModelServer2 | Remove-DbaDatabase -Confirm:$false
    }

    Context "Param validation" {
        It "Either Table or FromSql needs to be specified" {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameFullModel
            $result | Should -BeNullOrEmpty

            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameFullModel -Table dbo.Test -FromSql "FROM dbo.Test"
            $result | Should -BeNullOrEmpty
        }

        It "Invalid -Table value is provided" {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameFullModel -Table InvalidTableName -Confirm:$false
            $result | Should -BeNullOrEmpty
        }

        It "Invalid -FromSql value because it is missing the deleteFromTable table alias" {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameFullModel -FromSql "FROM dbo.Test a LEFT JOIN dbo.Test2 b ON a.Id = b.Id" -Confirm:$false
            $result | Should -BeNullOrEmpty
        }

        It "Invalid SQL used to test the error handling in the delete statement" {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameFullModel -Table dbo.Test -WhereSql "WHERE 1/0 = 1" -Confirm:$false
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Sql param options" {
        BeforeEach {
            $addRowsToSimpleModelDb = Invoke-DbaQuery -SqlInstance $server -Database $dbnameSimpleModel -Query $sqlAddRows
        }

        It "FromSql param is used to specify a delete based on a join" {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameSimpleModel -FromSql "FROM dbo.Test deleteFromTable LEFT JOIN dbo.Test2 b ON deleteFromTable.Id = b.Id" -BatchSize 10 -Confirm:$false
            $result.TotalIterations | Should -Be 10
            $result.TotalRowsDeleted | Should -Be 100
            $result.LogBackups.count | Should -Be 0
            $result.Timings.count | Should -Be 10
            $result.Database | Should -Be $dbnameSimpleModel
            (Invoke-DbaQuery -SqlInstance $server -Database $dbnameSimpleModel -Query 'SELECT COUNT(1) AS [RowCount] FROM dbo.Test').RowCount | Should -Be 0
        }

        It "WhereSql param is used to specify a where clause for the delete" {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameSimpleModel -Table dbo.Test -WhereSql "WHERE Id >= 50" -BatchSize 10 -Confirm:$false
            $result.TotalIterations | Should -Be 5
            $result.TotalRowsDeleted | Should -Be 50
            $result.LogBackups.count | Should -Be 0
            $result.Timings.count | Should -Be 5
            $result.Database | Should -Be $dbnameSimpleModel
            (Invoke-DbaQuery -SqlInstance $server -Database $dbnameSimpleModel -Query 'SELECT COUNT(1) AS [RowCount] FROM dbo.Test').RowCount | Should -Be 50
        }

        It "WhereSql param is used to specify an order by clause for the delete" {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameSimpleModel -Table dbo.Test -WhereSql "WHERE Id IN (SELECT TOP 10 Id FROM dbo.Test ORDER BY Id)" -BatchSize 10 -Confirm:$false
            $result.TotalIterations | Should -Be 10
            $result.TotalRowsDeleted | Should -Be 100
            $result.LogBackups.count | Should -Be 0
            $result.Timings.count | Should -Be 10
            $result.Database | Should -Be $dbnameSimpleModel
            (Invoke-DbaQuery -SqlInstance $server -Database $dbnameSimpleModel -Query 'SELECT COUNT(1) AS [RowCount] FROM dbo.Test').RowCount | Should -Be 0
        }
    }

    Context "Functionality with simple recovery model" {
        BeforeEach {
            $addRowsToSimpleModelDb = Invoke-DbaQuery -SqlInstance $server -Database $dbnameSimpleModel -Query $sqlAddRows
        }

        It 'Removes Data for a specified database' {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameSimpleModel -Table dbo.Test -BatchSize 10 -Confirm:$false
            $result.TotalIterations | Should -Be 10
            $result.TotalRowsDeleted | Should -Be 100
            $result.LogBackups.count | Should -Be 0
            $result.Timings.count | Should -Be 10
            $result.Database | Should -Be $dbnameSimpleModel
            (Invoke-DbaQuery -SqlInstance $server -Database $dbnameSimpleModel -Query 'SELECT COUNT(1) AS [RowCount] FROM dbo.Test').RowCount | Should -Be 0
        }
    }

    Context "Functionality with bulk_logged recovery model" {
        BeforeEach {
            $addRowsToBulkLoggedDb = Invoke-DbaQuery -SqlInstance $server -Database $dbnameBulkLoggedModel -Query $sqlAddRows
        }

        It 'Removes Data for a specified database' {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameBulkLoggedModel -Table dbo.Test -BatchSize 10 -LogBackupPath $logBackupPath -Confirm:$false
            $result.TotalIterations | Should -Be 10
            $result.TotalRowsDeleted | Should -Be 100
            $result.LogBackups.count | Should -Be 10
            $result.Timings.count | Should -Be 10
            $result.Database | Should -Be $dbnameBulkLoggedModel
            (Invoke-DbaQuery -SqlInstance $server -Database $dbnameBulkLoggedModel -Query 'SELECT COUNT(1) AS [RowCount] FROM dbo.Test').RowCount | Should -Be 0
        }
    }

    Context "Functionality with full recovery model" {
        BeforeEach {
            $addRowsToFullModelDb = Invoke-DbaQuery -SqlInstance $server -Database $dbnameFullModel -Query $sqlAddRows
        }

        It 'Removes Data for a specified database and specifies LogBackupTimeStampFormat' {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameFullModel -Table dbo.Test -BatchSize 10 -LogBackupPath $logBackupPath -LogBackupTimeStampFormat "yyMMddHHmm" -Confirm:$false
            $result.TotalIterations | Should -Be 10
            $result.TotalRowsDeleted | Should -Be 100
            $result.LogBackups.count | Should -Be 10
            $result.Timings.count | Should -Be 10
            $result.Database | Should -Be $dbnameFullModel
            (Invoke-DbaQuery -SqlInstance $server -Database $dbnameFullModel -Query 'SELECT COUNT(1) AS [RowCount] FROM dbo.Test').RowCount | Should -Be 0
        }

        It "The LogBackupPath param is not specified so no log backups are taken" {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameFullModel -Table dbo.Test -BatchSize 10 -Confirm:$false
            $result.TotalIterations | Should -Be 10
            $result.TotalRowsDeleted | Should -Be 100
            $result.LogBackups.count | Should -Be 0
            $result.Timings.count | Should -Be 10
            $result.Database | Should -Be $dbnameFullModel
            (Invoke-DbaQuery -SqlInstance $server -Database $dbnameFullModel -Query 'SELECT COUNT(1) AS [RowCount] FROM dbo.Test').RowCount | Should -Be 0
        }
    }

    Context "Database param" {
        BeforeEach {
            $addRowsToFullModelDb = Invoke-DbaQuery -SqlInstance $server -Database $dbnameFullModel -Query $sqlAddRows
            $addRowsToBulkLoggedModelDb = Invoke-DbaQuery -SqlInstance $server -Database $dbnameBulkLoggedModel -Query $sqlAddRows
        }

        It 'Removes Data from multiple databases via the Database param' {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameBulkLoggedModel, $dbnameFullModel -Table dbo.Test -BatchSize 10 -LogBackupPath $logBackupPath -Confirm:$false

            $result[0].TotalIterations | Should -Be 10
            $result[0].TotalRowsDeleted | Should -Be 100
            $result[0].LogBackups.count | Should -Be 10
            $result[0].Timings.count | Should -Be 10

            $result[1].TotalIterations | Should -Be 10
            $result[1].TotalRowsDeleted | Should -Be 100
            $result[1].LogBackups.count | Should -Be 10
            $result[1].Timings.count | Should -Be 10

            $result.Database | Should -BeIn @($dbnameBulkLoggedModel, $dbnameFullModel)
            (Invoke-DbaQuery -SqlInstance $server -Database $dbnameBulkLoggedModel -Query 'SELECT COUNT(1) AS [RowCount] FROM dbo.Test').RowCount | Should -Be 0
            (Invoke-DbaQuery -SqlInstance $server -Database $dbnameFullModel -Query 'SELECT COUNT(1) AS [RowCount] FROM dbo.Test').RowCount | Should -Be 0
        }
    }

    Context "Pipeline test for multiple databases" {
        BeforeEach {
            $addRowsToFullModelDb = Invoke-DbaQuery -SqlInstance $server -Database $dbnameFullModel -Query $sqlAddRows
            $addRowsToBulkLoggedModelDb = Invoke-DbaQuery -SqlInstance $server -Database $dbnameBulkLoggedModel -Query $sqlAddRows
        }

        It 'Removes Data from multiple databases via pipeline' {
            $result = (Get-DbaDatabase -SqlInstance $server -Database $dbnameBulkLoggedModel, $dbnameFullModel | Remove-DbaDbTableData -Table dbo.Test -BatchSize 10 -LogBackupPath $logBackupPath -Confirm:$false)

            $result[0].TotalIterations | Should -Be 10
            $result[0].TotalRowsDeleted | Should -Be 100
            $result[0].LogBackups.count | Should -Be 10
            $result[0].Timings.count | Should -Be 10

            $result[1].TotalIterations | Should -Be 10
            $result[1].TotalRowsDeleted | Should -Be 100
            $result[1].LogBackups.count | Should -Be 10
            $result[1].Timings.count | Should -Be 10

            $result.Database | Should -BeIn @($dbnameBulkLoggedModel, $dbnameFullModel)
            (Invoke-DbaQuery -SqlInstance $server -Database $dbnameBulkLoggedModel -Query 'SELECT COUNT(1) AS [RowCount] FROM dbo.Test').RowCount | Should -Be 0
            (Invoke-DbaQuery -SqlInstance $server -Database $dbnameFullModel -Query 'SELECT COUNT(1) AS [RowCount] FROM dbo.Test').RowCount | Should -Be 0
        }
    }

    Context "Pipeline test for multiple servers" {
        BeforeEach {
            $addRowsToSingleModelDb = Invoke-DbaQuery -SqlInstance $server -Database $dbnameSimpleModel -Query $sqlAddRows
            $addRowsToSingleModelDbServer2 = Invoke-DbaQuery -SqlInstance $server2 -Database $dbnameSimpleModel -Query $sqlAddRows
        }

        It 'Removes Data from multiple servers via pipeline' {
            $result = ([DbaInstanceParameter[]]$server.Name, $server2 | Remove-DbaDbTableData -Database $dbnameSimpleModel -Table dbo.Test -BatchSize 10 -Confirm:$false)

            $result[0].TotalIterations | Should -Be 10
            $result[0].TotalRowsDeleted | Should -Be 100
            $result[0].LogBackups.count | Should -Be 0
            $result[0].Timings.count | Should -Be 10

            $result[1].TotalIterations | Should -Be 10
            $result[1].TotalRowsDeleted | Should -Be 100
            $result[1].LogBackups.count | Should -Be 0
            $result[1].Timings.count | Should -Be 10

            $result.Database | Should -BeIn @($dbnameSimpleModel, $dbnameSimpleModel)
            $result.InstanceName | Should -BeIn @($server.Name, $server2.Name)

            (Invoke-DbaQuery -SqlInstance $server -Database $dbnameSimpleModel -Query 'SELECT COUNT(1) AS [RowCount] FROM dbo.Test').RowCount | Should -Be 0
            (Invoke-DbaQuery -SqlInstance $server2 -Database $dbnameSimpleModel -Query 'SELECT COUNT(1) AS [RowCount] FROM dbo.Test').RowCount | Should -Be 0
        }
    }
}