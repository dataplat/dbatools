#ValidationTags#FlowControl#
function Restore-DbaFromDatabaseSnapshot {
    <#
    .SYNOPSIS
        Restores databases from snapshots

    .DESCRIPTION
        Restores the database from the snapshot, discarding every modification made to the database
        NB: Restoring to a snapshot will result in every other snapshot of the same database to be dropped
        It also fixes some long-standing bugs in SQL Server when restoring from snapshots

    .PARAMETER SqlInstance
        The SQL Server that you're connecting to

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server as a different user

    .PARAMETER Database
        Restores from the last snapshot databases with this names only. You can pass either Databases or Snapshots

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER Snapshot
        Restores databases from snapshots with this names only. You can pass either Databases or Snapshots

    .PARAMETER Force
        If restoring from a snapshot involves dropping any other shapshot, you need to explicitly
        use -Force to let this command delete the ones not involved in the restore process.
        Also, -Force will forcibly kill all running queries that prevent the restore process.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run

    .PARAMETER Confirm
        Prompts for confirmation of every step.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DisasterRecovery, Snapshot, Backup, Restore, Database
        Author: niphlod

        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Restore-DbaFromDatabaseSnapshoT

    .EXAMPLE
        Restore-DbaFromDatabaseSnapshot -SqlInstance sqlserver2014a -Database HR, Accounting

        Restores HR and Accounting databases using the latest snapshot available

    .EXAMPLE
        Restore-DbaFromDatabaseSnapshot -SqlInstance sqlserver2014a -Database HR -Force

        Restores HR database from latest snapshot and kills any active connections in the database on sqlserver2014a.

    .EXAMPLE
        Restore-DbaFromDatabaseSnapshot -SqlInstance sqlserver2014a -Snapshot HR_snap_20161201, Accounting_snap_20161101

        Restores databases from snapshots named HR_snap_20161201 and Accounting_snap_20161101
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstance[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [object[]]$Snapshot,
        [switch]$Force,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        if (!$Snapshot -and !$Database -and !$ExcludeDatabase) {
            Stop-Function -Message "You must specify either -Snapshot (to restore from) or -Database/-ExcludeDatabase (to restore to)"
        }

        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Connecting to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            #$allDbs = $server.Databases
            $alldbq = @"
SELECT sn.name AS Name,
       dt.name AS DatabaseSnapshotBaseName,
       sn.create_date AS CreateDate,
       CASE
           WHEN sn.source_database_id IS NOT NULL
           THEN CASE
                    WHEN dt.state = 6
                    THEN 0
                    ELSE 1
                END
           ELSE CASE
                    WHEN sn.state = 6
                    THEN 0
                    ELSE 1
                END
       END AS IsAccessible,
       CASE
           WHEN sn.source_database_id IS NOT NULL
           THEN 1
           ELSE 0
       END AS IsDatabaseSnapshot
FROM sys.databases sn
     LEFT JOIN sys.databases dt ON sn.source_database_id = dt.database_id
"@
            $alldbs = $server.Query($alldbq)
            # vault to hold all programmed operations from --> to
            $operations = @()

            if (!$Snapshot -and !$Database -and !$ExcludeDatabase) {
                # Restore all databases from the latest snapshot
                Write-Message -Level Verbose -Message "Selected all databases"
                $dbs = $allDbs | Where-Object IsDatabaseSnapshot -EQ $true
            }
            elseif ($Database) {
                # Restore only these databases from their latest snapshot
                <#
                    Note, for some reason lookup of this property has to be done using $_.DatabaseSnapshotBaseName
                    Removing this will cause: Where-Object : A positional parameter cannot be found that accepts argument 'System.Object[]'
                #>
                Write-Message -Level Verbose -Message "Selected only databases"
                $dbs = $allDbs | Where-Object {$Database -contains $_.DatabaseSnapshotBaseName}
            }
            elseif ($ExcludeDatabase) {
                Write-Message -Level Verbose -Message "Excluded only databases"
                $dbs = $allDbs | Where-Object {$ExcludeDatabase -NotContains $_.DatabaseSnapshotBaseName}
            }
            elseif ($Snapshot) {
                # Restore databases from these snapshots
                Write-Message -Level Verbose -Message "Selected only snapshots"
                $dbs = $allDbs | Where-Object { $Snapshot -contains $_.Name }
                $baseDatabases = $dbs | Select-Object -ExpandProperty DatabaseSnapshotBaseName | Get-Unique
                if ($baseDatabases.Count -ne $Snapshot.Count -and $dbs.Count -ne 0) {
                    Write-Message -Level Warning -Message "Multiple snapshots selected for the same database, skipping"
                    continue
                }
            }
            $opsHash = @{ }
            foreach ($db in $dbs) {
                if (-not($db.IsAccessible)) {
                    Write-Message -Level Warning -Message "Database $db is not accessible."
                    continue
                }
                if ($db.DatabaseSnapshotBaseName -notin $opsHash.Keys) {
                    if ($snapshot.Count -gt 0) {
                        # just in the need to drop every other snapshot
                        $toDrop = $allDbs | Where-Object { $_.DatabaseSnapshotBaseName -eq $db.DatabaseSnapshotBaseName }
                        $toDrop = $todrop | Select-Object Name
                        $opsHash[$db.DatabaseSnapshotBaseName] = @{
                            'from' = $db | Select-Object Name, DatabaseSnapshotBaseName, CreateDate
                            'drop' = $toDrop
                        }
                    }
                    else {
                        $opsHash[$db.DatabaseSnapshotBaseName] = @{
                            'from' = $db
                            'drop' = @()
                        }
                    }
                }
                else {
                    # store each older snapshot in the drop list while enumerating
                    if ($db.CreateDate -gt $opsHash[$db.DatabaseSnapshotBaseName]['from'].CreateDate) {
                        $prev = $opsHash[$db.DatabaseSnapshotBaseName]['from']
                        $opsHash[$db.DatabaseSnapshotBaseName]['from'] = $db | Select-Object Name, DatabaseSnapshotBaseName, CreateDate
                        $opsHash[$db.DatabaseSnapshotBaseName]['drop'] += $prev
                    }
                }
            }
            foreach ($dbName in $opsHash.Keys) {
                $drop = @()
                foreach ($toDrop in $opsHash[$dbName]['drop']) {
                    $drop += $toDrop.Name
                }
                $operations += @{
                    'from' = $opsHash[$dbName]['from'].Name
                    'to'   = $dbName
                    'drop' = $drop
                }
            }
            foreach ($op in $operations) {
                # Check if there are FS, because then a restore is not possible
                $all_FS = $server.Databases[$op['to']].FileGroups | Where-Object FileGroupType -EQ 'FileStreamDataFileGroup'
                if ($all_FS.Count -gt 0) {
                    Write-Message -Level Warning -Message "Database $($op['to']) has FileStream group(s). You cannot restore from snapshots"
                    [PSCustomObject]@{
                        ComputerName = $server.NetName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $op['to']
                        Snapshot     = $op['from']
                        Status       = 'Error'
                        Notes        = "Database $($op['to']) has FileStream group(s). You cannot restore from snapshots"
                    }
                    break
                }
                # Get log size and autogrowth
                $orig_logproperties = $server.Databases[$op['to']].LogFiles | Select-Object Id, Size, Growth, GrowthType
                # Drop what needs to be dropped
                $opError = $false

                if ($op['drop'].Count -gt 1 -and $Force -eq $false) {
                    $warnMsg = @()
                    $warnMsg += "The restore process for $($op['to']) from $($op['from']) needs to drop the following:"
                    foreach ($db in $op['drop']) {
                        $warnMsg += $db
                    }
                    $warnMsg += "Use -Force if you really want to drop these snapshots."
                    Write-Message -Level Warning -Message ($warnMsg -join "`n")
                    break
                }
                foreach ($drop in $op['drop']) {
                    if ($Pscmdlet.ShouldProcess($server.name, "Remove db snapshot $drop")) {
                        # skip it if it's the same name
                        if ($drop -ne $($op['from'])) {
                            try {
                                if ($Force) {
                                    # snapshot with open transactions cannot be dropped
                                    $server.KillAllProcesses($drop)
                                }
                                $null = $server.Query("USE master; DROP DATABASE [$drop]")
                                $status = "Dropped"
                            }
                            catch {
                                Write-Message -Level Warning -Message $_
                                $operror = $true
                                break
                            }
                        }
                    }
                }
                if ($opError) {
                    Write-Message -Level Warning -Message "Errors trying to restore $($op['to']) from $($op['from'])"
                    [PSCustomObject]@{
                        ComputerName = $server.NetName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $op['to']
                        Snapshot     = $op['from']
                        Status       = 'Error'
                        Notes        = "Failed to drop some snapshots"
                    }
                    break
                }

                # Need a proper restore now
                if ($Pscmdlet.ShouldProcess($server.DomainInstanceName, "Restore db $($op['to']) from $($op['from'])")) {
                    $query = "USE master; RESTORE DATABASE [$($op['to'])] FROM DATABASE_SNAPSHOT='$($op['from'])'"
                    try {
                        if ($Force) {
                            # for whatever reason, a snapshot with open transactions, albeit read-only, block the restore process
                            $server.KillAllProcesses($op['from'])
                            # for a "good" reason, all open transactions on the destination block the restore process
                            $server.KillAllProcesses($op['to'])
                        }
                        $null = $server.Query($query)
                    }
                    catch {
                        $opError = $true
                        $inner = $_.Exception.Message
                        Stop-Function -Message "Original exception: $inner, Query issued: $query, Error: $_.Exception.InnerException.InnerException.Message" -ErrorRecord $_
                    }
                }
                if ($operror) {
                    Write-Message -Level Warning -Message "Errors trying to restore $($op['to']) from $($op['from'])"
                    [PSCustomObject]@{
                        ComputerName = $server.NetName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $op['to']
                        Snapshot     = $op['from']
                        Status       = 'Error'
                        Notes        = ''
                    }
                    break
                }
                # Comparing sizes before and after, need to refresh to see if size
                foreach ($log in $server.Databases[$op['to']].LogFiles) {
                    $log.Refresh()
                }
                foreach ($log in $server.Databases[$op['to']].LogFiles) {
                    $matching = $orig_logproperties | Where-Object ID -EQ $log.ID
                    $changeflag = 0
                    foreach ($prop in @('Size', 'Growth', 'Growth', 'GrowthType')) {
                        if ($matching.$prop -ne $log.$prop) {
                            $changeflag = 1
                            $log.$prop = $matching.$prop
                        }
                    }
                    if ($changeflag -ne 0) {
                        Write-Message -Level Verbose -Message "Restoring original settings for log file"
                        $log.Alter()
                    }
                }
                [PSCustomObject]@{
                    ComputerName = $server.NetName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Database     = $op['to']
                    Snapshot     = $op['from']
                    Status       = 'Restored'
                    Notes        = 'Remember to take a backup now, and also to remove the snapshot if not needed'
                }
            }
        }
    }
}
