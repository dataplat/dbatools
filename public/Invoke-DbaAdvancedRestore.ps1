function Invoke-DbaAdvancedRestore {
    <#
    .SYNOPSIS
        Executes database restores from processed BackupHistory objects with advanced customization options

    .DESCRIPTION
        This is the final execution step in the dbatools restore pipeline. It takes pre-processed BackupHistory objects and performs the actual SQL Server database restoration with support for complex scenarios that aren't handled by the standard Restore-DbaDatabase command.

        The typical pipeline flow is: Get-DbaBackupInformation | Select-DbaBackupInformation | Format-DbaBackupInformation | Test-DbaBackupInformation | Invoke-DbaAdvancedRestore

        This function handles advanced restore scenarios including point-in-time recovery, page-level restores, Azure blob storage backups, custom file relocations, and specialized options like CDC preservation or standby mode. It can generate T-SQL scripts for review before execution, verify backup integrity, or perform the actual restore operations.

        Most DBAs should use Restore-DbaDatabase for standard scenarios. This function is designed for situations requiring custom backup processing logic, complex migrations with file redirection, or when you need granular control over the restore process that isn't available in the simplified commands.

        Always validate your BackupHistory objects with Test-DbaBackupInformation before using this function to ensure the restore chain is logically consistent.

    .PARAMETER BackupHistory
        Processed BackupHistory objects from the dbatools restore pipeline containing backup file metadata and restore instructions.
        Typically comes from Format-DbaBackupInformation after running Get-DbaBackupInformation and Select-DbaBackupInformation.
        Each object contains the backup file paths, database name, file relocations, and sequencing information needed for the restore operation.

    .PARAMETER SqlInstance
        The SqlInstance to which the backups should be restored

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER OutputScriptOnly
        Generates T-SQL RESTORE scripts without executing them, allowing you to review the commands before running.
        Useful for validating complex restores, creating deployment scripts, or troubleshooting restore logic.
        The generated scripts can be saved and executed manually or through other automation tools.

    .PARAMETER VerifyOnly
        Performs RESTORE VERIFYONLY operations to check backup file integrity without actually restoring the database.
        Use this to validate backup files are readable and not corrupted before attempting a full restore.
        Particularly valuable when testing backup files from different environments or after transferring backup files.

    .PARAMETER RestoreTime
        Specifies the exact point-in-time for log restore operations when performing point-in-time recovery.
        Use this for recovering to a specific moment before data corruption or unwanted changes occurred.
        Must be within the timeframe covered by your transaction log backups and should match the value used in earlier pipeline stages.

    .PARAMETER StandbyDirectory
        Directory path where SQL Server creates standby files for read-only access during restore operations.
        Puts the database in standby mode, allowing read-only queries while maintaining the ability to apply additional transaction log restores.
        Commonly used for log shipping warm standby servers or when you need to query data during a staged restore process.

    .PARAMETER NoRecovery
        Leaves the database in RESTORING state after the operation, allowing additional transaction log restores to be applied.
        Essential for point-in-time recovery scenarios where you need to apply multiple transaction log backups sequentially.
        The database remains inaccessible until a final restore operation is performed WITH RECOVERY.

    .PARAMETER MaxTransferSize
        Sets the maximum amount of data transferred between SQL Server and backup devices in each read operation.
        Specify in bytes as a multiple of 64KB to optimize restore performance for large databases or slow storage.
        Higher values can improve performance but use more memory; typically ranges from 64KB to 4MB depending on your system.

    .PARAMETER Blocksize
        Physical block size used for backup device I/O operations, must be 512, 1024, 2048, 4096, 8192, 16384, 32768, or 65536 bytes.
        Should match the block size used when the backup was created to avoid performance issues.
        Most backups use the default 64KB unless created with specific block size requirements for tape devices or storage optimization.

    .PARAMETER BufferCount
        Number of I/O buffers SQL Server uses during the restore operation to improve throughput.
        Higher buffer counts can speed up restores for large databases, especially when reading from multiple backup files.
        Typically ranges from 2 to 64 buffers depending on available memory and restore performance requirements.

    .PARAMETER Continue
        Continues a previously started restore sequence where the database is already in RESTORING or STANDBY state.
        Use this when applying additional transaction log backups to a database that was restored WITH NORECOVERY.
        Automatically enables WithReplace to allow the operation on existing database objects.

    .PARAMETER AzureCredential
        Name of the SQL Server credential object required to access backup files stored in Azure Blob Storage.
        The credential must already exist on the target SQL Server instance with proper access keys for the storage account.
        Required when restoring from URLs that point to Azure blob storage containers instead of local file paths.

    .PARAMETER WithReplace
        Allows the restore operation to overwrite an existing database with the same name.
        Without this parameter, the restore will fail if a database with the target name already exists on the instance.
        Commonly used during database migrations, refresh operations, or when restoring over development/test databases.

    .PARAMETER KeepReplication
        Preserves replication settings when restoring a database that was part of a replication topology.
        Use this when restoring a replicated database to maintain publisher, subscriber, or distributor configurations.
        Without this parameter, replication metadata is removed during the restore process.

    .PARAMETER KeepCDC
        Preserves Change Data Capture (CDC) configuration and metadata during database restore operations.
        Essential when restoring databases where CDC is actively capturing data changes for auditing or ETL processes.
        Cannot be combined with NoRecovery or StandbyDirectory parameters as CDC requires the database to be fully recovered.

    .PARAMETER PageRestore
        Array of page objects from Get-DbaSuspectPage specifying corrupted pages to restore using page-level restore.
        Use this for targeted repair of specific corrupted pages without restoring the entire database.
        Each object should contain FileId and PageID properties identifying the exact pages needing restoration.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.

    .PARAMETER ExecuteAs
        SQL Server login name to impersonate during the restore operation, affecting database ownership.
        When specified, the restore runs under this login context, making them the database owner.
        Typically used to ensure specific ownership patterns or when the current login lacks sufficient permissions.

    .PARAMETER StopMark
        Named transaction mark in the transaction log where the restore operation should stop.
        Use this for precise point-in-time recovery to a specific marked transaction, typically created with BEGIN TRAN WITH MARK.
        Provides more granular control than timestamp-based recovery for critical business operations.

    .PARAMETER StopBefore
        Stops the restore operation just before the specified StopMark rather than after it.
        Use this when you need to exclude a particular marked transaction from the restored database.
        Only effective when used in combination with the StopMark parameter for mark-based recovery scenarios.

    .PARAMETER StopAfterDate
        DateTime value specifying that only StopMark occurrences after this date should be considered for restore termination.
        Use this when the same mark name appears multiple times in your transaction log backups.
        Ensures the restore stops at the correct instance of the mark when identical mark names exist at different times.

    .PARAMETER Checksum
        Enables backup checksum verification during restore operations. Forces the restore to verify backup checksums and fail if checksums are not present.
        Use this to ensure backup files contain checksums and validate them during restore, following backup best practices.
        Without this parameter, SQL Server verifies checksums if present but doesn't fail if checksums are missing. With this parameter, the operation fails if checksums are not present in the backup.

    .PARAMETER Restart
        Instructs the restore operation to restart an interrupted restore sequence.
        Use this when a previous restore operation was interrupted due to a reboot, service failure, or other system event.
        Allows resuming large transaction log restores that were partially completed before interruption.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Restore, Backup
        Author: Stuart Moore (@napalmgram), stuart-moore.com

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
        [switch]$Checksum,
        [switch]$Restart,
        [switch]$EnableException
    )
    begin {
        try {
            $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
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
                            $null = $server.Query("ALTER DATABASE $database SET OFFLINE WITH ROLLBACK IMMEDIATE; ALTER DATABASE $database SET RESTRICTED_USER; ALTER DATABASE $database SET ONLINE WITH ROLLBACK IMMEDIATE", 'master')
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
                        $restore.ToPointInTime = $backup.RestoreTime.ToString("yyyy-MM-ddTHH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture)
                    } else {
                        $restore.ToPointInTime = $RestoreTime.ToString("yyyy-MM-ddTHH:mm:ss.fff", [System.Globalization.CultureInfo]::InvariantCulture)
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
                if ($Checksum) {
                    $restore.Checksum = $Checksum
                }
                if ($Restart) {
                    $restore.Restart = $Restart
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
                if ($Pscmdlet.ShouldProcess($SqlInstance, "Restoring $database to $SqlInstance based on these files: $($backup.FullName -join ', ')")) {
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
                            $verify = $restore.SqlVerify($server)
                            Write-Progress -id 1 -activity "Verifying $database backup file on $SqlInstance - Backup $BackupCnt of $($Backups.count)" -status "Complete" -Completed
                            if ($verify) {
                                Write-Message -Message "VerifyOnly restore Succeeded" -Level Verbose
                                $restoreComplete = $true
                                return "Verify successful"
                            } else {
                                Write-Message -Message "VerifyOnly restore Failed" -Level Warning
                                $restoreComplete = $False
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
                                Add-TeppCacheItem -SqlInstance $server -Type database -Name $database
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

                            if ([bool]($backup.psobject.Properties.Name -contains 'CompressedBackupSize')) {
                                $bytes = [PSCustomObject]@{ Bytes = $backup.CompressedBackupSize.Byte }
                                $sum = ($bytes | Measure-Object -Property Bytes -Sum).Sum
                                $compressedbackupsize = [dbasize]($sum / $backup.FullName.Count)
                                $compressedbackupsizemb = [Math]::Round($sum / $backup.FullName.Count / 1mb, 2)
                            } else {
                                $compressedbackupsize = $null
                                $compressedbackupsizemb = $null
                            }

                            if ([bool]($backup.psobject.Properties.Name -contains 'TotalSize')) {
                                $bytes = [PSCustomObject]@{ Bytes = $backup.TotalSize.Byte }
                                $sum = ($bytes | Measure-Object -Property Bytes -Sum).Sum
                                $backupsize = [dbasize]($sum / $backup.FullName.Count)
                                $backupsizemb = [Math]::Round($sum / $backup.FullName.Count / 1mb, 2)
                            } else {
                                $backupsize = $null
                                $backupsizemb = $null
                            }

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
                                BackupSizeMB           = $backupsizemb
                                CompressedBackupSizeMB = $compressedbackupsizemb
                                BackupFile             = $backup.FullName -Join ','
                                RestoredFile           = $((Split-Path $backup.FileList.PhysicalName -Leaf) | Sort-Object -Unique) -Join ','
                                RestoredFileFull       = ($backup.Filelist.PhysicalName -Join ',')
                                RestoreDirectory       = $RestoreDirectory
                                BackupSize             = $backupsize
                                CompressedBackupSize   = $compressedbackupsize
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