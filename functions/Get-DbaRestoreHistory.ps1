function Get-DbaRestoreHistory {
    <#
        .SYNOPSIS
            Returns restore history details for databases on a SQL Server.

        .DESCRIPTION
            By default, this command will return the server name, database, username, restore type, date, from file and to files.

            Thanks to https://www.mssqltips.com/SqlInstancetip/1724/when-was-the-last-time-your-sql-server-database-was-restored/ for the query and https://sqlstudies.com/2016/07/27/when-was-this-database-restored/ for the idea.

        .PARAMETER SqlInstance
            Specifies the SQL Server instance(s) to operate on. Requires SQL Server 2005 or higher.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Database
            Specifies the database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

        .PARAMETER ExcludeDatabase
            Specifies the database(s) to exclude from processing. Options for this list are auto-populated from the server.

        .PARAMETER Since
            Specifies a datetime to use as the starting point for searching backup history.

        .PARAMETER Force
            Deprecated.

        .PARAMETER Last
            If this switch is enabled, the last restore action performed on each database is returned.
        
        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: DisasterRecovery, Backup, Restore, Databases

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaRestoreHistory

        .EXAMPLE
            Get-DbaRestoreHistory -SqlInstance sql2016

            Returns server name, database, username, restore type, date for all restored databases on sql2016.

        .EXAMPLE
            Get-DbaRestoreHistory -SqlInstance sql2016 -Database db1, db2 -Since '7/1/2016 10:47:00'

            Returns restore information only for databases db1 and db2 on sql2016 since July 1, 2016 at 10:47 AM.

        .EXAMPLE
            Get-DbaRestoreHistory -SqlInstance sql2014, sql2016 -Exclude db1

            Lots of detailed information for all databases except db1 on sql2014 and sql2016.

        .EXAMPLE
            Get-DbaRestoreHistory -SqlInstance sql2014 -Database AdventureWorks2014, pubs | Format-Table

            Adds From and To file information to output, returns information only for AdventureWorks2014 and pubs, and formats the data as a table.

        .EXAMPLE
            Get-DbaRegisteredServer -SqlInstance sql2016 | Get-DbaRestoreHistory

            Returns database restore information for every database on every server listed in the Central Management Server on sql2016.

    #>
    [CmdletBinding()]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [datetime]$Since,
        [switch]$Force,
        [switch]$Last,
        [switch][Alias('Silent')]
        $EnableException
    )

    begin {
        Test-DbaDeprecation -DeprecatedOn "1.0.0.0" -EnableException:$false -Parameter 'Force'

        if ($Since -ne $null) {
            $Since = $Since.ToString("yyyy-MM-dd HH:mm:ss")
        }
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
                $computername = $server.NetName
                $instancename = $server.ServiceName
                $servername = $server.DomainInstanceName

                if ($force -eq $true) {
                    $select = "SELECT '$computername' AS [ComputerName],
                    '$instancename' AS [InstanceName],
                    '$servername' AS [SqlInstance], * "
                }
                else {
                    $select = "SELECT
                    '$computername' AS [ComputerName],
                    '$instancename' AS [InstanceName],
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
                    bs.backup_finish_date
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
                    $wherearray += "rsh.restore_date >= '$since'"
                }


                if ($last) {
                    $wherearray += "rsh.backup_set_id in
                        (select max(backup_set_id) from msdb.dbo.restorehistory
                        group by destination_database_name
                        )"
                }

                if ($where.length -gt 0) {
                    $wherearray = $wherearray -join " and "
                    $where = "$where $wherearray"
                }

                $sql = "$select $from $where"

                Write-Message -Level Debug -Message $sql

                $results = $server.ConnectionContext.ExecuteWithResults($sql).Tables.Rows

                if ($last) {
                    $ga = $results | group-Object database
                    $tmpres = @()
                    $ga | foreach-Object {
                        $tmpres += $_.Group | Sort-Object -Property RESTORE_DATE -Descending | Select-Object -first 1
                    }
                    $results = $tmpres
                }
                Select-DefaultView -InputObject $results -Exclude first_lsn, last_lsn, checkpoint_lsn, database_backup_lsn, RowError, RowState, Table, ItemArray, HasErrors
            }
            catch {
                Stop-Function -Message "Failure" -Target $SqlInstance -Error $_ -Exception $_.Exception.InnerException -Continue
            }
        }
    }
}
