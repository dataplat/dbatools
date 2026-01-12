#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbTableData",
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
                "BatchSize",
                "Table",
                "DeleteSql",
                "LogBackupPath",
                "LogBackupTimeStampFormat",
                "AzureBaseUrl",
                "AzureCredential",
                "InputObject",
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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2

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
        $backupDbFull = Backup-DbaDatabase -SqlInstance $server -Database $dbnameFullModel -FilePath "$($TestConfig.Temp)\$dbnameFullModel.bak"
        $backupDbBulkLogged = Backup-DbaDatabase -SqlInstance $server -Database $dbnameBulkLoggedModel -FilePath "$($TestConfig.Temp)\$dbnameBulkLoggedModel.bak"
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

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        Get-DbaDatabase -SqlInstance $server -Database $dbnameSimpleModel, $dbnameFullModel, $dbnameBulkLoggedModel | Remove-DbaDatabase
        Get-DbaDatabase -SqlInstance $server2 -Database $dbnameSimpleModel | Remove-DbaDatabase

        # Remove backup files.
        Remove-Item -Path "$($TestConfig.Temp)\$dbnameFullModel*", "$($TestConfig.Temp)\$dbnameBulkLoggedModel*" -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Param validation" {
        It "Either -Table or -DeleteSql needs to be specified" {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameFullModel -WarningAction SilentlyContinue -WarningVariable warn
            $result | Should -BeNullOrEmpty
            $warn | Should -BeLike "*You must specify either -Table or -DeleteSql.*"

            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameFullModel -Table dbo.Test -DeleteSql "DELETE TOP (10) FROM dbo.Test" -WarningAction SilentlyContinue -WarningVariable warn
            $result | Should -BeNullOrEmpty
            $warn | Should -BeLike "*You must specify either -Table or -DeleteSql, but not both.*"
        }

        It "-BatchSize cannot be used when -DeleteSql is specified" {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameFullModel -DeleteSql "DELETE TOP (10) FROM dbo.Test" -BatchSize 10 -WarningAction SilentlyContinue -WarningVariable warn
            $result | Should -BeNullOrEmpty
            $warn | Should -BeLike "*When using -DeleteSql the -BatchSize param cannot be used.*"
        }

        It "Invalid -Table value is provided" {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameFullModel -Table InvalidTableName -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It "Invalid -DeleteSql due to missing DELETE keyword (i.e. user has not passed in a DELETE statement)" {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameFullModel -DeleteSql "SELECT TOP (10) FROM dbo.Test" -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It "Invalid -DeleteSql due to missing TOP (N) clause" {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameFullModel -DeleteSql "DELETE FROM dbo.Test" -WarningAction SilentlyContinue -WarningVariable warn
            $result | Should -BeNullOrEmpty
            $warn | Should -BeLike "*To use the -DeleteSql param you must specify the TOP (N) clause in the DELETE statement.*"
        }

        It "Invalid SQL used to test the error handling and reporting" {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameFullModel -DeleteSql "DELETE TOP (10) FROM dbo.Test WHERE 1/0 = 1" -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It "Either -LogBackupPath or -AzureBaseUrl needs to be specified, but not both" {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameFullModel -Table dbo.Test -LogBackupPath $logBackupPath -AzureBaseUrl https://dbatoolsaz.blob.core.windows.net/azbackups/ -WarningAction SilentlyContinue -WarningVariable warn
            $result | Should -BeNullOrEmpty
            $warn | Should -BeLike "*You must specify either -LogBackupPath or -AzureBaseUrl, but not both.*"
        }
    }

    Context "-DeleteSql examples" {
        BeforeEach {
            $addRowsToSimpleModelDb = Invoke-DbaQuery -SqlInstance $server -Database $dbnameSimpleModel -Query $sqlAddRows
        }

        It "-DeleteSql param is used to specify a delete based on a join" {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameSimpleModel -DeleteSql "DELETE TOP (10) deleteFromTable FROM dbo.Test deleteFromTable LEFT JOIN dbo.Test2 b ON deleteFromTable.Id = b.Id"
            $result.TotalIterations | Should -Be 10
            $result.TotalRowsDeleted | Should -Be 100
            $result.LogBackups.Count | Should -Be 0
            $result.Timings.Count | Should -Be 10
            $result.Database | Should -Be $dbnameSimpleModel
            (Invoke-DbaQuery -SqlInstance $server -Database $dbnameSimpleModel -Query "SELECT COUNT(1) AS [RowCount] FROM dbo.Test").RowCount | Should -Be 0
        }

        It "-DeleteSql param is used to specify an order by clause for the delete" {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameSimpleModel -DeleteSql "WITH ToDelete AS (SELECT TOP (10) Id FROM dbo.Test WHERE Id >= 50 ORDER BY Id DESC) DELETE FROM ToDelete"
            $result.TotalIterations | Should -Be 5
            $result.TotalRowsDeleted | Should -Be 50
            $result.LogBackups.Count | Should -Be 0
            $result.Timings.Count | Should -Be 5
            $result.Database | Should -Be $dbnameSimpleModel
            (Invoke-DbaQuery -SqlInstance $server -Database $dbnameSimpleModel -Query "SELECT COUNT(1) AS [RowCount] FROM dbo.Test").RowCount | Should -Be 50
        }
    }

    Context "Functionality with simple recovery model" {
        BeforeEach {
            $addRowsToSimpleModelDb = Invoke-DbaQuery -SqlInstance $server -Database $dbnameSimpleModel -Query $sqlAddRows
        }

        It "Removes Data for a specified database" {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameSimpleModel -Table dbo.Test -BatchSize 10
            $result.TotalIterations | Should -Be 10
            $result.TotalRowsDeleted | Should -Be 100
            $result.LogBackups.Count | Should -Be 0
            $result.Timings.Count | Should -Be 10
            $result.Database | Should -Be $dbnameSimpleModel
            (Invoke-DbaQuery -SqlInstance $server -Database $dbnameSimpleModel -Query "SELECT COUNT(1) AS [RowCount] FROM dbo.Test").RowCount | Should -Be 0
        }
    }

    Context "Functionality with bulk_logged recovery model" {
        BeforeEach {
            $addRowsToBulkLoggedDb = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database $dbnameBulkLoggedModel -Query $sqlAddRows
        }

        It "Removes Data for a specified database" {
            $bulkLoggedServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -Database $dbnameBulkLoggedModel -NonPooledConnection
            $result = Remove-DbaDbTableData -SqlInstance $bulkLoggedServer -Database $dbnameBulkLoggedModel -Table dbo.Test -BatchSize 10 -LogBackupPath $logBackupPath
            $result.TotalIterations | Should -Be 10
            $result.TotalRowsDeleted | Should -Be 100
            $result.LogBackups.Count | Should -Be 10
            $result.Timings.Count | Should -Be 10
            $result.Database | Should -Be $dbnameBulkLoggedModel
            (Invoke-DbaQuery -SqlInstance $bulkLoggedServer -Database $dbnameBulkLoggedModel -Query "SELECT COUNT(1) AS [RowCount] FROM dbo.Test").RowCount | Should -Be 0
        }
    }

    Context "Functionality with full recovery model" {
        BeforeEach {
            $addRowsToFullModelDb = Invoke-DbaQuery -SqlInstance $server -Database $dbnameFullModel -Query $sqlAddRows
        }

        It 'Removes Data for a specified database and specifies LogBackupTimeStampFormat' {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameFullModel -Table dbo.Test -BatchSize 10 -LogBackupPath $logBackupPath -LogBackupTimeStampFormat "yyMMddHHmm"
            $result.TotalIterations | Should -Be 10
            $result.TotalRowsDeleted | Should -Be 100
            $result.LogBackups.Count | Should -Be 10
            $result.Timings.Count | Should -Be 10
            $result.Database | Should -Be $dbnameFullModel
            (Invoke-DbaQuery -SqlInstance $server -Database $dbnameFullModel -Query "SELECT COUNT(1) AS [RowCount] FROM dbo.Test").RowCount | Should -Be 0
        }

        It "The LogBackupPath param is not specified so no log backups are taken" {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameFullModel -Table dbo.Test -BatchSize 10
            $result.TotalIterations | Should -Be 10
            $result.TotalRowsDeleted | Should -Be 100
            $result.LogBackups.Count | Should -Be 0
            $result.Timings.Count | Should -Be 10
            $result.Database | Should -Be $dbnameFullModel
            (Invoke-DbaQuery -SqlInstance $server -Database $dbnameFullModel -Query "SELECT COUNT(1) AS [RowCount] FROM dbo.Test").RowCount | Should -Be 0
        }

        It "Test with an invalid LogBackupPath location" {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameFullModel -Table dbo.Test -BatchSize 10 -LogBackupPath "C:\dbatools\$(Get-Random)" -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Database param" {
        BeforeEach {
            $addRowsToFullModelDb = Invoke-DbaQuery -SqlInstance $server -Database $dbnameFullModel -Query $sqlAddRows
            $addRowsToBulkLoggedModelDb = Invoke-DbaQuery -SqlInstance $server -Database $dbnameBulkLoggedModel -Query $sqlAddRows
        }

        It "Removes Data from multiple databases via the Database param" {
            $result = Remove-DbaDbTableData -SqlInstance $server -Database $dbnameBulkLoggedModel, $dbnameFullModel -Table dbo.Test -BatchSize 10 -LogBackupPath $logBackupPath

            $result[0].TotalIterations | Should -Be 10
            $result[0].TotalRowsDeleted | Should -Be 100
            $result[0].LogBackups.Count | Should -Be 10
            $result[0].Timings.Count | Should -Be 10

            $result[1].TotalIterations | Should -Be 10
            $result[1].TotalRowsDeleted | Should -Be 100
            $result[1].LogBackups.Count | Should -Be 10
            $result[1].Timings.Count | Should -Be 10

            $result.Database | Should -BeIn @($dbnameBulkLoggedModel, $dbnameFullModel)
            (Invoke-DbaQuery -SqlInstance $server -Database $dbnameBulkLoggedModel -Query "SELECT COUNT(1) AS [RowCount] FROM dbo.Test").RowCount | Should -Be 0
            (Invoke-DbaQuery -SqlInstance $server -Database $dbnameFullModel -Query "SELECT COUNT(1) AS [RowCount] FROM dbo.Test").RowCount | Should -Be 0
        }
    }

    Context "Pipeline test for multiple databases" {
        BeforeEach {
            $addRowsToFullModelDb = Invoke-DbaQuery -SqlInstance $server -Database $dbnameFullModel -Query $sqlAddRows
            $addRowsToBulkLoggedModelDb = Invoke-DbaQuery -SqlInstance $server -Database $dbnameBulkLoggedModel -Query $sqlAddRows
        }

        It "Removes Data from multiple databases via pipeline" {
            $result = (Get-DbaDatabase -SqlInstance $server -Database $dbnameBulkLoggedModel, $dbnameFullModel | Remove-DbaDbTableData -Table dbo.Test -BatchSize 10 -LogBackupPath $logBackupPath)

            $result[0].TotalIterations | Should -Be 10
            $result[0].TotalRowsDeleted | Should -Be 100
            $result[0].LogBackups.Count | Should -Be 10
            $result[0].Timings.Count | Should -Be 10

            $result[1].TotalIterations | Should -Be 10
            $result[1].TotalRowsDeleted | Should -Be 100
            $result[1].LogBackups.Count | Should -Be 10
            $result[1].Timings.Count | Should -Be 10

            $result.Database | Should -BeIn @($dbnameBulkLoggedModel, $dbnameFullModel)
            (Invoke-DbaQuery -SqlInstance $server -Database $dbnameBulkLoggedModel -Query "SELECT COUNT(1) AS [RowCount] FROM dbo.Test").RowCount | Should -Be 0
            (Invoke-DbaQuery -SqlInstance $server -Database $dbnameFullModel -Query "SELECT COUNT(1) AS [RowCount] FROM dbo.Test").RowCount | Should -Be 0
        }
    }

    Context "Pipeline test for multiple servers" {
        BeforeEach {
            $addRowsToSingleModelDb = Invoke-DbaQuery -SqlInstance $server -Database $dbnameSimpleModel -Query $sqlAddRows
            $addRowsToSingleModelDbServer2 = Invoke-DbaQuery -SqlInstance $server2 -Database $dbnameSimpleModel -Query $sqlAddRows
        }

        It "Removes Data from multiple servers via pipeline" {
            $result = ([DbaInstanceParameter[]]$server.Name, $server2 | Remove-DbaDbTableData -Database $dbnameSimpleModel -Table dbo.Test -BatchSize 10)

            $result[0].TotalIterations | Should -Be 10
            $result[0].TotalRowsDeleted | Should -Be 100
            $result[0].LogBackups.Count | Should -Be 0
            $result[0].Timings.Count | Should -Be 10

            $result[1].TotalIterations | Should -Be 10
            $result[1].TotalRowsDeleted | Should -Be 100
            $result[1].LogBackups.Count | Should -Be 0
            $result[1].Timings.Count | Should -Be 10

            $result.Database | Should -BeIn @($dbnameSimpleModel, $dbnameSimpleModel)
            $result.InstanceName | Should -BeIn @($server.Name, $server2.Name)

            (Invoke-DbaQuery -SqlInstance $server -Database $dbnameSimpleModel -Query "SELECT COUNT(1) AS [RowCount] FROM dbo.Test").RowCount | Should -Be 0
            (Invoke-DbaQuery -SqlInstance $server2 -Database $dbnameSimpleModel -Query "SELECT COUNT(1) AS [RowCount] FROM dbo.Test").RowCount | Should -Be 0
        }
    }
}