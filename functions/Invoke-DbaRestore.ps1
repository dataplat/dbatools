Function Invoke-DbaRestore{
    <#
    .SYNOPSIS
        Restores the contents of a BackupHistory object
    .DESCRIPTION
        Assumes a BackupHistory object has passed through the *-DbaBackupInformation pipeline to have been suitably filtered, transformed and tested so as to be ready for restore

    .PARAMETER BackupHistory
        The BackupHistory object to be restored.
        Can be passed in on pipeline

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

    .PARAMETER BlockSize
    .PARAMETER BufferCount
    .PARAMETER Continue
        Indicates that the restore is continuing a restore, so target database must be in Recovering or Standby states
    
    .PARAMETER AzureCredential
        AzureCredential required to connect to blob storage holding the backups

    .PARAMETER WithReplace    
        Indicated that if the database already exists it should be replaced

    .EXAMPLE
        $BackupHistory | Invoke-DbaRestore -SqlInstance MyInstance

        Will restore all the backups in the BackupHistory object according to the transformations it contains

    .EXAMPLE
        $BackupHistory | Invoke-DbaRestore -SqlInstance MyInstance -OutputScriptOnly
        $BackupHistory | Invoke-DbaRestore -SqlInstance MyInstance

        First generates just the T-SQL restore scripts so they can be sanity checked, and then if they are good perform the full restore. By  reusing the BackupHistory object there is no need to rescan all the backup files again 
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $BackupHistory,
        [Alias("ServerInstance", "SqlServer")]
        $SqlInstance,
        $SqlCredential,
        $OutputScriptOnly,
        $VerifyOnly,
        $RestoreTime=(Get-Date).AddDays(2),
        $StandbyDirectory,
        $NoRecovery,
        $MaxTransferSize,
        $BlockSize,
        $BufferCount,
        $Continue,
        $AzureCredential,
        $WithReplace,
        $EnableException
    )
    begin{
        try {
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        }
        catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            return
        }
        $ScriptOnly  = $false
        $InternalHistory = @()
    }
    Process{
        ForEach ($bh in $BackupHistory){
            $InternalHistory += $bh
        }
    }
    end{
        $Databases  = $InternalHistory.Database | select-Object -unique
        ForEach ($Database in $Databases){
            If ($Database -in $Server.databases.name) {
                if (($ScriptOnly -eq $true) -or ($verifyonly -ne $true)) {
                    if ($Pscmdlet.ShouldProcess("Killing processes in $Database on $SqlInstance as it exists and WithReplace specified  `n", "Cannot proceed if processes exist, ", "Database Exists and WithReplace specified, need to kill processes to restore")) {
                        try {
                            Write-Message -Level Verbose -Message "Set $Database single_user to kill processes"
                            Stop-DbaProcess -SqlInstance $Server -Database $Database -WarningAction Silentlycontinue
                            $null = $server.Query("Alter database $Database set offline with rollback immediate; alter database $Database set restricted_user; Alter database $Database set online with rollback immediate",'master')
                            $server.ConnectionContext.Connect()
                        }
                        catch {
                            Write-Message -Level Verbose -Message "No processes to kill in $Database"
                        }
                    }
                }
                else {
                    Stop-Function -Message "$Database exists and WithReplace not specified, stopping" -EnableException $EnableException 
                    return
                }
            }
            Write-Message -Message "WithReplace  = $Withreplace" -Level Verbose
            $backups = $InternalHistory | Where-Object {$_.Database -eq $Database} | Sort-Object -Property Type, FirstLsn
            ForEach ($backup in $backups){
                $Restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
                if (($backup -ne $backups[-1] -and $StandbyDirectory -eq '') -or $true -eq $NoRecovery){
                    $Restore.NoRecovery = $True
                }elseif ($backup -eq $backups[-1] -and '' -ne $StandbyDirectory) {
                    
                    $Restore.StandbyFile = $StandByDirectory + "\" + $Database + (get-date -Format yyyMMddHHmmss) + ".bak"
                    Write-Message -Level Verbose -Message "Setting standby on last file $($Restore.StandbyFile)"
                }
                else {
                    $Restore.NoRecovery = $False
                }
                if ($restoretime -gt (Get-Date)) {
                    $Restore.ToPointInTime = $null
                }
                else {
                    $Restore.ToPointInTime = $RestoreTime
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
                if ($true -ne $Continue){
                    ForEach ($file in $backup.FileList){
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
                Write-Message -Level Verbose -Message "restore action = $Action"
                $Restore.Action = $Action
                ForEach ($File in $backup.fullname){
                    Write-Message -Message "Adding device $file" -Level verbose
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
                If ($Pscmdlet.ShouldProcess("$Database on $SqlInstance `n `n", $ConfirmMessage)) {
                    try {
                        $RestoreComplete = $true
                        if ($ScriptOnly) {
                            $script = $Restore.Script($server)
                        }
                        elseif ($VerifyOnly) {
                            Write-Progress -id 2 -activity "Verifying $Database backup file on $servername" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                            $Verify = $Restore.sqlverify($server)
                            Write-Progress -id 2 -activity "Verifying $Database backup file on $servername" -status "Complete" -Completed
    
                            if ($verify -eq $true) {
                                return "Verify successful"
                            }
                            else {
                                return "Verify failed"
                            }
                        }
                        else {
                            Write-Progress -id 2 -activity "Restoring $Database to $ServerName" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                            $script = $Restore.Script($Server)
                            $Restore.sqlrestore($Server)
                            Write-Progress -id 2 -activity "Restoring $Database to $ServerName" -status "Complete" -Completed
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

                        if ($ScriptOnly -eq $false) {
                            [PSCustomObject]@{
                                SqlInstance            = $backup.SqlInstance
                                DatabaseName           = $backup.Database
                                DatabaseOwner          = $server.ConnectionContext.TrueLogin
                                NoRecovery             = $Restore.NoRecovery
                                WithReplace            = $WithReplace
                                RestoreComplete        = $RestoreComplete
                                BackupFilesCount       = $backup.FullName.Count
                                RestoredFilesCount     = $backup.Filelist.PhysicalName.count
                                BackupSizeMB           = if ([bool]($backup.psobject.Properties.Name -contains 'BackupSizeMB')) { ($RestoreFiles | Measure-Object -Property BackupSizeMB -Sum).Sum } else { $null }
                                CompressedBackupSizeMB = if ([bool]($backup.psobject.Properties.Name -contains 'CompressedBackupSizeMb')) { ($RestoreFiles | Measure-Object -Property CompressedBackupSizeMB -Sum).Sum } else { $null }
                                BackupFile             = $backup.FullName -Join ','
                                RestoredFile           = $((Split-Path $backup.FileList.PhysicalName -Leaf) | Sort-Object -Unique) -Join ','
                                RestoredFileFull       = $backup.Filelist.PhysicalName -Join ','
                                RestoreDirectory       = ((Split-Path $backup.FileList.PhysicalName) | Sort-Object -Unique) -Join ','
                                BackupSize             = if ([bool]($backup.psobject.Properties.Name -contains 'BackupSize')) { ($RestoreFiles | Measure-Object -Property BackupSize -Sum).Sum } else { $null }
                                CompressedBackupSize   = if ([bool]($backup.psobject.Properties.Name -contains 'CompressedBackupSize')) { ($RestoreFiles | Measure-Object -Property CompressedBackupSize -Sum).Sum } else { $null }
                                Script                 = $script
                                BackupFileRaw          = $RestoreFiles
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
            }
            if ($server.ConnectionContext.exists) {
                $server.ConnectionContext.Disconnect()
            }
            }
        }
    }
