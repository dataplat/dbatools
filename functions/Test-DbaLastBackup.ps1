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
        The destination server to use to test the restore. By default, the Destination will be set to the source server

        If a different Destination server is specified, you must ensure that the database backups are on a shared location

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER DestinationCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database backups to test. If -Database is not provided, all database backups will be tested.

    .PARAMETER ExcludeDatabase
        Exclude specific Database backups to test.

    .PARAMETER DataDirectory
        Specifies an alternative directory for mdfs, ndfs and so on. The command uses the SQL Server's default data directory for all restores.

    .PARAMETER LogDirectory
        Specifies an alternative directory for ldfs. The command uses the SQL Server's default log directory for all restores.

    .PARAMETER VerifyOnly
        If this switch is enabled, VERIFYONLY will be performed. An actual restore will not be executed.

    .PARAMETER NoCheck
        If this switch is enabled, DBCC CHECKDB will be skipped

    .PARAMETER NoDrop
        If this switch is enabled, the newly-created test database will not be dropped.

    .PARAMETER CopyFile
        If this switch is enabled, the backup file will be copied to the destination default backup location unless CopyPath is specified.

    .PARAMETER CopyPath
        Specifies a path relative to the SQL Server to copy backups when CopyFile is specified. If not specified will use destination default backup location. If destination SQL Server is not local, admin UNC paths will be utilized for the copy.

    .PARAMETER MaxSize
        Max size in MB. Databases larger than this value will not be restored.

    .PARAMETER MaxDop
        Allows you to pass in a MAXDOP setting to the DBCC CheckDB command to limit the number of parallel processes used.

    .PARAMETER DeviceType
        Specifies a filter for backup sets based on DeviceTypes. Valid options are 'Disk','Permanent Disk Device', 'Tape', 'Permanent Tape Device','Pipe','Permanent Pipe Device','Virtual Device', in addition to custom integers for your own DeviceTypes.

    .PARAMETER AzureCredential
        The name of the SQL Server credential on the destination instance that holds the key to the azure storage account.

    .PARAMETER IncludeCopyOnly
        If this switch is enabled, copy only backups will be counted as a last backup.

    .PARAMETER IgnoreLogBackup
        If this switch is enabled, transaction log backups will be ignored. The restore will stop at the latest full or differential backup point.

    .PARAMETER IgnoreDiffBackup
        If this switch is enabled, differential backuys will be ignored. The restore will only use Full and Log backups, so will take longer to complete

    .PARAMETER Prefix
        The database is restored as "dbatools-testrestore-$databaseName" by default. You can change dbatools-testrestore to whatever you would like using this parameter.

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER MaxTransferSize
        Parameter to set the unit of transfer. Values must be a multiple of 64kb and a max of 4GB
        Parameter is used as passtrough for Restore-DbaDatabase.

    .PARAMETER BufferCount
        Number of I/O buffers to use to perform the operation.
        Refererence: https://msdn.microsoft.com/en-us/library/ms178615.aspx#data-transfer-options
        Parameter is used as passtrough for Restore-DbaDatabase.

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
        When running the restore with these additional parameters and there is other server activity it could affect server OLTP performance. Please use with causion.
        Prior to running, you should check memory and server resources before configure it to run automatically.
        More information:
        https://www.mssqltips.com/sqlservertip/4935/optimize-sql-server-database-restore-performance/

    .EXAMPLE
        PS C:\> Test-DbaLastBackup -SqlInstance sql2016 -MaxDop 4

        The use of the MaxDop parameter will limit the number of processors used during the DBCC command
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "", Justification = "For Parameters DestinationCredential and AzureCredential")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [DbaInstanceParameter]$Destination,
        [object]$DestinationCredential,
        [string]$DataDirectory,
        [string]$LogDirectory,
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
                $DestinationCredential = $SqlCredential
            }

            if ($db.LastFullBackup.Year -eq 1) {
                [pscustomobject]@{
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
                $destserver = Connect-SqlInstance -SqlInstance $destination -SqlCredential $DestinationCredential
            } catch {
                Stop-Function -Message "Failed to connect to: $destination." -Target $destination -Continue
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
                $lastbackup = @{
                    Path = "No backups exist for this database"
                }
                $fileexists = $false
                $success = $restoreresult = $dbccresult = "Skipped"
                continue
            }

            if ($CopyFile) {
                try {
                    Write-Message -Level Verbose -Message "Gathering information for file copy."
                    $removearray = @()

                    foreach ($backup in $lastbackup) {
                        foreach ($file in $backup) {
                            $filename = Split-Path -Path $file.FullName -Leaf
                            Write-Message -Level Verbose -Message "Processing $filename."

                            $sourcefile = Join-AdminUnc -servername $instance.ComputerName -filepath "$($file.Path)"

                            if ($instance.IsLocalHost) {
                                $remotedestdirectory = Join-AdminUnc -servername $instance.ComputerName -filepath $copyPath
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
                                $backup.Path = $localdestfile
                                $backup.FullName = $localdestfile
                                $removearray += $remotedestfile
                            } catch {
                                $backup.Path = $sourcefile
                                $backup.FullName = $sourcefile
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
                $restorelist = Read-DbaBackupHeader -SqlInstance $destserver -Path $lastbackup[0].Path -AzureCredential $AzureCredential

                $totalsize = ($restorelist.BackupSize.Megabyte | Measure-Object -Sum ).Sum

                if ($MaxSize -and $MaxSize -lt $totalsize) {
                    $success = "The backup size for $dbName ($totalsize MB) exceeds the specified maximum size ($MaxSize MB)."
                    $dbccresult = "Skipped"
                } else {
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

                            if (Test-Bound "MaxTransferSize") {
                                $restoreSplat.Add('MaxTransferSize', $MaxTransferSize)
                            }
                            if (Test-Bound "BufferCount") {
                                $restoreSplat.Add('BufferCount', $BufferCount)
                            }

                            if ($verifyonly) {
                                $restoreresult = $lastbackup | Restore-DbaDatabase @restoreSplat -VerifyOnly:$VerifyOnly
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

                    $destserver = Connect-SqlInstance -SqlInstance $destination -SqlCredential $DestinationCredential

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
                        if ($Pscmdlet.ShouldProcess($dbName, "Dropping Database $dbName on $destination")) {
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
                [pscustomobject]@{
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
                    BackupDates    = [String[]]($lastbackup.Start)
                    BackupFiles    = $lastbackup.FullName
                }
            }
        }
    }
}