function Get-DbaDbBackupHistory {
    <#
    .SYNOPSIS
        Retrieves backup history records from MSDB for analysis and compliance reporting.

    .DESCRIPTION
        Queries the MSDB database backup tables to extract detailed backup history information including file paths, sizes, compression ratios, and LSN sequences. Essential for compliance auditing, disaster recovery planning, and troubleshooting backup issues without having to manually query system tables. The function automatically groups striped backup sets into single objects and excludes copy-only backups by default, making the output more practical for restoration scenarios. You can filter results by database name, backup type, date range, or retrieve only the most recent backup chains needed for point-in-time recovery.

        Reference: http://www.sqlhub.com/2011/07/find-your-backup-history-in-sql-server.html

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server instance as a different user. This can be a Windows or SQL Server account. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

    .PARAMETER Database
        Specifies one or more databases to include in the backup history search. Accepts wildcards for pattern matching.
        Use this when you need backup history for specific databases rather than all databases on the instance.

    .PARAMETER ExcludeDatabase
        Specifies one or more databases to exclude from the backup history search.
        Useful when you want history for most databases but need to skip system databases or specific user databases.

    .PARAMETER IncludeCopyOnly
        Includes copy-only backups in the results, which are normally excluded by default.
        Copy-only backups don't break the backup chain and are commonly used for ad-hoc backups or moving databases to other environments.

    .PARAMETER Force
        Returns all columns from the MSDB backup tables instead of the filtered standard output.
        Use this when you need access to additional backup metadata fields for detailed analysis or troubleshooting.

    .PARAMETER Since
        Filters backup history to only include backups taken after the specified date and time.
        Accepts DateTime objects or TimeSpan objects (which get added to the current time). Times are compared using the SQL Server instance's timezone.
        Essential for limiting results when dealing with databases that have extensive backup history.

    .PARAMETER RecoveryFork
        Filters results to a specific recovery fork GUID when a database has multiple recovery paths.
        Use this when a database has been restored from different backup chains or has experienced recovery fork scenarios, ensuring you get the correct backup sequence.

    .PARAMETER Last
        Returns the most recent complete backup chain (full, differential, and log backups) needed for point-in-time recovery.
        This provides the exact backup sequence you'd need to restore a database to its most current state.

    .PARAMETER LastFull
        Returns only the most recent full backup for each database.
        Use this to quickly identify the base backup needed for restore operations or to verify when the last full backup was taken.

    .PARAMETER LastDiff
        Returns only the most recent differential backup for each database.
        Useful for verifying differential backup schedules or identifying the latest differential backup in a restore scenario.

    .PARAMETER LastLog
        Returns only the most recent transaction log backup for each database.
        Critical for monitoring log backup frequency and identifying the latest point-in-time recovery option available.

    .PARAMETER DeviceType
        Filters backups by device type such as 'Disk', 'Tape', 'URL', or 'Virtual Device'.
        Use this to find backups stored on specific media types, particularly useful when backups go to different destinations like local disk vs cloud storage.

    .PARAMETER Raw
        Returns one object per backup file instead of grouping striped backup sets into single objects.
        Use this when you need to see individual backup file details for striped backups or need to analyze backup file distribution.

    .PARAMETER Type
        Filters results to specific backup types: 'Full', 'Log', 'Differential', 'File', 'Differential File', 'Partial Full', or 'Partial Differential'.
        Use this to focus on particular backup types when analyzing backup strategies or troubleshooting specific backup issues.

    .PARAMETER LastLsn
        Filters to only include backups with LSNs greater than the specified value, improving query performance on large backup histories.
        Use this when you know the LSN range you're interested in, typically when building restore sequences or analyzing backup chains.

    .PARAMETER IncludeMirror
        Includes mirror backup copies in the results, which are excluded by default.
        Use this when you need to see all backup copies created through backup mirroring, useful for verifying mirror backup configurations.

    .PARAMETER AgCheck
        Deprecated parameter. Use Get-DbaAgBackupHistory instead to retrieve backup history from all replicas in an Availability Group.
        This parameter is maintained for backward compatibility but no longer functions.

    .PARAMETER IgnoreDiffBackup
        Excludes differential backups from the results, showing only full and log backups.
        Useful when analyzing backup chains that don't use differential backups or when you want to focus on full and log backup patterns.

    .PARAMETER LsnSort
        Determines which LSN column to use for sorting results: 'FirstLsn', 'DatabaseBackupLsn', or 'LastLsn' (default).
        Use this to control backup ordering when working with complex backup scenarios or when you need results sorted by specific LSN checkpoints.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DisasterRecovery, Backup
        Author: Chrissy LeMaire (@cl) | Stuart Moore (@napalmgram)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbBackupHistory

    .EXAMPLE
        PS C:\> Get-DbaDbBackupHistory -SqlInstance SqlInstance2014a

        Returns server name, database, username, backup type, date for all database backups still in msdb history on SqlInstance2014a. This may return many rows; consider using filters that are included in other examples.

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        Get-DbaDbBackupHistory -SqlInstance SqlInstance2014a -SqlCredential $cred

        Does the same as above but connect to SqlInstance2014a as SQL user "sqladmin"

    .EXAMPLE
        PS C:\> Get-DbaDbBackupHistory -SqlInstance SqlInstance2014a -Database db1, db2 -Since ([DateTime]'2016-07-01 10:47:00')

        Returns backup information only for databases db1 and db2 on SqlInstance2014a since July 1, 2016 at 10:47 AM.

    .EXAMPLE
        PS C:\> Get-DbaDbBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014, pubs -Force | Format-Table

        Returns information only for AdventureWorks2014 and pubs and formats the results as a table.

    .EXAMPLE
        PS C:\> Get-DbaDbBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Last

        Returns information about the most recent full, differential and log backups for AdventureWorks2014 on sql2014.

    .EXAMPLE
        PS C:\> Get-DbaDbBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Last -DeviceType Disk

        Returns information about the most recent full, differential and log backups for AdventureWorks2014 on sql2014, but only for backups to disk.

    .EXAMPLE
        PS C:\> Get-DbaDbBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Last -DeviceType 148,107

        Returns information about the most recent full, differential and log backups for AdventureWorks2014 on sql2014, but only for backups with device_type 148 and 107.

    .EXAMPLE
        PS C:\> Get-DbaDbBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -LastFull

        Returns information about the most recent full backup for AdventureWorks2014 on sql2014.

    .EXAMPLE
        PS C:\> Get-DbaDbBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Type Full

        Returns information about all Full backups for AdventureWorks2014 on sql2014.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sql2016 | Get-DbaDbBackupHistory

        Returns database backup information for every database on every server listed in the Central Management Server on sql2016.

    .EXAMPLE
        PS C:\> Get-DbaDbBackupHistory -SqlInstance SqlInstance2014a, sql2016 -Force

        Returns detailed backup history for all databases on SqlInstance2014a and sql2016.

    .EXAMPLE
        PS C:\> Get-DbaDbBackupHistory -SqlInstance sql2016 -Database db1 -RecoveryFork 38e5e84a-3557-4643-a5d5-eed607bef9c6 -Last

        If db1 has multiple recovery forks, specifying the RecoveryFork GUID will restrict the search to that fork.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]
        $SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$IncludeCopyOnly,
        [Parameter(ParameterSetName = "NoLast")]
        [switch]$Force,
        [psobject]$Since = ([DateTime]::ParseExact("1970-01-01", "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)),
        [ValidateScript( { ($_ -match '^(\{){0,1}[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}(\}){0,1}$') -or ('' -eq $_) })]
        [string]$RecoveryFork,
        [switch]$Last,
        [switch]$LastFull,
        [switch]$LastDiff,
        [switch]$LastLog,
        [string[]]$DeviceType,
        [switch]$Raw,
        [bigint]$LastLsn,
        [switch]$IncludeMirror,
        [ValidateSet("Full", "Log", "Differential", "File", "Differential File", "Partial Full", "Partial Differential")]
        [string[]]$Type,
        [switch]$AgCheck,
        [switch]$IgnoreDiffBackup,
        [ValidateSet("FirstLsn", "DatabaseBackupLsn", "LastLsn")]
        [string]$LsnSort = "LastLsn",
        [switch]$EnableException
    )

    begin {
        Write-Message -Level System -Message "Active Parameter set: $($PSCmdlet.ParameterSetName)."
        Write-Message -Level System -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"

        $deviceTypeMapping = @{
            'Disk'                  = 2
            'Permanent Disk Device' = 102
            'Tape'                  = 5
            'Permanent Tape Device' = 105
            'Pipe'                  = 6
            'Permanent Pipe Device' = 106
            'Virtual Device'        = 7
            'URL'                   = 9
        }
        $deviceTypeFilter = @()
        foreach ($devType in $DeviceType) {
            if ($devType -in $deviceTypeMapping.Keys) {
                $deviceTypeFilter += $deviceTypeMapping[$devType]
            } else {
                $deviceTypeFilter += $devType
            }
        }
        $backupTypeMapping = @{
            'Log'                  = 'L'
            'Full'                 = 'D'
            'File'                 = 'F'
            'Differential'         = 'I'
            'Differential File'    = 'G'
            'Partial Full'         = 'P'
            'Partial Differential' = 'Q'
        }
        $backupTypeFilter = @()
        foreach ($typeFilter in $Type) {
            $backupTypeFilter += $backupTypeMapping[$typeFilter]
        }

        $internalLsnSort = switch ($LsnSort) {
            "FirstLsn" { "first_lsn" }
            "DatabaseBackupLsn" { "database_backup_lsn" }
            "LastLsn" { "last_lsn" }
        }
    }

    process {
        if ($AgCheck) {
            Stop-Function -Message "Parameter AGCheck is deprecated. This command does not check for history from replicas even if this paramater is not provided. The functionality to also get the history from all replicas if SqlInstance is part on an availability group has been moved to Get-DbaAgBackupHistory."
            return
        }

        if ($Since -is [TimeSpan]) {
            $Since = (Get-Date).Add($Since);
        } elseif ($Since -isnot [DateTime]) {
            Stop-Function -Message "-Since must be either a DateTime or TimeSpan object."
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.VersionMajor -ge 12) {
                $compressedFlag = $true
                # 2014 introduced encryption
                $backupCols = "
                backupset.backup_size AS TotalSize,
                backupset.compressed_backup_size as CompressedBackupSize,
                encryptor_thumbprint as EncryptorThumbprint,
                encryptor_type as EncryptorType,
                key_algorithm AS KeyAlgorithm"

            } elseif ($server.VersionMajor -ge 10 -and $server.VersionMajor -lt 12) {
                $compressedFlag = $true
                # 2008 introduced compressed_backup_size
                $backupCols = "
                backupset.backup_size AS TotalSize,
                backupset.compressed_backup_size as CompressedBackupSize,
                NULL as EncryptorThumbprint,
                NULL as EncryptorType,
                NULL AS KeyAlgorithm"
            } else {
                $compressedFlag = $false
                $backupCols = "
                backupset.backup_size AS TotalSize,
                NULL as CompressedBackupSize,
                NULL as EncryptorThumbprint,
                NULL as EncryptorType,
                NULL AS KeyAlgorithm"
            }

            $databases = @()
            if ($null -ne $Database) {
                foreach ($db in $Database) {
                    $databases += [PSCustomObject]@{ name = $db }
                }
            } else {
                $databases = $server.Databases
            }
            if ($ExcludeDatabase) {
                $databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
            }
            foreach ($d in $deviceTypeFilter) {
                $deviceTypeFilterRight = "IN ('" + ($deviceTypeFilter -Join "','") + "')"
            }
            foreach ($b in $backupTypeFilter) {
                $backupTypeFilterRight = "IN ('" + ($backupTypeFilter -Join "','") + "')"
            }

            if ($last) {
                foreach ($db in $databases) {
                    if ($since) {
                        $sinceSqlFilter = "AND backupset.backup_finish_date >= CONVERT(datetime,'$($Since.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))',126)"
                    }
                    if ($RecoveryFork) {
                        $recoveryForkSqlFilter = "AND backupset.last_recovery_fork_guid ='$RecoveryFork'"
                    }
                    if ($null -eq (Get-PSCallStack)[1].Command -or '{ScriptBlock}' -eq (Get-PSCallStack)[1].Command) {
                        $forkCheckSql = "
                                SELECT
                                    database_name,
                                    MIN(database_backup_lsn) as 'FirstLsn',
                                    MAX(database_backup_lsn) as 'FinalLsn',
                                    MIN(backup_start_date) as 'MinDate',
                                    MAX(backup_finish_date) as 'MaxDate',
                                    last_recovery_fork_guid 'RecFork',
                                    count(1) as 'backupcount'
                                FROM msdb.dbo.backupset
                                WHERE database_name='$($db.name)'
                                $sinceSqlFilter
                                $recoveryForkSqlFilter
                                GROUP by database_name, last_recovery_fork_guid
                                ORDER by MaxDate Asc
                                "

                        $results = $server.ConnectionContext.ExecuteWithResults($forkCheckSql).Tables.Rows
                        if ($results.count -gt 1) {
                            if (-not $LastFull) {
                                Write-Message -Message "Found backups from multiple recovery forks for $($db.name) on $($server.name), this may affect your results" -Level Verbose
                                foreach ($result in $results) {
                                    Write-Message -Message "Between $($result.MinDate)/$($result.FirstLsn) and $($result.MaxDate)/$($result.FinalLsn) $($result.database_name) was on Recovery Fork GUID $($result.RecFork) ($($result.backupcount) backups)" -Level Warning
                                }
                            }
                            if ($null -eq $RecoveryFork) {
                                $RecoveryFork = $results[-1].RecFork
                                Write-Message -Message "Defaulting to last Recovery Fork, ID - $RecoveryFork"
                            }
                        }
                    }
                    #Get the full and build upwards
                    $allBackups = @()
                    $allBackups += $fullDb = Get-DbaDbBackupHistory -SqlInstance $server -Database $db.Name -LastFull -raw:$Raw -DeviceType $DeviceType -IncludeCopyOnly:$IncludeCopyOnly -Since:$since -RecoveryFork $RecoveryFork
                    if ($null -eq $fullDb) {
                        Write-Message -Level Verbose -Message "No Full Backup found for database $($db.Name), skipping"
                        continue
                    }
                    if (-not $IgnoreDiffBackup) {
                        $diffDb = Get-DbaDbBackupHistory -SqlInstance $server -Database $db.Name -LastDiff -raw:$Raw -DeviceType $DeviceType -IncludeCopyOnly:$IncludeCopyOnly -Since:$since -RecoveryFork $RecoveryFork
                    }
                    if ($diffDb.LastLsn -gt $fullDb.LastLsn -and $diffDb.DatabaseBackupLSN -eq $fullDb.CheckPointLSN ) {
                        Write-Message -Level Verbose -Message "Valid Differential backup "
                        $allBackups += $diffDb
                        $tlogStartDsn = $diffDb.FirstLsn
                    } else {
                        if ($IgnoreDiffBackup) {
                            Write-Message -Level Verbose -Message "Ignoring Diff backups, so using Full backup FirstLSN"
                        } else {
                            Write-Message -Level Verbose -Message "No Diff found"
                        }
                        $tlogStartDsn = $fullDb.FirstLsn
                    }

                    if ($IncludeCopyOnly -eq $true) {
                        Write-Message -Level Verbose -Message 'Copy Only check'
                        $allBackups += Get-DbaDbBackupHistory -SqlInstance $server -Database $db.Name -raw:$raw -DeviceType $DeviceType -LastLsn $tlogStartDsn -IncludeCopyOnly:$IncludeCopyOnly -Since:$since -RecoveryFork $RecoveryFork | Where-Object { $_.Type -eq 'Log' -and [bigint]$_.LastLsn -gt [bigint]$tlogStartDsn -and $_.LastRecoveryForkGuid -eq $fullDb.LastRecoveryForkGuid }
                    } else {
                        $allBackups += Get-DbaDbBackupHistory -SqlInstance $server -Database $db.Name -raw:$raw -DeviceType $DeviceType -LastLsn $tlogStartDsn -IncludeCopyOnly:$IncludeCopyOnly -Since:$since -RecoveryFork $RecoveryFork | Where-Object { $_.Type -eq 'Log' -and [bigint]$_.LastLsn -gt [bigint]$tlogStartDsn -and [bigint]$_.DatabaseBackupLSN -eq [bigint]$fullDb.CheckPointLSN -and $_.LastRecoveryForkGuid -eq $fullDb.LastRecoveryForkGuid }
                    }
                    #This line does the output for -Last!!!
                    $allBackups | Sort-Object -Property LastLsn, Type
                }
                continue
            }

            if ($LastFull -or $LastDiff -or $LastLog) {
                if ($LastFull) {
                    $first = 'D'; $second = 'P'
                }
                if ($LastDiff) {
                    $first = 'I'; $second = 'Q'
                }
                if ($LastLog) {
                    $first = 'L'; $second = 'L'
                }
                $databases = $databases | Select-Object -Unique -Property Name
                $sql = ""
                foreach ($db in $databases) {
                    Write-Message -Level Verbose -Message "Processing $($db.name)" -Target $db
                    if ($since) {
                        $sinceSqlFilter = "AND backupset.backup_finish_date >= CONVERT(datetime,'$($Since.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))',126)"
                    }
                    if ($RecoveryFork) {
                        $recoveryForkSqlFilter = "AND backupset.last_recovery_fork_guid ='$RecoveryFork'"
                    }
                    if ((Get-PSCallStack)[1].Command -notlike ' Get-DbaDbBackupHistory*') {
                        $forkCheckSql = "
                            SELECT
                                database_name,
                                MIN(database_backup_lsn) as 'FirstLsn',
                                MAX(database_backup_lsn) as 'FinalLsn',
                                MIN(backup_start_date) as 'MinDate',
                                MAX(backup_finish_date) as 'MaxDate',
                                last_recovery_fork_guid 'RecFork',
                                count(1) as 'backupcount'
                            FROM msdb.dbo.backupset
                            WHERE database_name='$($db.name)'
                            $sinceSqlFilter
                            $recoveryForkSqlFilter
                            GROUP by database_name, last_recovery_fork_guid
                        "

                        $results = $server.ConnectionContext.ExecuteWithResults($forkCheckSql).Tables.Rows
                        if ($results.count -gt 1) {
                            if (-not $LastFull) {
                                Write-Message -Message "Found backups from multiple recovery forks for $($db.name) on $($server.name), this may affect your results" -Level Verbose
                                foreach ($result in $results) {
                                    Write-Message -Message "Between $($result.MinDate)/$($result.FirstLsn) and $($result.MaxDate)/$($result.FinalLsn) $($result.database_name) was on Recovery Fork GUID $($result.RecFork) ($($result.backupcount) backups)" -Level Warning
                                }
                            }
                        }
                    }
                    $whereCopyOnly = $null
                    if ($true -ne $IncludeCopyOnly) {
                        $whereCopyOnly = " AND is_copy_only='0' "
                    }
                    if ($true -ne $IncludeMirror) {
                        $whereMirror = " AND mediafamily.mirror='0' "
                    }
                    if ($deviceTypeFilter) {
                        $devTypeFilterWhere = "AND mediafamily.device_type $deviceTypeFilterRight"
                    }
                    if ($since) {
                        $sinceSqlFilter = "AND backupset.backup_finish_date >= CONVERT(datetime,'$($Since.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))',126)"
                    }
                    # recap for future editors (as this has been discussed over and over):
                    #   - original editors (from hereon referred as "we") rank over backupset.last_lsn desc, backupset.backup_finish_date desc for a good reason: DST
                    #     all times are recorded with the timezone of the server
                    #   - we thought about ranking over backupset.backup_set_id desc, backupset.last_lsn desc, backupset.backup_finish_date desc
                    #     but there is no explicit documentation about "when" a row gets inserted into backupset. Theoretically it _could_
                    #     happen that backup_set_id for the same database has not the same order of last_lsn.
                    #   - given ultimately to restore something lsn IS the source of truth, we decided to trust that and only that
                    #   - we know that sometimes it happens to drop a database without deleting the history. Assuming then to create a database with the same name,
                    #     and given the lsn are composed in the first part by the VLF SeqID, it happens seldomly that for the same database_name backupset holds
                    #     last_lsn out of order. To avoid this behaviour, we filter by database_guid choosing the guid that has MAX(backup_finish_date), as we know
                    #     last_lsn cannot be out-of-order for the same database, and the same database cannot have different database_guid
                    #   - because someone could restore a very old backup with low lsn values and continue to use this database we filter
                    #     not only by database_guid but also by the recovery fork of the last backup (see issue #6730 for more details)
                    #   - NEW: lsn order can now be based on first_lsn, database_backup_lsn or last_lsn with a default of last_lsn
                    $sql += "SELECT
                        a.BackupSetRank,
                        a.Server,
                        '' as AvailabilityGroupName,
                        a.[Database],
                        a.DatabaseId,
                        a.Username,
                        a.Start,
                        a.[End],
                        a.Duration,
                        a.[Path],
                        a.Type,
                        a.TotalSize,
                        a.CompressedBackupSize,
                        a.MediaSetId,
                        a.BackupSetID,
                        a.Software,
                        a.position,
                        a.first_lsn,
                        a.database_backup_lsn,
                        a.checkpoint_lsn,
                        a.last_lsn,
                        a.first_lsn as 'FirstLSN',
                        a.database_backup_lsn as 'DatabaseBackupLsn',
                        a.checkpoint_lsn as 'CheckpointLsn',
                        a.last_lsn as 'LastLsn',
                        a.software_major_version,
                        a.DeviceType,
                        a.is_copy_only,
                        a.last_recovery_fork_guid,
                        a.recovery_model,
                        a.EncryptorThumbprint,
                        a.EncryptorType,
                        a.KeyAlgorithm
                    FROM (
                        SELECT
                        RANK() OVER (ORDER BY backupset.$internalLsnSort desc, backupset.backup_finish_date DESC) AS 'BackupSetRank',
                        backupset.database_name AS [Database],
                        (SELECT database_id FROM sys.databases WHERE name = backupset.database_name) AS DatabaseId,
                        backupset.user_name AS Username,
                        backupset.backup_start_date AS Start,
                        backupset.server_name as [Server],
                        backupset.backup_finish_date AS [End],
                        DATEDIFF(SECOND, backupset.backup_start_date, backupset.backup_finish_date) AS Duration,
                        mediafamily.physical_device_name AS Path,
                        $backupCols,
                        CASE backupset.type
                        WHEN 'L' THEN 'Log'
                        WHEN 'D' THEN 'Full'
                        WHEN 'F' THEN 'File'
                        WHEN 'I' THEN 'Differential'
                        WHEN 'G' THEN 'Differential File'
                        WHEN 'P' THEN 'Partial Full'
                        WHEN 'Q' THEN 'Partial Differential'
                        ELSE NULL
                        END AS Type,
                        backupset.media_set_id AS MediaSetId,
                        mediafamily.media_family_id as mediafamilyid,
                        backupset.backup_set_id as BackupSetID,
                        CASE mediafamily.device_type
                        WHEN 2 THEN 'Disk'
                        WHEN 102 THEN 'Permanent Disk Device'
                        WHEN 5 THEN 'Tape'
                        WHEN 105 THEN 'Permanent Tape Device'
                        WHEN 6 THEN 'Pipe'
                        WHEN 106 THEN 'Permanent Pipe Device'
                        WHEN 7 THEN 'Virtual Device'
                        WHEN 9 THEN 'URL'
                        ELSE 'Unknown'
                        END AS DeviceType,
                        backupset.position,
                        backupset.first_lsn,
                        backupset.database_backup_lsn,
                        backupset.checkpoint_lsn,
                        backupset.last_lsn,
                        backupset.software_major_version,
                        mediaset.software_name AS Software,
                        backupset.is_copy_only,
                        backupset.last_recovery_fork_guid,
                        backupset.recovery_model
                        FROM msdb..backupmediafamily AS mediafamily
                        JOIN msdb..backupmediaset AS mediaset ON mediafamily.media_set_id = mediaset.media_set_id
                        JOIN msdb..backupset AS backupset ON backupset.media_set_id = mediaset.media_set_id
                        JOIN (
                            SELECT TOP 1 database_name, database_guid, last_recovery_fork_guid
                            FROM msdb..backupset
                            WHERE database_name = '$($db.Name)'
                            ORDER BY backup_finish_date DESC
                            ) AS last_guids ON last_guids.database_name = backupset.database_name AND last_guids.database_guid = backupset.database_guid AND last_guids.last_recovery_fork_guid = backupset.last_recovery_fork_guid
                    WHERE (type = '$first' OR type = '$second')
                    $whereCopyOnly
                    $devTypeFilterWhere
                    $sinceSqlFilter
                    $recoveryForkSqlFilter
                    $whereMirror
                    ) AS a
                    WHERE a.BackupSetRank = 1
                    ORDER BY a.Type;
                    "
                }
                $sql = $sql -join "; "
            } else {
                if ($Force -eq $true) {
                    $select = "SELECT * "
                } else {
                    $select = "
                    SELECT
                        '' as AvailabilityGroupName,
                        backupset.database_name AS [Database],
                        (SELECT database_id FROM sys.databases WHERE name = backupset.database_name) AS DatabaseId,
                        backupset.user_name AS Username,
                        backupset.server_name as [server],
                        backupset.backup_start_date AS [Start],
                        backupset.backup_finish_date AS [End],
                        DATEDIFF(SECOND, backupset.backup_start_date, backupset.backup_finish_date) AS Duration,
                        mediafamily.physical_device_name AS Path,
                        $backupCols,
                        CASE backupset.type
                            WHEN 'L' THEN 'Log'
                            WHEN 'D' THEN 'Full'
                            WHEN 'F' THEN 'File'
                            WHEN 'I' THEN 'Differential'
                            WHEN 'G' THEN 'Differential File'
                            WHEN 'P' THEN 'Partial Full'
                            WHEN 'Q' THEN 'Partial Differential'
                            ELSE NULL
                        END AS Type,
                        backupset.media_set_id AS MediaSetId,
                        mediafamily.media_family_id as MediaFamilyId,
                        backupset.backup_set_id as BackupSetId,
                        CASE mediafamily.device_type
                            WHEN 2 THEN 'Disk'
                            WHEN 102 THEN 'Permanent Disk Device'
                            WHEN 5 THEN 'Tape'
                            WHEN 105 THEN 'Permanent Tape Device'
                            WHEN 6 THEN 'Pipe'
                            WHEN 106 THEN 'Permanent Pipe Device'
                            WHEN 7 THEN 'Virtual Device'
                            WHEN 9 THEN 'URL'
                            ELSE 'Unknown'
                        END AS DeviceType,
                        backupset.position,
                        backupset.first_lsn,
                        backupset.database_backup_lsn,
                        backupset.checkpoint_lsn,
                        backupset.last_lsn,
                        backupset.first_lsn as 'FirstLSN',
                        backupset.database_backup_lsn as 'DatabaseBackupLsn',
                        backupset.checkpoint_lsn as 'CheckpointLsn',
                        backupset.last_lsn as 'LastLsn',
                        backupset.software_major_version,
                        mediaset.software_name AS Software,
                        backupset.is_copy_only,
                        backupset.last_recovery_fork_guid,
                        backupset.recovery_model"
                }

                $from = " FROM msdb..backupmediafamily mediafamily
                INNER JOIN msdb..backupmediaset mediaset ON mediafamily.media_set_id = mediaset.media_set_id
                INNER JOIN msdb..backupset backupset ON backupset.media_set_id = mediaset.media_set_id"
                if ($Database -or $ExcludeDatabase -or $Since -or $Last -or $LastFull -or $LastLog -or $LastDiff -or $deviceTypeFilter -or $LastLsn -or $backupTypeFilter) {
                    $where = " WHERE "
                }

                $whereArray = @()

                if ($Database.length -gt 0 -or $ExcludeDatabase.length -gt 0) {
                    $dbList = $databases.Name -join "','"
                    $whereArray += "database_name IN ('$dbList')"
                }

                if ($true -ne $IncludeCopyOnly) {
                    $whereArray += "is_copy_only='0'"
                }

                if ($true -ne $IncludeMirror) {
                    $whereArray += "mediafamily.mirror='0'"
                }

                if ($Last -or $LastFull -or $LastLog -or $LastDiff) {
                    $tempWhere = $whereArray -join " AND "
                    $whereArray += "type = 'Full' AND mediaset.media_set_id = (SELECT TOP 1 mediaset.media_set_id $from $tempWhere ORDER BY backupset.$internalLsnSort DESC)"
                }

                if ($IgnoreDiffBackup) {
                    $whereArray += "backupset.type not in ('I','G','Q')"
                }

                if ($null -ne $Since) {
                    $whereArray += "backupset.backup_finish_date >= CONVERT(datetime,'$($Since.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))',126)"
                }

                if ($deviceTypeFilter) {
                    $whereArray += "mediafamily.device_type $deviceTypeFilterRight"
                }
                if ($backupTypeFilter) {
                    $whereArray += "backupset.type $backupTypeFilterRight"
                }

                if ($LastLsn) {
                    $whereArray += "backupset.last_lsn > $LastLsn"
                }
                if ($where.Length -gt 0) {
                    $whereArray = $whereArray -join " AND "
                    $where = "$where $whereArray"
                }

                $sql = "$select $from $where ORDER BY backupset.$internalLsnSort DESC"
            }

            Write-Message -Level Debug -Message "SQL Statement: `n$sql"
            Write-Message -Level SomewhatVerbose -Message "Executing sql query on $server."
            $results = $server.ConnectionContext.ExecuteWithResults($sql).Tables.Rows | Select-Object * -ExcludeProperty BackupSetRank, RowError, RowState, Table, ItemArray, HasErrors

            if ($raw) {
                Write-Message -Level SomewhatVerbose -Message "Processing as Raw Output."
                $results | Select-Object *, @{ Name = "FullName"; Expression = { $_.Path } }
                Write-Message -Level SomewhatVerbose -Message "$($results.Count) result sets found."
            } else {
                Write-Message -Level SomewhatVerbose -Message "Processing as grouped output."
                $groupedResults = $results | Group-Object -Property BackupsetId
                Write-Message -Level SomewhatVerbose -Message "$($groupedResults.Count) result-groups found."
                $groupResults = @()
                $backupSetIds = $groupedResults.Name
                $backupSetIdsList = "Insert into #BackupSetIds( backup_set_id ) Values (" + ($backupSetIds -join ");Insert into #BackupSetIds( backup_set_id ) Values (") + ")"
                if ($groupedResults.Count -gt 0) {
                    $TempTable = "Create table #BackupSetIds ( backup_set_id int ); $backupSetIdsList;"
                    $fileAllSql = "$TempTable SELECT bf.backup_set_id, file_type as FileType, logical_name as LogicalName, physical_name as PhysicalName
                    FROM msdb..backupfile bf
                    join #BackupSetIds bs
                        on bs.backup_set_id = bf.backup_set_id
                    WHERE [state] <> 8;
                    Drop Table #BackupSetIds;" # <> 8 Used to eliminate data files that no longer exist
                    Write-Message -Level Debug -Message "FileSQL: $fileAllSql"
                    $fileListResults = $server.Query($fileAllSql)
                } else {
                    $fileListResults = @()
                }
                $fileListHash = @{ }
                foreach ($fl in $fileListResults) {
                    if (-not($fileListHash.ContainsKey($fl.backup_set_id))) {
                        $fileListHash[$fl.backup_set_id] = @()
                    }
                    $fileListHash[$fl.backup_set_id] += $fl
                }
                foreach ($group in $groupedResults) {
                    $commonFields = $group.Group[0]
                    $groupLength = $group.Group.Count
                    if ($groupLength -eq 1) {
                        $start = $commonFields.Start
                        $end = $commonFields.End
                        $duration = New-TimeSpan -Seconds $commonFields.Duration
                    } else {
                        $start = ($group.Group.Start | Measure-Object -Minimum).Minimum
                        $end = ($group.Group.End | Measure-Object -Maximum).Maximum
                        $duration = New-TimeSpan -Seconds ($group.Group.Duration | Measure-Object -Maximum).Maximum
                    }
                    $compressedBackupSize = $commonFields.CompressedBackupSize
                    if ($compressedFlag -eq $true) {
                        $ratio = [Math]::Round(($commonFields.TotalSize) / ($compressedBackupSize), 2)
                    } else {
                        $compressedBackupSize = $null
                        $ratio = 1
                    }
                    $historyObject = New-Object Dataplat.Dbatools.Database.BackupHistory
                    $historyObject.ComputerName = $server.ComputerName
                    $historyObject.InstanceName = $server.ServiceName
                    $historyObject.SqlInstance = $server.DomainInstanceName
                    $historyObject.Database = $commonFields.Database
                    if ( $commonFields.DatabaseId -is [int] ) {
                        $historyObject.DatabaseId = $commonFields.DatabaseId
                    }
                    $historyObject.UserName = $commonFields.UserName
                    $historyObject.Start = $start
                    $historyObject.End = $end
                    $historyObject.Duration = $duration
                    $historyObject.Path = $group.Group.Path
                    $historyObject.TotalSize = $commonFields.TotalSize
                    $historyObject.CompressedBackupSize = $compressedBackupSize
                    $historyObject.CompressionRatio = $ratio
                    $historyObject.Type = $commonFields.Type
                    $historyObject.BackupSetId = $commonFields.BackupSetId
                    $historyObject.DeviceType = $commonFields.DeviceType
                    $historyObject.Software = $commonFields.Software
                    $historyObject.FullName = $group.Group.Path
                    $historyObject.FileList = $fileListHash[$commonFields.BackupSetID] | Select-Object FileType, LogicalName, PhysicalName
                    $historyObject.Position = $commonFields.Position
                    $historyObject.FirstLsn = $commonFields.First_LSN
                    $historyObject.DatabaseBackupLsn = $commonFields.database_backup_lsn
                    $historyObject.CheckpointLsn = $commonFields.checkpoint_lsn
                    $historyObject.LastLsn = $commonFields.Last_Lsn
                    $historyObject.SoftwareVersionMajor = $commonFields.Software_Major_Version
                    $historyObject.IsCopyOnly = ($commonFields.is_copy_only -eq 1)
                    $historyObject.LastRecoveryForkGuid = $commonFields.last_recovery_fork_guid
                    $historyObject.RecoveryModel = $commonFields.recovery_model
                    $historyObject.EncryptorType = $commonFields.EncryptorType
                    $historyObject.EncryptorThumbprint = $commonFields.EncryptorThumbprint
                    $historyObject.KeyAlgorithm = $commonFields.KeyAlgorithm
                    $historyObject
                }
                $groupResults | Sort-Object -Property LastLsn, Type
            }
        }
    }
}