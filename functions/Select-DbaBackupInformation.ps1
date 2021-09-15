function Select-DbaBackupInformation {
    <#
    .SYNOPSIS
        Select a subset of backups from a dbatools backup history object

    .DESCRIPTION
        Select-DbaBackupInformation filters out a subset of backups from the dbatools backup history object with parameters supplied.

    .PARAMETER BackupHistory
        A dbatools.BackupHistory object containing backup history records

    .PARAMETER RestoreTime
        The point in time you want to restore to

    .PARAMETER IgnoreLogs
        This switch will cause Log Backups to be ignored. So will restore to the last Full or Diff backup only

    .PARAMETER IgnoreDiffs
        This switch will cause Differential backups to be ignored. Unless IgnoreLogs is specified, restore to point in time will still occur, just using all available log backups

    .PARAMETER DatabaseName
        A string array of Database Names that you want to filter to

    .PARAMETER ServerName
        A string array of Server Names that you want to filter

    .PARAMETER ContinuePoints
        The Output of Get-RestoreContinuableDatabase while provides 'Database',redo_start_lsn,'FirstRecoveryForkID' values. Used to filter backups to continue a restore on a database
        Sets IgnoreDiffs, and also filters databases to only those within the ContinuePoints object, or the ContinuePoints object AND DatabaseName if both specified

    .PARAMETER LastRestoreType
        The Output of Get-DbaDbRestoreHistory -last
        This is used to check the last type of backup to a database to see if a differential backup can be restored

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

        Returns all the backups in \\server1\backups$ to restore to 1 hour ago using only Full and Diff backups.

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
                    Write-Message -Message "$Database in ContinuePoints, will attmept to continue" -Level verbose
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
                    Write-Message -Message "$Database not in ContinuePoints, will attmept normal restore" -Level Warning
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
                $Full = [PsCustomObject]@{
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