function Remove-DbaDbTableData {
    <#
    .SYNOPSIS
        Performs batch deletion of table data while controlling transaction log growth during large-scale data removal operations.

    .DESCRIPTION
        Safely removes large amounts of table data without causing transaction log file growth issues that typically occur with single large DELETE operations. This command implements Aaron Bertrand's chunked deletion technique (https://sqlperformance.com/2013/03/io-subsystem/chunk-deletes) to break large deletions into manageable batches, preventing log file expansion and blocking issues.

        This is essential for DBAs who need to purge historical data, clean up audit tables, implement data retention policies, or remove test data without impacting database performance or running out of log space. The command automatically handles transaction log management based on your recovery model - taking log backups for Full/Bulk-logged recovery or performing checkpoints for Simple recovery.

        Foreign key constraints are respected and not temporarily disabled, so you need to delete from dependent tables first or ensure cascading deletes are configured. The command works with both on-premises SQL Server and Azure SQL Database, automatically adjusting log management strategies for each platform.

        Two deletion modes are supported:
        1. Simple table deletion using -Table and -BatchSize parameters where the DELETE statement is automatically generated
        2. Complex deletions with custom WHERE clauses, JOINs, or ORDER BY using the -DeleteSql parameter for advanced scenarios

        The command returns detailed metadata about the deletion process including row counts, timing information, and log backup details to help you monitor progress and performance.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to include in the table data removal operation. Accepts wildcards for pattern matching.
        If unspecified, all user databases on the instance will be processed, which means the same table deletion will occur across multiple databases.

    .PARAMETER BatchSize
        Controls how many rows are deleted per batch to prevent transaction log growth and blocking issues. Defaults to 100,000 rows and accepts values between 1 and 1 billion.
        Use smaller batch sizes (10,000-50,000) for heavily indexed tables or when other users need access during the operation. Can only be used with -Table parameter.
        For Azure SQL databases, large batch sizes may trigger error 40552 due to transaction log space limits.

    .PARAMETER Table
        Specifies the fully qualified table name from which to delete data (e.g., dbo.CustomerHistory, Sales.OrderDetails).
        Use this for simple scenarios where you want to delete all rows from a table. For complex deletions with WHERE clauses or JOINs, use -DeleteSql instead.

    .PARAMETER DeleteSql
        Provides a custom DELETE statement for complex deletion scenarios involving WHERE clauses, JOINs, or ORDER BY conditions.
        Must include a TOP (N) clause to control batch size (e.g., "DELETE TOP (100000) FROM dbo.Orders WHERE OrderDate < '2020-01-01'").
        Use this when -Table parameter is insufficient for your deletion logic. Cannot be combined with -Table or -BatchSize parameters.

    .PARAMETER LogBackupPath
        Specifies the directory path where transaction log backup files will be created during the deletion process.
        Required for databases in Full or Bulk-logged recovery models to prevent log file growth during large deletions. Only applies to on-premises SQL Server instances.
        The SQL Server service account must have write permissions to this directory. Not used for Simple recovery model or Azure SQL databases.

    .PARAMETER LogBackupTimeStampFormat
        Controls the timestamp format used in transaction log backup file names. Defaults to 'yyyyMMddHHmm' (e.g., 202312151430).
        Use Get-Date format strings to customize the naming pattern. Invalid formats will cause the operation to fail.
        Helps organize log backup files chronologically when performing multiple large deletion operations.

    .PARAMETER AzureBaseUrl
        Specifies the Azure Storage container URL for storing transaction log backups during the deletion process.
        Use this when you need log backups stored in Azure Blob Storage instead of local file system storage.
        Cannot be combined with -LogBackupPath parameter. See Backup-DbaDatabase documentation for container URL format requirements.

    .PARAMETER AzureCredential
        Provides the credential name for authenticating to Azure Storage when using -AzureBaseUrl for log backups.
        Must reference a SQL Server credential that contains the Azure Storage account access key or SAS token.
        Required when backing up transaction logs to Azure Blob Storage during the deletion process.

    .PARAMETER InputObject
        Accepts piped input from other dbatools commands like Get-DbaDatabase or Connect-DbaInstance.
        Use this to chain commands together, such as filtering databases first and then performing table data removal.
        Supports Database, Server, and DbaInstanceParameter objects from the dbatools pipeline.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts for confirmation before executing any data modification operations.

    .OUTPUTS
        PSCustomObject

        Returns one object per database where table data removal was performed, providing detailed metrics about the batch deletion operation.

        Default display properties (via Select-DefaultView):
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The name of the SQL Server instance
        - Database: The name of the database where table data was removed
        - Sql: The T-SQL DELETE statement that was executed
        - TotalRowsDeleted: The total number of rows deleted from the table across all batches (integer)
        - TotalTimeMillis: The total execution time for all delete operations in milliseconds (double)
        - AvgTimeMillis: The average execution time per batch iteration in milliseconds (double)
        - TotalIterations: The number of batch iterations performed (integer)

        Additional properties available (all properties accessible via Select-Object *):
        - Timings: Array of TimeSpan objects representing the execution time of each individual batch deletion iteration
        - LogBackups: Array of backup objects returned from Backup-DbaDatabase operations performed during the deletion (empty for Simple recovery model or Azure SQL Database)

        When using Select-DefaultView without parameters, only the default properties listed above are displayed. Use Select-Object * to access the Timings and LogBackups array properties if needed for advanced analysis of the deletion performance metrics.

    .NOTES
        Tags: Table, Data
        Author: Adam Lancaster, github.com/lancasteradam

        Website: https://dbatools.io
        Copyright: (c) 2020 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Reference material used: https://sqlperformance.com/2013/03/io-subsystem/chunk-deletes by Aaron Bertrand

    .LINK
        https://dbatools.io/Remove-DbaDbTableData

    .EXAMPLE
        PS C:\> Remove-DbaDbTableData -SqlInstance localhost -Database TestDb -Table dbo.Test -BatchSize 1000000 -LogBackupPath E:\LogBackups -Confirm:$false

        Removes all data from the dbo.Test table in the TestDb database on the local SQL instance. The deletes are done in batches of 1000000 rows each and the log backups are written to E:\LogBackups.

    .EXAMPLE
        PS C:\> Remove-DbaDbTableData -SqlInstance localhost -Database TestDb -DeleteSql "DELETE TOP (1000000) deleteFromTable FROM dbo.Test deleteFromTable LEFT JOIN dbo.Test2 b ON deleteFromTable.Id = b.Id" -LogBackupPath E:\LogBackups -Confirm:$false

        Removes data from the dbo.Test table in the TestDb database on the local SQL instance. When specifying -DeleteSql the DELETE statement needs to specify the TOP (N) clause. In this example the deletes are done in batches of 1000000 rows each and the log backups are written to E:\LogBackups.

    .EXAMPLE
        PS C:\> Remove-DbaDbTableData -SqlInstance localhost -Database TestDb -Table dbo.Test -DeleteSql "WITH ToDelete AS (SELECT TOP (1000000) Id FROM dbo.Test ORDER BY Id DESC;) DELETE FROM ToDelete;" -LogBackupPath E:\LogBackups -Confirm:$false

        Removes data from the dbo.Test table based on the DELETE statement specified in the -DeleteSql. The deletes occur in the TestDb database on the local SQL instance. The deletes are done in batches of 1000000 rows each and the log backups are written to E:\LogBackups.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance localhost -Database TestDb1, TestDb2  | Remove-DbaDbTableData -Table dbo.Test -BatchSize 1000000 -LogBackupPath E:\LogBackups -Confirm:$false

        Removes data from the dbo.Test table in the TestDb1 and TestDb2 databases on the local SQL instance. The deletes are done in batches of 1000000 rows each and the log backups are written to E:\LogBackups.

    .EXAMPLE
        PS C:\> $server, $server2 | Remove-DbaDbTableData -Database TestDb -Table dbo.Test -BatchSize 1000000 -LogBackupPath E:\LogBackups -Confirm:$false

        Removes data from the dbo.Test table in the TestDb database on the SQL instances represented by $server and $server2. The deletes are done in batches of 1000000 rows each and the log backups are written to E:\LogBackups.

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -ConnectionString "Data Source=TCP:yourserver.database.windows.net,1433;MultipleActiveResultSets=False;Connect Timeout=30;Encrypt=True;TrustServerCertificate=False;User Id=dbuser;Password=strongpassword;Database=TestDb"

        Remove-DbaDbTableData -SqlInstance $server -Database TestDb -Table dbo.Test -BatchSize 1000000 -Confirm:$false

        Removes data from the dbo.Test table in the TestDb database on the Azure SQL server yourserver.database.windows.net. The deletes are done in batches of 1000000 rows. Log backups are managed by Azure SQL. Note: for Azure SQL databases error 40552 could occur for large batch deletions: https://docs.microsoft.com/en-us/azure/azure-sql/database/troubleshoot-common-errors-issues#error-40552-the-session-has-been-terminated-because-of-excessive-transaction-log-space-usage
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [ValidateRange(1, 1000000000)][int]$BatchSize = 100000,
        [string]$Table,
        [string]$DeleteSql,
        [string]$LogBackupPath,
        [string]$LogBackupTimeStampFormat,
        [string[]]$AzureBaseUrl,
        [string]$AzureCredential,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        if ((Test-Bound Table) -and (Test-Bound DeleteSql)) {
            Stop-Function -Message "You must specify either -Table or -DeleteSql, but not both. See the command description for more details."
            return
        }

        if (-not $Table -and -not $DeleteSql) {
            Stop-Function -Message "You must specify either -Table or -DeleteSql. See the command description for more details."
            return
        }

        if ((Test-Bound BatchSize) -and (Test-Bound DeleteSql)) {
            Stop-Function -Message "When using -DeleteSql the -BatchSize param cannot be used. See the command description for more details."
            return
        }

        if ((Test-Bound LogBackupPath) -and (Test-Bound AzureBaseUrl)) {
            Stop-Function -Message "You must specify either -LogBackupPath or -AzureBaseUrl, but not both. See the command description for more details."
            return
        }

        if (Test-Bound DeleteSql) {
            if ($DeleteSql -inotmatch "top") {
                Stop-Function -Message "To use the -DeleteSql param you must specify the TOP (N) clause in the DELETE statement. See the command description for more details."
                return
            }

            if ($DeleteSql -inotmatch "delete") {
                Stop-Function -Message "The -DeleteSql param must be a DELETE statement with a TOP (N) clause. See the command description for more details."
                return
            }
        }

        if (-not (Test-Bound 'LogBackupTimeStampFormat')) {
            Write-Message -Message 'Setting Default LogBackupTimeStampFormat' -Level Verbose
            $LogBackupTimeStampFormat = "yyyyMMddHHmm"
        }

        # build the delete statement based on the caller's parameters
        $sql = "
            SET DEADLOCK_PRIORITY LOW;
            SET NOCOUNT ON;
            SET XACT_ABORT ON;

            DECLARE
                @RowCount       INTEGER         = 0
            ,   @ErrorMessage   NVARCHAR(MAX)   = NULL;

            BEGIN TRANSACTION;

            BEGIN TRY
            "

        if (Test-Bound Table) {
            $sql += "    DELETE TOP ($BatchSize) FROM $Table;"
        } elseif (Test-Bound DeleteSql) {
            $sql += "    $DeleteSql;"
        }

        $sql += "
                SET @RowCount = @@ROWCOUNT;
                COMMIT TRANSACTION;
            END TRY
            BEGIN CATCH
                SET @ErrorMessage = 'Error number = ' + CAST(ERROR_NUMBER() AS NVARCHAR(MAX)) +
                                    ', Severity = ' + CAST(ERROR_SEVERITY() AS NVARCHAR(MAX)) +
                                    ', Line = ' + CAST(ERROR_LINE() AS NVARCHAR(MAX)) +
                                    ', Message = ' + CAST(ERROR_MESSAGE() AS NVARCHAR(MAX));

                IF @@TRANCOUNT > 0
                    ROLLBACK TRANSACTION;
            END CATCH;

            SELECT
                @RowCount       AS [RowCount]
            ,   @ErrorMessage   AS ErrorMessage;"
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must specify a SqlInstance or pipe in a database or a server. See the command description."
            return
        }

        if ($SqlInstance) {
            $InputObject = $SqlInstance
        }

        foreach ($input in $InputObject) {
            $inputType = $input.GetType().FullName
            switch ($inputType) {
                # get the db(s) based on the caller's parameters
                'Dataplat.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject"
                    $dbDatabases = Get-DbaDatabase -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeSystem
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject"
                    $dbDatabases = Get-DbaDatabase -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeSystem
                }
                'Microsoft.SqlServer.Management.Smo.Database' {
                    Write-Message -Level Verbose -Message "Processing Database through InputObject"
                    $dbDatabases = $input | Where-Object { -not $_.IsSystemObject }
                }
                default {
                    Stop-Function -Message "InputObject is not a server or database. See the command description for examples."
                    return
                }
            }

            foreach ($db in $dbDatabases) {

                $server = $db.Parent

                if (Test-Bound LogBackupPath -and $server.DatabaseEngineType -ne "SqlAzureDatabase") {
                    $pathCheck = Test-DbaPath -SqlInstance $server -Path $LogBackupPath
                    if (-not $pathCheck) {
                        Stop-Function -Message "The service account for $server is not able to create log backups in $LogBackupPath."
                        return
                    }
                }

                # warn the caller if the database is using one of these configurations for on-prem
                if ($server.DatabaseEngineType -ne "SqlAzureDatabase") {

                    $isDbLogShipping = $db.Query("SELECT COUNT(1) FROM msdb.dbo.log_shipping_monitor_primary WHERE primary_database = '$($db.Name)'")

                    if ($isDbLogShipping -eq 1) {
                        Write-Message -Level Warning -Message "$($db.Name) is the primary db in a log shipping configuration. Be sure to re-sync after this command completes."
                    }

                    if ($db.IsMirroringEnabled) {
                        Write-Message -Level Warning -Message "$($db.Name) is configured for mirroring. Be sure to validate the mirror is synchronized after this command completes."
                    }

                    if (-not [string]::IsNullOrEmpty($db.AvailabilityGroupName)) {
                        Write-Message -Level Warning -Message "$($db.Name) is part of an availability group. Be sure to validate the secondary database(s) is synchronized after this command completes."
                    }
                }

                if ($Pscmdlet.ShouldProcess($db.Name, "Removing data using $sql on $($db.Parent.Name)")) {

                    # metadata to collect while running the loop
                    $totalRowsDeleted = 0
                    $totalTimeMillis = 0
                    $iterationCount = 0
                    $logBackupsArray = @()
                    $timingsArray = @()

                    do {
                        $rowCount = 0

                        try {
                            $commandTiming = Measure-Command {
                                $result = $db.Query($sql)
                            }

                            # Check if a runtime error occurred during the delete. Malformed SQL errors skip over this and end up in the catch block below.
                            if (-not [string]::IsNullOrEmpty($result.ErrorMessage)) {
                                throw $result.ErrorMessage
                            }

                            $rowCount = $result.RowCount

                            if ($rowCount -gt 0) {
                                # rows were deleted on the last statement execution, so collect the metadata and print out a verbose message.
                                $totalRowsDeleted += $rowCount
                                $timingsArray += $commandTiming
                                $totalTimeMillis += $commandTiming.TotalMilliseconds

                                Write-Message -Level Verbose -Message "Iteration $iterationCount took $($commandTiming.TotalMilliseconds) milliseconds to remove $rowCount rows"
                            }
                        } catch {
                            Stop-Function -Message "Error removing data from $Table $DeleteSql using $sql on $($db.Parent.Name)" -ErrorRecord $_
                            return
                        }

                        if ($rowCount -gt 0) {
                            $iterationCount += 1

                            #If the db is in Azure then we won't do a checkpoint or a log backup since those are automatically managed.
                            if ($server.DatabaseEngineType -ne "SqlAzureDatabase") {

                                if ($db.RecoveryModel -eq "Simple") {
                                    try {
                                        $checkPointResult = $db.Query("CHECKPOINT")

                                        if (-not [string]::IsNullOrEmpty($checkPointResult.ErrorMessage)) {
                                            throw $checkPointResult.ErrorMessage
                                        }
                                    } catch {
                                        Stop-Function -Message "Error during checkpoint on $($db.Parent.Name)" -ErrorRecord $_
                                        return
                                    }

                                } else {
                                    # bulk-logged or full recovery model

                                    if (Test-Bound LogBackupPath) {
                                        $timestamp = Get-Date -Format $LogBackupTimeStampFormat
                                        $logBackupsArray += Backup-DbaDatabase -SqlInstance $server -Database $db.Name -Type Log -FilePath "$LogBackupPath\$($db.Name)_$($timestamp)_$($iterationCount).trn"
                                    } elseif (Test-Bound AzureBaseUrl) {
                                        $logBackupsArray += Backup-DbaDatabase -SqlInstance $server -Database $db.Name -Type Log -AzureBaseUrl $AzureBaseUrl -AzureCredential $AzureCredential
                                    }
                                }
                            }
                        }

                        if (Test-FunctionInterrupt) { return }

                    } while ($rowCount -gt 0)

                    [PSCustomObject]@{
                        ComputerName     = $db.Parent.ComputerName
                        InstanceName     = $db.Parent.Name
                        Database         = $db.Name
                        Sql              = $sql
                        TotalRowsDeleted = $totalRowsDeleted
                        Timings          = $timingsArray
                        TotalTimeMillis  = $totalTimeMillis
                        AvgTimeMillis    = $totalTimeMillis / $(if ($iterationCount -le 0) { 1 } else { $iterationCount })
                        TotalIterations  = $iterationCount
                        LogBackups       = $logBackupsArray

                    } | Select-DefaultView -Property "ComputerName", "InstanceName", "Database", "Sql", "TotalRowsDeleted", "TotalTimeMillis", "AvgTimeMillis", "TotalIterations"
                }
            }
        }
    }
}