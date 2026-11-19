#nullable enable

namespace Dataplat.Dbatools.Commands;

/// <summary>Hop script TAIL for Test-DbaLastBackup (W3-110): phase C (the shared
/// restore loop over $workItems), the __w3110State sentinel emission (runs even after
/// the dot-block's early returns - dot-source semantics) and the continue-relay
/// marker. See ScriptHead for the composition contract.</summary>
public sealed partial class TestDbaLastBackupCommand
{
    private const string ProcessScriptTail = """
            $removearray = @()
            if ($CopyFile) {
                try {
                    Write-Message -Level Verbose -Message "Gathering information for file copy." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"
                    $removearray = @()

                    foreach ($backup in $lastbackup) {
                        foreach ($file in $backup.Path) {
                            $filename = Split-Path -Path $file -Leaf
                            Write-Message -Level Verbose -Message "Processing $filename." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"

                            $sourcefile = Join-AdminUnc -servername $instance.ComputerName -filepath $file

                            if (-not $Destination.IsLocalHost) {
                                $remotedestdirectory = Join-AdminUnc -servername $Destination.ComputerName -filepath $copyPath
                            } else {
                                $remotedestdirectory = $copyPath
                            }

                            $remotedestfile = "$remotedestdirectory\$filename"
                            $localdestfile = "$copyPath\$filename"
                            Write-Message -Level Verbose -Message "Destination directory is $destdirectory." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"
                            Write-Message -Level Verbose -Message "Destination filename is $remotedestfile." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"

                            try {
                                Write-Message -Level Verbose -Message "Copying $sourcefile to $remotedestfile." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"
                                Copy-Item -Path $sourcefile -Destination $remotedestfile -ErrorAction Stop
                                $backup.Path = $backup.Path.Replace($file, $localdestfile)
                                $backup.FullName = $backup.Path.Replace($file, $localdestfile)
                                $removearray += $remotedestfile
                            } catch {
                                $backup.Path = $backup.Path.Replace($file, $sourcefile)
                                $backup.FullName = $backup.Path.Replace($file, $sourcefile)
                            }
                        }
                    }
                    $copysuccess = $true
                } catch {
                    Write-Message -Level Warning -Message "Failed to copy backups for $dbName on $instance - $_." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"
                    $copysuccess = $false
                }
            }

            $fileexists = $true
            $skipRestoreResult = $null
            $skipDbccResult = $null

            if (-not $copysuccess) {
                Write-Message -Level Verbose -Message "Failed to copy backups." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"
                $lastbackup = @{
                    Path = "Failed to copy backups"
                }
                $fileexists = $false
                $skipRestoreResult = "Skipped"
                $skipDbccResult = "Skipped"
            } elseif (-not ($lastbackup | Where-Object { $_.type -eq "Full" })) {
                Write-Message -Level Verbose -Message "No full backup returned from lastbackup." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"
                $lastbackup = @{
                    Path = "Not found"
                }
                $fileexists = $false
                $skipRestoreResult = "Skipped"
                $skipDbccResult = "Skipped"
            } elseif ($source -ne $destination -and $lastbackup[0].Path.StartsWith("\\") -eq $false -and $lastbackup[0].Path -notlike "http*" -and $lastbackup[0].Path -notlike "s3*" -and -not $CopyFile) {
                Write-Message -Level Verbose -Message "Path not UNC or cloud storage and source does not match destination. Use -CopyFile to move the backup file." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"
                $fileexists = "Skipped"
                $skipRestoreResult = "Restore not located on shared location"
                $skipDbccResult = "Skipped"
            } elseif (($lastbackup[0].Path | ForEach-Object { Test-DbaPath -SqlInstance $destserver -Path $_ }) -eq $false) {
                Write-Message -Level Verbose -Message "SQL Server cannot find backup." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"
                $fileexists = $false
                $skipRestoreResult = "Skipped"
                $skipDbccResult = "Skipped"
            }

            if (-not $skipRestoreResult -and ($lastbackup[0].Path -like "http*" -or $lastbackup[0].Path -like "s3*")) {
                Write-Message -Level Verbose -Message "Looking good." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"
                $fileexists = $true
            }

            $null = $workItems.Add(@{
                    DbName                    = $dbName
                    LastBackup                = $lastbackup
                    Source                    = $source
                    DestServer                = $destserver
                    DestinationName           = $destination
                    DestinationCredential     = $DestinationSqlCredential
                    FileExists                = $fileexists
                    SkipRestoreResult         = $skipRestoreResult
                    SkipDbccResult            = $skipDbccResult
                    TrustDbBackupHistory      = $true
                    IgnoreDiffBackupInRestore = $false
                    RemoveArray               = $removearray
                    EffectiveDataDirectory    = $effectiveDataDirectory
                    EffectiveLogDirectory     = $effectiveLogDirectory
                })
        }

        # Shared restore loop - processes work items from both -Path and -InputObject paths
        foreach ($workItem in $workItems) {
            $dbName = $workItem.DbName
            $lastbackup = $workItem.LastBackup
            $source = $workItem.Source
            $destserver = $workItem.DestServer
            $destinationName = $workItem.DestinationName
            $fileexists = $workItem.FileExists
            $ogdbname = $dbName
            $prefixedDbName = "$prefix$dbName"

            $restoreresult = $null
            $dbccresult = $null
            $success = $null
            $errormsg = $null
            $dbccElapsed = $restoreElapsed = $startRestore = $endRestore = $startDbcc = $endDbcc = $dbccOutput = $null

            if ($workItem.SkipRestoreResult) {
                $success = $workItem.SkipRestoreResult
                $dbccresult = $workItem.SkipDbccResult
            } else {
                $destdb = $destserver.Databases[$prefixedDbName]

                if ($destdb) {
                    Stop-Function -Message "$prefixedDbName already exists on $destinationName - skipping." -Continue -FunctionName Test-DbaLastBackup
                }

                if ($__realCmdlet.ShouldProcess($destinationName, "Restoring $ogdbname as $prefixedDbName.")) {
                    Write-Message -Level Verbose -Message "Performing restore." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"
                    $startRestore = Get-Date
                    try {
                        if ($ReuseSourceFolderStructure) {
                            $restoreSplat = @{
                                SqlInstance                = $destserver
                                RestoredDatabaseNamePrefix = $prefix
                                DestinationFilePrefix      = $Prefix
                                IgnoreLogBackup            = $IgnoreLogBackup
                                StorageCredential          = $StorageCredential
                                ReuseSourceFolderStructure = $true
                                EnableException            = $true
                            }
                        } else {
                            $restoreSplat = @{
                                SqlInstance                = $destserver
                                RestoredDatabaseNamePrefix = $prefix
                                DestinationFilePrefix      = $Prefix
                                DestinationDataDirectory   = $workItem.EffectiveDataDirectory
                                DestinationLogDirectory    = $workItem.EffectiveLogDirectory
                                IgnoreLogBackup            = $IgnoreLogBackup
                                StorageCredential          = $StorageCredential
                                EnableException            = $true
                            }
                        }

                        if ($workItem.TrustDbBackupHistory) {
                            $restoreSplat.Add("TrustDbBackupHistory", $true)
                        }
                        if ($__boundMaxTransferSize) {
                            $restoreSplat.Add("MaxTransferSize", $MaxTransferSize)
                        }
                        if ($__boundBufferCount) {
                            $restoreSplat.Add("BufferCount", $BufferCount)
                        }
                        if ($__boundFileStreamDirectory) {
                            $restoreSplat.Add("DestinationFileStreamDirectory", $FileStreamDirectory)
                        }
                        if ($__boundChecksum) {
                            $restoreSplat.Add("Checksum", $Checksum)
                        }
                        if ($workItem.IgnoreDiffBackupInRestore) {
                            $restoreSplat.Add("IgnoreDiffBackup", $true)
                        }

                        if ($verifyonly) {
                            $restoreresult = $lastbackup | Restore-DbaDatabase @restoreSplat -VerifyOnly
                        } else {
                            $restoreresult = $lastbackup | Restore-DbaDatabase @restoreSplat
                            Write-Message -Level Verbose -Message " Restore-DbaDatabase -SqlInstance $destserver -RestoredDatabaseNamePrefix $prefix -DestinationFilePrefix $Prefix -DestinationDataDirectory $($workItem.EffectiveDataDirectory) -DestinationLogDirectory $($workItem.EffectiveLogDirectory) -IgnoreLogBackup:$IgnoreLogBackup -StorageCredential $StorageCredential -TrustDbBackupHistory:$($workItem.TrustDbBackupHistory)" -FunctionName Test-DbaLastBackup -ModuleName "dbatools"
                        }
                    } catch {
                        $errormsg = Get-ErrorMessage -Record $_
                    }

                    $endRestore = Get-Date
                    $restorets = New-TimeSpan -Start $startRestore -End $endRestore
                    $ts = [timespan]::fromseconds($restorets.TotalSeconds)
                    $restoreElapsed = "{0:HH:mm:ss}" -f ([datetime]$ts.Ticks)

                    if ($restoreresult.RestoreComplete -eq $true) {
                        $success = "Success"
                    } elseif ($errormsg) {
                        $success = $errormsg
                    } else {
                        $success = "Failure"
                    }
                }

                $destserver = Connect-DbaInstance -SqlInstance $destinationName -SqlCredential $workItem.DestinationCredential

                if (-not $NoCheck -and -not $VerifyOnly) {
                    # shouldprocess is taken care of in Start-DbccCheck
                    if ($ogdbname -eq "master") {
                        $dbccresult = "DBCC CHECKDB skipped for restored master ($prefixedDbName) database. The master database cannot be copied off of a server and have a successful DBCC CHECKDB. See https://www.itprotoday.com/my-master-database-really-corrupt for more information."
                    } else {
                        if ($success -eq "Success") {
                            Write-Message -Level Verbose -Message "Starting DBCC." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"

                            $startDbcc = Get-Date
                            $dbccCheckResult = Start-DbccCheck -Server $destserver -DbName $prefixedDbName -MaxDop $MaxDop -DetailedOutput 3>$null
                            $dbccresult = $dbccCheckResult.Status
                            $dbccOutput = $dbccCheckResult.Output
                            $endDbcc = Get-Date

                            $dbccts = New-TimeSpan -Start $startDbcc -End $endDbcc
                            $ts = [timespan]::fromseconds($dbccts.TotalSeconds)
                            $dbccElapsed = "{0:HH:mm:ss}" -f ([datetime]$ts.Ticks)
                        } else {
                            $dbccresult = "Skipped"
                        }
                    }
                }

                if ($VerifyOnly) {
                    $dbccresult = "Skipped"
                }

                if (-not $NoDrop -and $null -ne $destserver.Databases[$prefixedDbName]) {
                    if ($__realCmdlet.ShouldProcess($prefixedDbName, "Dropping Database $prefixedDbName on $destinationName")) {
                        Write-Message -Level Verbose -Message "Dropping database." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"

                        ## Drop the database
                        try {
                            #Variable $removeresult marked as unused by PSScriptAnalyzer replace with $null to catch output
                            $null = Remove-DbaDatabase -SqlInstance $destserver -Database $prefixedDbName -Confirm:$false
                            Write-Message -Level Verbose -Message "Dropped $prefixedDbName Database on $destinationName." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"
                        } catch {
                            $destserver.Databases.Refresh()
                            if ($destserver.Databases[$prefixedDbName]) {
                                Write-Message -Level Warning -Message "Failed to Drop database $prefixedDbName on $destinationName." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"
                            }
                        }
                    }
                }

                #Cleanup BackupFiles if -CopyFile and backup was moved to destination

                $destserver.Databases.Refresh()
                if ($destserver.Databases[$prefixedDbName] -and -not $NoDrop) {
                    Write-Message -Level Warning -Message "$prefixedDbName was not dropped." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"
                }

                if ($workItem.RemoveArray) {
                    Write-Message -Level Verbose -Message "Removing copied backup file from $destinationName." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"
                    try {
                        $workItem.RemoveArray | Remove-Item -ErrorAction Stop
                    } catch {
                        Write-Message -Level Warning -Message $_ -ErrorRecord $_ -Target $workItem.Source -FunctionName Test-DbaLastBackup -ModuleName "dbatools"
                    }
                }
            }

            if ($__realCmdlet.ShouldProcess("console", "Showing results")) {
                [PSCustomObject]@{
                    SourceServer   = $source
                    TestServer     = $destinationName
                    Database       = $ogdbname
                    FileExists     = $fileexists
                    Size           = [dbasize](($lastbackup.TotalSize | Measure-Object -Sum).Sum)
                    RestoreResult  = $success
                    DbccResult     = $dbccresult
                    RestoreStart   = [dbadatetime]$startRestore
                    RestoreEnd     = [dbadatetime]$endRestore
                    RestoreElapsed = $restoreElapsed
                    DbccMaxDop     = [int]$MaxDop
                    DbccStart      = [dbadatetime]$startDbcc
                    DbccEnd        = [dbadatetime]$endDbcc
                    DbccElapsed    = $dbccElapsed
                    DbccOutput     = $dbccOutput
                    BackupDates    = [dbadatetime[]]($lastbackup.Start)
                    BackupFiles    = $lastbackup.FullName
                }
            }

            if ($Wait) {
                Write-Message -Level Verbose -Message "Waiting $Wait seconds before processing next database." -FunctionName Test-DbaLastBackup -ModuleName "dbatools"
                Start-Sleep -Seconds $Wait
            }
        }
        }
        $__continueEscaped = $false
    }
    @{ __w3110State = @{ CopyPath = $CopyPath } }
    if ($__continueEscaped) { $__continueMarker }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $Destination $DestinationSqlCredential $DataDirectory $LogDirectory $FileStreamDirectory $Prefix $VerifyOnly $NoCheck $NoDrop $CopyFile $CopyPath $MaxSize $DeviceType $IncludeCopyOnly $IgnoreLogBackup $StorageCredential $InputObject $MaxTransferSize $BufferCount $IgnoreDiffBackup $MaxDop $ReuseSourceFolderStructure $Checksum $Wait $Path $EnableException $__boundDatabase $__boundExcludeDatabase $__boundPath $__boundDestination $__boundStorageCredential $__boundIgnoreDiffBackup $__boundIgnoreLogBackup $__boundCopyFile $__boundMaxTransferSize $__boundBufferCount $__boundFileStreamDirectory $__boundChecksum $__state $__realCmdlet $__continueMarker $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the composed per-record hop script (raw strings drop the trailing newline -
    // the "\n" join is load-bearing; the composed text is parse-checked by the row
    // verification).
    private const string ProcessScript = ProcessScriptHead + "\n" + ProcessScriptTail;

    // PS: the engine-authored `continue` for the relay (the W3-102 mechanism).
    private const string ContinueRelayScript = """
continue
""";
}
