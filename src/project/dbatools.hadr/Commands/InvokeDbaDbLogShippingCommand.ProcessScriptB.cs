#nullable enable

namespace Dataplat.Dbatools.Commands;

public sealed partial class InvokeDbaDbLogShippingCommand
{
    // PS: the process block VERBATIM, second third; see ProcessScriptA for the frame
    // and substitution inventory.
    private const string ProcessScriptB = """
                # Check the parameters for initialization of the secondary database
                if (-not $NoInitialization -and ($GenerateFullBackup -or $UseExistingFullBackup -or $UseBackupFolder)) {
                    # Check if the restore data and log folder are set
                    if ($setupResult -ne 'Failed') {
                        if ($RestoreDataFolder) {
                            $DatabaseRestoreDataFolder = $RestoreDataFolder
                        } else {
                            Write-Message -Message "Restore data folder is not set. Using server default." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                            $DatabaseRestoreDataFolder = $DestinationServer.DefaultFile
                        }
                        Write-Message -Message "Restore data folder is set to $DatabaseRestoreDataFolder" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"

                        if ($RestoreLogFolder) {
                            $DatabaseRestoreLogFolder = $RestoreLogFolder
                        } else {
                            Write-Message -Message "Restore log folder is not set. Using server default." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                            $DatabaseRestoreLogFolder = $DestinationServer.DefaultLog
                        }
                        Write-Message -Message "Restore log folder is set to $DatabaseRestoreLogFolder" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"

                        # Check if the restore data folder exists (skip for Azure SQL as it manages storage)
                        if (-not $DestinationServer.IsAzure) {
                            Write-Message -Message "Testing database restore data path $DatabaseRestoreDataFolder" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                            if ((Test-DbaPath  -Path $DatabaseRestoreDataFolder -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential) -ne $true) {
                                if ($PSCmdlet.ShouldProcess($DestinationServerName, "Creating database restore data folder $DatabaseRestoreDataFolder on $DestinationServerName")) {
                                    # Try creating the data folder
                                    try {
                                        Invoke-Command2 -Credential $DestinationCredential -ScriptBlock {
                                            Write-Message -Message "Creating data folder $DatabaseRestoreDataFolder" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                                            $null = New-Item -Path $DatabaseRestoreDataFolder -ItemType Directory -Force:$Force
                                        }
                                    } catch {
                                        $setupResult = "Failed"
                                        $comment = "Something went wrong creating the restore data directory"
                                        Stop-Function -Message "Something went wrong creating the restore data directory" -ErrorRecord $_ -Target $SourceSqlInstance -Continue -FunctionName Invoke-DbaDbLogShipping
                                    }
                                }
                            }
                        }

                        # Check if the restore log folder exists (skip for Azure SQL as it manages storage)
                        if (-not $DestinationServer.IsAzure) {
                            Write-Message -Message "Testing database restore log path $DatabaseRestoreLogFolder" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                            if ((Test-DbaPath  -Path $DatabaseRestoreLogFolder -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential) -ne $true) {
                                if ($PSCmdlet.ShouldProcess($DestinationServerName, "Creating database restore log folder $DatabaseRestoreLogFolder on $DestinationServerName")) {
                                    # Try creating the log folder
                                    try {
                                        Write-Message -Message "Restore log folder $DatabaseRestoreLogFolder not found. Trying to create it.." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"

                                        Invoke-Command2 -Credential $DestinationCredential -ScriptBlock {
                                            Write-Message -Message "Restore log folder $DatabaseRestoreLogFolder not found. Trying to create it.." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                                            $null = New-Item -Path $DatabaseRestoreLogFolder -ItemType Directory -Force:$Force
                                        }
                                    } catch {
                                        $setupResult = "Failed"
                                        $comment = "Something went wrong creating the restore log directory"
                                        Stop-Function -Message "Something went wrong creating the restore log directory" -ErrorRecord $_ -Target $SourceSqlInstance -Continue -FunctionName Invoke-DbaDbLogShipping
                                    }
                                }
                            }
                        }
                    }

                    # Check if the full backup path can be reached
                    if ($setupResult -ne 'Failed') {
                        if ($FullBackupPath) {
                            # Skip path validation for Azure blob URLs
                            if (-not $UseAzure) {
                                Write-Message -Message "Testing full backup path $FullBackupPath" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                                if ((Test-DbaPath -Path $FullBackupPath -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential) -ne $true) {
                                    $setupResult = "Failed"
                                    $comment = "The path to the full backup could not be reached"
                                    Stop-Function -Message ("The path to the full backup could not be reached. Check the path and/or the crdential") -Target $destInstance -Continue -FunctionName Invoke-DbaDbLogShipping
                                }
                            }

                            $BackupPath = $FullBackupPath
                        } elseif ($UseBackupFolder.Length -ge 1) {
                            # Skip path validation for Azure blob URLs
                            if (-not $UseAzure) {
                                Write-Message -Message "Testing backup folder $UseBackupFolder" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                                if ((Test-DbaPath -Path $UseBackupFolder -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential) -ne $true) {
                                    $setupResult = "Failed"
                                    $comment = "The path to the backup folder could not be reached"
                                    Stop-Function -Message ("The path to the backup folder could not be reached. Check the path and/or the crdential") -Target $destInstance -Continue -FunctionName Invoke-DbaDbLogShipping
                                }
                            }

                            $BackupPath = $UseBackupFolder
                        } elseif ($UseExistingFullBackup) {
                            Write-Message -Message "No path to the full backup is set. Trying to retrieve the last full backup for $db from $SourceSqlInstance" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"

                            # Get the last full backup
                            $LastBackup = Get-DbaDbBackupHistory -SqlInstance $SourceSqlInstance -Database $($db.Name) -LastFull -SqlCredential $SourceSqlCredential

                            # Check if there was a last backup
                            if ($null -ne $LastBackup) {
                                # Skip path validation for Azure blob URLs
                                if (-not $UseAzure) {
                                    # Test the path to the backup
                                    Write-Message -Message "Testing last backup path $(($LastBackup[-1]).Path[-1])" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                                    if ((Test-DbaPath -Path ($LastBackup[-1]).Path[-1] -SqlInstance $SourceSqlInstance -SqlCredential $SourceSqlCredential) -ne $true) {
                                        $setupResult = "Failed"
                                        $comment = "The full backup could not be found"
                                        Stop-Function -Message "The full backup could not be found on $($LastBackup.Path). Check path and/or credentials" -Target $destInstance -Continue -FunctionName Invoke-DbaDbLogShipping
                                    }
                                    # Check if the source for the last full backup is remote and the backup is on a shared location
                                    elseif (($LastBackup.Computername -ne $SourceServerName) -and (($LastBackup[-1]).Path[-1].StartsWith('\\') -eq $false)) {
                                        $setupResult = "Failed"
                                        $comment = "The last full backup is not located on shared location"
                                        Stop-Function -Message "The last full backup is not located on shared location. `n$($_.Exception.Message)" -Target $destInstance -Continue -FunctionName Invoke-DbaDbLogShipping
                                    }
                                }

                                if ($setupResult -ne 'Failed') {
                                    #$FullBackupPath = $LastBackup.Path
                                    $BackupPath = $LastBackup.Path
                                    Write-Message -Message "Full backup found for $db. Path $BackupPath" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                                }
                            } else {
                                Write-Message -Message "No Full backup found for $db." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                            }
                        }
                    }
                }

                # Set the copy destination folder to include the database name
                if ($UseAzure) {
                    # For Azure, append database name to URL path
                    $DatabaseCopyDestinationFolder = "$CopyDestinationFolder/$($db.Name)"
                    Write-Message -Message "Copy destination URL set to $DatabaseCopyDestinationFolder (Azure - no local copy)." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                } else {
                    if ($CopyDestinationFolder.EndsWith("\")) {
                        $DatabaseCopyDestinationFolder = "$CopyDestinationFolder$($db.Name)"
                    } else {
                        $DatabaseCopyDestinationFolder = "$CopyDestinationFolder\$($db.Name)"
                    }
                    Write-Message -Message "Copy destination folder set to $DatabaseCopyDestinationFolder." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                }

                # Check if the copy job name is set
                # For Azure, still need to set a name because sp_add_log_shipping_secondary_primary requires it
                # (the job will be deleted immediately after creation)
                if ($CopyJob) {
                    $DatabaseCopyJob = "$($CopyJob)$($db.Name)"
                } else {
                    $DatabaseCopyJob = "LSCopy_$($SourceServerName)_$($db.Name)"
                }
                if ($UseAzure) {
                    Write-Message -Message "Copy job name set to $DatabaseCopyJob (will be removed - not needed for Azure)" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                } else {
                    Write-Message -Message "Copy job name set to $DatabaseCopyJob" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                }

                # Check if the copy job schedule name is set
                if ($CopySchedule) {
                    $DatabaseCopySchedule = "$($CopySchedule)$($db.Name)"
                } else {
                    $DatabaseCopySchedule = "LSCopySchedule_$($SourceServerName)_$($db.Name)"
                    Write-Message -Message "Copy job schedule name set to $DatabaseCopySchedule" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                }

                # Check if the copy destination folder exists (skip for Azure blob storage and Azure SQL)
                if ($setupResult -ne 'Failed' -and -not $UseAzure -and -not $DestinationServer.IsAzure) {
                    Write-Message -Message "Testing database copy destination path $DatabaseCopyDestinationFolder" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                    if ((Test-DbaPath -Path $DatabaseCopyDestinationFolder -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential) -ne $true) {
                        if ($PSCmdlet.ShouldProcess($DestinationServerName, "Creating copy destination folder on $DestinationServerName")) {
                            try {
                                # If the destination server is remote and the credential is set
                                if (-not $IsDestinationLocal -and $DestinationCredential) {
                                    Invoke-Command2 -ComputerName $DestinationServerName -Credential $DestinationCredential -ScriptBlock {
                                        Write-Message -Message "Copy destination folder $DatabaseCopyDestinationFolder not found. Trying to create it.. ." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                                        $null = New-Item -Path $DatabaseCopyDestinationFolder -ItemType Directory -Force:$Force
                                    }
                                }
                                # If the server is local and the credential is set
                                elseif ($DestinationCredential) {
                                    Invoke-Command2 -Credential $DestinationCredential -ScriptBlock {
                                        Write-Message -Message "Copy destination folder $DatabaseCopyDestinationFolder not found. Trying to create it.. ." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                                        $null = New-Item -Path $DatabaseCopyDestinationFolder -ItemType Directory -Force:$Force
                                    }
                                }
                                # If the server is local and the credential is not set
                                else {
                                    Write-Message -Message "Copy destination folder $DatabaseCopyDestinationFolder not found. Trying to create it.. ." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                                    $null = New-Item -Path $DatabaseCopyDestinationFolder -ItemType Directory -Force:$Force
                                }
                                Write-Message -Message "Database copy destination folder $DatabaseCopyDestinationFolder created." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                            } catch {
                                $setupResult = "Failed"
                                $comment = "Something went wrong creating the database copy destination folder"
                                Stop-Function -Message "Something went wrong creating the database copy destination folder. `n$($_.Exception.Message)" -ErrorRecord $_ -Target $DestinationServerName -Continue -FunctionName Invoke-DbaDbLogShipping
                            }
                        }
                    }
                }

                # Check if the restore job name is set
                if ($RestoreJob) {
                    $DatabaseRestoreJob = "$($RestoreJob)$($db.Name)"
                } else {
                    $DatabaseRestoreJob = "LSRestore_$($SourceServerName)_$($db.Name)"
                }
                Write-Message -Message "Restore job name set to $DatabaseRestoreJob" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"

                # Check if the restore job schedule name is set
                if ($RestoreSchedule) {
                    $DatabaseRestoreSchedule = "$($RestoreSchedule)$($db.Name)"
                } else {
                    $DatabaseRestoreSchedule = "LSRestoreSchedule_$($SourceServerName)_$($db.Name)"
                }
                Write-Message -Message "Restore job schedule name set to $DatabaseRestoreSchedule" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"

                # If the database needs to be backed up first
                if ($setupResult -ne 'Failed') {
                    if ($GenerateFullBackup) {
                        if ($PSCmdlet.ShouldProcess($SourceSqlInstance, "Backing up database $db")) {

                            Write-Message -Message "Generating full backup." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                            Write-Message -Message "Backing up database $db to $DatabaseSharedPath" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"

                            try {
                                $Timestamp = Get-Date -format "yyyyMMddHHmmss"

                                if ($UseAzure) {
                                    # Backup to Azure blob storage - use container base URL only
                                    # Azure blob names can contain slashes for virtual folders
                                    $AzureBlobName = "$($db.Name)_FullBackup_PreLogShipping_$Timestamp.bak"
                                    $splatBackup = @{
                                        SqlInstance    = $SourceSqlInstance
                                        SqlCredential  = $SourceSqlCredential
                                        Database       = $($db.Name)
                                        AzureBaseUrl   = $SharedPath
                                        BackupFileName = $AzureBlobName
                                        Type           = "Full"
                                    }

                                    # Only specify credential for storage account key authentication
                                    # For SAS tokens, SQL Server finds credential automatically by URL
                                    if ($AzureCredential) {
                                        $splatBackup.AzureCredential = $AzureCredential
                                    }

                                    $LastBackup = Backup-DbaDatabase @splatBackup
                                } else {
                                    # Backup to file share
                                    $splatBackup = @{
                                        SqlInstance      = $SourceSqlInstance
                                        SqlCredential    = $SourceSqlCredential
                                        BackupDirectory  = $DatabaseSharedPath
                                        BackupFileName   = "FullBackup_$($db.Name)_PreLogShipping_$Timestamp.bak"
                                        Database         = $($db.Name)
                                        Type             = "Full"
                                        IgnoreFileChecks = $IgnoreFileChecks
                                    }

                                    $LastBackup = Backup-DbaDatabase @splatBackup
                                }

                                Write-Message -Message "Backup completed." -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"

                                # Get the last full backup path
                                #$FullBackupPath = $LastBackup.BackupPath
                                $BackupPath = $LastBackup.BackupPath

                                Write-Message -Message "Backup is located at $BackupPath" -Level Verbose -FunctionName Invoke-DbaDbLogShipping -ModuleName "dbatools"
                            } catch {
                                $setupResult = "Failed"
                                $comment = "Something went wrong generating the full backup"
                                Stop-Function -Message "Something went wrong generating the full backup" -ErrorRecord $_ -Target $DestinationServerName -Continue -FunctionName Invoke-DbaDbLogShipping
                            }
                        }
                    }
                }

                # Check of the MonitorServerSecurityMode value is of type string and set the integer value
                if ($PrimaryMonitorServerSecurityMode -notin 0, 1) {
                    $PrimaryMonitorServerSecurityMode = switch ($PrimaryMonitorServerSecurityMode) {
                        "SQLSERVER" { 0 } "WINDOWS" { 1 } default { 1 }
                    }
                }

                # Check the PrimaryMonitorServerSecurityMode if it's SQL Server authentication
                if ($PrimaryMonitorServerSecurityMode -eq 0) {
                    if ($PrimaryMonitorServerLogin) {
                        $setupResult = "Failed"
                        $comment = "The PrimaryMonitorServerLogin cannot be empty"
                        Stop-Function -Message "The PrimaryMonitorServerLogin cannot be empty when using SQL Server authentication." -Target $SourceSqlInstance -Continue -FunctionName Invoke-DbaDbLogShipping
                    }

                    if ($PrimaryMonitorServerPassword) {
                        $setupResult = "Failed"
                        $comment = "The PrimaryMonitorServerPassword cannot be empty"
                        Stop-Function -Message "The PrimaryMonitorServerPassword cannot be empty when using SQL Server authentication." -Target $ -Continue -FunctionName Invoke-DbaDbLogShipping
                    }
                }

                # Check of the SecondaryMonitorServerSecurityMode value is of type string and set the integer value
                if ($SecondaryMonitorServerSecurityMode -notin 0, 1) {
                    $SecondaryMonitorServerSecurityMode = switch ($SecondaryMonitorServerSecurityMode) {
                        "SQLSERVER" { 0 } "WINDOWS" { 1 } default { 1 }
                    }
                }

                # Check the MonitorServerSecurityMode if it's SQL Server authentication
                if ($SecondaryMonitorServerSecurityMode -eq 0) {
                    if ($SecondaryMonitorServerLogin) {
                        $setupResult = "Failed"
                        $comment = "The SecondaryMonitorServerLogin cannot be empty"
                        Stop-Function -Message "The SecondaryMonitorServerLogin cannot be empty when using SQL Server authentication." -Target $SourceSqlInstance -Continue -FunctionName Invoke-DbaDbLogShipping
                    }

                    if ($SecondaryMonitorServerPassword) {
                        $setupResult = "Failed"
                        $comment = "The SecondaryMonitorServerPassword cannot be empty"
                        Stop-Function -Message "The SecondaryMonitorServerPassword cannot be empty when using SQL Server authentication." -Target $SourceSqlInstance -Continue -FunctionName Invoke-DbaDbLogShipping
                    }
                }

""";
}
