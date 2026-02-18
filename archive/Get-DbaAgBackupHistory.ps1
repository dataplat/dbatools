function Get-DbaAgBackupHistory {
    <#
    .SYNOPSIS
        Retrieves backup history from msdb across all replicas in a SQL Server Availability Group

    .DESCRIPTION
        Queries the msdb backup history tables across all replicas in an Availability Group and aggregates the results into a unified view. This function automatically discovers all replicas (either through a listener or by querying individual replicas) and combines their backup history data, which is essential since backups can be taken from any replica but are only recorded in the local msdb.

        This solves the common AG challenge where DBAs need to piece together backup history from multiple replicas for compliance reporting, recovery planning, or troubleshooting backup strategies. You can filter by backup type, date ranges, or get just the latest backups, and the function adds availability group context to help identify which replica performed each backup.

        Reference: http://www.sqlhub.com/2011/07/find-your-backup-history-in-sql-server.html

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

        If you pass in one availability group listener, all replicas are automatically determined and queried.
        If you pass in a list of individual replicas, they will be queried. This enables you to use custom ports for the replicas.

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server instance as a different user. This can be a Windows or SQL Server account. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

    .PARAMETER AvailabilityGroup
        Specifies the name of the availability group to query for backup history.
        Required parameter that identifies which AG's databases should be included in the backup history retrieval.

    .PARAMETER Database
        Specifies which databases within the availability group to include in the backup history.
        If omitted, backup history for all databases in the availability group will be returned.
        Useful when you need backup history for specific databases rather than the entire AG.

    .PARAMETER ExcludeDatabase
        Specifies databases within the availability group to exclude from backup history results.
        Use this when you want most AG databases but need to omit specific ones like test or temporary databases.

    .PARAMETER IncludeCopyOnly
        Includes copy-only backups in the results, which are normally excluded by default.
        Copy-only backups don't affect the backup chain sequence and are often used for ad-hoc copies or third-party backup tools.
        Enable this when you need a complete view of all backup activity including copy-only operations.

    .PARAMETER Force
        Returns detailed backup information including additional metadata fields normally hidden for readability.
        Use this when you need comprehensive backup details for troubleshooting or detailed analysis beyond the standard summary view.

    .PARAMETER Since
        Filters backup history to only include backups taken after this date and time.
        Defaults to January 1, 1970 if not specified, effectively including all backup history.
        Use this to limit results to recent backups or investigate backup activity within a specific timeframe.

    .PARAMETER RecoveryFork
        Filters backup history to a specific recovery fork identified by its GUID.
        Recovery forks occur after point-in-time restores and create branching backup chains.
        Use this when investigating backup history related to a specific restore operation or recovery scenario.

    .PARAMETER Last
        Returns the most recent complete backup chain (full, differential, and log backups) needed for point-in-time recovery.
        This provides the minimum set of backups required to restore each database to its most recent recoverable state.
        Essential for recovery planning and validating that you have all necessary backup files.

    .PARAMETER LastFull
        Returns only the most recent full backup for each database in the availability group.
        Use this to quickly identify the latest full backup baseline for each database, which is the foundation for any restore operation.

    .PARAMETER LastDiff
        Returns only the most recent differential backup for each database in the availability group.
        Useful for identifying the latest differential backup that can reduce restore time by applying changes since the last full backup.

    .PARAMETER LastLog
        Returns only the most recent transaction log backup for each database in the availability group.
        Critical for determining the latest point-in-time recovery option and ensuring log backup chains are current.

    .PARAMETER DeviceType
        Filters backup history by the storage device type where backups were written.
        Common values include 'Disk' for local/network storage, 'URL' for Azure/S3 cloud storage, or 'Tape' for tape devices.
        Use this when you need to locate backups stored on specific media types or troubleshoot backup destinations.

    .PARAMETER Raw
        Returns individual backup file details instead of grouping striped backup files into single backup set objects.
        Enable this when you need to see each physical backup file separately, useful for investigating striped backups or file-level backup issues.
        By default, related backup files are grouped together as logical backup sets.

    .PARAMETER Type
        Filters results to specific backup types such as 'Full', 'Log', or 'Differential'.
        Use this when you need to focus on particular backup types, like reviewing only transaction log backups for log shipping validation.
        If not specified, all backup types are included unless using one of the Last switches.

    .PARAMETER LastLsn
        Filters backup history to only include backups with Log Sequence Numbers greater than this value.
        Use this to find backups taken after a specific point in the transaction log, improving performance when dealing with large backup histories.
        Commonly used when building incremental backup chains or investigating activity after a known LSN checkpoint.

    .PARAMETER IncludeMirror
        Includes mirrored backup sets in the results, which are normally excluded for clarity.
        Mirrored backups are identical copies written simultaneously to multiple destinations during backup operations.
        Enable this when you need to see all backup copies or verify mirror backup destinations.

    .PARAMETER LsnSort
        Determines which LSN field to use for sorting when filtering with Last switches (LastFull, LastDiff, LastLog).
        Options are 'FirstLsn' (default), 'DatabaseBackupLsn', or 'LastLsn' to control chronological ordering.
        Use 'LastLsn' when you need backups sorted by their ending checkpoint rather than starting point.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        Dataplat.Dbatools.Database.BackupHistory

        Returns one backup history object per physical backup file or per logical backup set (when backups are striped across multiple files). Each object represents backup metadata from MSDB including timing, size, location, and LSN sequence information.

        When using -Last, -LastFull, -LastDiff, or -LastLog switches, returns only the most recent backup(s) of the specified type across all replicas. When using -Raw, returns individual backup file details instead of grouping striped files into single logical sets.

        Default display properties (via Format-Table):
        - SqlInstance: The SQL Server instance name (computer\instance)
        - Database: The database name
        - Type: Backup type (Full, Differential, Log, etc.)
        - TotalSize: Total backup size in bytes
        - DeviceType: Storage device type (Disk, Tape, URL, Virtual Device)
        - Start: Backup start time
        - Duration: Time span of the backup operation
        - End: Backup completion time

        Additional properties available (can be accessed via Select-Object *):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - DatabaseId: System database identifier
        - UserName: User account that performed the backup
        - CompressedBackupSize: Compressed size in bytes (null for SQL Server 2005)
        - CompressionRatio: Ratio of TotalSize to CompressedBackupSize
        - BackupSetId: Unique identifier for the backup set
        - Software: Backup software name and version
        - FullName: Full path to backup files (array of paths for striped backups)
        - FileList: Details of database and log files in the backup
        - Position: Position of the backup within a media set
        - FirstLsn: Starting log sequence number
        - DatabaseBackupLsn: LSN of the last database backup (for log/differential backups)
        - CheckpointLsn: LSN of the checkpoint during backup
        - LastLsn: Ending log sequence number
        - SoftwareVersionMajor: Major version of SQL Server that created the backup
        - IsCopyOnly: Boolean indicating if this is a copy-only backup
        - LastRecoveryForkGuid: GUID of the recovery fork (for point-in-time restore scenarios)
        - RecoveryModel: Database recovery model at time of backup (Simple, Full, BulkLogged)
        - EncryptorThumbprint: Thumbprint of backup encryption certificate (SQL Server 2014+)
        - EncryptorType: Type of encryption used (SQL Server 2014+)
        - KeyAlgorithm: Encryption algorithm used (SQL Server 2014+)
        - AvailabilityGroupName: Name of the availability group being queried (added by Get-DbaAgBackupHistory)

    .NOTES
        Tags: AG, HA
        Author: Chrissy LeMaire (@cl) | Stuart Moore (@napalmgram), Andreas Jordan

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgBackupHistory

    .EXAMPLE
        PS C:\> Get-DbaAgBackupHistory -SqlInstance AgListener -AvailabilityGroup AgTest1

        Returns information for all database backups still in msdb history on all replicas of availability group AgTest1 using the listener AgListener to determine all replicas.

    .EXAMPLE
        PS C:\> Get-DbaAgBackupHistory -SqlInstance Replica1, Replica2, Replica3 -AvailabilityGroup AgTest1

        Returns information for all database backups still in msdb history on the given replicas of availability group AgTest1.

    .EXAMPLE
        PS C:\> Get-DbaAgBackupHistory -SqlInstance 'Replica1:14331', 'Replica2:14332', 'Replica3:14333' -AvailabilityGroup AgTest1

        Returns information for all database backups still in msdb history on the given replicas of availability group AgTest1 using custom ports.

    .EXAMPLE
        PS C:\> $ListOfReplicas | Get-DbaAgBackupHistory -AvailabilityGroup AgTest1

        Returns information for all database backups still in msdb history on the replicas in $ListOfReplicas of availability group AgTest1.

    .EXAMPLE
        PS C:\> $serverWithAllAgs = Connect-DbaInstance -SqlInstance MyServer
        PS C:\> $allAgResults = foreach ( $ag in $serverWithAllAgs.AvailabilityGroups ) {
        >>     Get-DbaAgBackupHistory -SqlInstance $ag.AvailabilityReplicas.Name -AvailabilityGroup $ag.Name
        >> }
        >>
        PS C:\> $allAgResults | Format-Table

        Returns information for all database backups on all replicas for all availability groups on SQL instance MyServer.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]
        $SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string]$AvailabilityGroup,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [switch]$IncludeCopyOnly,
        [Parameter(ParameterSetName = "NoLast")]
        [switch]$Force,
        [DateTime]$Since = (Get-Date '01/01/1970'),
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
        [ValidateSet("FirstLsn", "DatabaseBackupLsn", "LastLsn")]
        [string]$LsnSort = "FirstLsn",
        [switch]$EnableException
    )

    begin {
        Write-Message -Level System -Message "Active Parameter set: $($PSCmdlet.ParameterSetName)."
        Write-Message -Level System -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"
        $serverList = @()
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Only work on instances with availability groups
            if ($server.AvailabilityGroups.Count -eq 0) {
                Stop-Function -Message "Instance $instance has no availability groups, so skipping." -Target $instance -Continue
            }

            # Only work on instances with the specific availability group
            if ($AvailabilityGroup -notin $server.AvailabilityGroups.Name) {
                Stop-Function -Message "Instance $instance has no availability group named '$AvailabilityGroup', so skipping." -Target $instance -Continue
            }

            Write-Message -Level Verbose -Message "Added $server to serverList"
            $serverList += $server
        }
    }

    end {
        if ($serverList.Count -eq 0) {
            Stop-Function -Message "No instances with availability group named '$AvailabilityGroup' found, so finishing without results."
            return
        }

        if ($serverList.Count -eq 1) {
            Write-Message -Level Verbose -Message "We have one server, so it should be a listener"
            $server = $serverList[0]

            $replicaNames = ($server.AvailabilityGroups | Where-Object { $_.Name -in $AvailabilityGroup } ).AvailabilityReplicas.Name
            Write-Message -Level Verbose -Message "We have found these replicas: $replicaNames"

            $serverList = $replicaNames
        }

        Write-Message -Level Verbose -Message "We have more than one server, so query them all and aggregate"
        # If -Database is not set, we want to filter on all databases of the availability group
        if (Test-Bound -Not -ParameterName Database) {
            $agDatabase = (Get-DbaAgDatabase -SqlInstance $serverList[0] -AvailabilityGroup $AvailabilityGroup).Name
            $PSBoundParameters.Add('Database', $agDatabase)
        }
        $null = $PSBoundParameters.Remove('SqlInstance')
        $null = $PSBoundParameters.Remove('AvailabilityGroup')
        $null = $PSBoundParameters.Remove('Last')
        $AgResults = Get-DbaDbBackupHistory -SqlInstance $serverList @PSBoundParameters
        foreach ($agr in $AgResults) {
            $agr.AvailabilityGroupName = $AvailabilityGroup
        }

        if ($Last) {
            Write-Message -Level Verbose -Message "Filtering Ag backups for Last"
            $AgResults | Select-DbaBackupInformation -ServerName $AvailabilityGroup
        } elseif ($LastFull) {
            Write-Message -Level Verbose -Message "Filtering Ag backups for LastFull"
            Foreach ($AgDb in ( $AgResults.Database | Select-Object -Unique)) {
                $AgResults | Where-Object { $_.Database -eq $AgDb } | Sort-Object -Property $LsnSort | Select-Object -Last 1
            }
        } elseif ($LastDiff) {
            Write-Message -Level Verbose -Message "Filtering Ag backups for LastDiff"
            Foreach ($AgDb in ( $AgResults.Database | Select-Object -Unique)) {
                $AgResults | Where-Object { $_.Database -eq $AgDb } | Sort-Object -Property $LsnSort | Select-Object -Last 1
            }
        } elseif ($LastLog) {
            Write-Message -Level Verbose -Message "Filtering Ag backups for LastLog"
            Foreach ($AgDb in ( $AgResults.Database | Select-Object -Unique)) {
                $AgResults | Where-Object { $_.Database -eq $AgDb } | Sort-Object -Property $LsnSort | Select-Object -Last 1
            }
        } else {
            Write-Message -Level Verbose -Message "Output Ag backups without filtering"
            $AgResults
        }
    }
}