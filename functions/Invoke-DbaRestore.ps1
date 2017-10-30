Function Invoke-DbaRestore{
    <#
    .SYNOPSIS
        Transforms the data in a dbatools backuphistory object for a restore
    
    .DESCRIPTION
       Performs various mapping on Backup History, ready restoring
       Options include changing restore paths, backup paths, database name and many others
    
    .PARAMETER BackupHistory

    .PARAMETER ReplaceDatabasName
        If a single value is provided, this will be replaced do all occurences a database name
        If a Hashtable is passed in, each database name mention will be replaced as specified. If a database's name does not apper it will not be replace
        DatabaseName will also be replaced where it  occurs in the file paths of data and log files.
        Please note, that this won't change the Logical Names of datafiles, that has to be done with a seperate Alter DB call
    
    .PARAMETER DatabaseNamePrefix
        This string will be prefixed to all restored database's name 
        
    .PARAMETER DataFileDirectory
        This will move ALL restored files to this location during the restore

    .PARAMETER LogFileDirectory
        This will move all log files to this location. 
    
    .PARAMETER FileNamePrefix
        This string will  be prefixed to all restored files (Data and Log)

    .PARAMETER RebaseBackupFolder
        Use this to rebase where your backups are stored. 

    .EXAMPLE
        $History | Format-DbaBackupInformation -ReplaceDatabaseName NewDb

    .EXAMPLE
        $History | Format-DbaBackupInformation -ReplaceDatabaseName @{'OldB'='NewDb';'ProdHr'='DevPr'}   
    
    .EXAMPLE
        $History | Format-DbaBackupInformation -DataFileDirectory 'D:\DataFiles\' -LogFileDirectory 'E:\LogFiles\
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]$BackupHistory,
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$OutputScriptOnly,
        [switch]$VerifyOnly,
        [DateTime]$RestoreTime,
        [switch]$NoRecovery,
        [int]$MaxTransferSize,
        [int]$BlockSize,
        [int]$BufferCount,
        [string]$StandbyDirectory,
        [switch]$Continue,
        [string]$AzureCredential,
        [switch]$WithReplace,
        [switch]$EnableException
    )
    begin{
        try {
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        }
        catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            return
        }
    }
    Process{}
    end{
        $Databases  = $backupHistory.Database | select-Object -unique
        ForEach ($Database in $Databases){
            $backups = $backupHistory | Where-Object {$_.Database -eq $Database} | Sort-Object -Property LastLsn
            ForEach ($backup in $backups){
                $Restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
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
                ForEach ($file in $backup.FileList){
                    $MoveFile = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile
                    $MoveFile.LogicalFileName = $File.LogicalName
                    $MoveFile.PhysicalFileName = $File.PhysicalName
                    $null = $Restore.RelocateFiles.Add($MoveFile)
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
                $ConfirmMessage = "`n Restore Database $DbName on $SqlInstance `n from files: $RestoreFileNames `n with these file moves: `n $LogicalFileMovesString `n $ConfirmPointInTime `n"
                If ($Pscmdlet.ShouldProcess("$DBName on $SqlInstance `n `n", $ConfirmMessage)) {
                    try {
                        $RestoreComplete = $true
                        if ($ScriptOnly) {
                            $script = $Restore.Script($server)
                        }
                        elseif ($VerifyOnly) {
                            Write-Progress -id 2 -activity "Verifying $dbname backup file on $servername" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                            $Verify = $Restore.sqlverify($server)
                            Write-Progress -id 2 -activity "Verifying $dbname backup file on $servername" -status "Complete" -Completed
    
                            if ($verify -eq $true) {
                                return "Verify successful"
                            }
                            else {
                                return "Verify failed"
                            }
                        }
                        else {
                            Write-Progress -id 2 -activity "Restoring $DbName to $ServerName" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                            $script = $Restore.Script($Server)
                            $Restore.sqlrestore($Server)
                            Write-Progress -id 2 -activity "Restoring $DbName to $ServerName" -status "Complete" -Completed
                        }
                    }
                    catch {
                        Write-Message -Level Verbose -Message "Failed, Closing Server connection"
                        $RestoreComplete = $False
                        $ExitError = $_.Exception.InnerException
                        Stop-Function -Message "Failed to restore db $DbName, stopping" -ErrorRecord $_
                        return
                    }
                    finally {

                        if ($ScriptOnly -eq $false) {
                            [PSCustomObject]@{
                                SqlInstance            = $SqlInstance
                                DatabaseName           = $DatabaseName
                                DatabaseOwner          = $server.ConnectionContext.TrueLogin
                                NoRecovery             = $Restore.NoRecovery
                                WithReplace            = $ReplaceDatabase
                                RestoreComplete        = $RestoreComplete
                                BackupFilesCount       = $RestoreFiles.Count
                                RestoredFilesCount     = $RestoreFiles[0].Filelist.PhysicalName.count
                                BackupSizeMB           = if ([bool]($RestoreFiles[0].psobject.Properties.Name -contains 'BackupSizeMB')) { ($RestoreFiles | Measure-Object -Property BackupSizeMB -Sum).Sum } else { $null }
                                CompressedBackupSizeMB = if ([bool]($RestoreFiles[0].psobject.Properties.Name -contains 'CompressedBackupSizeMb')) { ($RestoreFiles | Measure-Object -Property CompressedBackupSizeMB -Sum).Sum } else { $null }
                                BackupFile             = $RestoreFiles.BackupPath -Join ','
                                RestoredFile           = $RestoredFile
                                RestoredFileFull       = $RestoredFileFull
                                RestoreDirectory       = $RestoreDirectory
                                BackupSize             = if ([bool]($RestoreFiles[0].psobject.Properties.Name -contains 'BackupSize')) { ($RestoreFiles | Measure-Object -Property BackupSize -Sum).Sum } else { $null }
                                CompressedBackupSize   = if ([bool]($RestoreFiles[0].psobject.Properties.Name -contains 'CompressedBackupSize')) { ($RestoreFiles | Measure-Object -Property CompressedBackupSize -Sum).Sum } else { $null }
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
