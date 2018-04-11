#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Get-DbaBackupHistory {
    <#
        .SYNOPSIS
            Returns backup history details for databases on a SQL Server.

        .DESCRIPTION
            Returns backup history details for some or all databases on a SQL Server.

            You can even get detailed information (including file path) for latest full, differential and log files.

            Backups taken with the CopyOnly option will NOT be returned, unless the IncludeCopyOnly switch is present

            Reference: http://www.sqlhub.com/2011/07/find-your-backup-history-in-sql-server.html

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            Credential object used to connect to the SQL Server Instance as a different user. This can be a Windows or SQL Server account. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

        .PARAMETER Database
            Specifies one or more database(s) to process. If unspecified, all databases will be processed.

        .PARAMETER ExcludeDatabase
            Specifies one or more database(s) to exclude from processing.

        .PARAMETER IncludeCopyOnly
            By default Get-DbaBackupHistory will ignore backups taken with the CopyOnly option. This switch will include them

        .PARAMETER Force
            If this switch is enabled, a large amount of information is returned, similar to what SQL Server itself returns.

        .PARAMETER Since
            Specifies a DateTime object to use as the starting point for the search for backups.

        .PARAMETER Last
            If this switch is enabled, the most recent full chain of full, diff and log backup sets is returned.

        .PARAMETER LastFull
            If this switch is enabled, the most recent full backup set is returned.

        .PARAMETER LastDiff
            If this switch is enabled, the most recent differential backup set is returned.

        .PARAMETER LastLog
            If this switch is enabled, the most recent log backup is returned.

        .PARAMETER DeviceType
            Specifies a filter for backup sets based on DeviceTypes. Valid options are 'Disk','Permanent Disk Device', 'Tape', 'Permanent Tape Device','Pipe','Permanent Pipe Device','Virtual Device', in addition to custom integers for your own DeviceTypes.

        .PARAMETER Raw
            If this switch is enabled, one object per backup file is returned. Otherwise, media sets (striped backups across multiple files) will be grouped into a single return object.

        .PARAMETER Type
            Specifies one or more types of backups to return. Valid options are 'Full', 'Log', 'Differential', 'File', 'Differential File', 'Partial Full', and 'Partial Differential'. Otherwise, all types of backups will be returned unless one of the -Last* switches is enabled.

        .PARAMETER LastLsn
            Specifies a minimum LSN to use in filtering backup history. Only backups with an LSN greater than this value will be returned, which helps speed the retrieval process.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: DisasterRecovery, Backup
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaBackupHistory

        .EXAMPLE
            Get-DbaBackupHistory -SqlInstance SqlInstance2014a

            Returns server name, database, username, backup type, date for all backups databases on SqlInstance2014a. This may return many rows; consider using filters that are included in other examples.

        .EXAMPLE
            $cred = Get-Credential sqladmin
            Get-DbaBackupHistory -SqlInstance SqlInstance2014a -SqlCredential $cred

            Does the same as above but logs in as SQL user "sqladmin"

        .EXAMPLE
            Get-DbaBackupHistory -SqlInstance SqlInstance2014a -Database db1, db2 -Since '7/1/2016 10:47:00'

            Returns backup information only for databases db1 and db2 on SqlInstance2014a since July 1, 2016 at 10:47 AM.

        .EXAMPLE
            Get-DbaBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014, pubs -Force | Format-Table

            Returns information only for AdventureWorks2014 and pubs and formats the results as a table.

        .EXAMPLE
            Get-DbaBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Last

            Returns information about the most recent full, differential and log backups for AdventureWorks2014 on sql2014.

        .EXAMPLE
            Get-DbaBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Last -DeviceType Disk

            Returns information about the most recent full, differential and log backups for AdventureWorks2014 on sql2014, but only for backups to disk.

        .EXAMPLE
            Get-DbaBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Last -DeviceType 148,107

            Returns information about the most recent full, differential and log backups for AdventureWorks2014 on sql2014, but only for backups with device_type 148 and 107.

        .EXAMPLE
            Get-DbaBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -LastFull

            Returns information about the most recent full backup for AdventureWorks2014 on sql2014.

        .EXAMPLE
            Get-DbaBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Type Full

            Returns information about all Full backups for AdventureWorks2014 on sql2014.

        .EXAMPLE
            Get-DbaRegisteredServer -SqlInstance sql2016 | Get-DbaBackupHistory

            Returns database backup information for every database on every server listed in the Central Management Server on sql2016.

        .EXAMPLE
            Get-DbaBackupHistory -SqlInstance SqlInstance2014a, sql2016 -Force

            Returns detailed backup history for all databases on SqlInstance2014a and sql2016.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]
        $SqlInstance,
        [Alias("Credential")]
        [PsCredential]$SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$IncludeCopyOnly,
        [Parameter(ParameterSetName = "NoLast")]
        [switch]$Force,
        [Parameter(ParameterSetName = "NoLast")]
        [DateTime]$Since,
        [Parameter(ParameterSetName = "Last")]
        [switch]$Last,
        [Parameter(ParameterSetName = "Last")]
        [switch]$LastFull,
        [Parameter(ParameterSetName = "Last")]
        [switch]$LastDiff,
        [Parameter(ParameterSetName = "Last")]
        [switch]$LastLog,
        [string[]]$DeviceType,
        [switch]$Raw,
        [bigint]$LastLsn,
        [ValidateSet("Full", "Log", "Differential", "File", "Differential File", "Partial Full", "Partial Differential")]
        [string[]]$Type,
        [Alias('Silent')]
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
            }
            else {
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

    }

    process {
        foreach ($instance in $SqlInstance) {

            try {
                Write-Message -Level Verbose -Message "Connecting to $instance." -Target $instance
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.VersionMajor -ge 10) {
                $compressedFlag = $true
                # 2008 introduced compressed_backup_size
                $backupCols = "
                backupset.backup_size AS TotalSize,
                backupset.compressed_backup_size as CompressedBackupSize"
            }
            else {
                $compressedFlag = $false
                $backupCols = "
                backupset.backup_size AS TotalSize,
                NULL as CompressedBackupSize"
            }

            $databases = @()
            if ($null -ne $Database) {
                foreach ($db in $Database) {
                    $databases += [PSCustomObject]@{name = $db}
                }
            }
            else {
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

                    #Get the full and build upwards
                    $allBackups = @()
                    $allBackups += $fullDb = Get-DbaBackupHistory -SqlInstance $server -Database $db.Name -LastFull -raw:$Raw -DeviceType $DeviceType -IncludeCopyOnly:$IncludeCopyOnly
                    $diffDb = Get-DbaBackupHistory -SqlInstance $server -Database $db.Name -LastDiff -raw:$Raw -DeviceType $DeviceType -IncludeCopyOnly:$IncludeCopyOnly
                    if ($diffDb.LastLsn -gt $fullDb.LastLsn -and $diffDb.DatabaseBackupLSN -eq $fullDb.CheckPointLSN ) {
                        Write-Message -Level Verbose -Message "Valid Differential backup "
                        $allBackups += $diffDb
                        $tlogStartDsn = ($diffDb.FirstLsn -as [bigint])
                    }
                    else {
                        Write-Message -Level Verbose -Message "No Diff found"
                        try {
                            [bigint]$tlogStartDsn = $fullDb.FirstLsn.ToString()
                        }
                        catch {
                            continue
                        }
                    }
                    $allBackups += Get-DbaBackupHistory -SqlInstance $server -Database $db.Name -raw:$raw -DeviceType $DeviceType -LastLsn $tlogStartDsn -IncludeCopyOnly:$IncludeCopyOnly | Where-Object {
                        $_.Type -eq 'Log' -and [bigint]$_.LastLsn -gt [bigint]$tlogStartDsn -and [bigint]$_.DatabaseBackupLSN -eq [bigint]$fullDb.CheckPointLSN -and $_.LastRecoveryForkGuid -eq $fullDb.LastRecoveryForkGuid
                    }
                    #This line does the output for -Last!!!
                    $allBackups |  Sort-Object -Property LastLsn, Type
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
                    $whereCopyOnly = $null
                    if ($true -ne $IncludeCopyOnly) {
                        $whereCopyOnly = " AND is_copy_only='0' "
                    }
                    if ($deviceTypeFilter) {
                        $devTypeFilterWhere = "AND mediafamily.device_type $deviceTypeFilterRight"
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
                    $sql += "
                                SELECT
                                    a.BackupSetRank,
                                    a.Server,
                                    a.[Database],
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
                                    a.last_recovery_fork_guid
                                FROM (SELECT
                                  RANK() OVER (ORDER BY backupset.last_lsn desc, backupset.backup_finish_date DESC) AS 'BackupSetRank',
                                  backupset.database_name AS [Database],
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
                                JOIN msdb..backupmediaset AS mediaset
                                  ON mediafamily.media_set_id = mediaset.media_set_id
                                JOIN msdb..backupset AS backupset
                                  ON backupset.media_set_id = mediaset.media_set_id
                                JOIN (
                                    SELECT DISTINCT database_guid, database_name, backup_finish_date
                                    FROM msdb..backupset
                                    WHERE backupset.database_name = '$($db.Name)'
                                ) dbguid
                                  ON dbguid.database_name = backupset.database_name
                                  AND dbguid.database_guid = backupset.database_guid
                                JOIN (
                                    SELECT database_name, MAX(backup_finish_date) max_finish_date
                                    FROM msdb..backupset
                                    WHERE backupset.database_name = '$($db.Name)'
                                    GROUP BY database_name
                                ) dbguid_support
                                  ON dbguid_support.database_name = backupset.database_name
                                  AND dbguid.backup_finish_date = dbguid_support.max_finish_date
                                WHERE backupset.database_name = '$($db.Name)' $whereCopyOnly
                                AND (type = '$first' OR type = '$second')
                                $devTypeFilterWhere
                                ) AS a
                                WHERE a.BackupSetRank = 1
                                ORDER BY a.Type;
                                "
                }
                $sql = $sql -join "; "
            }
            else {
                if ($Force -eq $true) {
                    $select = "SELECT * "
                }
                else {
                    $select = "
                            SELECT
                              backupset.database_name AS [Database],
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
                if ($Database -or $Since -or $Last -or $LastFull -or $LastLog -or $LastDiff -or $deviceTypeFilter -or $LastLsn -or $backupTypeFilter) {
                    $where = " WHERE "
                }

                $whereArray = @()

                if ($Database.length -gt 0) {
                    $dbList = $Database -join "','"
                    $whereArray += "database_name IN ('$dbList')"
                }

                if ($true -ne $IncludeCopyOnly) {
                    $whereArray += "is_copy_only='0'"
                }

                if ($Last -or $LastFull -or $LastLog -or $LastDiff) {
                    $tempWhere = $whereArray -join " AND "
                    $whereArray += "type = 'Full' AND mediaset.media_set_id = (SELECT TOP 1 mediaset.media_set_id $from $tempWhere ORDER BY backupset.last_lsn DESC)"
                }

                if ($null -ne $Since) {
                    $whereArray += "backupset.backup_finish_date >= '$($Since.ToString("yyyy-MM-ddTHH:mm:ss"))'"
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

                $sql = "$select $from $where ORDER BY backupset.last_lsn DESC"
            }

            Write-Message -Level Debug -Message "SQL Statement: `n$sql"
            Write-Message -Level SomewhatVerbose -Message "Executing sql query."
            $results = $server.ConnectionContext.ExecuteWithResults($sql).Tables.Rows | Select-Object * -ExcludeProperty BackupSetRank, RowError, RowState, Table, ItemArray, HasErrors

            if ($raw) {
                Write-Message -Level SomewhatVerbose -Message "Processing as Raw Output."
                $results | Select-Object *, @{ Name = "FullName"; Expression = { $_.Path } }
                Write-Message -Level SomewhatVerbose -Message "$($results.Count) result sets found."
            }
            else {
                Write-Message -Level SomewhatVerbose -Message "Processing as grouped output."
                $groupedResults = $results | Group-Object -Property BackupsetId
                Write-Message -Level SomewhatVerbose -Message "$($groupedResults.Count) result-groups found."
                $groupResults = @()
                $backupSetIds = $groupedResults.Name
                $backupSetIdsList = $backupSetIds -Join ","
                if ($groupedResults.Count -gt 0) {
                    $backupSetIdsWhere = "backup_set_id IN ($backupSetIdsList)"
                    $fileAllSql = "SELECT backup_set_id, file_type as FileType, logical_name as LogicalName, physical_name as PhysicalName
                                   FROM msdb..backupfile WHERE $backupSetIdsWhere"
                    Write-Message -Level Debug -Message "FileSQL: $fileAllSql"
                    $fileListResults = $server.Query($fileAllSql)
                }
                else {
                    $fileListResults = @()
                }
                $fileListHash = @{}
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
                    }
                    else {
                        $start = ($group.Group.Start | Measure-Object -Minimum).Minimum
                        $end = ($group.Group.End | Measure-Object -Maximum).Maximum
                        $duration = New-TimeSpan -Seconds ($group.Group.Duration | Measure-Object -Maximum).Maximum
                    }
                    $compressedBackupSize = $commonFields.CompressedBackupSize
                    if ($compressedFlag -eq $true) {
                        $ratio = [Math]::Round(($commonFields.TotalSize) / ($compressedBackupSize), 2)
                    }
                    else {
                        $compressedBackupSize = $null
                        $ratio = 1
                    }
                    $historyObject = New-Object Sqlcollaborative.Dbatools.Database.BackupHistory
                    $historyObject.ComputerName = $server.NetName
                    $historyObject.InstanceName = $server.ServiceName
                    $historyObject.SqlInstance = $server.DomainInstanceName
                    $historyObject.Database = $commonFields.Database
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
                    $historyObject.RecoveryModel = $commonFields.Recovery_Model
                    $historyObject
                }
                $groupResults | Sort-Object -Property LastLsn, Type
            }
        }
    }
}
