function Get-DbaAgBackupHistory {
    <#
    .SYNOPSIS
        Returns backup history details for databases on a SQL Server Availability Group.

    .DESCRIPTION
        Returns backup history details for some or all databases on a SQL Server Availability Group.

        You can even get detailed information (including file path) for latest full, differential and log files.

### Discuss this:
        Backups taken with the CopyOnly option will NOT be returned, unless the IncludeCopyOnly switch is present or the target includes an Availability Group listener or a database in an Availability Group

        Reference: http://www.sqlhub.com/2011/07/find-your-backup-history-in-sql-server.html

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server instance as a different user. This can be a Windows or SQL Server account. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

    .PARAMETER AvailabilityGroup
        Specify the availability groups to process.

    .PARAMETER Database
        Specifies one or more database(s) to process. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        Specifies one or more database(s) to exclude from processing.

    .PARAMETER IncludeCopyOnly
        By default Get-DbaAgBackupHistory will ignore backups taken with the CopyOnly option. This switch will include them.

    .PARAMETER Force
        If this switch is enabled, a large amount of information is returned, similar to what SQL Server itself returns.

    .PARAMETER Since
        Specifies a DateTime object to use as the starting point for the search for backups.

    .PARAMETER RecoveryFork
        Specifies the Recovery Fork you want backup history for

    .PARAMETER Last
        If this switch is enabled, the most recent full chain of full, diff and log backup sets is returned.

    .PARAMETER LastFull
        If this switch is enabled, the most recent full backup set is returned.

    .PARAMETER LastDiff
        If this switch is enabled, the most recent differential backup set is returned.

    .PARAMETER LastLog
        If this switch is enabled, the most recent log backup is returned.

    .PARAMETER DeviceType
        Specifies a filter for backup sets based on DeviceType. Valid options are 'Disk','Permanent Disk Device', 'Tape', 'Permanent Tape Device','Pipe','Permanent Pipe Device','Virtual Device','URL', in addition to custom integers for your own DeviceType.

    .PARAMETER Raw
        If this switch is enabled, one object per backup file is returned. Otherwise, media sets (striped backups across multiple files) will be grouped into a single return object.

    .PARAMETER Type
        Specifies one or more types of backups to return. Valid options are 'Full', 'Log', 'Differential', 'File', 'Differential File', 'Partial Full', and 'Partial Differential'. Otherwise, all types of backups will be returned unless one of the -Last* switches is enabled.

    .PARAMETER LastLsn
        Specifies a minimum LSN to use in filtering backup history. Only backups with an LSN greater than this value will be returned, which helps speed the retrieval process.

    .PARAMETER IncludeMirror
        By default mirrors of backups are not returned, this switch will cause them to be returned

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
        https://dbatools.io/Get-DbaAgBackupHistory

    .EXAMPLE
        PS C:\> Get-DbaAgBackupHistory -SqlInstance SqlInstance2014a

        Returns server name, database, username, backup type, date for all database backups still in msdb history on SqlInstance2014a. This may return many rows; consider using filters that are included in other examples.

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        Get-DbaAgBackupHistory -SqlInstance SqlInstance2014a -SqlCredential $cred

        Does the same as above but connect to SqlInstance2014a as SQL user "sqladmin"

    .EXAMPLE
        PS C:\> Get-DbaAgBackupHistory -SqlInstance SqlInstance2014a -Database db1, db2 -Since '2016-07-01 10:47:00'

        Returns backup information only for databases db1 and db2 on SqlInstance2014a since July 1, 2016 at 10:47 AM.

    .EXAMPLE
        PS C:\> Get-DbaAgBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014, pubs -Force | Format-Table

        Returns information only for AdventureWorks2014 and pubs and formats the results as a table.

    .EXAMPLE
        PS C:\> Get-DbaAgBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Last

        Returns information about the most recent full, differential and log backups for AdventureWorks2014 on sql2014.

    .EXAMPLE
        PS C:\> Get-DbaAgBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Last -DeviceType Disk

        Returns information about the most recent full, differential and log backups for AdventureWorks2014 on sql2014, but only for backups to disk.

    .EXAMPLE
        PS C:\> Get-DbaAgBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Last -DeviceType 148,107

        Returns information about the most recent full, differential and log backups for AdventureWorks2014 on sql2014, but only for backups with device_type 148 and 107.

    .EXAMPLE
        PS C:\> Get-DbaAgBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -LastFull

        Returns information about the most recent full backup for AdventureWorks2014 on sql2014.

    .EXAMPLE
        PS C:\> Get-DbaAgBackupHistory -SqlInstance sql2014 -Database AdventureWorks2014 -Type Full

        Returns information about all Full backups for AdventureWorks2014 on sql2014.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sql2016 | Get-DbaAgBackupHistory

        Returns database backup information for every database on every server listed in the Central Management Server on sql2016.

    .EXAMPLE
        PS C:\> Get-DbaAgBackupHistory -SqlInstance SqlInstance2014a, sql2016 -Force

        Returns detailed backup history for all databases on SqlInstance2014a and sql2016.

    .EXAMPLE
        PS C:\> Get-DbaAgBackupHistory -SqlInstance sql2016 -Database db1 -RecoveryFork 38e5e84a-3557-4643-a5d5-eed607bef9c6 -Last

        If db1 has multiple recovery forks, specifying the RecoveryFork GUID will restrict the search to that fork.

    .EXAMPLE
        PS C:\> Get-DbaAgBackupHistory -SqlInstance AgListener -Last

        Will query all replicas in the Availability Group with AgListener and return the backup chain (Full, Diff and Log) to restore to the most rececnt point in time

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]
        $SqlInstance,
        [PsCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
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
        [switch]$EnableException
    )

    begin {
        Write-Message -Level System -Message "Active Parameter set: $($PSCmdlet.ParameterSetName)."
        Write-Message -Level System -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $AgResults = @()
            $ProcessedAgDatabases = @()
            if ($server.AvailabilityGroups.Count -gt 0) {
                $agShortInstance = $instance.FullName.split('.')[0]
                if ($agShortInstance -in ($server.AvailabilityGroups.AvailabilityGroupListeners).Name) {
                    # We have a listener passed in, just query the dbs specified or all in the AG
                    $null = $PSBoundParameters.Remove('SqlInstance')
                    $null = $PSBoundParameters.Remove('IncludeCopyOnly')
                    Write-Message -Level Verbose -Message "Fetching history from replicas on $($AvailabilityGroupBase.AvailabilityReplicas.name)"
                    $AvailabilityGroupBase = ($server.AvailabilityGroups | Where-Object { $_.AvailabilityGroupListeners.name -eq $agShortInstance })
                    $AgLoopResults = Get-DbaDbBackupHistory -SqlInstance $AvailabilityGroupBase.AvailabilityReplicas.name @PSBoundParameters -IncludeCopyOnly
                    $AvailabilityGroupName = $AvailabilityGroupBase.name
                    Foreach ($agr in $AgLoopResults) {
                        $agr.AvailabilityGroupName = $AvailabilityGroupName
                    }
                    if ($Last) {
                        Write-Message -Level Verbose -Message "Filtering Ag backups for Last"
                        $AgResults = $AgLoopResults | Select-DbaBackupInformation -ServerName $AvailabilityGroupName
                    } elseif ($LastFull) {
                        Foreach ($AgDb in ( $AgLoopResults.Database | Select-Object -Unique)) {
                            $AgResults += $AgLoopResults | Where-Object { $_.Database -eq $AgDb } | Sort-Object -Property FirstLsn | Select-Object -Last 1
                        }
                    } elseif ($LastDiff) {
                        Foreach ($AgDb in ( $AgLoopResults.Database | Select-Object -Unique)) {
                            $AgResults += $AgLoopResults | Where-Object { $_.Database -eq $AgDb } | Sort-Object -Property FirstLsn | Select-Object -Last 1
                        }
                    } elseif ($LastLog) {
                        Foreach ($AgDb in ( $AgLoopResults.Database | Select-Object -Unique)) {
                            $AgResults += $AgLoopResults | Where-Object { $_.Database -eq $AgDb } | Sort-Object -Property FirstLsn | Select-Object -Last 1
                        }
                    } else {
                        $AgResults += $AgLoopResults
                    }
                    # Results are already in the correct format so drop to output
                    $agresults
                    ### Discuss: What if more than one SqlInstance is passed in?
                    # We're done at this point so exit function
                    return
                }
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
            if ($server.AvailabilityGroups.Count -gt 0) {
                $adbs = $databases | Where-Object Name -In $server.AvailabilityGroups.AvailabilityDatabases.Name
                $adbs = $adbs | Where-Object Name -NotIn $ProcessedAgDatabases
                ForEach ($adb in $adbs) {
                    Write-Message -Level Verbose -Message "Fetching history from replicas for db $($adb.name)"
                    if ($adb.GetType().name -ne 'Database') {
                        $adb = Get-DbaDatabase -SqlInstance $server -Database $adb.name
                    }
                    $AvailabilityGroupBase = $adb.parent.AvailabilityGroups[$adb.AvailabilityGroupName]
                    $AvailabilityGroupListener = $AvailabilityGroupBase.AvailabilityGroupListeners.Name
                    if ($null -eq $AvailabilityGroupListener) {
                        Write-Message -Level Verbose -Message "AvailabilityGroup $($AvailabilityGroupBase.Name) has no listener, so skipping fetching history from replicas for db $($adb.name)"
                        continue
                    }
                    $null = $PSBoundParameters.Remove('SqlInstance')
                    $null = $PSBoundParameters.Remove('Database')
                    $AgLoopResults = Get-DbaAgBackupHistory -SqlInstance $AvailabilityGroupListener -Database $adb.Name @PSBoundParameters
                    $AvailabilityGroupName = $AvailabilityGroupBase.name
                    Foreach ($agr in $AgLoopResults) {
                        $agr.AvailabilityGroupName = $AvailabilityGroupName
                    }
                    # Results already in the right format, drop straight to output
                    $AgLoopResults
                    # Remove database from collection as it is now done with
                    $databases = $databases | Where-Object Name -NE $adb.name
                }
            }

            $null = $PSBoundParameters.Remove('SqlInstance')
            Get-DbaDbBackupHistory -SqlInstance $server @PSBoundParameters
        }
    }
}