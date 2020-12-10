function Remove-DbaDbTableData {
    <#
    .SYNOPSIS
        Removes table data using a batch technique from a database(s) for each instance(s) of on-prem SQL Server. SQL Azure DB is not supported.

    .DESCRIPTION
        This command does a batch delete of table data using the technique described by Aaron Bertrand here: https://sqlperformance.com/2013/03/io-subsystem/chunk-deletes. The main goal of this command is to ensure that the log file size is controlled while deleting data. This command can be used for doing both very large deletes or small deletes. Foreign keys are not temporarily removed, so the caller needs to perform deletes in the correct order with dependent tables or enable cascading deletes. When a database is using the full or bulk_logged recovery model this command will take log backups at the end of each batch. If the database is using the simple recovery model then CHECKPOINTs will be performed. The object returned will contain metadata about the batch deletion process including the log backup details.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. This list is auto-populated from the server. If unspecified, all user databases will be processed.

    .PARAMETER BatchSize
        The number of rows to delete per batch. This param is defaulted to 100000 and limited to a value between 1 and 1000000000 (1 billion).

    .PARAMETER Table
        The name of the table that data should be deleted. This param is required except when FromSql is specified.

    .PARAMETER FromSql
        A SQL fragment that includes the FROM clause of a DELETE statement. This param facilitates a delete based on a join. The target table to delete data should have a table alias of 'deleteFromTable'. See the example command invocation for -FromSql. This param may be used instead of -Table.

    .PARAMETER WhereSql
        A SQL fragment for the WHERE clause of a DELETE statement. See the example command invocation for -WhereSql.

    .PARAMETER LogBackupPath
        The directory to store the log backups. This command creates log backups when the database is using the full or bulk_logged recovery models. If this param is not provided the command will not take log backups.

    .PARAMETER LogBackupTimeStampFormat
        By default the command timestamps the log backup files using the format yyyyMMddHHmm. The timestamp format should be defined using the Get-Date formats, because illegal formats will cause an error to be thrown.

    .PARAMETER AzureBaseUrl
        See https://dbatools.io/Backup-DbaDatabase for information on this parameter. This function invokes Backup-DbaDatabase with -AzureBaseUrl if it is provided.

    .PARAMETER AzureCredential
        See https://dbatools.io/Backup-DbaDatabase for information on this parameter. This function invokes Backup-DbaDatabase with -AzureCredential if it is provided.

    .PARAMETER InputObject
        Enables piped input of Microsoft.SqlServer.Management.Smo.Database, Microsoft.SqlServer.Management.Smo.Server, and Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter objects.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts for confirmation before executing any data modification operations.

    .NOTES
        Tags: Data, Database, Delete, LogFile, Performance, Remove, Space, Table
        Author: Adam Lancaster https://github.com/lancasteradam

        Website: https://dbatools.io
        Copyright: (c) 2020 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Reference material used: https://sqlperformance.com/2013/03/io-subsystem/chunk-deletes by Aaron Bertrand

    .LINK
        https://dbatools.io/Remove-DbaDbTableData

    .EXAMPLE
        PS C:\> Remove-DbaDbTableData -SqlInstance localhost -Database TestDb -Table dbo.Test -BatchSize 1000000 -LogBackupPath E:\LogBackups -Confirm:$false

        Removes all data from the dbo.Test table in the TestDb database on the local SQL instance. The deletes are dones in batches of 1000000 rows each and the log backups are written to E:\LogBackups.

    .EXAMPLE
        PS C:\> Remove-DbaDbTableData -SqlInstance localhost -Database TestDb -FromSql "FROM dbo.Test deleteFromTable LEFT JOIN dbo.Test2 b ON deleteFromTable.Id = b.Id" -BatchSize 1000000 -LogBackupPath E:\LogBackups -Confirm:$false

        Removes data from the dbo.Test table in the TestDb database on the local SQL instance. When specifying -FromSql the SQL fragment needs to have a table alias of 'deleteFromTable' for the target deletion table. The deletes are dones in batches of 1000000 rows each and the log backups are written to E:\LogBackups.

    .EXAMPLE
        PS C:\> Remove-DbaDbTableData -SqlInstance localhost -Database TestDb -Table dbo.Test -WhereSql "WHERE Id IN (SELECT TOP 1000000 Id FROM dbo.Test ORDER BY Id)" -BatchSize 1000000 -LogBackupPath E:\LogBackups -Confirm:$false

        Removes data from the dbo.Test table based on the ORDER BY specified in the -WhereSql. The deletes occur in the TestDb database on the local SQL instance. The deletes are dones in batches of 1000000 rows each and the log backups are written to E:\LogBackups.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance localhost -Database TestDb1, TestDb2  | Remove-DbaDbTableData -Table dbo.Test -BatchSize 1000000 -LogBackupPath E:\LogBackups -Confirm:$false

        Removes data from the dbo.Test table in the TestDb1 and TestDb2 databases on the local SQL instance. The deletes are dones in batches of 1000000 rows each and the log backups are written to E:\LogBackups.

    .EXAMPLE
        PS C:\> $server, $server2 | Remove-DbaDbTableData -Database TestDb -Table dbo.Test -BatchSize 1000000 -LogBackupPath E:\LogBackups -Confirm:$false

        Removes data from the dbo.Test table in the TestDb database on the SQL instances represented by $server and $server2. The deletes are dones in batches of 1000000 rows each and the log backups are written to E:\LogBackups.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [ValidateRange(1, 1000000000)][int]$BatchSize = 100000,
        [string]$Table,
        [string]$FromSql,
        [string]$WhereSql,
        [string]$LogBackupPath,
        [string]$LogBackupTimeStampFormat,
        [string[]]$AzureBaseUrl,
        [string]$AzureCredential,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        if ((Test-Bound Table) -and (Test-Bound FromSql)) {
            Stop-Function -Message "You must specify either -Table or -FromSql, but not both. See the command description for more details."
            return
        }

        if (-not $Table -and -not $FromSql) {
            Stop-Function -Message "You must specify either -Table or -FromSql. See the command description for more details."
            return
        }

        if (Test-Bound LogBackupPath) {
            $null = Test-ExportDirectory -Path $LogBackupPath
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
                DELETE TOP ($BatchSize) "

        if (Test-Bound Table) {
            $sql += " FROM $Table "
        } elseif (Test-Bound FromSql) {
            if ($FromSql -notmatch "deleteFromTable") {
                Stop-Function -Message "To use the -FromSql param you must alias the target table as 'deleteFromTable' in your FROM clause. See the command description for more details."
                return
            }

            $sql += " deleteFromTable $FromSql "
        }

        if (Test-Bound WhereSql) {
            $sql += " $WhereSql "
        }

        $sql += "
                ;SET @RowCount = @@ROWCOUNT;
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
                'Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter' {
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

                $instance = $db.Parent

                # warn the caller if the database is using one of these configurations.
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

                if ($instance.DatabaseEngineType -eq "SqlAzureDatabase") {
                    Stop-Function -Message "Sql Azure DB is not supported by this command."
                    return
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

                            if ( $rowCount -gt 0 ) {
                                # rows were deleted on the last statement execution, so collect the metadata and print out a verbose message.
                                $totalRowsDeleted += $rowCount
                                $timingsArray += $commandTiming
                                $totalTimeMillis += $commandTiming.TotalMilliseconds

                                Write-Message -Level Verbose -Message "Iteration $iterationCount took $($commandTiming.TotalMilliseconds) milliseconds to remove $rowCount rows"
                            }
                        } catch {
                            Stop-Function -Message "Error removing data from $Table $FromSql using $sql on $($db.Parent.Name)" -ErrorRecord $_
                            return
                        }

                        if ( $rowCount -gt 0 ) {
                            $iterationCount += 1

                            # perform a checkpoint or log backup depending on the recovery model
                            if ( $db.RecoveryModel -eq "Simple" ) {
                                $result = $db.Query("CHECKPOINT")
                            } elseif (Test-Bound LogBackupPath) {
                                $timestamp = Get-Date -Format $LogBackupTimeStampFormat

                                if (Test-Bound AzureBaseUrl) {
                                    $backupLog = Backup-DbaDatabase -SqlInstance $instance -Database $db.Name -Type Log -AzureBaseUrl $AzureBaseUrl -AzureCredential $AzureCredential
                                } else {
                                    $backupLog = Backup-DbaDatabase -SqlInstance $instance -Database $db.Name -Type Log -FilePath "$LogBackupPath\$($db.Name)_$($timestamp)_$($iterationCount).trn"
                                }
                                $logBackupsArray += $backupLog
                            }
                        }

                        if (Test-FunctionInterrupt) { return }

                    } while ($rowCount -gt 0)

                    [pscustomobject]@{
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