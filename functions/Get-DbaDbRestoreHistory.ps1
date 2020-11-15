function Get-DbaDbRestoreHistory {
    <#
    .SYNOPSIS
        Returns restore history details for databases on a SQL Server.

    .DESCRIPTION
        By default, this command will return the server name, database, username, restore type, date, from file and to files.

        Thanks to https://www.mssqltips.com/SqlInstancetip/1724/when-was-the-last-time-your-sql-server-database-was-restored/ for the query and https://sqlstudies.com/2016/07/27/when-was-this-database-restored/ for the idea.

    .PARAMETER SqlInstance
        Specifies the SQL Server instance(s) to operate on. Requires SQL Server 2005 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

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
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
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