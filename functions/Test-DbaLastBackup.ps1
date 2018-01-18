function Test-DbaLastBackup {
    <#
.SYNOPSIS
Quickly and easily tests the last set of full backups for a server

.DESCRIPTION
Restores all or some of the latest backups and performs a DBCC CHECKDB

1. Gathers information about the last full backups
2. Restores the backups to the Destination with a new name. If no Destination is specified, the originating SqlServer wil be used.
3. The database is restored as "dbatools-testrestore-$databaseName" by default, but you can change dbatools-testrestore to whatever you would like using -Prefix
4. The internal file names are also renamed to prevent conflicts with original database
5. A DBCC CHECKDB is then performed
6. And the test database is finally dropped

.PARAMETER SqlInstance
The SQL Server to connect to. Unlike many of the other commands, you cannot specify more than one server.

.PARAMETER Destination
The destination server to use to test the restore. By default, the Destination will be set to the source server

If a different Destination server is specified, you must ensure that the database backups are on a shared location

.PARAMETER SqlCredential
Allows you to login to servers using alternative credentials

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter

Windows Authentication will be used if SqlCredential is not specified

.PARAMETER DestinationCredential
Allows you to login to servers using alternative credentials

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter

Windows Authentication will be used if SqlCredential is not specified

.PARAMETER Database
The database backups to test. If -Database is not provided, all database backups will be tested

.PARAMETER ExcludeDatabase
Exclude specific Database backups to test

.PARAMETER DataDirectory
The command uses the SQL Server's default data directory for all restores. Use this parameter to specify a different directory for mdfs, ndfs and so on.

.PARAMETER LogDirectory
The command uses the SQL Server's default log directory for all restores. Use this parameter to specify a different directory for ldfs.

.PARAMETER VerifyOnly
Do not perform the actual restore. Just perform a VERIFYONLY

.PARAMETER NoCheck
Skip DBCC CHECKDB

.PARAMETER NoDrop
Do not drop newly created test database

.PARAMETER CopyFile
Will copy the backup file to the destination default backup location unless CopyPath is specified.

.PARAMETER CopyPath
Specify a path relative to the SQL Server to copy backups when CopyFile is specified. If not specified will use destination default backup location. If destination SQL Server is not local, admin UNC paths will be utilized for the copy.

.PARAMETER MaxMB
Do not restore databases larger than MaxMB

.PARAMETER AzureCredential
The name of the SQL Server credential on the destination instance that holds the key to the azure storage account
fied, Copy Options are not allowed.

.PARAMETER IncludeCopyOnly
If set, copy only backups will not be counted as a last backup

.PARAMETER IgnoreLogBackup
This switch tells the function to ignore transaction log backups. The process will restore to the latest full or differential backup point only

.PARAMETER Prefix
The database is restored as "dbatools-testrestore-$databaseName" by default. You can change dbatools-testrestore to whatever you would like using this parameter.

.PARAMETER WhatIf
Shows what would happen if the command were to run

.PARAMETER Confirm
Prompts for confirmation of every step. For example:

Are you sure you want to perform this action?
Performing the operation "Restoring model as dbatools-testrestore-model" on target "SQL2016\VNEXT".
[Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Tags: DisasterRecovery, Backup, Restore

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Test-DbaLastBackup

.EXAMPLE
Test-DbaLastBackup -SqlInstance sql2016

Determines the last full backup for ALL databases, attempts to restore all databases (with a different name and file structure), then performs a DBCC CHECKDB

Once the test is complete, the test restore will be dropped

.EXAMPLE
Test-DbaLastBackup -SqlInstance sql2016 -Database master

Determines the last full backup for master, attempts to restore it, then performs a DBCC CHECKDB

.EXAMPLE
Test-DbaLastBackup -SqlInstance sql2016 -Database model, master -VerifyOnly

.EXAMPLE
Test-DbaLastBackup -SqlInstance sql2016 -NoCheck -NoDrop

Skips the DBCC CHECKDB check. This can help speed up the tests but makes it less tested. NoDrop means that the test restores will remain on the server.

.EXAMPLE
Test-DbaLastBackup -SqlInstance sql2016 -DataDirectory E:\bigdrive -LogDirectory L:\bigdrive -MaxMB 10240

Restores data and log files to alternative locations and only restores databases that are smaller than 10 GB

.EXAMPLE
Test-DbaLastBackup -SqlInstance sql2014 -Destination sql2016 -CopyFile

Copies the backup files for sql2014 databases to sql2016 default backup locations and then attempts restore from there.

.EXAMPLE
Test-DbaLastBackup -SqlInstance sql2014 -Destination sql2016 -CopyFile -CopyPath "\\BackupShare\TestRestore\"

Copies the backup files for sql2014 databases to sql2016 default backup locations and then attempts restore from there.

#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer", "Source")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
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
        [int]$MaxMB,
        [switch]$IncludeCopyOnly,
        [switch]$IgnoreLogBackup,
        [string]$AzureCredential,
        [switch][Alias('Silent')]$EnableException
    )

    process {
        foreach ($instance in $sqlinstance) {

            if (-not $destination -or $nodestination) {
                $nodestination = $true
                $destination = $instance
                $DestinationCredential = $SqlCredential
            }

            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $sourceserver = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                Write-Message -Level Verbose -Message "Connecting to $destination"
                $destserver = Connect-SqlInstance -SqlInstance $destination -SqlCredential $DestinationCredential
            }
            catch {
                Stop-Function -Message "Failed to connect to: $destination" -Target $destination -Continue
            }

            if ($destserver.VersionMajor -lt $sourceserver.VersionMajor) {
                Stop-Function -Message "$Destination is a lower version than $instance. Backups would be incompatible." -Continue
            }

            if ($destserver.VersionMajor -eq $sourceserver.VersionMajor -and $destserver.VersionMinor -lt $sourceserver.VersionMinor) {
                Stop-Function -Message "$Destination is a lower version than $instance. Backups would be incompatible." -Continue
            }

            if ($CopyPath) {
                $testpath = Test-DbaSqlPath -SqlInstance $destserver -Path $CopyPath
                if (!$testpath) {
                    Stop-Function -Message "$destserver cannot access $CopyPath" -Continue
                }
            }
            else {
                # If not CopyPath is specified, use the destination server default backup directory
                $copyPath = $destserver.BackupDirectory
            }

            if ($instance -ne $destination -and !$CopyFile) {
                $sourcerealname = $sourceserver.ComputerNetBiosName
                $destrealname = $destserver.ComputerNetBiosName

                if ($BackupFolder) {
                    if ($BackupFolder.StartsWith("\\") -eq $false -and $sourcerealname -ne $destrealname) {
                        Stop-Function -Message "Backup folder must be a network share if the source and destination servers are not the same." -Continue
                    }
                }
            }

            $source = $sourceserver.DomainInstanceName
            $destination = $destserver.DomainInstanceName

            if ($datadirectory) {
                if (!(Test-DbaSqlPath -SqlInstance $destserver -Path $datadirectory)) {
                    $serviceaccount = $destserver.ServiceAccount
                    Stop-Function -Message "Can't access $datadirectory Please check if $serviceaccount has permissions" -Continue
                }
            }
            else {
                $datadirectory = Get-SqlDefaultPaths -SqlInstance $destserver -FileType mdf
            }

            if ($logdirectory) {
                if (!(Test-DbaSqlPath -SqlInstance $destserver -Path $logdirectory)) {
                    $serviceaccount = $destserver.ServiceAccount
                    Stop-Function -Message "$Destination can't access its local directory $logdirectory. Please check if $serviceaccount has permissions" -Continue
                }
            }
            else {
                $logdirectory = Get-SqlDefaultPaths -SqlInstance $destserver -FileType ldf
            }

            if ((Test-Bound "AzureCredential") -and (Test-Bound "CopyFile")) {
                Stop-Function -Message "Cannot use copyfile with Azure backups, set to false" -continue
                $CopyFile = $false
            }

            if (!$Database) {
                $database = $sourceserver.databases.Name | Where-Object Name -ne 'tempdb'
            }

            if ($ExcludeDatabase) {
                $database = $database | Where-Object { $_ -notin $ExcludeDatabase }
            }

            if ($Database -or $ExcludeDatabase) {
                $dblist = $database

                Write-Message -Level Verbose -Message "Getting recent backup history for $instance"

                foreach ($dbname in $dblist) {
                    if ($dbname -eq 'tempdb') {
                        Write-Message -Level Verbose -Message "Skipping tempdb"
                        continue
                    }

                    Write-Message -Level Verbose -Message "Processing $dbname"

                    $copysuccess = $true
                    $db = $sourceserver.databases[$dbname]

                    # The db check is needed when the number of databases exceeds 255, then it's no longer auto-populated
                    if (!$db) {
                        Stop-Function -Message "$dbname does not exist on $source." -Continue
                    }

                    $lastbackup = Get-DbaBackupHistory -SqlInstance $sourceserver -Database $dbname -Last -IncludeCopyOnly:$IncludeCopyOnly #-raw
                    if ($CopyFile) {
                        try {
                            Write-Message -Level Verbose -Message "Gathering information for file copy"
                            $removearray = @()

                            if (Test-Bound "IgnoreLogBackup") {
                                Write-Message -Level Verbose -Message "Skipping Log backups as requested"
                                $lastbackup = @()
                                $lastbackup += $full = Get-DbaBackupHistory -SqlInstance $sourceserver -Database $dbname -IncludeCopyOnly:$IncludeCopyOnly -LastFull #-raw
                                $diff = Get-DbaBackupHistory -SqlInstance $sourceserver -Database $dbname -IncludeCopyOnly:$IncludeCopyOnly -LastDiff # -raw
                                if ($full.start -le $diff.start) {
                                    $lastbackup += $diff
                                }
                            }
                            else {
                                $lastbackup = Get-DbaBackupHistory -SqlInstance $sourceserver -Database $dbname -Last -IncludeCopyOnly:$IncludeCopyOnly #-raw
                            }

                            foreach ($backup in $lastbackup) {
                                foreach ($file in $backup) {
                                    $filename = Split-Path -Path $file.FullName -Leaf
                                    Write-Message -Level Verbose -Message "Processing $filename"

                                    $sourcefile = Join-AdminUnc -servername $sourceserver.ComputerNamePhysicalNetBIOS -filepath $file.Path

                                    if ($destserver.ComputerNamePhysicalNetBIOS -ne $env:COMPUTERNAME) {
                                        $remotedestdirectory = Join-AdminUnc -servername $destserver.ComputerNamePhysicalNetBIOS -filepath $copyPath
                                    }
                                    else {
                                        $remotedestdirectory = $copyPath
                                    }

                                    $remotedestfile = "$remotedestdirectory\$filename"
                                    $localdestfile = "$copyPath\$filename"
                                    Write-Message -Level Verbose -Message "Destination directory is $destdirectory"
                                    Write-Message -Level Verbose -Message "Destination filename is $remotedestfile"

                                    try {
                                        Write-Message -Level Verbose -Message "Copying $sourcefile to $remotedestfile"
                                        Copy-Item -Path $sourcefile -Destination $remotedestfile -ErrorAction Stop
                                        $backup.Path = $localdestfile
                                        $backup.FullName = $localdestfile
                                        $removearray += $remotedestfile
                                    }
                                    catch {
                                        $backup.Path = $sourcefile
                                        $backup.FullName = $sourcefile
                                    }
                                }
                            }
                            $copysuccess = $true
                        }
                        catch {
                            Write-Message -Level Warning -Message "Failed to copy backups for $dbname on $instance to $destdirectory - $_"
                            $copysuccess = $false
                        }
                    }
                    if ($null -eq $lastbackup) {
                        Write-Message -Level Verbose -Message "No backups exist for this database"
                        $lastbackup = @{ Path = "No backups exist for this database" }
                        $fileexists = $false
                        $success = $restoreresult = $dbccresult = "Skipped"
                    }
                    if (!$copysuccess) {
                        Write-Message -Level Verbose -Message "Failed to copy backups"
                        $lastbackup = @{ Path = "Failed to copy backups" }
                        $fileexists = $false
                        $success = $restoreresult = $dbccresult = "Skipped"
                    }
                    elseif (!($lastbackup | Where-Object { $_.type -eq 'Full' })) {
                        Write-Message -Level Verbose -Message "No full backup returned from lastbackup"
                        $lastbackup = @{ Path = "Not found" }
                        $fileexists = $false
                        $success = $restoreresult = $dbccresult = "Skipped"
                    }
                    elseif ($source -ne $destination -and $lastbackup[0].Path.StartsWith('\\') -eq $false -and !$CopyFile) {
                        Write-Message -Level Verbose -Message "Path not UNC and source does not match destination. Use -CopyFile to move the backup file."
                        $fileexists = $dbccresult = "Skipped"
                        $success = $restoreresult = "Restore not located on shared location"
                    }
                    elseif (($lastbackup[0].Path | ForEach-Object { Test-DbaSqlPath -SqlInstance $destserver -Path $_ }) -eq $false) {
                        Write-Message -Level Verbose -Message "SQL Server cannot find backup"
                        $fileexists = $false
                        $success = $restoreresult = $dbccresult = "Skipped"
                    }
                    if ($restoreresult -ne "Skipped" -or $lastbackup[0].Path -like 'http*') {
                        Write-Message -Level Verbose -Message "Looking good!"

                        $fileexists = $true
                        $ogdbname = $dbname
                        $restorelist = Read-DbaBackupHeader -SqlInstance $destserver -Path $lastbackup[0].Path -AzureCredential $AzureCredential
                        $mb = $restorelist.BackupSizeMB

                        if ($MaxMB -gt 0 -and $MaxMB -lt $mb) {
                            $success = "The backup size for $dbname ($mb MB) exceeds the specified maximum size ($MaxMB MB)"
                            $dbccresult = "Skipped"
                        }
                        else {
                            $dbccElapsed = $restoreElapsed = $startRestore = $endRestore = $startDbcc = $endDbcc = $null

                            $dbname = "$prefix$dbname"
                            $destdb = $destserver.databases[$dbname]

                            if ($destdb) {
                                Stop-Function -Message "$dbname already exists on $destination - skipping" -Continue
                            }

                            if ($Pscmdlet.ShouldProcess($destination, "Restoring $ogdbname as $dbname")) {
                                Write-Message -Level Verbose -Message "Performing restore"
                                $startRestore = Get-Date
                                if ($verifyonly) {
                                    $restoreresult = $lastbackup | Restore-DbaDatabase -SqlInstance $destserver -RestoredDatabaseNamePrefix $prefix -DestinationFilePrefix $Prefix -DestinationDataDirectory $datadirectory -DestinationLogDirectory $logdirectory -VerifyOnly:$VerifyOnly -IgnoreLogBackup:$IgnoreLogBackup -AzureCredential $AzureCredential -TrustDbBackupHistory
                                }
                                else {
                                    $restoreresult = $lastbackup | Restore-DbaDatabase -SqlInstance $destserver -RestoredDatabaseNamePrefix $prefix -DestinationFilePrefix $Prefix -DestinationDataDirectory $datadirectory -DestinationLogDirectory $logdirectory -IgnoreLogBackup:$IgnoreLogBackup -AzureCredential $AzureCredential -TrustDbBackupHistory
                                    Write-verbose " Restore-DbaDatabase -SqlInstance $destserver -RestoredDatabaseNamePrefix $prefix -DestinationFilePrefix $Prefix -DestinationDataDirectory $datadirectory -DestinationLogDirectory $logdirectory -IgnoreLogBackup:$IgnoreLogBackup -AzureCredential $AzureCredential -TrustDbBackupHistory"

                                }

                                $endRestore = Get-Date
                                $restorets = New-TimeSpan -Start $startRestore -End $endRestore
                                $ts = [timespan]::fromseconds($restorets.TotalSeconds)
                                $restoreElapsed = "{0:HH:mm:ss}" -f ([datetime]$ts.Ticks)

                                if ($restoreresult.RestoreComplete -eq $true) {
                                    $success = "Success"
                                }
                                else {
                                    $success = "Failure"
                                }
                            }

                            $destserver = Connect-SqlInstance -SqlInstance $destination -SqlCredential $DestinationCredential

                            if (!$NoCheck -and !$VerifyOnly) {
                                # shouldprocess is taken care of in Start-DbccCheck
                                if ($ogdbname -eq "master") {
                                    $dbccresult = "DBCC CHECKDB skipped for restored master ($dbname) database"
                                }
                                else {
                                    if ($success -eq "Success") {
                                        Write-Message -Level Verbose -Message "Starting DBCC"

                                        $startDbcc = Get-Date
                                        $dbccresult = Start-DbccCheck -Server $destserver -DbName $dbname 3>$null
                                        $endDbcc = Get-Date

                                        $dbccts = New-TimeSpan -Start $startDbcc -End $endDbcc
                                        $ts = [timespan]::fromseconds($dbccts.TotalSeconds)
                                        $dbccElapsed = "{0:HH:mm:ss}" -f ([datetime]$ts.Ticks)
                                    }
                                    else {
                                        $dbccresult = "Skipped"
                                    }
                                }
                            }

                            if ($VerifyOnly) { $dbccresult = "Skipped" }

                            if (!$NoDrop -and $null -ne $destserver.databases[$dbname]) {
                                if ($Pscmdlet.ShouldProcess($dbname, "Dropping Database $dbname on $destination")) {
                                    Write-Message -Level Verbose -Message "Dropping database"

                                    ## Drop the database
                                    try {
                                        $removeresult = Remove-SqlDatabase -SqlInstance $destserver -DbName $dbname
                                        Write-Message -Level Verbose -Message "Dropped $dbname Database on $destination"
                                    }
                                    catch {
                                        $destserver.Databases.Refresh()
                                        if ($destserver.databases[$dbname]) {
                                            Write-Message -Level Warning -Message "Failed to Drop database $dbname on $destination"
                                        }
                                    }
                                }
                            }

                            #Cleanup BackupFiles if -CopyFile and backup was moved to destination
                            if ($CopyFile) {
                                Write-Message -Level Verbose -Message "Removing copied backup file from $destination"
                                try {
                                    $removearray | Remove-item -ErrorAction Stop
                                }
                                catch {
                                    Write-Message -Level Warning -Message $_ -ErrorRecord $_ -Target $instance
                                }
                            }

                            $destserver.Databases.Refresh()
                            if ($destserver.Databases[$dbname] -and !$NoDrop) {
                                Write-Message -Level Warning -Message "$dbname was not dropped"
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
                            DbccStart      = [dbadatetime]$startDbcc
                            DbccEnd        = [dbadatetime]$endDbcc
                            DbccElapsed    = $dbccElapsed
                            BackupDate     = $lastbackup.Start
                            BackupFiles    = $lastbackup.FullName
                        }
                    }
                }
            }
        }
    }
}
