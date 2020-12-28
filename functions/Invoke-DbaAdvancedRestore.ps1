function Invoke-DbaAdvancedRestore {
    <#
    .SYNOPSIS
        Allows the restore of modified BackupHistory Objects
        For 90% of users Restore-DbaDatabase should be your point of access to this function. The other 10% use it at their own risk

    .DESCRIPTION
        This is the final piece in the Restore-DbaDatabase Stack. Usually a BackupHistory object will arrive here from `Restore-DbaDatabase` via the following pipeline:
        `Get-DbaBackupInformation  | Select-DbaBackupInformation | Format-DbaBackupInformation | Test-DbaBackupInformation | Invoke-DbaAdvancedRestore`

        We have exposed these functions publicly to allow advanced users to perform operations that we don't support, or won't add as they would make things too complex for the majority of our users

        For example if you wanted to do some very complex redirection during a migration, then doing the rewrite of destinations may be better done with your own custom scripts rather than via `Format-DbaBackupInformation`

        We would recommend ALWAYS pushing your input through `Test-DbaBackupInformation` just to make sure that it makes sense to us.

    .PARAMETER BackupHistory
        The BackupHistory object to be restored.
        Can be passed in on the pipeline

    .PARAMETER SqlInstance
        The SqlInstance to which the backups should be restored

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER OutputScriptOnly
        If set, the restore will not be performed, but the T-SQL scripts to perform it will be returned

    .PARAMETER VerifyOnly
        If set, performs a Verify of the backups rather than a full restore

    .PARAMETER RestoreTime
        Point in Time to which the database should be restored.

        This should be the same value or earlier, as used in the previous pipeline stages

    .PARAMETER StandbyDirectory
        A folder path where a standby file should be created to put the recovered databases in a standby mode

    .PARAMETER NoRecovery
        Leave the database in a restoring state so that further restore may be made

    .PARAMETER MaxTransferSize
        Parameter to set the unit of transfer. Values must be a multiple by 64kb

    .PARAMETER Blocksize
        Specifies the block size to use. Must be one of 0.5kb,1kb,2kb,4kb,8kb,16kb,32kb or 64kb
        Can be specified in bytes
        Refer to https://msdn.microsoft.com/en-us/library/ms178615.aspx for more detail

    .PARAMETER BufferCount
        Number of I/O buffers to use to perform the operation.
        Refer to https://msdn.microsoft.com/en-us/library/ms178615.aspx for more detail

    .PARAMETER Continue
        Indicates that the restore is continuing a restore, so target database must be in Recovering or Standby states
        When specified, WithReplace will be set to true

    .PARAMETER AzureCredential
        AzureCredential required to connect to blob storage holding the backups

    .PARAMETER WithReplace
        Indicated that if the database already exists it should be replaced

    .PARAMETER KeepReplication
        Indicates whether replication configuration should be restored as part of the database restore operation

    .PARAMETER KeepCDC
        Indicates whether CDC information should be restored as part of the database

    .PARAMETER PageRestore
        The output from Get-DbaSuspect page containing the suspect pages to be restored.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.

    .PARAMETER ExecuteAs
        If set, this will cause the database(s) to be restored (and therefore owned) as the SA user

    .PARAMETER StopMark
        Mark in the transaction log to stop the restore at

    .PARAMETER StopBefore
        Switch to indicate the restore should stop before StopMark

    .PARAMETER StopAfterDate
        By default the restore will stop at the first occurence of StopMark found in the chain, passing a datetime where will cause it to stop the first StopMark atfer that datetime

    .PARAMETER EnableException
        Replaces user friendly yellow warnings with bloody red exceptions of doom!
        Use this if you want the function to throw terminating errors you want to catch.

    .NOTES
        Tags: Restore, Backup
        Author: Stuart Moore (@napalmgram - http://stuart-moore.com)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaAdvancedRestore

    .EXAMPLE
        PS C:\> $BackupHistory | Invoke-DbaAdvancedRestore -SqlInstance MyInstance

        Will restore all the backups in the BackupHistory object according to the transformations it contains

    .EXAMPLE
        PS C:\> $BackupHistory | Invoke-DbaAdvancedRestore -SqlInstance MyInstance -OutputScriptOnly
        PS C:\> $BackupHistory | Invoke-DbaAdvancedRestore -SqlInstance MyInstance

        First generates just the T-SQL restore scripts so they can be sanity checked, and then if they are good perform the full restore.
        By reusing the BackupHistory object there is no need to rescan all the backup files again

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "AzureCredential", Justification = "For Parameter AzureCredential")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Object[]]$BackupHistory,
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$OutputScriptOnly,
        [switch]$VerifyOnly,
        [datetime]$RestoreTime = (Get-Date).AddDays(2),
        [string]$StandbyDirectory,
        [switch]$NoRecovery,
        [int]$MaxTransferSize,
        [int]$BlockSize,
        [int]$BufferCount,
        [switch]$Continue,
        [string]$AzureCredential,
        [switch]$WithReplace,
        [switch]$KeepReplication,
        [switch]$KeepCDC,
        [object[]]$PageRestore,
        [string]$ExecuteAs,
        [switch]$StopBefore,
        [string]$StopMark,
        [datetime]$StopAfterDate,
        [switch]$EnableException
    )
    begin {
        try {
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $SqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            return
        }
        if ($KeepCDC -and ($NoRecovery -or ('' -ne $StandbyDirectory))) {
            Stop-Function -Category InvalidArgument -Message "KeepCDC cannot be specified with Norecovery or Standby as it needs recovery to work"
            return
        }

        if ($null -ne $PageRestore) {
            Write-Message -Message "Doing Page Recovery" -Level Verbose
            $tmpPages = @()
            foreach ($Page in $PageRestore) {
                $tmpPages += "$($Page.FileId):$($Page.PageID)"
            }
            $NoRecovery = $True
            $Pages = $tmpPages -join ','
        }
        $internalHistory = @()
    }
    process {
        foreach ($bh in $BackupHistory) {
            $internalHistory += $bh
        }
    }
    end {
        if (Test-FunctionInterrupt) { return }
        if ($Continue -eq $True) {
            $WithReplace = $True
        }
        $databases = $internalHistory.Database | Select-Object -Unique
        foreach ($database in $databases) {
            $databaseRestoreStartTime = Get-Date
            if ($database -in $server.Databases.Name) {
                if (-not $OutputScriptOnly -and -not $VerifyOnly -and $server.DatabaseEngineEdition -ne "SqlManagedInstance") {
                    if ($Pscmdlet.ShouldProcess("Killing processes in $database on $SqlInstance as it exists and WithReplace specified  `n", "Cannot proceed if processes exist, ", "Database Exists and WithReplace specified, need to kill processes to restore")) {
                        try {
                            Write-Message -Level Verbose -Message "Killing processes on $database"
                            $null = Stop-DbaProcess -SqlInstance $server -Database $database -WarningAction Silentlycontinue
                            $null = $server.Query("Alter database $database set offline with rollback immediate; alter database $database set restricted_user; Alter database $database set online with rollback immediate", 'master')
                            $server.ConnectionContext.Connect()
                        } catch {
                            Write-Message -Level Verbose -Message "No processes to kill in $database"
                        }
                    }
                } elseif (-not $OutputScriptOnly -and -not $VerifyOnly -and $server.DatabaseEngineEdition -eq "SqlManagedInstance") {
                    if ($Pscmdlet.ShouldProcess("Dropping $database on $SqlInstance as it exists and WithReplace specified  `n", "Cannot proceed if database exist, ", "Database Exists and WithReplace specified, need to drop database to restore")) {
                        try {
                            Write-Message -Level Verbose "$SqlInstance is a Managed instance so dropping database was WithReplace not supported"
                            $null = Stop-DbaProcess -SqlInstance $server -Database $database -WarningAction Silentlycontinue
                            $null = Remove-DbaDatabase -SqlInstance $server -Database $database -Confirm:$false
                            $server.ConnectionContext.Connect()
                        } catch {
                            Write-Message -Level Verbose -Message "No processes to kill in $database"
                        }
                    }

                } elseif (-not $WithReplace -and (-not $VerifyOnly)) {
                    Write-Message -Level verbose -Message "$database exists and WithReplace not specified, stopping"
                    continue
                }
            }
            Write-Message -Message "WithReplace  = $WithReplace" -Level Debug
            $backups = @($internalHistory | Where-Object { $_.Database -eq $database } | Sort-Object -Property Type, FirstLsn)
            $BackupCnt = 1

            foreach ($backup in $backups) {
                $fileRestoreStartTime = Get-Date
                $restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
                if (($backup -ne $backups[-1]) -or $true -eq $NoRecovery) {
                    $restore.NoRecovery = $True
                } elseif ($backup -eq $backups[-1] -and '' -ne $StandbyDirectory) {
                    $restore.StandbyFile = $StandByDirectory + "\" + $database + (Get-Date -Format yyyyMMddHHmmss) + ".bak"
                    Write-Message -Level Verbose -Message "Setting standby on last file $($restore.StandbyFile)"
                } else {
                    $restore.NoRecovery = $False
                }
                if (-not [string]::IsNullOrEmpty($StopMark)) {
                    if ($StopBefore -eq $True) {
                        $restore.StopBeforeMarkName = $StopMark
                        if ($null -ne $StopAfterDate) {
                            $restore.StopBeforeMarkAfterDate = $StopAfterDate
                        }
                    } else {
                        $restore.StopAtMarkName = $StopMark
                        if ($null -ne $StopAfterDate) {
                            $restore.StopAtMarkAfterDate = $StopAfterDate
                        }
                    }
                } elseif ($RestoreTime -gt (Get-Date) -or $backup.RestoreTime -gt (Get-Date) -or $backup.RecoveryModel -eq 'Simple') {
                    $restore.ToPointInTime = $null
                } else {
                    if ($RestoreTime -ne $backup.RestoreTime) {
                        $restore.ToPointInTime = $backup.RestoreTime
                    } else {
                        $restore.ToPointInTime = $RestoreTime
                    }
                }

                $restore.Database = $database
                if ($server.DatabaseEngineEdition -ne "SqlManagedInstance") {
                    $restore.ReplaceDatabase = $WithReplace
                }
                if ($MaxTransferSize) {
                    $restore.MaxTransferSize = $MaxTransferSize
                }
                if ($BufferCount) {
                    $restore.BufferCount = $BufferCount
                }
                if ($BlockSize) {
                    $restore.Blocksize = $BlockSize
                }
                if ($KeepReplication) {
                    $restore.KeepReplication = $KeepReplication
                }
                if ($true -ne $Continue -and ($null -eq $Pages)) {
                    foreach ($file in $backup.FileList) {
                        $moveFile = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile
                        $moveFile.LogicalFileName = $file.LogicalName
                        $moveFile.PhysicalFileName = $file.PhysicalName
                        $null = $restore.RelocateFiles.Add($moveFile)
                    }
                }
                $action = switch ($backup.Type) {
                    '1' { 'Database' }
                    '2' { 'Log' }
                    '5' { 'Database' }
                    'Transaction Log' { 'Log' }
                    Default { 'Database' }
                }

                Write-Message -Level Debug -Message "restore action = $action"
                $restore.Action = $action
                foreach ($file in $backup.FullName) {
                    Write-Message -Message "Adding device $file" -Level Debug
                    $device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem
                    $device.Name = $file
                    if ($file.StartsWith("http")) {
                        $device.devicetype = "URL"
                    } else {
                        $device.devicetype = "File"
                    }

                    if ($AzureCredential) {
                        $restore.CredentialName = $AzureCredential
                    }

                    $restore.FileNumber = $backup.Position
                    $restore.Devices.Add($device)
                }
                Write-Message -Level Verbose -Message "Performing restore action"
                $confirmMessage = "`n Restore Database $database on $SqlInstance `n from files: $RestoreFileNames `n with these file moves: `n $LogicalFileMovesString `n $ConfirmPointInTime `n"
                if ($Pscmdlet.ShouldProcess("$database on $SqlInstance `n `n", $confirmMessage)) {
                    try {
                        $restoreComplete = $true
                        if ($KeepCDC -and $restore.NoRecovery -eq $false) {
                            $script = $restore.Script($server)
                            if ($script -like '*WITH*') {
                                $script = $script.TrimEnd() + ' , KEEP_CDC'
                            } else {
                                $script = $script.TrimEnd() + ' WITH KEEP_CDC'
                            }
                            if ($true -ne $OutputScriptOnly) {
                                Write-Progress -id 1 -activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                                $null = $server.ConnectionContext.ExecuteNonQuery($script)
                                Write-Progress -id 1 -activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -status "Complete" -Completed
                            }
                        } elseif ($null -ne $Pages -and $action -eq 'Database') {
                            $script = $restore.Script($server)
                            $script = $script -replace "] FROM", "] PAGE='$pages' FROM"
                            if ($true -ne $OutputScriptOnly) {
                                Write-Progress -id 1 -activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                                $null = $server.ConnectionContext.ExecuteNonQuery($script)
                                Write-Progress -id 1 -activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -status "Complete" -Completed
                            }
                        } elseif ($OutputScriptOnly) {
                            $script = $restore.Script($server)
                            if ($ExecuteAs -ne '' -and $BackupCnt -eq 1) {
                                $script = "EXECUTE AS LOGIN='$ExecuteAs'; " + $script
                            }
                        } elseif ($VerifyOnly) {
                            Write-Message -Message "VerifyOnly restore" -Level Verbose
                            Write-Progress -id 1 -activity "Verifying $database backup file on $SqlInstance - Backup $BackupCnt of $($Backups.count)" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                            $Verify = $restore.SqlVerify($server)
                            Write-Progress -id 1 -activity "Verifying $database backup file on $SqlInstance - Backup $BackupCnt of $($Backups.count)" -status "Complete" -Completed
                            if ($verify -eq $true) {
                                Write-Message -Message "VerifyOnly restore Succeeded" -Level Verbose
                                return "Verify successful"
                            } else {
                                Write-Message -Message "VerifyOnly restore Failed" -Level Verbose
                                return "Verify failed"
                            }
                        } else {
                            $outerProgress = $BackupCnt / $Backups.Count * 100
                            if ($BackupCnt -eq 1) {
                                Write-Progress -id 1 -Activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -percentcomplete 0
                            }
                            Write-Progress -id 2 -ParentId 1 -Activity "Restore $($backup.FullName -Join ',')" -percentcomplete 0
                            $script = $restore.Script($server)
                            if ($ExecuteAs -ne '' -and $BackupCnt -eq 1) {
                                Write-Progress -id 1 -activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                                $script = "EXECUTE AS LOGIN='$ExecuteAs'; " + $script
                                $null = $server.ConnectionContext.ExecuteNonQuery($script)
                                Write-Progress -id 1 -activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -status "Complete" -Completed
                            } else {
                                $percentcomplete = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
                                    Write-Progress -id 2 -ParentId 1 -Activity "Restore $($backup.FullName -Join ',')" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
                                }
                                $restore.add_PercentComplete($percentcomplete)
                                $restore.PercentCompleteNotification = 1
                                $restore.SqlRestore($server)
                                Write-Progress -id 2 -ParentId 1 -Activity "Restore $($backup.FullName -Join ',')" -Completed
                            }
                            Write-Progress -id 1 -Activity "Restoring $database to $SqlInstance - Backup $BackupCnt of $($Backups.count)" -percentcomplete $outerProgress -status ([System.String]::Format("Progress: {0:N2} %", $outerProgress))
                        }
                    } catch {
                        Write-Message -Level Verbose -Message "Failed, Closing Server connection"
                        $restoreComplete = $False
                        $ExitError = $_.Exception.InnerException
                        Stop-Function -Message "Failed to restore db $database, stopping" -ErrorRecord $_ -Continue
                        break
                    } finally {
                        if ($OutputScriptOnly -eq $false) {
                            $pathSep = Get-DbaPathSep -Server $server
                            $RestoreDirectory = ((Split-Path $backup.FileList.PhysicalName -Parent) | Sort-Object -Unique).Replace('\', $pathSep) -Join ','
                            [PSCustomObject]@{
                                ComputerName           = $server.ComputerName
                                InstanceName           = $server.ServiceName
                                SqlInstance            = $server.DomainInstanceName
                                Database               = $backup.Database
                                DatabaseName           = $backup.Database
                                DatabaseOwner          = $server.ConnectionContext.TrueLogin
                                Owner                  = $server.ConnectionContext.TrueLogin
                                NoRecovery             = $restore.NoRecovery
                                WithReplace            = $WithReplace
                                KeepReplication        = $KeepReplication
                                RestoreComplete        = $restoreComplete
                                BackupFilesCount       = $backup.FullName.Count
                                RestoredFilesCount     = $backup.Filelist.PhysicalName.count
                                BackupSizeMB           = if ([bool]($backup.psobject.Properties.Name -contains 'TotalSize')) { [Math]::Round(($backup | Measure-Object -Property TotalSize -Sum).Sum / $backup.FullName.Count / 1mb, 2) } else { $null }
                                CompressedBackupSizeMB = if ([bool]($backup.psobject.Properties.Name -contains 'CompressedBackupSize')) { [Math]::Round(($backup | Measure-Object -Property CompressedBackupSize -Sum).Sum / $backup.FullName.Count / 1mb, 2) } else { $null }
                                BackupFile             = $backup.FullName -Join ','
                                RestoredFile           = $((Split-Path $backup.FileList.PhysicalName -Leaf) | Sort-Object -Unique) -Join ','
                                RestoredFileFull       = ($backup.Filelist.PhysicalName -Join ',')
                                RestoreDirectory       = $RestoreDirectory
                                BackupSize             = if ([bool]($backup.psobject.Properties.Name -contains 'TotalSize')) { [dbasize](($backup | Measure-Object -Property TotalSize -Sum).Sum / $backup.FullName.Count) } else { $null }
                                CompressedBackupSize   = if ([bool]($backup.psobject.Properties.Name -contains 'CompressedBackupSize')) { [dbasize](($backup | Measure-Object -Property CompressedBackupSize -Sum).Sum / $backup.FullName.Count) } else { $null }
                                BackupStartTime        = $backup.Start
                                BackupEndTime          = $backup.End
                                RestoreTargetTime      = if ($RestoreTime -lt (Get-Date)) { $RestoreTime } else { 'Latest' }
                                Script                 = $script
                                BackupFileRaw          = ($backups.Fullname)
                                FileRestoreTime        = New-TimeSpan -Seconds ((Get-Date) - $fileRestoreStartTime).TotalSeconds
                                DatabaseRestoreTime    = New-TimeSpan -Seconds ((Get-Date) - $databaseRestoreStartTime).TotalSeconds
                                ExitError              = $ExitError
                            } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, BackupFile, BackupFilesCount, BackupSize, CompressedBackupSize, Database, Owner, DatabaseRestoreTime, FileRestoreTime, NoRecovery, RestoreComplete, RestoredFile, RestoredFilesCount, Script, RestoreDirectory, WithReplace
                        } else {
                            $script
                        }
                        if ($restore.Devices.Count -gt 0) {
                            $restore.Devices.Clear()
                        }
                        Write-Message -Level Verbose -Message "Succeeded, Closing Server connection"
                        $server.ConnectionContext.Disconnect()
                    }
                }
                $BackupCnt++
            }
            Write-Progress -id 2 -Activity "Finished" -Completed
            if ($server.ConnectionContext.exists) {
                $server.ConnectionContext.Disconnect()
            }
            Write-Progress -id 1 -Activity "Finished" -Completed
        }
    }
}
