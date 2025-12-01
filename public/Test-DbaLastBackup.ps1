function Test-DbaLastBackup {
    <#
    .SYNOPSIS
        Quickly and easily tests the last set of full backups for a server.

    .DESCRIPTION
        Restores all or some of the latest backups and performs a DBCC CHECKDB.

        1. Gathers information about the last full backups
        2. Restores the backups to the Destination with a new name. If no Destination is specified, the originating SQL Server instance wil be used.
        3. The database is restored as "dbatools-testrestore-$databaseName" by default, but you can change dbatools-testrestore to whatever you would like using -Prefix
        4. The internal file names are also renamed to prevent conflicts with original database
        5. A DBCC CHECKDB is then performed
        6. And the test database is finally dropped

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Unlike many of the other commands, you cannot specify more than one server.

    .PARAMETER Destination
        Specifies the SQL Server instance where test restores will be performed. Defaults to the source server if not specified.
        Use this when you want to test restores on a different server, such as isolating test operations from production workloads.
        When using a different destination server, backup files must be accessible from that server via shared storage or use -CopyFile.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER DestinationSqlCredential
        Credentials for connecting to the destination SQL Server instance when different from the source.
        Use this when the destination server requires different authentication than the source server.
        Accepts PowerShell credentials (Get-Credential) and supports Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated.

    .PARAMETER Database
        Specifies which databases to include in the backup test. Accepts wildcards for pattern matching.
        Use this to limit testing to specific databases instead of all databases on the instance.
        Helpful when you only want to verify critical databases or troubleshoot specific backup issues.

    .PARAMETER ExcludeDatabase
        Specifies databases to exclude from backup testing. Accepts wildcards for pattern matching.
        Use this to skip non-critical databases, large databases, or databases with known backup issues.
        Commonly used to exclude system databases or databases that would take too long to test.

    .PARAMETER DataDirectory
        Specifies the directory where restored database data files (.mdf, .ndf) will be placed. Defaults to the SQL Server's default data directory.
        Use this when you need to direct test restores to specific storage, such as faster drives for testing or isolated storage locations.
        The SQL Server service account must have write permissions to this directory.

    .PARAMETER LogDirectory
        Specifies the directory where restored database log files (.ldf) will be placed. Defaults to the SQL Server's default log directory.
        Use this when you want to separate test database logs from production logs or direct them to faster storage for testing.
        The SQL Server service account must have write permissions to this directory.

    .PARAMETER FileStreamDirectory
        Specifies the directory where FileStream data will be restored for databases that use FileStream storage.
        Use this when testing databases with FileStream-enabled tables to ensure the FileStream data is properly restored and accessible.
        Required only for databases that contain FileStream data and when not using -ReuseSourceFolderStructure.

    .PARAMETER VerifyOnly
        Performs backup verification only without actually restoring the database. Uses T-SQL RESTORE VERIFYONLY command.
        Use this for faster backup validation when you only need to confirm backup file integrity without full restore testing.
        Skips DBCC CHECKDB since no actual database is restored.

    .PARAMETER NoCheck
        Skips the DBCC CHECKDB operation after restoring the test database.
        Use this to speed up the testing process when you only need to verify that backups can be restored successfully.
        Reduces testing time but provides less thorough validation of database integrity.

    .PARAMETER NoDrop
        Prevents the test database from being automatically dropped after the test completes.
        Use this when you need to examine the restored database manually or perform additional testing.
        Remember to manually clean up test databases later to avoid storage issues.

    .PARAMETER CopyFile
        Copies backup files to the destination server's default backup directory before attempting the restore.
        Use this when backup files are not accessible from the destination server, such as local backups on different servers.
        Cannot be used with Azure SQL Database backups.

    .PARAMETER CopyPath
        Specifies the destination directory where backup files will be copied when using -CopyFile. Defaults to the destination server's default backup directory.
        Use this to control where backup files are temporarily stored during testing, such as directing them to faster storage.
        Path must be accessible to the destination SQL Server service account.

    .PARAMETER MaxSize
        Maximum database size in MB. Databases with backups larger than this value will be skipped.
        Use this to avoid testing extremely large databases that would consume excessive time or storage resources.
        Helps focus testing on databases that can be practically tested within available resources.

    .PARAMETER MaxDop
        Sets the maximum degree of parallelism for the DBCC CHECKDB operation. Limits the number of parallel processes used.
        Use this to control resource usage during integrity checks, especially on busy servers or when testing multiple databases.
        Lower values reduce CPU usage but increase DBCC runtime.

    .PARAMETER DeviceType
        Filters backups by device type such as 'Disk', 'Tape', or 'Virtual Device'. Accepts multiple values.
        Use this when you need to test only backups from specific backup devices or exclude certain device types.
        Commonly used to test only disk backups or exclude tape backups that may be offline.

    .PARAMETER AzureCredential
        Specifies the name of the SQL Server credential that contains the key for accessing Azure Storage where backups are stored.
        Use this when testing backups stored in Azure Blob Storage that require credential-based authentication.
        The credential must already exist on the destination SQL Server instance.

    .PARAMETER IncludeCopyOnly
        Includes copy-only backups when determining the most recent backup to test.
        Use this when you want to test copy-only backups that were created for specific purposes like migrations or testing.
        Copy-only backups don't break the backup chain but are normally excluded from 'last backup' queries.

    .PARAMETER IgnoreLogBackup
        Skips transaction log backups during restore, stopping at the most recent full or differential backup.
        Use this for faster testing when point-in-time recovery precision isn't critical for the test.
        Results in some data loss compared to a complete restore chain but significantly reduces testing time.

    .PARAMETER IgnoreDiffBackup
        Skips differential backups during restore, using only full and transaction log backups.
        Use this to test restore scenarios that don't rely on differential backups or when differential backups are suspected to be problematic.
        May significantly increase restore time due to processing more transaction log backups.

    .PARAMETER Prefix
        Specifies the naming prefix for test databases. Defaults to 'dbatools-testrestore-' resulting in names like 'dbatools-testrestore-MyDB'.
        Use this to customize test database naming for organizational standards or to avoid naming conflicts.
        Choose prefixes that clearly identify databases as temporary test restores.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase for pipeline processing.
        Use this to test backups for databases selected through Get-DbaDatabase filtering options.
        Enables complex database selection scenarios beyond simple name matching.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER MaxTransferSize
        Sets the data transfer unit size for backup restoration. Must be a multiple of 64KB with a maximum of 4GB.
        Use this to optimize restore performance by increasing buffer size, especially for large databases on high-speed storage.
        Higher values can improve performance but consume more memory during the restore operation.

    .PARAMETER BufferCount
        Specifies the number of I/O buffers used during the restore operation.
        Use this to optimize restore performance by controlling memory allocation for the restore process.
        Higher values can improve performance but consume more memory, so balance against other server activity.

    .PARAMETER ReuseSourceFolderStructure
        Maintains the original file paths and directory structure from the source database during restore.
        Use this when testing databases that have specific file location requirements or when simulating exact production restore scenarios.
        Ensures the destination server has the same directory structure as the source or the restore will fail.

    .PARAMETER Checksum
        Enables backup checksum verification during restore operations. When used with -VerifyOnly, forces the RESTORE VERIFYONLY command to use WITH CHECKSUM.
        Use this to ensure backup files contain checksums and validate them during testing, following backup best practices.
        Without this parameter, SQL Server verifies checksums if present but doesn't fail if checksums are missing. With this parameter, the operation fails if checksums are not present in the backup.

    .PARAMETER Wait
        Specifies the number of seconds to wait between each database restore test.
        Use this to prevent I/O errors on checkpoint files by allowing time for cleanup between restore operations.
        Helpful when restoring to network shares or storage systems that need additional time to release file handles.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.


    .NOTES
        Tags: DisasterRecovery, Backup, Restore
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaLastBackup

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2016

        Determines the last full backup for ALL databases, attempts to restore all databases (with a different name and file structure), then performs a DBCC CHECKDB. Once the test is complete, the test restore will be dropped.

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2016 -Database SharePoint_Config

        Determines the last full backup for SharePoint_Config, attempts to restore it, then performs a DBCC CHECKDB.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016, sql2017 | Test-DbaLastBackup

        Tests every database backup on sql2016 and sql2017

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016, sql2017 -Database SharePoint_Config | Test-DbaLastBackup

        Tests the database backup for the SharePoint_Config database on sql2016 and sql2017

    .EXAMPLE
       PS C:\> Test-DbaLastBackup -SqlInstance sql2016 -Database model, master -VerifyOnly

       Skips performing an action restore of the database and simply verifies the backup using VERIFYONLY option of the restore.

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2016 -NoCheck -NoDrop

        Skips the DBCC CHECKDB check. This can help speed up the tests but makes it less tested. The test restores will remain on the server.

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2016 -DataDirectory E:\bigdrive -LogDirectory L:\bigdrive -MaxSize 10240

        Restores data and log files to alternative locations and only restores databases that are smaller than 10 GB.

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2014 -Destination sql2016 -CopyFile

        Copies the backup files for sql2014 databases to sql2016 default backup locations and then attempts restore from there.

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2014 -Destination sql2016 -CopyFile -CopyPath "\\BackupShare\TestRestore\"

        Copies the backup files for sql2014 databases to sql2016 default backup locations and then attempts restore from there.

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2016 -NoCheck -MaxTransferSize 4194302 -BufferCount 24

        Determines the last full backup for ALL databases, attempts to restore all databases (with a different name and file structure).
        The Restore will use more memory for reading the backup files. Do not set these values to high or you can get an Out of Memory error!!!
        When running the restore with these additional parameters and there is other server activity it could affect server OLTP performance. Please use with caution.
        Prior to running, you should check memory and server resources before configure it to run automatically.
        More information:
        https://www.mssqltips.com/sqlservertip/4935/optimize-sql-server-database-restore-performance/

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2016 -MaxDop 4

        The use of the MaxDop parameter will limit the number of processors used during the DBCC command

    .EXAMPLE
       PS C:\> Test-DbaLastBackup -SqlInstance sql2016 -Database model, master -VerifyOnly -Checksum

       Verifies the backup files using RESTORE VERIFYONLY WITH CHECKSUM. This will fail if the backups do not contain checksums, ensuring that backups follow best practices.

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2016 -Wait 5

        Tests all database backups on sql2016 and waits 5 seconds between each database restore test. This helps prevent I/O errors on checkpoint files when restoring to network shares.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "", Justification = "For Parameters DestinationSqlCredential and AzureCredential")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [DbaInstanceParameter]$Destination,
        [object]$DestinationSqlCredential,
        [string]$DataDirectory,
        [string]$LogDirectory,
        [string]$FileStreamDirectory,
        [string]$Prefix = "dbatools-testrestore-",
        [switch]$VerifyOnly,
        [switch]$NoCheck,
        [switch]$NoDrop,
        [switch]$CopyFile,
        [string]$CopyPath,
        [int]$MaxSize,
        [string[]]$DeviceType,
        [switch]$IncludeCopyOnly,
        [switch]$IgnoreLogBackup,
        [string]$AzureCredential,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [int]$MaxTransferSize,
        [int]$BufferCount,
        [switch]$IgnoreDiffBackup,
        [int]$MaxDop,
        [switch]$ReuseSourceFolderStructure,
        [switch]$Checksum,
        [int]$Wait,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            if ($db.Name -eq "tempdb") {
                continue
            }

            $sourceserver = $db.Parent
            $source = $db.Parent.Name
            $instance = [DbaInstanceParameter]$source
            $copysuccess = $true
            $dbName = $db.Name
            $restoreresult = $null

            if (-not (Test-Bound -ParameterName Destination)) {
                $destination = $sourceserver.Name
                $DestinationSqlCredential = $SqlCredential
            }

            if ($db.LastFullBackup.Year -eq 1) {
                [PSCustomObject]@{
                    SourceServer   = $source
                    TestServer     = $destination
                    Database       = $db.name
                    FileExists     = $false
                    Size           = $null
                    RestoreResult  = "Skipped"
                    DbccResult     = "Skipped"
                    RestoreStart   = $null
                    RestoreEnd     = $null
                    RestoreElapsed = $null
                    DbccMaxDop     = $null
                    DbccStart      = $null
                    DbccEnd        = $null
                    DbccElapsed    = $null
                    BackupDates    = $null
                    BackupFiles    = $null
                }
                continue
            }

            try {
                $destserver = Connect-DbaInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Destination -Continue
            }

            if ($destserver.VersionMajor -lt $sourceserver.VersionMajor) {
                Stop-Function -Message "$Destination is a lower version than $instance. Backups would be incompatible." -Continue
            }

            if ($destserver.VersionMajor -eq $sourceserver.VersionMajor -and $destserver.VersionMinor -lt $sourceserver.VersionMinor) {
                Stop-Function -Message "$Destination is a lower version than $instance. Backups would be incompatible." -Continue
            }

            if ($CopyPath) {
                $testpath = Test-DbaPath -SqlInstance $destserver -Path $CopyPath
                if (-not $testpath) {
                    Stop-Function -Message "$destserver cannot access $CopyPath." -Continue
                }
            } else {
                # If not CopyPath is specified, use the destination server default backup directory
                $copyPath = $destserver.BackupDirectory
            }

            if ($instance -ne $destination -and -not $CopyFile) {
                $sourcerealname = $sourceserver.ComputerNetBiosName
                $destrealname = $destserver.ComputerNetBiosName

                if ($BackupFolder) {
                    if ($BackupFolder.StartsWith("\\") -eq $false -and $sourcerealname -ne $destrealname) {
                        Stop-Function -Message "Backup folder must be a network share if the source and destination servers are not the same." -Continue
                    }
                }
            }

            if ($datadirectory) {
                if (-not (Test-DbaPath -SqlInstance $destserver -Path $datadirectory)) {
                    $serviceAccount = $destserver.ServiceAccount
                    Stop-Function -Message "Can't access $datadirectory Please check if $serviceAccount has permissions." -Continue
                }
            } else {
                $datadirectory = Get-SqlDefaultPaths -SqlInstance $destserver -FileType mdf
            }

            if ($logdirectory) {
                if (-not (Test-DbaPath -SqlInstance $destserver -Path $logdirectory)) {
                    $serviceAccount = $destserver.ServiceAccount
                    Stop-Function -Message "$Destination can't access its local directory $logdirectory. Please check if $serviceAccount has permissions." -Continue
                }
            } else {
                $logdirectory = Get-SqlDefaultPaths -SqlInstance $destserver -FileType ldf
            }

            if ((Test-Bound -ParameterName AzureCredential) -and (Test-Bound -ParameterName CopyFile)) {
                Stop-Function -Message "Cannot use copyfile with Azure backups, set to false." -continue
                $CopyFile = $false
            }

            Write-Message -Level Verbose -Message "Getting recent backup history for $($db.Name) on $instance."

            if (Test-Bound "IgnoreLogBackup") {
                Write-Message -Level Verbose -Message "Skipping Log backups as requested."
                $lastbackup = @()
                $lastbackup += $full = Get-DbaDbBackupHistory -SqlInstance $sourceserver -Database $dbName -IncludeCopyOnly:$IncludeCopyOnly -LastFull -DeviceType $DeviceType -WarningAction SilentlyContinue
                if (-not (Test-Bound "IgnoreDiffBackup")) {
                    $diff = Get-DbaDbBackupHistory -SqlInstance $sourceserver -Database $dbName -IncludeCopyOnly:$IncludeCopyOnly -LastDiff -DeviceType $DeviceType -WarningAction SilentlyContinue
                }
                if ($full.start -le $diff.start) {
                    $lastbackup += $diff
                }
            } else {
                $lastbackup = Get-DbaDbBackupHistory -SqlInstance $sourceserver -Database $dbName -IncludeCopyOnly:$IncludeCopyOnly -Last -DeviceType $DeviceType -WarningAction SilentlyContinue -IgnoreDiffBackup:$IgnoreDiffBackup
            }

            if (-not $lastbackup) {
                Write-Message -Level Verbose -Message "No backups exist for this database."
                # This code should never be executed as there is already a test for databases without backup in line 241.
                continue
            }

            $totalSizeMB = ($lastbackup.TotalSize.Megabyte | Measure-Object -Sum).Sum
            if ($MaxSize -and $MaxSize -lt $totalSizeMB) {
                [PSCustomObject]@{
                    SourceServer   = $source
                    TestServer     = $destination
                    Database       = $db.name
                    FileExists     = $null
                    Size           = [dbasize](($lastbackup.TotalSize | Measure-Object -Sum).Sum)
                    RestoreResult  = "The backup size for $dbName ($totalSizeMB MB) exceeds the specified maximum size ($MaxSize MB)."
                    DbccResult     = "Skipped"
                    RestoreStart   = $null
                    RestoreEnd     = $null
                    RestoreElapsed = $null
                    DbccMaxDop     = $null
                    DbccStart      = $null
                    DbccEnd        = $null
                    DbccElapsed    = $null
                    BackupDates    = [dbadatetime[]]($lastbackup.Start)
                    BackupFiles    = $lastbackup.FullName
                }
                continue
            }

            if ($CopyFile) {
                try {
                    Write-Message -Level Verbose -Message "Gathering information for file copy."
                    $removearray = @()

                    foreach ($backup in $lastbackup) {
                        foreach ($file in $backup.Path) {
                            $filename = Split-Path -Path $file -Leaf
                            Write-Message -Level Verbose -Message "Processing $filename."

                            $sourcefile = Join-AdminUnc -servername $instance.ComputerName -filepath $file

                            if (-not $Destination.IsLocalHost) {
                                $remotedestdirectory = Join-AdminUnc -servername $Destination.ComputerName -filepath $copyPath
                            } else {
                                $remotedestdirectory = $copyPath
                            }

                            $remotedestfile = "$remotedestdirectory\$filename"
                            $localdestfile = "$copyPath\$filename"
                            Write-Message -Level Verbose -Message "Destination directory is $destdirectory."
                            Write-Message -Level Verbose -Message "Destination filename is $remotedestfile."

                            try {
                                Write-Message -Level Verbose -Message "Copying $sourcefile to $remotedestfile."
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
                    Write-Message -Level Warning -Message "Failed to copy backups for $dbName on $instance to $destdirectory - $_."
                    $copysuccess = $false
                }
            }
            if (-not $copysuccess) {
                Write-Message -Level Verbose -Message "Failed to copy backups."
                $lastbackup = @{
                    Path = "Failed to copy backups"
                }
                $fileexists = $false
                $success = $restoreresult = $dbccresult = "Skipped"
            } elseif (-not ($lastbackup | Where-Object { $_.type -eq 'Full' })) {
                Write-Message -Level Verbose -Message "No full backup returned from lastbackup."
                $lastbackup = @{
                    Path = "Not found"
                }
                $fileexists = $false
                $success = $restoreresult = $dbccresult = "Skipped"
            } elseif ($source -ne $destination -and $lastbackup[0].Path.StartsWith('\\') -eq $false -and -not $CopyFile) {
                Write-Message -Level Verbose -Message "Path not UNC and source does not match destination. Use -CopyFile to move the backup file."
                $fileexists = $dbccresult = "Skipped"
                $success = $restoreresult = "Restore not located on shared location"
            } elseif (($lastbackup[0].Path | ForEach-Object { Test-DbaPath -SqlInstance $destserver -Path $_ }) -eq $false) {
                Write-Message -Level Verbose -Message "SQL Server cannot find backup."
                $fileexists = $false
                $success = $restoreresult = $dbccresult = "Skipped"
            }
            if ($restoreresult -ne "Skipped" -or $lastbackup[0].Path -like 'http*') {
                Write-Message -Level Verbose -Message "Looking good."

                $fileexists = $true
                $ogdbname = $dbName
                $dbccElapsed = $restoreElapsed = $startRestore = $endRestore = $startDbcc = $endDbcc = $null
                $dbName = "$prefix$dbName"
                $destdb = $destserver.databases[$dbName]

                if ($destdb) {
                    Stop-Function -Message "$dbName already exists on $destination - skipping." -Continue
                }

                if ($Pscmdlet.ShouldProcess($destination, "Restoring $ogdbname as $dbName.")) {
                    Write-Message -Level Verbose -Message "Performing restore."
                    $startRestore = Get-Date
                    try {
                        if ($ReuseSourceFolderStructure) {
                            $restoreSplat = @{
                                SqlInstance                = $destserver
                                RestoredDatabaseNamePrefix = $prefix
                                DestinationFilePrefix      = $Prefix
                                IgnoreLogBackup            = $IgnoreLogBackup
                                AzureCredential            = $AzureCredential
                                TrustDbBackupHistory       = $true
                                ReuseSourceFolderStructure = $true
                                EnableException            = $true
                            }
                        } else {
                            $restoreSplat = @{
                                SqlInstance                = $destserver
                                RestoredDatabaseNamePrefix = $prefix
                                DestinationFilePrefix      = $Prefix
                                DestinationDataDirectory   = $datadirectory
                                DestinationLogDirectory    = $logdirectory
                                IgnoreLogBackup            = $IgnoreLogBackup
                                AzureCredential            = $AzureCredential
                                TrustDbBackupHistory       = $true
                                EnableException            = $true
                            }
                        }

                        if (Test-Bound "MaxTransferSize") {
                            $restoreSplat.Add('MaxTransferSize', $MaxTransferSize)
                        }
                        if (Test-Bound "BufferCount") {
                            $restoreSplat.Add('BufferCount', $BufferCount)
                        }
                        if (Test-Bound "FileStreamDirectory") {
                            $restoreSplat.Add('DestinationFileStreamDirectory', $FileStreamDirectory)
                        }
                        if (Test-Bound "Checksum") {
                            $restoreSplat.Add('Checksum', $Checksum)
                        }

                        if ($verifyonly) {
                            $restoreresult = $lastbackup | Restore-DbaDatabase @restoreSplat -VerifyOnly
                        } else {
                            $restoreresult = $lastbackup | Restore-DbaDatabase @restoreSplat
                            Write-Message -Level Verbose -Message " Restore-DbaDatabase -SqlInstance $destserver -RestoredDatabaseNamePrefix $prefix -DestinationFilePrefix $Prefix -DestinationDataDirectory $datadirectory -DestinationLogDirectory $logdirectory -IgnoreLogBackup:$IgnoreLogBackup -AzureCredential $AzureCredential -TrustDbBackupHistory"
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
                    } else {
                        if ($errormsg) {
                            $success = $errormsg
                        } else {
                            $success = "Failure"
                        }
                    }
                }

                $destserver = Connect-DbaInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

                if (-not $NoCheck -and -not $VerifyOnly) {
                    # shouldprocess is taken care of in Start-DbccCheck
                    if ($ogdbname -eq "master") {
                        $dbccresult =
                        "DBCC CHECKDB skipped for restored master ($dbName) database. `
                            The master database cannot be copied off of a server and have a successful DBCC CHECKDB. `
                            See https://www.itprotoday.com/my-master-database-really-corrupt for more information."
                    } else {
                        if ($success -eq "Success") {
                            Write-Message -Level Verbose -Message "Starting DBCC."

                            $startDbcc = Get-Date
                            $dbccresult = Start-DbccCheck -Server $destserver -DbName $dbName -MaxDop $MaxDop 3>$null
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

                if (-not $NoDrop -and $null -ne $destserver.databases[$dbName]) {
                    if ($PSCmdlet.ShouldProcess($dbName, "Dropping Database $dbName on $destination")) {
                        Write-Message -Level Verbose -Message "Dropping database."

                        ## Drop the database
                        try {
                            #Variable $removeresult marked as unused by PSScriptAnalyzer replace with $null to catch output
                            $null = Remove-DbaDatabase -SqlInstance $destserver -Database $dbName -Confirm:$false
                            Write-Message -Level Verbose -Message "Dropped $dbName Database on $destination."
                        } catch {
                            $destserver.Databases.Refresh()
                            if ($destserver.databases[$dbName]) {
                                Write-Message -Level Warning -Message "Failed to Drop database $dbName on $destination."
                            }
                        }
                    }
                }

                #Cleanup BackupFiles if -CopyFile and backup was moved to destination

                $destserver.Databases.Refresh()
                if ($destserver.Databases[$dbName] -and -not $NoDrop) {
                    Write-Message -Level Warning -Message "$dbName was not dropped."
                }

                if ($CopyFile) {
                    Write-Message -Level Verbose -Message "Removing copied backup file from $destination."
                    try {
                        $removearray | Remove-Item -ErrorAction Stop
                    } catch {
                        Write-Message -Level Warning -Message $_ -ErrorRecord $_ -Target $instance
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess("console", "Showing results")) {
                [PSCustomObject]@{
                    SourceServer   = $source
                    TestServer     = $destination
                    Database       = $db.name
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
                    BackupDates    = [dbadatetime[]]($lastbackup.Start)
                    BackupFiles    = $lastbackup.FullName
                }
            }

            if ($Wait) {
                Write-Message -Level Verbose -Message "Waiting $Wait seconds before processing next database."
                Start-Sleep -Seconds $Wait
            }
        }
    }
}