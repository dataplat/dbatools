function Get-DbaDbRestoreHistory {
    <#
    .SYNOPSIS
        Retrieves database restore history from MSDB for compliance reporting and recovery analysis.

    .DESCRIPTION
        Queries the MSDB database's restorehistory and backupset tables to retrieve detailed information about all database restore operations performed on a SQL Server instance. This function returns comprehensive restore details including who performed the restore, when it occurred, what type of restore was performed, and the source and destination file paths.

        Use this command to track restore activity for compliance auditing, troubleshoot database issues by determining when databases were last restored, or investigate unexpected changes by identifying recent restore operations. The function supports filtering by database name, restore type (Database, File, Filegroup, Differential, Log, Verifyonly, Revert), date ranges, and can return only the most recent restore for each database.

        This eliminates the need to manually query MSDB system tables or write complex SQL joins to gather restore history information across multiple instances.

        Thanks to https://www.mssqltips.com/SqlInstancetip/1724/when-was-the-last-time-your-sql-server-database-was-restored/ for the query and https://sqlstudies.com/2016/07/27/when-was-this-database-restored/ for the idea.

    .PARAMETER SqlInstance
        Specifies the SQL Server instance(s) to operate on. Requires SQL Server 2005 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Filters restore history to specific database(s). Accepts wildcards for pattern matching.
        Use this when investigating restore activity for particular databases rather than reviewing all restore operations on the instance.

    .PARAMETER ExcludeDatabase
        Excludes specific database(s) from the restore history results. Accepts wildcards for pattern matching.
        Useful when you need to filter out system databases or other databases that aren't relevant to your investigation.

    .PARAMETER Since
        Filters restore history to operations that occurred on or after the specified date and time.
        Use this when investigating recent restore activity or limiting results to a specific time period for compliance reporting.

    .PARAMETER Force
        This parameter is deprecated and no longer used.
        Previously controlled whether to return all available columns, but this functionality has been removed.

    .PARAMETER Last
        Returns only the most recent restore operation for each database, filtering out all earlier restore history.
        Use this when you need to quickly identify when each database was last restored without seeing the full restore timeline.

    .PARAMETER RestoreType
        Filters results to a specific type of restore operation: Database, File, Filegroup, Differential, Log, Verifyonly, or Revert.
        Use this when troubleshooting specific restore scenarios, such as finding all log restores during a point-in-time recovery or identifying differential restores for performance analysis.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DisasterRecovery, Backup, Restore
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbRestoreHistory

    .EXAMPLE
        PS C:\> Get-DbaDbRestoreHistory -SqlInstance sql2016

        Returns server name, database, username, restore type, date for all restored databases on sql2016.

    .EXAMPLE
        PS C:\> Get-DbaDbRestoreHistory -SqlInstance sql2016 -Database db1, db2 -Since '2016-07-01 10:47:00'

        Returns restore information only for databases db1 and db2 on sql2016 since July 1, 2016 at 10:47 AM.

    .EXAMPLE
        PS C:\> Get-DbaDbRestoreHistory -SqlInstance sql2014, sql2016 -Exclude db1

        Returns restore information for all databases except db1 on sql2014 and sql2016.

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Get-DbaDbRestoreHistory -SqlInstance sql2014 -Database AdventureWorks2014, pubs -SqlCredential $cred | Format-Table

        Returns database restore information for AdventureWorks2014 and pubs database on sql2014, connects using SQL Authentication via sqladmin account. Formats the data as a table.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sql2016 | Get-DbaDbRestoreHistory

        Returns database restore information for every database on every server listed in the Central Management Server on sql2016.

    .EXAMPLE
        PS C:\> Get-DbaDbRestoreHistory -SqlInstance sql2016 -RestoreType Log

        Returns log restore information for every database on the sql2016 instance.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [datetime]$Since,
        [switch]$Force,
        [switch]$Last,
        [ValidateSet('Database', 'File', 'Filegroup', 'Differential', 'Log', 'Verifyonly', 'Revert')]
        [string]$RestoreType,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }
                $computername = $server.ComputerName
                $instanceName = $server.ServiceName
                $servername = $server.DomainInstanceName

                if ($force -eq $true) {
                    $select = "SELECT '$computername' AS [ComputerName],
                    '$instanceName' AS [InstanceName],
                    '$servername' AS [SqlInstance], * "
                } else {
                    $select = "SELECT
                    '$computername' AS [ComputerName],
                    '$instanceName' AS [InstanceName],
                    '$servername' AS [SqlInstance],
                     rsh.destination_database_name AS [Database],
                     --rsh.restore_history_id as RestoreHistoryID,
                     rsh.user_name AS [Username],
                     CASE
                         WHEN rsh.restore_type = 'D' THEN 'Database'
                         WHEN rsh.restore_type = 'F' THEN 'File'
                         WHEN rsh.restore_type = 'G' THEN 'Filegroup'
                         WHEN rsh.restore_type = 'I' THEN 'Differential'
                         WHEN rsh.restore_type = 'L' THEN 'Log'
                         WHEN rsh.restore_type = 'V' THEN 'Verifyonly'
                         WHEN rsh.restore_type = 'R' THEN 'Revert'
                         ELSE rsh.restore_type
                     END AS [RestoreType],
                     rsh.restore_date AS [Date],
                     ISNULL(STUFF((SELECT ', ' + bmf.physical_device_name
                                    FROM msdb.dbo.backupmediafamily bmf
                                   WHERE bmf.media_set_id = bs.media_set_id
                                 FOR XML PATH('')), 1, 2, ''), '') AS [From],
                     ISNULL(STUFF((SELECT ', ' + rf.destination_phys_name
                                    FROM msdb.dbo.restorefile rf
                                   WHERE rsh.restore_history_id = rf.restore_history_id
                                 FOR XML PATH('')), 1, 2, ''), '') AS [To],
                    bs.first_lsn,
                    bs.last_lsn,
                    bs.checkpoint_lsn,
                    bs.database_backup_lsn,
                    bs.backup_finish_date,
                    bs.backup_finish_date AS BackupFinishDate
                    "
                }

                $from = " FROM msdb.dbo.restorehistory rsh
                    INNER JOIN msdb.dbo.backupset bs ON rsh.backup_set_id = bs.backup_set_id"

                if ($ExcludeDatabase -or $Database -or $Since -or $last) {
                    $where = " WHERE "
                }

                $wherearray = @()

                if ($ExcludeDatabase) {
                    $dblist = $ExcludeDatabase -join "','"
                    $wherearray += " destination_database_name not in ('$dblist')"
                }

                if ($Database) {
                    $dblist = $Database -join "','"
                    $wherearray += "destination_database_name in ('$dblist')"
                }

                if ($null -ne $Since) {
                    $wherearray += "rsh.restore_date >= CONVERT(datetime,'$($Since.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))',126)"
                }

                if ($last) {
                    $wherearray += "rsh.restore_history_id IN
                        (SELECT MAX(restore_history_id) FROM msdb.dbo.restorehistory
                        GROUP BY destination_database_name
                        )"
                }

                if ($RestoreType) {
                    $wherearray += "rsh.restore_type =
                                        (CASE
                                            WHEN '$RestoreType' = 'Database'        THEN 'D'
                                            WHEN '$RestoreType' = 'File'            THEN 'F'
                                            WHEN '$RestoreType' = 'Filegroup'       THEN 'G'
                                            WHEN '$RestoreType' = 'Differential'    THEN 'I'
                                            WHEN '$RestoreType' = 'Log'             THEN 'L'
                                            WHEN '$RestoreType' = 'Verifyonly'      THEN 'V'
                                            WHEN '$RestoreType' = 'Revert'          THEN 'R'
                                            ELSE 'D'
                                        END)"
                }

                if ($where.length -gt 0) {
                    $wherearray = $wherearray -join " and "
                    $where = "$where $wherearray"
                }

                $sql = "$select $from $where"

                Write-Message -Level Debug -Message $sql

                $results = $server.ConnectionContext.ExecuteWithResults($sql).Tables.Rows
                if ($last) {
                    $ga = $results | Group-Object Database
                    $tmpres = @()
                    foreach ($g in $ga) {
                        $tmpres += $g.Group | Sort-Object -Property Date -Descending | Select-Object -First 1
                    }
                    $results = $tmpres
                }
                $results | Select-DefaultView -ExcludeProperty first_lsn, last_lsn, checkpoint_lsn, database_backup_lsn, backup_finish_date
            } catch {
                Stop-Function -Message "Failure" -Target $SqlInstance -Error $_ -Exception $_.Exception.InnerException -Continue
            }
        }
    }
}