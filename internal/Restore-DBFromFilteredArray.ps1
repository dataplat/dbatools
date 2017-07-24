Function Restore-DBFromFilteredArray {
    <#
    .SYNOPSIS
    Internal function. Restores .bak file to SQL database. Creates db if it doesn't exist. $filestructure is
    a custom object that contains logical and physical file locations.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [object]$SqlInstance,
        [string]$DbName,
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]$Files,
        [String]$DestinationDataDirectory,
        [String]$DestinationLogDirectory,
        [String]$DestinationFilePrefix,
        [DateTime]$RestoreTime = (Get-Date).addyears(1),
        [switch]$NoRecovery,
        [switch]$ReplaceDatabase,
        [switch]$Scripts,
        [switch]$ScriptOnly,
        [switch]$VerifyOnly,
        [object]$filestructure,
        [PSCredential]$SqlCredential,
        [switch]$UseDestinationDefaultDirectories,
        [switch]$ReuseSourceFolderStructure,
        [switch]$Force,
        [string]$RestoredDatababaseNamePrefix,
        [switch]$TrustDbBackupHistory,
        [int]$MaxTransferSize,
        [int]$BlockSize,
        [int]$BufferCount,
        [switch]$Silent,
        [string]$StandbyDirectory,
        [switch]$Continue,
        [string]$AzureCredential,
        [switch]$ReplaceDbNameInFile,
        [string]$OldDatabaseName,
        [string]$DestinationFileSuffix
    )
    begin {
        $FunctionName = (Get-PSCallstack)[0].Command
        Write-Message -Level Verbose -Message "Starting"
        Write-Message -Level Verbose -Message "Parameters bound: $($PSBoundParameters.Keys -Join ", ")"


        $InternalFiles = @()
        if (($MaxTransferSize % 64kb) -ne 0 -or $MaxTransferSize -gt 4mb) {
            Write-Message -Level Warning -Message "MaxTransferSize value must be a multiple of 64kb and no greater than 4MB"
            break
        }
        if ($BlockSize) {
            if ($BlockSize -notin (0.5kb, 1kb, 2kb, 4kb, 8kb, 16kb, 32kb, 64kb)) {
                Write-Message -Level Warning -Message "Block size must be one of 0.5kb,1kb,2kb,4kb,8kb,16kb,32kb,64kb"
                break
            }
        }

    }
    process {

        foreach ($File in $Files) {
            $InternalFiles += $File
        }
    }
    end {
        try {
            $Server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        }
        catch {
            Write-Message -Level Warning -Message "Cannot connect to $SqlInstance"
            break
        }

        $ServerName = $Server.name
        $Server.ConnectionContext.StatementTimeout = 0
        $Restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
        $Restore.ReplaceDatabase = $ReplaceDatabase

        if ($UseDestinationDefaultDirectories) {
            $DestinationDataDirectory = Get-SqlDefaultPaths $Server data
            $DestinationLogDirectory = Get-SqlDefaultPaths $Server log
        }

        If ($DbName -in $Server.databases.name) {
            if (($ScriptOnly -eq $true) -or ($verifyonly -eq $true)) {
                Write-Message -Level Verbose -Message "No need to close db for this operation"
            }
            elseIf ($WithReplace -eq $true -and $VerifyOnly -eq $false) {
                if ($Pscmdlet.ShouldProcess("Killing processes in $dbname on $SqlInstance as it exists and WithReplace specified  `n", "Cannot proceed if processes exist, ", "Database Exists and WithReplace specified, need to kill processes to restore")) {
                    try {
                        Write-Message -Level Verbose -Message "Set $DbName single_user to kill processes"
                        Stop-DbaProcess -SqlInstance $Server -Databases $Dbname -WarningAction Silentlycontinue
                        if ($Continue -eq $false) {
                            $server.Query("Alter database $DbName set offline with rollback immediate; alter database $DbName set restricted_user; Alter database $DbName set online with rollback immediate",'master')
                        }
                        $server.ConnectionContext.Connect()
                    }
                    catch {
                        Write-Message -Level Verbose -Message "No processes to kill in $DbName"
                    }
                }
            }
            else {
                Stop-Function -Message "$Dbname exists and WithReplace not specified, stopping" -Silent $silent 
                return
            }
        }


        $MissingFiles = @()
        if ($TrustDbBackupHistory) {
            Write-Message -Level Verbose -Message "Trusted File checks"
            Foreach ($File in $InternalFiles) {
                if ($File.BackupPath -notlike "http*") {
                    Write-Message -Level Verbose -Message "Checking $($File.BackupPath) exists"
                    if ((Test-DbaSqlPath -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Path $File.BackupPath) -eq $false) {
                        Write-Message -Level VeryVerbose "$($File.backupPath) is missing"
                        $MissingFiles += $File.BackupPath
                    }
                }
            }
            if ($MissingFiles.Length -gt 0) {
                Write-Message -Level Warning -Message "Files $($MissingFiles -Join ',') are missing, cannot progress"
                return $false
            }
        }
        $RestorePoints = @()
        $if = $InternalFiles | Where-Object {$_.BackupTypeDescription -eq 'Database'} | Group-Object FirstLSN
        $RestorePoints += @([PSCustomObject]@{order = [Decimal]1; 'Files' = $if.group})
        $if = $InternalFiles | Where-Object {$_.BackupTypeDescription -eq 'Database Differential'}| Group-Object FirstLSN
        if ($null -ne $if) {
            $RestorePoints += @([PSCustomObject]@{order = [Decimal]2; 'Files' = $if.group})
        }


        foreach ($if in ($InternalFiles | Where-Object {$_.BackupTypeDescription -eq 'Transaction Log'} | Group-Object BackupSetGuid)) {
            #$RestorePoints  += [PSCustomObject]@{order=[Decimal]($if.Name); 'Files' = $if.group}
            $RestorePoints += [PSCustomObject]@{order = [Decimal](($if.Group.backupstartdate | Sort-Object -Unique).ticks); 'Files' = $if.group}
        }
        $SortedRestorePoints = $RestorePoints | Sort-Object -property order
        if ($ReuseSourceFolderStructure) {
            Write-Message -Level Verbose -Message "Checking for files folders for Reusing old structure"
            foreach ($File in ($RestorePoints.Files.filelist.PhysicalName | Sort-Object -Unique)) {
                Write-Message -Level VeryVerbose -Message "File = $file"
                if ((Test-DbaSqlPath -Path $File -SqlInstance:$SqlInstance -SqlCredential:$SqlCredential) -ne $true) {
                    Write-Message -Level VeryVerbose "File doesn't exist, check for parent folder"
                    if ((Test-DbaSqlPath -Path (Split-Path -Path $File -Parent) -SqlInstance:$SqlInstance -SqlCredential:$SqlCredential) -ne $true) {
                        Write-Message -Level debug -Message "$(Split-Path -Path $File -Parent) does not exist on $sqlinstance"
                        if ((New-DbaSqlDirectory -Path (Split-Path -Path $File -Parent) -SqlInstance:$SqlInstance -SqlCredential:$SqlCredential).Created -ne $true) {
                            Stop-Function -message "Destination folder $(Split-Path -Path $File -Parent) does not exist, and could not be created on $SqlInstance" -TargetObject $file -Category 'DeviceError'
                            return
                        } 
                        else {
                            Write-Message -Level Veryverbose -Message "Folder $(Split-Path -Path $File -Parent) created on $sqlinstance"
                        }   
                    }
                    else {
                        Write-Message -Level Veryverbose -Message "Folder $(Split-Path -Path $File -Parent) exists on $sqlinstance"
                    }

                }
                else {
                    Write-Message -Level Veryverbose -Message "Bombing out created on $sqlinstance"
                    #Stop-Function -message "Destination File $File  exists on $SqlInstance" -TargetObject $file -Category 'DeviceError' -silent:$false
                    throw "Destination File $File  exists on $SqlInstance"
                    return   
                }    
                Write-Message -Level Veryverbose -Message "past resuse tests"
            }
        }
        $RestoreCount = 0
        $RPCount = if ($SortedRestorePoints.count -gt 0) {$SortedRestorePoints.count}else {1}
        Write-Message -Level VeryVerbose -Message "RPcount = $rpcount"
        if ($continue) {
            Write-Message -Level VeryVerbose -Message "continuing in restore script = $ScriptOnly"
            $SortedRestorePoints = $SortedRestorePoints | Where-Object {$_.order -ne 1}
        }
        #$SortedRestorePoints
        #return
        #Not happy with this, but leaving in in case someone can convince me to make it available
        #$RestoreFileCount = Measure-Object ($SortedRestorePoints.Filelist | measure-Object -count) -maximum
        foreach ($RestorePoint in $SortedRestorePoints) {
            $RestoreCount++
            Write-Progress -id 1 -Activity "Restoring" -Status "Restoring File" -CurrentOperation "$RestoreCount of $RpCount for database $Dbname"
            $RestoreFiles = $RestorePoint.files
            $RestoreFileNames = $RestoreFiles.BackupPath -Join '`n ,'
            Write-Message -Level Verbose -Message "Restoring $Dbname backup starting at order $($RestorePoint.order) - LSN $($RestoreFiles[0].FirstLSN) in $($RestoreFiles[0].BackupPath)"
            $LogicalFileMoves = @()

            if ($Restore.RelocateFiles.count -gt 0) {
                $Restore.RelocateFiles.Clear()
            }
            if ($DestinationDataDirectory -ne '' -and $null -eq $FileStructure) {
                if ($DestinationDataDirectory.EndsWith('\')) {
                    $DestinationDataDirectory = $DestinationDataDirectory.TrimEnd('\')
                }
                if ($DestinationLogDirectory.EndsWith('\')) {
                    $DestinationLogDirectory = $DestinationLogDirectory.TrimEnd('\')
                }
                $FileID = 1
                foreach ($File in $RestoreFiles.Filelist) {
                    Write-Message -Level Verbose -Message "Moving $($File.PhysicalName)"
                    $MoveFile = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile
                    $MoveFile.LogicalFileName = $File.LogicalName
                    $filename, $extension = (Split-Path $file.PhysicalName -leaf).split('.')
                    if ($ReplaceDbNameInFile) {
                        $Filename = $filename -replace $OldDatabaseName, $dbname
                    }
                    if (Test-Bound "DestinationFilePrefix") {
                        $Filename = $DestinationFilePrefix + $FileName
                    }
                    if (Test-Bound "DestinationFileSuffix") {
                        $Filename = $FileName + $DestinationFileSuffix
                    }
                    #Not happy with this, but leaving in in case someone can convince me to make it available
                    if ($DestinationFileNumber) {
                        $FileName = $FileName + '_' + $FileId + '_of_' + $RestoreFileCountFileCount
                    }
                    if ($null -ne $extension) {
                        $filename = $filename + '.' + $extension
                    }
                    Write-Message -Level VeryVerbose -Message "past the checks"
                    if (($File.Type -eq 'L' -or $File.filetype -eq 'L') -and $DestinationLogDirectory -ne '') {
                        $MoveFile.PhysicalFileName = $DestinationLogDirectory + '\' + $FileName
                    }
                    else {
                        $MoveFile.PhysicalFileName = $DestinationDataDirectory + '\' + $FileName
                        Write-Message -Level Verbose -Message "Moving $($file.PhysicalName) to $($MoveFile.PhysicalFileName) "
                    }
                    $LogicalFileMoves += "Relocating $($MoveFile.LogicalFileName) to $($MoveFile.PhysicalFileName)"
                    $null = $Restore.RelocateFiles.Add($MoveFile)
                    $FileId ++
                }

            }
            elseif ($DestinationDataDirectory -eq '' -and $null -ne $FileStructure) {

                foreach ($key in $FileStructure.keys) {
                    $MoveFile = New-Object Microsoft.SqlServer.Management.Smo.RelocateFile
                    $MoveFile.LogicalFileName = $key
                    $MoveFile.PhysicalFileName = $filestructure[$key]

                    $null = $Restore.RelocateFiles.Add($MoveFile)
                    $LogicalFileMoves += "Relocating $($MoveFile.LogicalFileName) to $($MoveFile.PhysicalFileName)"
                }
            }
            elseif ($DestinationDataDirectory -ne '' -and $null -ne $FileStructure) {
                Write-Message -Level Warning -Message "Conflicting options only one of FileStructure or DestinationDataDirectory allowed"
                break
            }
            $LogicalFileMovesString = $LogicalFileMoves -Join ", `n"
            Write-Message -Level VeryVerbose -Message "$LogicalFileMovesString"

            if ($MaxTransferSize) {
                $Restore.MaxTransferSize = $MaxTransferSize
            }
            if ($BufferCount) {
                $Restore.BufferCount = $BufferCount
            }
            if ($BlockSize) {
                $Restore.Blocksize = $BlockSize
            }

            Write-Message -Level Verbose -Message "Beginning Restore of $Dbname"
            $percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
                Write-Progress -id 2 -activity "Restoring $dbname to $servername" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
            }
            $Restore.add_PercentComplete($percent)
            $Restore.PercentCompleteNotification = 1
            $Restore.add_Complete($complete)
            $Restore.ReplaceDatabase = $ReplaceDatabase
            if ($RestoreTime -gt (Get-Date)) {
                $Restore.ToPointInTime = $null
                Write-Message -Level Verbose -Message "restoring $DbName to latest point in time"

            }
            elseif ($RestoreFiles[0].RecoveryModel -ne 'Simple') {
                $Restore.ToPointInTime = $RestoreTime
                Write-Message -Level Verbose -Message "restoring to $RestoreTime"

            }
            else {
                Write-Message -Level Verbose -Message "Restoring a Simple mode db, no restoretime"
            }
            if ($DbName -ne '') {
                $Restore.Database = $DbName
            }
            else {
                $Restore.Database = $RestoreFiles[0].DatabaseName
            }
            $Action = switch ($RestoreFiles[0].BackupType) {
                '1' {'Database'}
                '2' {'Log'}
                '5' {'Database'}
                Default {'Unknown'}
            }
            Write-Message -Level Verbose -Message "restore action = $Action"
            $Restore.Action = $Action
            if ($RestorePoint -eq $SortedRestorePoints[-1]) {
                if ($NoRecovery -ne $true -and '' -eq $StandbyDirectory) {
                    #Do recovery on last file
                    Write-Message -Level Verbose -Message "Doing Recovery on last file"
                    $Restore.NoRecovery = $false
                }
                elseif ('' -ne $StandbyDirectory) {
                    Write-Message -Level Verbose -Message "Setting standby on last file"
                    $Restore.StandbyFile = $StandByDirectory + "\" + $Dbname + (get-date -Format yyyMMddHHmmss) + ".bak"
                }
                else {
                    Write-Message -Level Verbose -Message "Last File and NoRecovery specified"
                    $Restore.NoRecovery = $true
                }
            }
            else {
                Write-Message -Level Verbose -Message "More files to restore, NoRecovery set"
                $Restore.NoRecovery = $true
            }
            Foreach ($RestoreFile in $RestoreFiles) {
                Write-Message -Level Verbose -Message "Adding device"
                $Device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem
                $Device.Name = $RestoreFile.BackupPath
                if ($RestoreFile.BackupPath -like "http*") {
                    $Device.devicetype = "URL"
                    $Restore.CredentialName = $AzureCredential
                }
                else {
                    $Device.devicetype = "File"
                }
                $Restore.FileNumber = $RestoreFile.Position
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
                        Write-Progress -id 2 -activity "Restoring $DbName to ServerName" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                        $script = $Restore.Script($Server)
                        $Restore.sqlrestore($Server)
                        Write-Progress -id 2 -activity "Restoring $DbName to $ServerName" -status "Complete" -Completed
                    }
                }
                catch {
                    Write-Message -Level Verbose -Message "Failed, Closing Server connection"
                    $RestoreComplete = $False
                    $ExitError = $_.Exception.InnerException
                    Stop-Function -Message  "Failed to restore db $DbName, stopping" -InnerErrorRecord $ExitError 
                    #Exit as once one restore has failed there's no point continuing
                    break
                }
                finally {
                    if ($ReuseSourceFolderStructure) {
                        $RestoreDirectory = ((Split-Path $RestoreFiles[0].FileList.PhysicalName) | Sort-Object -Unique) -Join ','
                        $RestoredFile = ((Split-Path $RestoreFiles[0].FileList.PhysicalName -Leaf) | Sort-Object -Unique) -Join ','
                        $RestoredFileFull = $RestoreFiles[0].Filelist.PhysicalName -Join ','
                    }
                    else {
                        $RestoreDirectory = ((Split-Path $Restore.RelocateFiles.PhysicalFileName) | Sort-Object -Unique) -Join ','
                        $RestoredFile = (Split-Path $Restore.RelocateFiles.PhysicalFileName -Leaf) -Join ','
                        $RestoredFileFull = $Restore.RelocateFiles.PhysicalFileName -Join ','
                    }
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
                            BackupSizeMB           = if ([bool]($RestoreFiles[0].psobject.Properties.Name -match 'BackupSizeMB')) { ($RestoreFiles | Measure-Object -Property BackupSizeMB -Sum).Sum } else { $null }
                            CompressedBackupSizeMB = if ([bool]($RestoreFiles[0].psobject.Properties.Name -match 'CompressedBackupSizeMb')) { ($RestoreFiles | Measure-Object -Property CompressedBackupSizeMB -Sum).Sum } else { $null }
                            BackupFile             = $RestoreFiles.BackupPath -Join ','
                            RestoredFile           = $RestoredFile
                            RestoredFileFull       = $RestoredFileFull
                            RestoreDirectory       = $RestoreDirectory
                            BackupSize             = if ([bool]($RestoreFiles[0].psobject.Properties.Name -match 'BackupSize')) { ($RestoreFiles | Measure-Object -Property BackupSize -Sum).Sum } else { $null }
                            CompressedBackupSize   = if ([bool]($RestoreFiles[0].psobject.Properties.Name -match 'CompressedBackupSize')) { ($RestoreFiles | Measure-Object -Property CompressedBackupSize -Sum).Sum } else { $null }
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
