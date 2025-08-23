function Select-DbaBackupInformation {
    <#
    .SYNOPSIS
        Filters backup history to identify the minimum backup chain needed for point-in-time database recovery

    .DESCRIPTION
        Analyzes backup history objects and determines the exact sequence of backups required to restore a database to a specific point in time. This function handles the complex LSN logic to identify which full, differential, and log backups are needed, eliminating the guesswork of manual restore planning. It supports continuing interrupted restores, filtering by database or server names, and accommodating different restore strategies by optionally ignoring differential or log backups. Perfect for automating disaster recovery procedures or when you need to restore to a precise moment without restoring unnecessary backup files.

    .PARAMETER BackupHistory
        Backup history records from Get-DbaBackupInformation containing backup metadata and file paths.
        This function analyzes these records to determine the minimum backup chain needed for point-in-time recovery.

    .PARAMETER RestoreTime
        The specific point in time to restore the database to. Defaults to one month in the future if not specified.
        Use this when you need to recover to a specific moment, such as just before a data corruption incident occurred.

    .PARAMETER IgnoreLogs
        Excludes transaction log backups from the restore chain, limiting recovery to the most recent full or differential backup.
        Use this when you don't need point-in-time recovery or when log backups are unavailable or corrupted.

    .PARAMETER IgnoreDiffs
        Excludes differential backups from the restore chain, using only full backups and transaction logs.
        Use this when differential backups are corrupted or when you want to test a restore strategy using only full and log backups.

    .PARAMETER DatabaseName
        Filters results to only include backup chains for the specified database names. Accepts wildcards.
        Use this when you only need to restore specific databases from a backup set containing multiple databases.

    .PARAMETER ServerName
        Filters results to only include backups from the specified server or availability group names.
        For Availability Groups, this filters by the AG name rather than individual replica server names.

    .PARAMETER ContinuePoints
        Output from Get-RestoreContinuableDatabase containing LSN and fork information for resuming interrupted restores.
        Use this when continuing a partial restore operation on a database that's already in a restoring state.

    .PARAMETER LastRestoreType
        Output from Get-DbaDbRestoreHistory -Last showing the most recent restore operation performed on the target database.
        This determines whether differential backups can be applied based on the last restore type performed.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Backup, Restore
        Author:Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Select-DbaBackupInformation

    .EXAMPLE
        PS C:\> $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\server1\backups$
        PS C:\> $FilteredBackups = $Backups | Select-DbaBackupInformation -RestoreTime (Get-Date).AddHours(-1)

        Returns all backups needed to restore all the backups in \\server1\backups$ to 1 hour ago

    .EXAMPLE
        PS C:\> $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\server1\backups$
        PS C:\> $FilteredBackups = $Backups | Select-DbaBackupInformation -RestoreTime (Get-Date).AddHours(-1) -DatabaseName ProdFinance

        Returns all the backups needed to restore Database ProdFinance to an hour ago

    .EXAMPLE
        PS C:\> $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\server1\backups$
        PS C:\> $FilteredBackups = $Backups | Select-DbaBackupInformation -RestoreTime (Get-Date).AddHours(-1) -IgnoreLogs

        Returns all the backups in \\server1\backups$ to restore to as close prior to 1 hour ago as can be managed with only full and differential backups

    .EXAMPLE
        PS C:\> $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\server1\backups$
        PS C:\> $FilteredBackups = $Backups | Select-DbaBackupInformation -RestoreTime (Get-Date).AddHours(-1) -IgnoreDiffs

        Returns all the backups in \\server1\backups$ to restore to 1 hour ago using only Full and Log backups.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [object]$BackupHistory,
        [DateTime]$RestoreTime = (Get-Date).addmonths(1),
        [switch]$IgnoreLogs,
        [switch]$IgnoreDiffs,
        [string[]]$DatabaseName,
        [string[]]$ServerName,
        [object]$ContinuePoints,
        [object]$LastRestoreType,
        [switch]$EnableException
    )
    begin {
        $InternalHistory = @()
        $IgnoreFull = $false
        if ((Test-Bound -ParameterName ContinuePoints) -and $null -ne $ContinuePoints) {
            Write-Message -Message "ContinuePoints provided so setting up for a continue" -Level Verbose
            $IgnoreFull = $true
            $Continue = $True
            if (Test-Bound -ParameterName DatabaseName) {
                $DatabaseName = $DatabaseName | Where-Object { $_ -in ($ContinuePoints | Select-Object -Property Database).Database }

                $DroppedDatabases = $DatabaseName | Where-Object { $_ -notin ($ContinuePoints | Select-Object -Property Database).Database }
                if ($null -ne $DroppedDatabases) {
                    Write-Message -Message "$($DroppedDatabases.join(',')) filtered out as not in ContinuePoints" -Level Verbose
                }
            } else {
                $DatabaseName = ($ContinuePoints | Select-Object -Property Database).Database
            }
        }
    }
    process {
        $internalHistory += $BackupHistory
    }

    end {
        ForEach ($History in $InternalHistory) {
            if ("RestoreTime" -notin $History.PSobject.Properties.name) {
                $History | Add-Member -Name 'RestoreTime' -Type NoteProperty -Value $RestoreTime
            }
        }
        if ((Test-Bound -ParameterName DatabaseName) -and '' -ne $DatabaseName) {
            Write-Message -Message "Filtering by DatabaseName" -Level Verbose
            #  $InternalHistory = $InternalHistory | Where-Object {$_.Database -in $DatabaseName}
        }

        # Check for AGs
        if (Test-Bound -ParameterName ServerName) {
            if (($InternalHistory | Where-Object { $_.AvailabilityGroupName -ne '' }).count -ne 0) {
                Write-Message -Level Verbose -Message 'Dealing with Availabilitygroups'
                $InternalHistory = $InternalHistory | Where-Object { $_.AvailabilityGroupName -in $servername }
            } else {
                Write-Message -Message "Filtering by ServerName" -Level Verbose
                $InternalHistory = $InternalHistory | Where-Object { $_.InstanceName -in $servername }
            }
        }

        $Databases = ($InternalHistory | Select-Object -Property Database -unique).Database
        if ($continue -and $Databases.count -gt 1 -and $DatabaseName.count -gt 1) {
            Stop-Function -Message "Cannot perform continuing restores on multiple databases with renames, exiting"
            return
        }


        ForEach ($Database in $Databases) {
            #Cope with restores renaming the db
            # $database = the name of database in the backups being scanned
            # $databasefilter = the name of the database the backups are being restore to/against
            if ($null -ne $DatabaseName) {
                $databasefilter = $DatabaseName
            } else {
                $databasefilter = $database
            }

            if ($true -eq $Continue) {
                #Test if Database is in a continuing state and the LSN to continue from:
                if ($Databasefilter -in ($ContinuePoints | Select-Object -Property Database).Database) {
                    Write-Message -Message "$Database in ContinuePoints, will attempt to continue" -Level verbose
                    $IgnoreFull = $True
                    #Check what the last backup restored was
                    if (($LastRestoreType | Where-Object { $_.Database -eq $Databasefilter }).RestoreType -eq 'log') {
                        #log Backup last restored, so diffs cannot be used
                        $IgnoreDiffs = $true
                    } else {
                        #Last restore was a diff or full, so can restore diffs or logs
                        $IgnoreDiffs = $false
                    }
                } else {
                    Write-Message -Message "$Database not in ContinuePoints, will attempt normal restore" -Level Warning
                }
            }

            $dbhistory = @()
            $DatabaseHistory = $internalhistory | Where-Object { $_.Database -eq $Database }
            #For a standard restore, work out the full backup
            if ($false -eq $IgnoreFull) {
                $Full = $DatabaseHistory | Where-Object { $_.Type -in ('Full', 'Database') -and $_.End -le $RestoreTime } | Sort-Object -Property LastLsn -Descending | Select-Object -First 1
                if ($full.Fullname) {
                    $full.Fullname = ($DatabaseHistory | Where-Object { $_.Type -in ('Full', 'Database') -and $_.BackupSetID -eq $Full.BackupSetID }).Fullname
                } else {
                    Stop-Function -Message "Fullname property not found. This could mean that a full backup could not be found or the command must be re-run with the -Continue switch."
                    return
                }
                $dbHistory += $full
            } elseif ($true -eq $IgnoreFull -and $false -eq $IgnoreDiffs) {
                #Fake the Full backup
                Write-Message -Message "Continuing, so setting a fake full backup from the existing database"
                $Full = [PSCustomObject]@{
                    CheckpointLSN = ($ContinuePoints | Where-Object { $_.Database -eq $DatabaseFilter }).differential_base_lsn
                }
            }

            if ($false -eq $IgnoreDiffs) {
                Write-Message -Message "processing diffs" -Level Verbose
                $Diff = $DatabaseHistory | Where-Object { $_.Type -in ('Differential', 'Database Differential') -and $_.End -le $RestoreTime -and $_.DatabaseBackupLSN -eq $Full.CheckpointLSN } | Sort-Object -Property LastLsn -Descending | Select-Object -First 1
                if ($null -ne $Diff) {
                    if ($Diff.FullName) {
                        $Diff.FullName = ($DatabaseHistory | Where-Object { $_.Type -in ('Differential', 'Database Differential') -and $_.BackupSetID -eq $diff.BackupSetID }).Fullname
                    } else {
                        Stop-Function -Message "Fullname property not found. This could mean that a full backup could not be found or the command must be re-run with the -Continue switch."
                        return
                    }
                    $dbhistory += $Diff
                }
            }

            #Sort out the LSN for the log restores
            if ($null -ne ($dbHistory | Sort-Object -Property LastLsn -Descending | Select-Object -First 1).lastLsn) {
                #We have history so use this
                [bigint]$LogBaseLsn = ($dbHistory | Sort-Object -Property LastLsn -Descending | Select-Object -First 1).lastLsn.ToString()
                $FirstRecoveryForkID = $Full.FirstRecoveryForkID
                Write-Message -Level Verbose -Message "Found LogBaseLsn: $LogBaseLsn and FirstRecoveryForkID: $FirstRecoveryForkID"
            } else {
                Write-Message -Message "No full or diff, so attempting to pull from Continue informmation" -Level Verbose
                try {
                    [bigint]$LogBaseLsn = ($ContinuePoints | Where-Object { $_.Database -eq $DatabaseFilter }).redo_start_lsn
                    $FirstRecoveryForkID = ($ContinuePoints | Where-Object { $_.Database -eq $DatabaseFilter }).FirstRecoveryForkID
                    Write-Message -Level Verbose -Message "Found LogBaseLsn: $LogBaseLsn and FirstRecoveryForkID: $FirstRecoveryForkID from Continue information"
                } catch {
                    Stop-Function -Message "Failed to find LSN or RecoveryForkID for $DatabaseFilter" -Category InvalidOperation -Target $DatabaseFilter
                }
            }

            if ($false -eq $IgnoreLogs) {
                $FilteredLogs = $DatabaseHistory | Where-Object { $_.Type -in ('Log', 'Transaction Log') -and $_.Start -lt $RestoreTime -and $_.LastLSN -ge $LogBaseLsn -and $_.FirstLSN -ne $_.LastLSN } | Sort-Object -Property LastLsn, FirstLsn
                $GroupedLogs = $FilteredLogs | Group-Object -Property BackupSetID
                ForEach ($Group in $GroupedLogs) {
                    $Log = $Group.group[0]
                    $Log.FullName = $Group.group.fullname
                    $dbhistory += $Log
                }
                # Get Last T-log

                $lastLog = $DatabaseHistory | Where-Object { $_.Type -in ('Log', 'Transaction Log') -and $_.End -ge $RestoreTime -and $_.DatabaseBackupLSN -ge $Full.CheckpointLSN } | Sort-Object -Property LastLsn, FirstLsn | Select-Object -First 1
                if ($null -ne $lastlog) {
                    $lastLog.FullName = ($DatabaseHistory | Where-Object { $_.BackupSetID -eq $lastLog.BackupSetID }).Fullname
                }
                $dbHistory += $lastLog
            }
            $dbhistory
        }
    }
}