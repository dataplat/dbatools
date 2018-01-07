function Invoke-DbaAdvancedRestore {
    <#
    .SYNOPSIS
        Allows the restore of modified BackupHistory Objects
        For 90% of users Restore-DbaDatabase should be your point of access to this function. The other 10% use it at their own risk

    .DESCRIPTION
        This is the final piece in the Restore-DbaDatabase Stack. Uusally a BackupHistory object will arrive here from Restore-DbaDatabse via the following pipeline:
        Get-DbaBackupInformation  | Select-DbaBackupInformation | Format-DbaBackupInformation | Test-DbaBackupInformation | Invoke-DbaAdvancedRestore

        We have exposed these functions publically to allow advanced users to perform operations that we don't support, or won't add as they would make things too complex for the majority of our users

        For example if you wanted to do some very complex redirection during a migration, then doing the rewrite of destinations may be better done with your own custom scripts rather than via Format-DbaBackupInformation

        We would recommend ALWAYS pushing your input through Test-DbaBackupInformation just to make sure that it makes sense to us.

    .PARAMETER BackupHistory
        The BackupHistory object to be restored.
        Can be passed in on the pipeline

    .PARAMETER SqlInstance
        The SqlInstance to which the backups should be restored

    .PARAMETER SqlCredential
        SqlCredential to be used to connect to the target SqlInstance

    .PARAMETER OutputScriptOnly
        If set, the restore will not be performed, but the T-SQL scripts to perform it will be returned

    .PARAMETER VerifyOnly
        If set, performs a Verify of the backups rather than a full restore

    .PARAMETER RestoreTime
        Point in Time to which the database should be restored.

        This should be the same value or earlier, as used in the previous pipeline stages

    .PARAMETER StandbyDirectory
        A folder path where a standby file should be created to put the recoverd databases in a standby mode

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

    .PARAMETER AzureCredential
        AzureCredential required to connect to blob storage holding the backups

    .PARAMETER WithReplace
        Indicated that if the database already exists it should be replaced

    .PARAMETER KeepCDC
        Indicates whether CDC information should be restored as part of the database

    .PARAMETER PageRestore
        The output from Get-DbaSuspect page containing the suspect pages to be restored.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.

    .PARAMETER EnableException
        Replaces user friendly yellow warnings with bloody red exceptions of doom!
        Use this if you want the function to throw terminating errors you want to catch.

    .EXAMPLE
        $BackupHistory | Invoke-DbaAdvancedRestore -SqlInstance MyInstance

        Will restore all the backups in the BackupHistory object according to the transformations it contains

    .EXAMPLE
        $BackupHistory | Invoke-DbaAdvancedRestore -SqlInstance MyInstance -OutputScriptOnly
        $BackupHistory | Invoke-DbaAdvancedRestore -SqlInstance MyInstance

        First generates just the T-SQL restore scripts so they can be sanity checked, and then if they are good perform the full restore. By  reusing the BackupHistory object there is no need to rescan all the backup files again
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Object[]]$BackupHistory,
        [Alias("ServerInstance", "SqlServer")]
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
        [PSCredential]$AzureCredential,
        [switch]$WithReplace,
        [switch]$KeepCDC,
        [object[]]$PageRestore,
        [switch]$EnableException
    )
    begin {
        try {
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        }
        catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            return
        }
        if ($KeepCDC -and ($NoRecovery -or ('' -ne $StandbyDirectory))) {
            Stop-Function -Category InvalidArgument -Message "KeepCDC cannot be specified with Norecovery or Standby as it needs recovery to work"
            return
        }

        If ($null -ne $PageRestore) {
            Write-Message -Message "Doing Page Recovery" -Level Verbose
            $tmpPages = @()
            ForEach ($Page in $PageRestore) {
                $tmppages += "$($Page.FileId):$($Page.PageID)"
            }
            $NoRecovery = $True
            $Pages = $tmpPages -join ','
        }
        #$OutputScriptOnly  = $false
        $InternalHistory = @()
    }
    process {
        ForEach ($bh in $BackupHistory) {
            $InternalHistory += $bh
        }
    }
    end {
        if (Test-FunctionInterrupt) { return }
        $Databases = $InternalHistory.Database | Select-Object -Unique
        foreach ($Database in $Databases) {
            if ($Database -in $Server.Databases.Name) {
                if (-not $OutputScriptOnly -and -not $VerifyOnly) {
                    if ($Pscmdlet.ShouldProcess("Killing processes in $Database on $SqlInstance as it exists and WithReplace specified  `n", "Cannot proceed if processes exist, ", "Database Exists and WithReplace specified, need to kill processes to restore")) {
                        try {
                            Write-Message -Level Verbose -Message "Killing processes on $Database"
                            $null = Stop-DbaProcess -SqlInstance $Server -Database $Database -WarningAction Silentlycontinue
                            $null = $server.Query("Alter database $Database set offline with rollback immediate; alter database $Database set restricted_user; Alter database $Database set online with rollback immediate", 'master')
                            $server.ConnectionContext.Connect()
                        }
                        catch {
                            Write-Message -Level Verbose -Message "No processes to kill in $Database"
                        }
                    }
                }
                elseif (-not $WithReplace -and (-not $VerifyOnly)) {
                    Stop-Function -Message "$Database exists and WithReplace not specified, stopping" -EnableException $EnableException
                    return
                }
            }
            Write-Message -Message "WithReplace  = $WithReplace" -Level Debug
            $backups = $InternalHistory | Where-Object {$_.Database -eq $Database} | Sort-Object -Property Type, FirstLsn
            $BackupCnt = 1
            foreach ($backup in $backups) {
                $Restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
                if (($backup -ne $backups[-1]) -or $true -eq $NoRecovery) {
                    $Restore.NoRecovery = $True
                }
                elseif ($backup -eq $backups[-1] -and '' -ne $StandbyDirectory) {
                    $Restore.StandbyFile = $StandByDirectory + "\" + $Database + (get-date -Format yyyMMddHHmmss) + ".bak"
                    Write-Message -Level Verbose -Message "Setting standby on last file $($Restore.StandbyFile)"
                }
                else {
                    $Restore.NoRecovery = $False
                }
                if ($restoretime -gt (Get-Date) -or $Restore.RestoreTime -gt (Get-Date)) {
                    $Restore.ToPointInTime = $null
                }
                else {
                    if ($RestoreTime -ne $Restore.RestoreTime) {
                        $Restore.ToPointInTime = $backup.RestoreTime
                    }
                    else {
                        $Restore.ToPointInTime = $RestoreTime
                    }
                }

                $Restore.Database = $database
                $Restore.ReplaceDatabase = $WithReplace
                if ($MaxTransferSize) {
                    $Restore.MaxTransferSize = $MaxTransferSize
                }
                if ($BufferCount) {
                    $Restore.BufferCount = $BufferCount
                }
                if ($BlockSize) {
                    $Restore.Blocksize = $BlockSize
                }
                if ($true -ne $Continue -and ($null -eq $Pages)) {
                    foreach ($file in $backup.FileList) {
                        $MoveFile = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile
                        $MoveFile.LogicalFileName = $File.LogicalName
                        $MoveFile.PhysicalFileName = $File.PhysicalName
                        $null = $Restore.RelocateFiles.Add($MoveFile)
                    }
                }
                $Action = switch ($backup.Type) {
                    '1' {'Database'}
                    '2' {'Log'}
                    '5' {'Database'}
                    'Transaction Log' {'Log'}
                    Default {'Database'}
                }

                Write-Message -Level Debug -Message "restore action = $Action"
                $Restore.Action = $Action
                foreach ($File in $backup.FullName) {
                    Write-Message -Message "Adding device $file" -Level Debug
                    $Device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem
                    $Device.Name = $file
                    if ($file -like "http*") {
                        $Device.devicetype = "URL"
                        $Restore.CredentialName = $AzureCredential
                    }
                    else {
                        $Device.devicetype = "File"
                    }
                    $Restore.FileNumber = $backup.Position
                    $Restore.Devices.Add($device)
                }
                Write-Message -Level Verbose -Message "Performing restore action"
                $ConfirmMessage = "`n Restore Database $Database on $SqlInstance `n from files: $RestoreFileNames `n with these file moves: `n $LogicalFileMovesString `n $ConfirmPointInTime `n"
                if ($Pscmdlet.ShouldProcess("$Database on $SqlInstance `n `n", $ConfirmMessage)) {
                    try {
                        $RestoreComplete = $true
                        if ($KeepCDC -and $Restore.NoRecovery -eq $false) {
                            $script = $Restore.Script($server)
                            if ($script -like '*WITH*') {
                                $script = $script.TrimEnd() + ' , KEEP_CDC'
                            }
                            else {
                                $script = $script.TrimEnd() + ' WITH KEEP_CDC'
                            }
                            if ($true -ne $OutputScriptOnly) {
                                Write-Progress -id 2 -activity "Restoring $Database to $sqlinstance `n Backup $BackupCnt of $($Backups.count)" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                                $null = $server.ConnectionContext.ExecuteNonQuery($script)
                                Write-Progress -id 2 -activity "Restoring $Database to $sqlinstance `n Backup $BackupCnt of $($Backups.count)" -status "Complete" -Completed
                            }
                        }
                        elseif ($null -ne $Pages -and $Action -eq 'Database') {
                            $script = $Restore.Script($server)
                            $script = $script -replace "] FROM", "] PAGE='$pages' FROM"
                            if ($true -ne $OutputScriptOnly) {
                                Write-Progress -id 2 -activity "Restoring $Database to $sqlinstance `n Backup $BackupCnt of $($Backups.count)" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                                $null = $server.ConnectionContext.ExecuteNonQuery($script)
                                Write-Progress -id 2 -activity "Restoring $Database to $sqlinstance `n Backup $BackupCnt of $($Backups.count)" -status "Complete" -Completed
                            }
                        }
                        elseif ($OutputScriptOnly) {
                            $script = $Restore.Script($server)
                        }
                        elseif ($VerifyOnly) {
                            Write-Message -Message "VerifyOnly restore" -Level Verbose
                            Write-Progress -id 2 -activity "Verifying $Database backup file on $sqlinstance `n Backup $BackupCnt of $($Backups.count)" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                            $Verify = $Restore.sqlverify($server)
                            Write-Progress -id 2 -activity "Verifying $Database backup file on $sqlinstance `n Backup $BackupCnt of $($Backups.count)" -status "Complete" -Completed
                            if ($verify -eq $true) {
                                Write-Message -Message "VerifyOnly restore Succeeded" -Level Verbose
                                return "Verify successful"
                            }
                            else {
                                Write-Message -Message "VerifyOnly restore Failed" -Level Verbose
                                return "Verify failed"
                            }
                        }
                        else {
                            Write-Progress -id 2 -activity "Restoring $Database to $sqlinstance `n Backup $BackupCnt of $($Backups.count)" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                            $script = $Restore.Script($Server)
                            $Restore.sqlrestore($Server)
                            Write-Progress -id 2 -activity "Restoring $Database to $sqlinstance `n Backup $BackupCnt of $($Backups.count)" -status "Complete" -Completed
                        }
                    }
                    catch {
                        Write-Message -Level Verbose -Message "Failed, Closing Server connection"
                        $RestoreComplete = $False
                        $ExitError = $_.Exception.InnerException
                        Stop-Function -Message "Failed to restore db $Database, stopping" -ErrorRecord $_
                        return
                    }
                    finally {

                        if ($OutputScriptOnly -eq $false) {
                            [PSCustomObject]@{
                                SqlInstance            = $SqlInstance
                                DatabaseName           = $backup.Database
                                DatabaseOwner          = $server.ConnectionContext.TrueLogin
                                NoRecovery             = $Restore.NoRecovery
                                WithReplace            = $WithReplace
                                RestoreComplete        = $RestoreComplete
                                BackupFilesCount       = $backup.FullName.Count
                                RestoredFilesCount     = $backup.Filelist.PhysicalName.count
                                BackupSizeMB           = if ([bool]($backup.psobject.Properties.Name -contains 'TotalSize')) { [Math]::Round(($backup | Measure-Object -Property TotalSize -Sum).Sum / 1mb, 2) } else { $null }
                                CompressedBackupSizeMB = if ([bool]($backup.psobject.Properties.Name -contains 'CompressedBackupSize')) { [Math]::Round(($backup | Measure-Object -Property CompressedBackupSize -Sum).Sum / 1mb, 2) } else { $null }
                                BackupFile             = $backup.FullName -Join ','
                                RestoredFile           = $((Split-Path $backup.FileList.PhysicalName -Leaf) | Sort-Object -Unique) -Join ','
                                RestoredFileFull       = ($backup.Filelist.PhysicalName -Join ',')
                                RestoreDirectory       = ((Split-Path $backup.FileList.PhysicalName) | Sort-Object -Unique) -Join ','
                                BackupSize             = if ([bool]($backup.psobject.Properties.Name -contains 'TotalSize')) { ($backup | Measure-Object -Property TotalSize -Sum).Sum } else { $null }
                                CompressedBackupSize   = if ([bool]($backup.psobject.Properties.Name -contains 'CompressedBackupSize')) { ($backup | Measure-Object -Property CompressedBackupSize -Sum).Sum } else { $null }
                                Script                 = $script
                                BackupFileRaw          = ($backups.Fullname)
                                ExitError              = $ExitError
                            } | Select-DefaultView -ExcludeProperty BackupSize, CompressedBackupSize, ExitError, BackupFileRaw, RestoredFileFull
                        }
                        else {
                            $script
                        }
                        while ($Restore.Devices.count -gt 0) {
                            $device = $Restore.devices[0]
                            $null = $Restore.devices.remove($Device)
                        }
                        Write-Message -Level Verbose -Message "Succeeded, Closing Server connection"
                        $server.ConnectionContext.Disconnect()
                    }
                }
                Write-Progress -id 1 -Activity "Restoring" -Completed
                $BackupCnt++
            }
            if ($server.ConnectionContext.exists) {
                $server.ConnectionContext.Disconnect()
            }
        }
    }
}
