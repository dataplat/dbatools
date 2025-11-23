function Copy-DbaDatabase {
    <#
    .SYNOPSIS
        Migrates SQL Server databases between instances using backup/restore or detach/attach methods.

    .DESCRIPTION
        Moves user databases from one SQL Server instance to another, supporting both on-premises and Azure SQL Managed Instance destinations. Ideal for server migrations, environment refreshes, disaster recovery testing, and cloud migrations where you need to relocate entire databases with their data and structure intact.

        Offers two migration methods: backup/restore (safer, supports cross-version migrations) and detach/attach (faster, requires same SQL Server version). The backup/restore method creates copy-only backups to avoid breaking your existing backup chain, while detach/attach physically moves database files via administrative shares.

        Automatically handles file path mapping, preserves database properties like ownership chaining and trustworthy settings, and includes safety checks for Availability Groups, mirroring, and replication. By default, databases are placed in the destination server's default data and log directories, but you can preserve the original folder structure.

        Works with named instances, clusters, SQL Server Express Edition, and Azure blob storage for cloud scenarios. Supports multiple destination servers, database renaming, and batch operations for migrating multiple databases efficiently.

        If you are experiencing issues with Copy-DbaDatabase, please use Backup-DbaDatabase | Restore-DbaDatabase instead.

    .PARAMETER Source
        Specifies the source SQL Server instance containing the databases to migrate.
        Supports named instances, clusters, and SQL Server Express editions.

    .PARAMETER SourceSqlCredential
        Specifies credentials for connecting to the source SQL Server instance when Windows authentication is not available.
        Use this when the source server requires SQL authentication or when running under a different security context.

    .PARAMETER Destination
        Specifies one or more destination SQL Server instances where databases will be migrated.
        Supports on-premises instances and Azure SQL Managed Instances for cloud migrations.
        When targeting multiple destinations, backups are performed once and shared across all targets.

    .PARAMETER DestinationSqlCredential
        Specifies credentials for connecting to the destination SQL Server instance when Windows authentication is not available.
        Required for Azure SQL Managed Instance destinations or when destination requires SQL authentication.

    .PARAMETER Database
        Specifies which user databases to migrate by name.
        Use this when you need to migrate specific databases rather than all databases on the instance.
        Supports tab completion from the source instance and accepts multiple database names.

    .PARAMETER ExcludeDatabase
        Specifies databases to exclude when using -AllDatabases.
        Use this to skip problematic databases like those in use, under maintenance, or containing sensitive data.

    .PARAMETER AllDatabases
        Migrates all user databases from the source instance, excluding system databases (master, model, msdb, tempdb).
        Use this for full server migrations or when moving all business databases to a new instance.

    .PARAMETER BackupRestore
        Uses backup and restore method for database migration, creating copy-only backups to preserve existing backup chains.
        This is the safest method for cross-version migrations and works with Azure blob storage.
        Requires either -SharedPath for backup location or -UseLastBackup to use existing backups.

    .PARAMETER AdvancedBackupParams
        Specifies additional parameters for the backup operation as a hashtable.
        Use this to enable compression (@{CompressBackup = $true}), checksum verification, or other backup options.

    .PARAMETER SharedPath
        Specifies the storage location accessible by both source and destination SQL Server instances.
        Accepts local paths (C:\Backups), UNC shares (\\server\backups), or Azure blob storage URLs.
        SQL Server service accounts on both instances must have read/write permissions to this location.

    .Parameter AzureCredential
        Specifies the SQL Server credential name for Azure blob storage authentication.
        Required when using storage access keys with Azure blob storage paths.
        For SAS tokens, the credential name should match the Azure storage URL.

    .PARAMETER WithReplace
        Overwrites existing databases at the destination with the same name.
        Use this when refreshing existing databases or when you want to replace destination databases completely.

    .PARAMETER NoRecovery
        Restores databases in NORECOVERY mode, leaving them ready for additional transaction log restores.
        Use this for staging environments or when setting up log shipping scenarios.

    .PARAMETER NoBackupCleanup
        Preserves backup files after migration instead of automatically deleting them.
        Use this when you want to keep backups for additional restores or compliance requirements.

    .PARAMETER NumberFiles
        Specifies how many backup files to create for each database backup to improve performance.
        Default is 3 files, which provides good parallelism for most databases.
        Increase for very large databases or high-performance storage systems.

    .PARAMETER DetachAttach
        Uses detach/copy/attach method for database migration by moving physical database files.
        This method is faster than backup/restore but requires same SQL Server versions and administrative share access.
        Source databases are automatically reattached if destination attachment fails.

    .PARAMETER Reattach
        Reattaches databases to the source instance after successful detach/attach migration.
        Required when using -DetachAttach with multiple destination servers to restore source functionality.

    .PARAMETER SetSourceReadOnly
        Sets source databases to read-only before migration to prevent data changes during the process.
        Use this to ensure data consistency when databases must remain accessible at the source during migration.

    .PARAMETER ReuseSourceFolderStructure
        Maintains the exact file path structure from the source instance on the destination.
        Use this when destination servers have identical drive layouts or when preserving specific organizational folder structures.
        The destination instance must have matching directory paths available.

    .PARAMETER IncludeSupportDbs
        Migrates SQL Server feature databases including ReportServer, ReportServerTempDB, SSISDB, and distribution databases.
        Use this when migrating servers that host Reporting Services, Integration Services, or replication components.

    .PARAMETER InputObject
        Accepts database objects piped from Get-DbaDatabase for migration.
        Use this to migrate databases filtered by specific criteria like size, compatibility level, or other properties.

    .PARAMETER UseLastBackup
        Uses existing backups from backup history instead of creating new ones.
        The most recent full, differential, and log backups must be accessible to all destination servers.
        Useful for migration scenarios where fresh backups already exist.

    .PARAMETER Continue
        Continues restoration by applying transaction log backups to databases in RECOVERING or STANDBY states.
        Use this with -UseLastBackup when resuming interrupted restore operations or applying additional log backups.

    .PARAMETER NoCopyOnly
        Creates regular backups instead of copy-only backups, which affects the database's backup chain.
        Only use this when you want migration backups to be part of the regular backup sequence.
        Default copy-only behavior preserves existing backup chains and is recommended for migrations.

    .PARAMETER NewName
        Renames the database during migration when copying a single database.
        The database name and physical file names are updated to use the new name.
        Cannot be used with multiple databases or together with -Prefix parameter.

    .PARAMETER Prefix
        Adds a prefix to all migrated database names and their physical file names.
        Use this to distinguish migrated databases (e.g., 'DEV_' prefix for development copies).
        Cannot be used together with -NewName parameter.

    .PARAMETER SetSourceOffline
        Sets source databases to offline status after successful migration.
        Use this for cutover scenarios where source databases should be unavailable after migration.

    .PARAMETER KeepCDC
        Preserves Change Data Capture (CDC) configuration and data during migration.
        Use this when destination databases need to maintain CDC tracking for auditing or replication.

    .PARAMETER KeepReplication
        Preserves replication configuration during database migration.
        Use this when migrating publisher or subscriber databases that participate in replication topologies.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        Forcibly overwrites existing databases at the destination and bypasses safety checks.
        Breaks database mirroring, removes databases from Availability Groups, and rolls back blocking transactions.
        Use with caution as this will permanently destroy existing destination databases.

    .NOTES
        Tags: Migration, Backup, Restore
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

        Limitations:
        - Doesn't cover what it doesn't cover (replication, certificates, etc)
        - SQL Server 2000 databases cannot be directly migrated to SQL Server 2012 and above.
        - Logins within SQL Server 2012 and above logins cannot be migrated to SQL Server 2008 R2 and below.

    .LINK
        https://dbatools.io/Copy-DbaDatabase

    .EXAMPLE
        PS C:\> Copy-DbaDatabase -Source sql2014a -Destination sql2014b -Database TestDB -BackupRestore -SharedPath \\fileshare\sql\migration

        Migrates a single user database TestDB using Backup and restore from instance sql2014a to sql2014b. Backup files are stored in \\fileshare\sql\migration.

    .EXAMPLE
        PS C:\> Copy-DbaDatabase -Source sql2012 -Destination sql2014, sql2016 -DetachAttach -Reattach

        Databases will be migrated from sql2012 to both sql2014 and sql2016 using the detach/copy files/attach method. The following will be performed: kick all users out of the database, detach all data/log files, files copied to the admin share (\\SqlSERVER\M$\MSSql...) of destination server, attach file on destination server, reattach at source. If the database files (*.mdf, *.ndf, *.ldf) on *destination* exist and aren't in use, they will be overwritten.

    .EXAMPLE
        PS C:\> Copy-DbaDatabase -Source sql2014a -Destination sqlcluster, sql2016 -BackupRestore -UseLastBackup -Force

        Migrates all user databases to sqlcluster and sql2016 using the last Full, Diff and Log backups from sql204a. If the databases exist on the destinations, they will be dropped prior to attach.

        Note that the backups must exist in a location accessible by all destination servers, such a network share.

    .EXAMPLE
        PS C:\> Copy-DbaDatabase -Source sql2014a -Destination sqlcluster -ExcludeDatabase Northwind, pubs -IncludeSupportDbs -Force -BackupRestore -SharedPath \\fileshare\sql\migration

        Migrates all user databases except for Northwind and pubs by using backup/restore (copy-only). Backup files are stored in \\fileshare\sql\migration. If the database exists on the destination, it will be dropped prior to attach.

        It also includes the support databases (ReportServer, ReportServerTempDb, SSISDB, distribution).
    .EXAMPLE
        PS C:\> Copy-DbaDatabase -Source sql2014 -Destination managedinstance.cus19c972e4513d6.database.windows.net -DestinationSqlCredential $cred -AllDatabases -BackupRestore -SharedPath https://someblob.blob.core.windows.net/sql

        Migrate all user databases from instance sql2014 to the specified Azure SQL Manage Instance using the blob storage account https://someblob.blob.core.windows.net/sql using a Shared Access Signature (SAS) credential with a name matching the blob storage account

    .EXAMPLE
        PS C:\> Copy-DbaDatabase -Source sql2014 -Destination managedinstance.cus19c972e4513d6.database.windows.net -DestinationSqlCredential $cred -Database MyDb -NewName AzureDb -WithReplace -BackupRestore -SharedPath https://someblob.blob.core.windows.net/sql -AzureCredential AzBlobCredential

        Migrates Mydb from instance sql2014 to AzureDb on the specified Azure SQL Manage Instance, replacing the existing AzureDb if it exists, using the blob storage account https://someblob.blob.core.windows.net/sql using the Sql Server Credential AzBlobCredential

    .EXAMPLE
        PS C:\> Copy-DbaDatabase -Source sql2014a -Destination sqlcluster -BackupRestore -SharedPath \\FS\Backup -AdvancedBackupParams @{ CompressBackup = $true }

        Migrates all user databases to sqlcluster. Uses the parameter CompressBackup with the backup command to save some space on the shared path.

    .EXAMPLE
        PS C:\> Copy-DbaDatabase -Source sqlcs -Destination sqlcs -Database t -DetachAttach -NewName t_copy -Reattach

        Copies database t from sqlcs to the same server (sqlcs) using the detach/copy/attach method. The new database will be named t_copy and the original database will be reattached.
    #>
    [CmdletBinding(DefaultParameterSetName = "DbBackup", SupportsShouldProcess, ConfirmImpact = "Medium")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "AzureCredential", Justification = "Unfortunate variable name that doesn't hold a password")]
    param (
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [Alias("All")]
        [parameter(ParameterSetName = "DbBackup")]
        [parameter(ParameterSetName = "DbAttachDetach")]
        [switch]$AllDatabases,
        [parameter(Mandatory, ParameterSetName = "DbBackup")]
        [switch]$BackupRestore,
        [parameter(ParameterSetName = "DbBackup")]
        [hashtable]$AdvancedBackupParams,
        [parameter(ParameterSetName = "DbBackup",
            HelpMessage = "Specify a valid network share in the format \\server\share that can be accessed by your account and the SQL Server service accounts for both Source and Destination.")]
        [string]$SharedPath,
        [string]$AzureCredential,
        [parameter(ParameterSetName = "DbBackup")]
        [switch]$WithReplace,
        [parameter(ParameterSetName = "DbBackup")]
        [switch]$NoRecovery,
        [parameter(ParameterSetName = "DbBackup")]
        [switch]$NoBackupCleanup,
        [parameter(ParameterSetName = "DbBackup")]
        [ValidateRange(1, 64)]
        [int]$NumberFiles = 3,
        [parameter(Mandatory, ParameterSetName = "DbAttachDetach")]
        [switch]$DetachAttach,
        [parameter(ParameterSetName = "DbAttachDetach")]
        [switch]$Reattach,
        [parameter(ParameterSetName = "DbBackup")]
        [parameter(ParameterSetName = "DbAttachDetach")]
        [switch]$SetSourceReadOnly,
        [Alias("ReuseFolderStructure")]
        [parameter(ParameterSetName = "DbBackup")]
        [parameter(ParameterSetName = "DbAttachDetach")]
        [switch]$ReuseSourceFolderStructure,
        [parameter(ParameterSetName = "DbBackup")]
        [parameter(ParameterSetName = "DbAttachDetach")]
        [switch]$IncludeSupportDbs,
        [parameter(ParameterSetName = "DbBackup")]
        [switch]$UseLastBackup,
        [parameter(ParameterSetName = "DbBackup")]
        [switch]$Continue,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$NoCopyOnly,
        [parameter(ParameterSetName = "DbBackup")]
        [switch]$KeepCDC,
        [parameter(ParameterSetName = "DbBackup")]
        [switch]$KeepReplication,
        [switch]$SetSourceOffline,
        [string]$NewName,
        [string]$Prefix,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        $CopyOnly = -not $NoCopyOnly

        if (-not $InputObject -and -not $Source) {
            Stop-Function -Message "With no piped input a -Source must be specified."
            return
        }
        if ($BackupRestore -and (-not $SharedPath -and -not $UseLastBackup)) {
            Stop-Function -Message "When using -BackupRestore, you must specify -SharedPath or -UseLastBackup"
            return
        }
        if ($SharedPath -and $UseLastBackup) {
            Stop-Function -Message "-SharedPath cannot be used with -UseLastBackup because the backup path is determined by the paths in the last backups"
            return
        }
        if ($DetachAttach -and -not $Reattach -and $Destination.Count -gt 1) {
            Stop-Function -Message "When using -DetachAttach with multiple servers, you must specify -Reattach to reattach database at source"
            return
        }
        if ($SharedPath -like 'https*' -and $DetachAttach) {
            Stop-Function -Message "Cannot use DetachAttach with Azure storage. Option is only available with BackupRestore"
            return
        }
        if ($Continue -and -not $UseLastBackup) {
            Stop-Function -Message "-Continue cannot be used without -UseLastBackup"
            return
        }

        if ($Force) {
            $ConfirmPreference = 'none'
        }

        function Get-SqlFileStructure {
            $dbcollection = @{
            };
            $databaseProgressbar = 0

            foreach ($db in $databaseList) {
                Write-Progress -Id 1 -Activity "Processing database file structure" -PercentComplete ($databaseProgressbar / $dbCount * 100) -Status "Processing $databaseProgressbar of $dbCount."
                $dbName = $db.Name
                Write-Message -Level Verbose -Message $dbName

                $databaseProgressbar++
                $dbStatus = $db.status.toString()
                if ($dbStatus.StartsWith("Normal") -eq $false) {
                    continue
                }
                $destinstancefiles = @{
                }; $sourcefiles = @{
                }

                $where = "Filetype <> 'LOG' and Filetype <> 'FULLTEXT'"

                $datarows = $dbFileTable.Tables.Select("dbname = '$dbName' and $where")

                # Data Files
                foreach ($file in $datarows) {
                    # Destination File Structure
                    $d = @{
                    }
                    if ($ReuseSourceFolderStructure) {
                        $d.physical = $file.filename
                    } elseif ($WithReplace) {
                        $name = $file.Name
                        $destfile = $remoteDbFileTable.Tables[0].Select("dbname = '$dbName' and name = '$name'")
                        $d.physical = $destfile.filename

                        if ($null -eq $d.physical) {
                            $directory = Get-SqlDefaultPaths $destServer data
                            $fileName = Split-Path $file.filename -Leaf
                            $d.physical = "$directory\$fileName"
                        }
                    } else {
                        $directory = Get-SqlDefaultPaths $destServer data
                        $fileName = Split-Path $file.filename -Leaf
                        $d.physical = "$directory\$fileName"
                    }
                    $d.logical = $file.Name

                    $d.remotefilename = Join-AdminUNC $destFullComputerName $d.physical
                    $destinstancefiles.add($file.Name, $d)

                    # Source File Structure
                    $s = @{
                    }
                    $s.logical = $file.Name
                    $s.physical = $file.filename
                    $s.remotefilename = Join-AdminUNC $sourceFullComputerName $s.physical
                    $sourcefiles.add($file.Name, $s)
                }

                # Add support for Full Text Catalogs in SQL Server 2005 and below
                if ($sourceServer.VersionMajor -lt 10) {
                    try {
                        $fttable = $null = $sourceServer.Databases[$dbName].ExecuteWithResults('sp_help_fulltext_catalogs')
                        $allrows = $fttable.Tables[0].rows
                    } catch {
                        # Nothing, it's just not enabled
                        # here to avoid an empty catch
                        $null = 1
                    }

                    foreach ($ftc in $allrows) {
                        # Destination File Structure
                        $d = @{
                        }
                        $pre = "sysft_"
                        $name = $ftc.Name
                        $physical = $ftc.Path # RootPath
                        $logical = "$pre$name"
                        if ($ReuseSourceFolderStructure) {
                            $d.physical = $physical
                        } else {
                            $directory = Get-SqlDefaultPaths $destServer data
                            if ($destServer.VersionMajor -lt 10) {
                                $directory = "$directory\FTDATA"
                            }
                            $fileName = Split-Path($physical) -Leaf
                            $d.physical = "$directory\$fileName"
                        }
                        $d.logical = $logical
                        $d.remotefilename = Join-AdminUNC $destFullComputerName $d.physical
                        $destinstancefiles.add($logical, $d)

                        # Source File Structure
                        $s = @{
                        }
                        $pre = "sysft_"
                        $name = $ftc.Name
                        $physical = $ftc.Path # RootPath
                        $logical = "$pre$name"

                        $s.logical = $logical
                        $s.physical = $physical
                        $s.remotefilename = Join-AdminUNC $sourceFullComputerName $s.physical
                        $sourcefiles.add($logical, $s)
                    }
                }

                $where = "Filetype = 'LOG'"
                $datarows = $dbFileTable.Tables[0].Select("dbname = '$dbName' and $where")

                # Log Files
                foreach ($file in $datarows) {
                    $d = @{
                    }
                    if ($ReuseSourceFolderStructure) {
                        $d.physical = $file.filename
                    } elseif ($WithReplace) {
                        $name = $file.Name
                        $destfile = $remoteDbFileTable.Tables[0].Select("dbname = '$dbName' and name = '$name'")
                        $d.physical = $destfile.filename

                        if ($null -eq $d.physical) {
                            $directory = Get-SqlDefaultPaths $destServer data
                            $fileName = Split-Path $file.filename -Leaf
                            $d.physical = "$directory\$fileName"
                        }
                    } else {
                        $directory = Get-SqlDefaultPaths $destServer log
                        $fileName = Split-Path $file.filename -Leaf
                        $d.physical = "$directory\$fileName"
                    }
                    $d.logical = $file.Name
                    $d.remotefilename = Join-AdminUNC $destFullComputerName $d.physical
                    $destinstancefiles.add($file.Name, $d)

                    $s = @{
                    }
                    $s.logical = $file.Name
                    $s.physical = $file.filename
                    $s.remotefilename = Join-AdminUNC $sourceFullComputerName $s.physical
                    $sourcefiles.add($file.Name, $s)
                }

                $location = @{
                }
                $location.add("Destination", $destinstancefiles)
                $location.add("Source", $sourcefiles)
                $dbcollection.Add($($db.Name), $location)
            }

            $fileStructure = [PSCustomObject]@{
                "databases" = $dbcollection
            }
            Write-Progress -Id 1 -Activity "Processing database file structure" -Status "Completed" -Completed
            return $fileStructure
        }

        function Dismount-SqlDatabase {
            [CmdletBinding()]
            param (
                [object]$server,
                [string]$dbName
            )

            $currentdb = $server.databases[$dbName]
            if ($currentdb.IsMirroringEnabled) {
                try {
                    Write-Message -Level Verbose -Message "Breaking mirror for $dbName"
                    $currentdb.ChangeMirroringState([Microsoft.SqlServer.Management.Smo.MirroringOption]::Off)
                    $currentdb.Alter()
                    $currentdb.Refresh()
                    Write-Message -Level Verbose -Message "Could not break mirror for $dbName. Skipping."
                } catch {
                    Stop-Function -Message "Issue breaking mirror." -Target $dbName -ErrorRecord $_
                    return $false
                }
            }

            if ($currentdb.AvailabilityGroupName) {
                $agName = $currentdb.AvailabilityGroupName
                Write-Message -Level Verbose -Message "Attempting remove from Availability Group $agName."
                try {
                    $server.AvailabilityGroups[$currentdb.AvailabilityGroupName].AvailabilityDatabases[$dbName].Drop()
                    Write-Message -Level Verbose -Message "Successfully removed $dbName from  detach from $agName on $($server.Name)."
                } catch {
                    Stop-Function -Message "Could not remove $dbName from $agName on $($server.Name)." -Target $dbName -ErrorRecord $_
                    return $false
                }
            }

            Write-Message -Level Verbose -Message "Attempting detach from $dbName from $source."

            ####### Using Sql to detach does not modify the $currentdb collection #######

            $server.KillAllProcesses($dbName)

            try {
                $sql = "ALTER DATABASE [$dbName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE"
                Write-Message -Level Verbose -Message $sql
                $null = $server.Query($sql)
                Write-Message -Level Verbose -Message "Successfully set $dbName to single-user from $source."
            } catch {
                Stop-Function -Message "Issue setting database to single-user." -Target $dbName -ErrorRecord $_
            }

            try {
                $sql = "EXEC master.dbo.sp_detach_db N'$dbName'"
                Write-Message -Level Verbose -Message $sql
                $null = $server.Query($sql)
                Write-Message -Level Verbose -Message "Successfully detached $dbName from $source."
                return $true
            } catch {
                Stop-Function -Message "Issue detaching database." -Target $dbName -ErrorRecord $_
                return $false
            }
        }

        function Mount-SqlDatabase {
            [CmdletBinding()]
            param (
                [object]$server,
                [string]$dbName,
                [object]$fileStructure,
                [string]$dbOwner
            )

            if ($null -eq $server.Logins.Item($dbOwner)) {
                try {
                    $dbOwner = ($destServer.logins | Where-Object {
                            $_.id -eq 1
                        }).Name
                } catch {
                    $dbOwner = "sa"
                }
            }
            try {
                $null = $server.AttachDatabase($dbName, $fileStructure, $dbOwner, [Microsoft.SqlServer.Management.Smo.AttachOptions]::None)
                return $true
            } catch {
                Stop-Function -Message "Issue mounting database." -ErrorRecord $_
                return $false
            }
        }

        function Start-SqlFileTransfer {
            <#

                SYNOPSIS
                Internal function. Uses BITS to transfer detached files (.mdf, .ndf, .ldf, and filegroups) to
                another server over admin UNC paths. Locations of data files are kept in the
                custom object generated by Get-SqlFileStructure

                #>
            [CmdletBinding(SupportsShouldProcess)]
            param (
                [object]$fileStructure,
                [string]$dbName
            )
            $filestructure
            $copydb = $fileStructure.databases[$dbName]
            $dbsource = $copydb.source
            $dbdestination = $copydb.destination

            foreach ($file in $dbsource.keys) {
                if ($Pscmdlet.ShouldProcess($file, "Starting Sql File Transfer")) {
                    $remotefilename = $dbdestination[$file].remotefilename
                    $from = $dbsource[$file].remotefilename
                    try {
                        if (Test-Path $from -PathType container) {
                            $null = New-Item -ItemType Directory -Path $remotefilename -Force
                            Start-BitsTransfer -Source "$from\*.*" -Destination $remotefilename -ErrorAction Stop

                            $directories = (Get-ChildItem -Recurse $from | Where-Object {
                                    $_.PsIsContainer
                                }).FullName
                            foreach ($directory in $directories) {
                                $newdirectory = $directory.replace($from, $remotefilename)
                                $null = New-Item -ItemType Directory -Path $newdirectory -Force
                                Start-BitsTransfer -Source "$directory\*.*" -Destination $newdirectory -ErrorAction Stop
                            }
                        } else {
                            Write-Message -Level Verbose -Message "Copying $from for $dbName."
                            Start-BitsTransfer -Source $from -Destination $remotefilename -ErrorAction Stop
                        }
                    } catch {
                        try {
                            # Sometimes BITS trips out temporarily on cloned drives.
                            Start-BitsTransfer -Source $from -Destination $remotefilename -ErrorAction Stop
                        } catch {
                            Write-Message -Level Verbose -Message "Start-BitsTransfer did not succeed. Now attempting with Copy-Item - no progress bar will be shown."
                            try {
                                Copy-Item -Path $from -Destination $remotefilename -ErrorAction Stop
                                $remotefilename
                            } catch {
                                Write-Message -Level Verbose -Message "Access denied. This can happen for a number of reasons including issues with cloned disks."
                                Stop-Function -Message "Alternatively, you may need to run PowerShell as Administrator, especially when running on localhost." -Target $from -ErrorRecord $_
                                return
                            }
                        }
                    }
                }
            }
            return $true
        }

        function Start-SqlDetachAttach {
            <#

                    .SYNOPSIS
                    Internal function. Performs checks, then executes Dismount-SqlDatabase on a database, copies its files to the new server, then performs Mount-SqlDatabase. $sourceServer and $destServer are SMO server objects.

                    $fileStructure is a custom object generated by Get-SqlFileStructure

                    #>
            [CmdletBinding(SupportsShouldProcess)]
            param (
                [object]$sourceServer,
                [object]$destServer,
                [object]$fileStructure,
                [string]$dbName
            )
            if ($Pscmdlet.ShouldProcess($dbName, "Starting detaching and re-attaching from $sourceServer to $destServer")) {
                $destfilestructure = New-Object System.Collections.Specialized.StringCollection
                $sourceFileStructure = New-Object System.Collections.Specialized.StringCollection
                $dbOwner = $sourceServer.databases[$dbName].owner
                $destDbName = $fileStructure.databases[$dbName].destinationDbName

                if ($null -eq $dbOwner) {
                    try {
                        $dbOwner = ($destServer.logins | Where-Object {
                                $_.id -eq 1
                            }).Name
                    } catch {
                        $dbOwner = "sa"
                    }
                }

                foreach ($file in $fileStructure.databases[$dbName].destination.values) {
                    $null = $destfilestructure.add($file.physical)
                }
                foreach ($file in $fileStructure.databases[$dbName].source.values) {
                    $null = $sourceFileStructure.add($file.physical)
                }

                $detachresult = Dismount-SqlDatabase $sourceServer $dbName

                if ($detachresult) {

                    $transfer = Start-SqlFileTransfer $fileStructure $dbName
                    if ($transfer -eq $false) {
                        Write-Message -Level Verbose -Message "Could not copy files."
                        return "Could not copy files."
                    }
                    $attachresult = Mount-SqlDatabase $destServer $destDbName $destfilestructure $dbOwner

                    if ($attachresult -eq $true) {
                        # add to added dbs because ATTACH was successful
                        Write-Message -Level Verbose -Message "Successfully attached $dbName to $destinstance."
                        return $true
                    } else {
                        # add to failed because ATTACH was unsuccessful
                        Write-Message -Level Verbose -Message "Could not attach $dbName."
                        return "Could not attach database."
                    }
                } else {
                    # add to failed because DETACH was unsuccessful
                    Write-Message -Level Verbose -Message "Could not detach $dbName."
                    return "Could not detach database."
                }
            }
        }
        $backupCollection = @()
    }
    process {
        if (Test-FunctionInterrupt) {
            return
        }

        # testing twice for whatif reasons
        if ($BackupRestore -and (-not $SharedPath -and -not $UseLastBackup)) {
            Stop-Function -Message "When using -BackupRestore, you must specify -SharedPath or -UseLastBackup"
            return
        }
        if ($SharedPath -and $UseLastBackup) {
            Stop-Function -Message "-SharedPath cannot be used with -UseLastBackup because the backup path is determined by the paths in the last backups"
            return
        }
        if ($DetachAttach -and -not $Reattach -and $Destination.Count -gt 1) {
            Stop-Function -Message "When using -DetachAttach with multiple servers, you must specify -Reattach to reattach database at source"
            return
        }
        if (($AllDatabases -or $IncludeSupportDbs -or $Database) -and !$DetachAttach -and !$BackupRestore) {
            Stop-Function -Message "You must specify -DetachAttach or -BackupRestore when migrating databases."
            return
        }

        if (-not $AllDatabases -and -not $IncludeSupportDbs -and -not $Database -and -not $InputObject) {
            Stop-Function -Message "You must specify a -AllDatabases or -Database to continue."
            return
        }

        if ((Test-Bound 'NewName') -and (Test-Bound 'Prefix')) {
            Stop-Function -Message "NewName and Prefix are exclusive options, cannot specify both"
            return
        }

        if ($InputObject) {
            $Source = $InputObject[0].Parent
            $Database = $InputObject.Name
        }

        if ($Database -contains "master" -or $Database -contains "msdb" -or $Database -contains "tempdb") {
            Stop-Function -Message "Migrating system databases is not currently supported." -Continue
        }

        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }

        if ($SharedPath -like 'https*') {
            if ($AzureCredential -eq '') {
                $tAzureCredential = $SharedPath
            } else {
                $tAzureCredential = $AzureCredential
            }
            if (-not (Get-DbaCredential -SqlInstance $sourceServer -Name $tAzureCredential.trim('/'))) {
                Stop-Function -Message "Azure storage path passed in, but no matching credential found" -Category InvalidArgument -Target $sourceServer
                return
            }
        }

        Invoke-SmoCheck -SqlInstance $sourceServer

        # Fix #6600
        $sourceFullComputerName = Resolve-DbaComputerName -ComputerName $sourceServer.ComputerName
        Write-Message -Level Verbose -Message "Using $sourceFullComputerName as sourceFullComputerName."

        Write-Message -Level Verbose -Message "Ensuring user databases exist (counting databases)."

        if ($sourceserver.Databases.IsSystemObject -notcontains $false) {
            Stop-Function -Message "No user databases to migrate"
            return
        }

        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }

            if ($sourceServer.ComputerName -eq $destServer.ComputerName) {
                $script:sameserver = $true
            } else {
                $script:sameserver = $false
            }
            if ($SharedPath -like 'https*') {
                if ($AzureCredential -eq '') {
                    $tAzureCredential = $SharedPath
                } else {
                    $tAzureCredential = $AzureCredential
                }
                if (-not (Get-DbaCredential -SqlInstance $destServer -Name $tAzureCredential.trim('/'))) {
                    Stop-Function -Message "Azure storage path passed in, but no matching credential found" -Category InvalidArgument -Target $destServer -Continue
                }
            }
            if ($script:sameserver -and $DetachAttach) {
                if (-not (Test-ElevationRequirement -ComputerName $sourceServer)) {
                    return
                }
            }

            $destVersionLower = $destServer.VersionMajor -lt $sourceServer.VersionMajor
            $destVersionMinorLow = ($destServer.VersionMajor -eq 10 -and $sourceServer.VersionMajor -eq 10) -and ($destServer.VersionMinor -lt $sourceServer.VersionMinor)

            if ($destVersionLower -or $destVersionMinorLow) {
                Stop-Function -Message "Error: copy database cannot be made from newer $($sourceServer.VersionString) to older $($destServer.VersionString) SQL Server version."
                return
            }
            $miRestore = $false
            if ($destServer.DatabaseEngineEdition -eq 'SqlManagedInstance') {
                # we have a managed instance destination, set an internal flag to disable switches that don't work
                $miRestore = $True
            }
            if ($DetachAttach) {
                if ($sourceServer.ComputerName -eq $env:COMPUTERNAME -or $destServer.ComputerName -eq $env:COMPUTERNAME) {
                    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
                        Write-Message -Level Verbose -Message "When running DetachAttach locally on the console, it's possible you'll need to Run As Administrator. Trying anyway."
                    }
                }
            }

            if ($SharedPath -and $SharedPath -notlike 'https*') {
                if ($(Test-DbaPath -SqlInstance $sourceServer -Path $SharedPath) -eq $false) {
                    Write-Message -Level Verbose -Message "$Source may not be able to access $SharedPath. Trying anyway."
                }

                if ($(Test-DbaPath -SqlInstance $destServer -Path $SharedPath) -eq $false) {
                    Write-Message -Level Verbose -Message "$destinstance may not be able to access $SharedPath. Trying anyway."
                }

                if ($SharedPath.StartsWith('\\')) {
                    try {
                        $shareServer = ($SharedPath -split "\\")[2]
                        $hostEntry = ([Net.Dns]::GetHostEntry($shareServer)).HostName -split "\."

                        if ($shareServer -ne $hostEntry[0]) {
                            Write-Message -Level Verbose -Message "Using CNAME records for the network share may present an issue if an SPN has not been created. Trying anyway. If it doesn't work, use a different (A record) hostname."
                        }
                    } catch {
                        Stop-Function -Message "Error validating unc path: $_"
                        return
                    }
                }
            }

            # Fix #6600
            $destFullComputerName = Resolve-DbaComputerName -ComputerName $destserver.ComputerName
            Write-Message -Level Verbose -Message "Using $destFullComputerName as destFullComputerName."

            Write-Message -Level Verbose -Message "Performing SMO version check."
            Invoke-SmoCheck -SqlInstance $destServer

            Write-Message -Level Verbose -Message "Checking to ensure the source isn't the same as the destination."
            if ($source -eq $destinstance) {
                Stop-Function -Message "Source and Destination SQL Servers instances are the same. Quitting." -Continue
            }

            Write-Message -Level Verbose -Message "Checking to ensure server is not SQL Server 7 or below."
            if ($sourceServer.VersionMajor -lt 8 -or $destServer.VersionMajor -lt 8) {
                Stop-Function -Message "This script can only be run on SQL Server 2000 and above. Quitting." -Continue
            }

            Write-Message -Level Verbose -Message "Checking to ensure detach/attach is not attempted on SQL Server 2000."
            if ($destServer.VersionMajor -lt 9 -and $DetachAttach) {
                Stop-Function -Message "Detach/Attach not supported when destination SQL Server is version 2000. Quitting." -Target $destServer -Continue
            }

            Write-Message -Level Verbose -Message "Checking to ensure SQL Server 2000 migration isn't directly attempted to SQL Server 2012."
            if ($sourceServer.VersionMajor -lt 9 -and $destServer.VersionMajor -gt 10) {
                Stop-Function -Message "SQL Server 2000 databases cannot be migrated to SQL Server versions 2012 and above. Quitting." -Target $destServer -Continue
            }

            Write-Message -Level Verbose -Message "Warning if migration from 2005 to 2012 and above and attach/detach is used."
            if ($sourceServer.VersionMajor -eq 9 -and $destServer.VersionMajor -gt 9 -and !$BackupRestore -and !$Force -and $DetachAttach) {
                Stop-Function -Message "Backup and restore is the safest method for migrating from SQL Server 2005 to other SQL Server versions. Please use the -BackupRestore switch or override this requirement by specifying -Force." -Continue
            }

            if ($sourceServer.Collation -ne $destServer.Collation) {
                Write-Message -Level Verbose -Message "Warning on different collation."
                Write-Message -Level Verbose -Message "Collation on $Source, $($sourceServer.Collation) differs from the $destinstance, $($destServer.Collation)."
            }

            Write-Message -Level Verbose -Message "Ensuring destination server version is equal to or greater than source."
            if ($sourceServer.VersionMajor -ge $destServer.VersionMajor) {
                if ($sourceServer.VersionMinor -gt $destServer.VersionMinor) {
                    Stop-Function -Message "Source SQL Server version build must be <= destination SQL Server for database migration." -Continue
                }
            }

            # SMO's filestreamlevel is sometimes null
            $sql = "SELECT COALESCE(SERVERPROPERTY('FilestreamConfiguredLevel'),0) AS fs"
            $sourceFilestream = $sourceServer.ConnectionContext.ExecuteScalar($sql)
            $destFilestream = $destServer.ConnectionContext.ExecuteScalar($sql)
            if ($sourceFilestream -gt 0 -and $destFilestream -eq 0) {
                $fsWarning = $true
            }

            Write-Message -Level Verbose -Message "Writing warning about filestream being enabled."
            if ($fsWarning) {
                Write-Message -Level Verbose -Message "FILESTREAM enabled on $source but not $destinstance. Databases that use FILESTREAM will be skipped."
            }

            if ($DetachAttach -eq $true) {
                Write-Message -Level Verbose -Message "Checking access to remote directories."
                $remoteSourcePath = Join-AdminUNC $sourceFullComputerName (Get-SqlDefaultPaths -SqlInstance $sourceServer -filetype data)

                if ((Test-Path $remoteSourcePath) -ne $true -and $DetachAttach) {
                    Write-Message -Level Warning -Message "Can't access remote Sql directories on $source which is required to perform detach/copy/attach."
                    Write-Message -Level Warning -Message "You can manually try accessing $remoteSourcePath to diagnose any issues."
                    Stop-Function -Message "Halting database migration"
                    return
                }

                $remoteDestPath = Join-AdminUNC $destFullComputerName (Get-SqlDefaultPaths -SqlInstance $destServer -filetype data)
                If ((Test-Path $remoteDestPath) -ne $true -and $DetachAttach) {
                    Write-Message -Level Warning -Message "Can't access remote Sql directories on $destinstance which is required to perform detach/copy/attach."
                    Write-Message -Level Warning -Message "You can manually try accessing $remoteDestPath to diagnose any issues."
                    Stop-Function -Message "Halting database migration" -Continue
                }
            }

            if (($Database -or $ExcludeDatabase -or $IncludeSupportDbs) -and (!$DetachAttach -and !$BackupRestore)) {
                Stop-Function -Message "You did not select a migration method. Please use -BackupRestore or -DetachAttach."
                return
            }

            if ((!$Database -and !$AllDatabases -and !$IncludeSupportDbs) -and ($DetachAttach -or $BackupRestore)) {
                Stop-Function -Message "You did not select any databases to migrate. Please use -AllDatabases or -Database or -IncludeSupportDbs."
                return
            }

            Write-Message -Level Verbose -Message "Building database list."
            $databaseList = New-Object System.Collections.ArrayList
            $SupportDBs = "ReportServer", "ReportServerTempDB", "distribution", "SSISDB"
            foreach ($currentdb in ($sourceServer.Databases | Where-Object IsAccessible)) {
                $dbName = $currentdb.Name
                $dbOwner = $currentdb.Owner

                if ($currentdb.Id -le 4) {
                    continue
                }
                if ($Database -and $Database -notcontains $dbName) {
                    continue
                }
                if ($IncludeSupportDBs -eq $false -and $SupportDBs -contains $dbName) {
                    continue
                }
                if ($IncludeSupportDBs -eq $true -and $SupportDBs -notcontains $dbName) {
                    if ($AllDatabases -eq $false -and $Database.length -eq 0) {
                        continue
                    }
                }
                $null = $databaseList.Add($currentdb)
            }

            Write-Message -Level Verbose -Message "Performing count."
            $dbCount = $databaseList.Count

            if ((Test-Bound 'NewName') -and $dbCount -gt 1) {
                Stop-Function -Message "Cannot use NewName when copying multiple databases"
                return
            }


            Write-Message -Level Verbose -Message "Building file structure inventory for $dbCount databases."

            if ($sourceServer.VersionMajor -eq 8) {
                $sql = "SELECT DB_NAME (dbid) AS dbname, name, filename, CASE WHEN groupid = 0 THEN 'LOG' ELSE 'ROWS' END AS filetype FROM sysaltfiles"
            } else {
                $sql = "SELECT db.Name AS dbname, type_desc AS FileType, mf.Name, Physical_Name AS filename FROM sys.master_files mf INNER JOIN sys.databases db ON db.database_id = mf.database_id"
            }

            $dbFileTable = $sourceServer.Databases['master'].ExecuteWithResults($sql)

            if ($destServer.VersionMajor -eq 8) {
                $sql = "SELECT DB_NAME (dbid) AS dbname, name, filename, CASE WHEN groupid = 0 THEN 'LOG' ELSE 'ROWS' END AS filetype FROM sysaltfiles"
            } else {
                $sql = "SELECT db.Name AS dbname, type_desc AS FileType, mf.Name, Physical_Name AS filename FROM sys.master_files mf INNER JOIN sys.databases db ON db.database_id = mf.database_id"
            }

            $remoteDbFileTable = $destServer.Databases['master'].ExecuteWithResults($sql)

            $fileStructure = Get-SqlFileStructure -sourceserver $sourceServer -destserver $destServer -databaselist $databaseList -ReuseSourceFolderStructure $ReuseSourceFolderStructure

            $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
            $started = Get-Date
            $script:TimeNow = (Get-Date -UFormat "%m%d%Y%H%M%S")

            if ($AllDatabases -or $ExcludeDatabase -or $IncludeSupportDbs -or $Database) {
                foreach ($currentdb in $databaseList) {
                    $dbName = $currentdb.Name
                    $dbOwner = $currentdb.Owner
                    $destinationDbName = $dbName
                    if ((Test-Bound "NewName")) {
                        Write-Message -Level Verbose -Message "NewName specified, copying $dbName as $NewName"
                        $destinationDbName = $NewName
                        $replaceInFile = $True
                    }
                    if ($(Test-Bound "Prefix")) {
                        $destinationDbName = $prefix + $destinationDbName
                        Write-Message -Level Verbose -Message "Prefix supplied, copying $dbName as $destinationDbName"
                    }

                    $filestructure.databases[$dbName].Add('destinationDbName', $destinationDbName)
                    ForEach ($key in $filestructure.databases[$dbName].Destination.Keys) {
                        $splitFileName = Split-Path $fileStructure.databases[$dbName].Destination[$key].remotefilename -Leaf
                        $SplitPath = Split-Path $fileStructure.databases[$dbName].Destination[$key].remotefilename
                        if ($replaceInFile) {
                            $splitFileName = $splitFileName.replace($dbName, $destinationDbName)
                        }
                        $splitFileName = $prefix + $splitFileName
                        $filestructure.databases[$dbName].Destination.$key.remotefilename = Join-DbaPath -Path $SplitPath -ChildPath $splitFileName
                        $splitFileName = Split-Path $filestructure.databases[$dbName].Destination[$key].physical -Leaf
                        $SplitPath = Split-Path $fileStructure.databases[$dbName].Destination[$key].physical
                        if ($replaceInFile) {
                            $splitFileName = $splitFileName.replace($dbName, $destinationDbName)
                        }
                        $splitFileName = $prefix + $splitFileName
                        $filestructure.databases[$dbName].Destination.$key.physical = Join-DbaPath -Path $SplitPath -ChildPath $splitFileName
                    }

                    $copyDatabaseStatus = [PSCustomObject]@{
                        SourceServer        = $sourceServer.Name
                        DestinationServer   = $destServer.Name
                        Name                = $dbName
                        DestinationDatabase = $destinationDbName
                        Type                = "Database"
                        Status              = $null
                        Notes               = $null
                        DateTime            = [DbaDateTime](Get-Date)
                    }

                    Write-Message -Level Verbose -Message "`n######### Database: $dbName #########"
                    $dbStart = Get-Date

                    if ($ExcludeDatabase -contains $dbName) {
                        Write-Message -Level Verbose -Message "$dbName excluded. Skipping."
                        continue
                    }

                    Write-Message -Level Verbose -Message "Checking for accessibility."
                    if ($currentdb.IsAccessible -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Skipping $dbName. Database is inaccessible.")) {
                            Write-Message -Level Verbose -Message "Skipping $dbName. Database is inaccessible."

                            $copyDatabaseStatus.Status = "Skipped"
                            $copyDatabaseStatus.Notes = "Database is not accessible"
                            $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }
                        continue
                    }

                    if ($fsWarning) {
                        $fsRows = $dbFileTable.Tables[0].Select("dbname = '$dbName' and FileType = 'FileStream'")

                        if ($fsRows.Count -gt 0) {
                            if ($Pscmdlet.ShouldProcess($destinstance, "Skipping $dbName (contains FILESTREAM).")) {
                                Write-Message -Level Verbose -Message "Skipping $dbName (contains FILESTREAM)."
                                $copyDatabaseStatus.Status = "Skipped"
                                $copyDatabaseStatus.Notes = "Contains FILESTREAM"
                                $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            }
                            continue
                        }
                    }

                    if ($ReuseSourceFolderStructure) {
                        $fgRows = $dbFileTable.Tables[0].Select("dbname = '$dbName' and FileType = 'ROWS'")[0]
                        $remotePath = Split-Path $fgRows.Filename

                        if (!(Test-DbaPath -SqlInstance $destServer -Path $remotePath)) {
                            if ($Pscmdlet.ShouldProcess($destinstance, "$remotePath does not exist on $destinstance and ReuseSourceFolderStructure was specified")) {
                                # Stop-Function -Message "Cannot resolve $remotePath on $source. `n`nYou have specified ReuseSourceFolderStructure and exact folder structure does not exist. Halting script."
                                $copyDatabaseStatus.Status = "Failed"
                                $copyDatabaseStatus.Notes = "$remotePath does not exist on $destinstance and ReuseSourceFolderStructure was specified" #"Can't resolve $remotePath"
                                $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            }
                            continue
                        }
                    }

                    Write-Message -Level Verbose -Message "Checking Availability Group status."
                    if ($currentdb.AvailabilityGroupName -and !$force -and $DetachAttach) {
                        $agName = $currentdb.AvailabilityGroupName
                        Write-Message -Level Verbose -Message "Database is part of an Availability Group ($agName). Use -Force to drop from $agName and migrate. Alternatively, you can use the safer backup/restore method."
                        continue
                    }

                    $dbStatus = $currentdb.Status.ToString()

                    if ($dbStatus.StartsWith("Normal") -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "$dbName is not in a Normal state. Skipping.")) {
                            Write-Message -Level Verbose -Message "$dbName is not in a Normal state. Skipping."

                            $copyDatabaseStatus.Status = "Skipped"
                            $copyDatabaseStatus.Notes = "Not in normal state"
                            $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }
                        continue
                    }

                    if ($currentdb.ReplicationOptions -ne "None" -and $DetachAttach -eq $true) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "$dbName is part of replication. Skipping.")) {
                            Write-Message -Level Verbose -Message "$dbName is part of replication. Skipping."

                            $copyDatabaseStatus.Status = "Skipped"
                            $copyDatabaseStatus.Notes = "Part of replication"
                            $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }
                        continue
                    }

                    if ($currentdb.IsMirroringEnabled -and !$force -and $DetachAttach) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Database is being mirrored. Use -Force to break mirror and migrate. Alternatively, you can use the safer backup/restore method.")) {
                            Write-Message -Level Verbose -Message "Database is being mirrored. Use -Force to break mirror and migrate. Alternatively, you can use the safer backup/restore method."

                            $copyDatabaseStatus.Status = "Skipped"
                            $copyDatabaseStatus.Notes = "Database is mirrored"
                            $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }

                        continue
                    }

                    if (($null -ne $destServer.Databases[$destinationDbName]) -and !$force -and !$WithReplace -and !$Continue) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "$destinationDbName exists at destination. Use -Force to drop and migrate. Aborting routine for this database.")) {
                            Write-Message -Level Verbose -Message "$destinationDbName exists at destination. Use -Force to drop and migrate. Aborting routine for this database."

                            $copyDatabaseStatus.Status = "Skipped"
                            $copyDatabaseStatus.Notes = "Already exists on destination"
                            $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }
                        continue
                    } elseif ($null -ne $destServer.Databases[$destinationDbName] -and $force) {
                        if ($sourceServer.Name -eq $destServer.Name -and $dbName -eq $destinationDbName) {
                            Write-Message -Level Verbose -Message "Source and destination database are the same. Aborting routine for this database."
                            $copyDatabaseStatus.Status = "Failed"
                            $copyDatabaseStatus.Notes = "Source and destination database are the same."
                            $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            continue
                        }
                        if ($Pscmdlet.ShouldProcess($destinstance, "DROP DATABASE $destinationDbName")) {
                            Write-Message -Level Verbose -Message "$destinationDbName already exists. -Force was specified. Dropping $destinationDbName on $destinstance."
                            $removeresult = Remove-DbaDatabase -SqlInstance $destserver -Database $destinationDbName -Confirm:$false
                            $dropResult = $removeresult.Status -eq 'Dropped'

                            if ($dropResult -eq $false) {
                                Write-Message -Level Verbose -Message "Database could not be dropped. Aborting routine for this database."

                                $copyDatabaseStatus.Status = "Failed"
                                $copyDatabaseStatus.Notes = "Could not drop database"
                                $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                continue
                            }
                        }
                    }

                    if ($force) {
                        $WithReplace = $true
                    }

                    Write-Message -Level Verbose -Message "Started: $dbStart."

                    if ($sourceServer.VersionMajor -ge 9) {
                        $sourceDbOwnerChaining = $sourceServer.Databases[$dbName].DatabaseOwnershipChaining
                        $sourceDbTrustworthy = $sourceServer.Databases[$dbName].Trustworthy
                        $sourceDbBrokerEnabled = $sourceServer.Databases[$dbName].BrokerEnabled
                    }

                    $sourceDbReadOnly = $sourceServer.Databases[$dbName].ReadOnly

                    if ($SetSourceReadOnly) {
                        If ($Pscmdlet.ShouldProcess($source, "Set $dbName to read-only")) {
                            Write-Message -Level Verbose -Message "Setting database to read-only."
                            try {
                                $result = Set-DbaDbState -SqlInstance $sourceServer -Database $dbName -ReadOnly -EnableException -Force
                            } catch {
                                Stop-Function -Continue -Message "Couldn't set database to read-only. Aborting routine for this database" -ErrorRecord $_
                            }
                        }
                    }

                    if ($BackupRestore) {
                        if ($UseLastBackup) {
                            $whatifmsg = "Gathering last backup information for $dbName from $Source and restoring"
                        } else {
                            $whatifmsg = "Backup $dbName from $source and restoring"
                        }
                        If ($Pscmdlet.ShouldProcess($destinstance, $whatifmsg)) {
                            if ($UseLastBackup) {
                                if ($Continue) {
                                    $backupTmpResult = Get-DbaDbBackupHistory -SqlInstance $sourceServer -Database $dbName -IncludeCopyOnly -Last -IgnoreDiffBackup
                                } else {
                                    $backupTmpResult = Get-DbaDbBackupHistory -SqlInstance $sourceServer -Database $dbName -IncludeCopyOnly -Last
                                }
                                if (-not $backupTmpResult) {
                                    $copyDatabaseStatus.Type = "Database (BackupRestore)"
                                    $copyDatabaseStatus.Status = "Failed"
                                    $copyDatabaseStatus.Notes = "No backups for $dbName on $source"
                                    $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                    continue
                                }
                            } else {
                                $backupTmpResult = $backupCollection | Where-Object Database -eq $dbName
                                if (-not $backupTmpResult) {
                                    if ($SharedPath -like 'https*') {
                                        if ($AdvancedBackupParams) {
                                            $backupTmpResult = Backup-DbaDatabase -SqlInstance $sourceServer -Database $dbName -AzureBaseUrl $SharedPath -FileCount $numberfiles -CopyOnly:$CopyOnly -AzureCredential $AzureCredential @AdvancedBackupParams
                                        } else {
                                            $backupTmpResult = Backup-DbaDatabase -SqlInstance $sourceServer -Database $dbName -AzureBaseUrl $SharedPath -FileCount $numberfiles -CopyOnly:$CopyOnly -AzureCredential $AzureCredential
                                        }

                                    } else {
                                        if ($AdvancedBackupParams) {
                                            $backupTmpResult = Backup-DbaDatabase -SqlInstance $sourceServer -Database $dbName -BackupDirectory $SharedPath -FileCount $numberfiles -CopyOnly:$CopyOnly @AdvancedBackupParams
                                        } else {
                                            $backupTmpResult = Backup-DbaDatabase -SqlInstance $sourceServer -Database $dbName -BackupDirectory $SharedPath -FileCount $numberfiles -CopyOnly:$CopyOnly
                                        }
                                    }

                                    if ((-not $backupTmpResult) -or (-not $backupTmpResult.BackupComplete)) {
                                        $serviceAccount = $sourceServer.ServiceAccount
                                        Write-Message -Level Verbose -Message "Backup Failed. Does SQL Server account $serviceAccount have access to $($SharedPath)? Aborting routine for this database."

                                        $copyDatabaseStatus.Status = "Failed"
                                        $copyDatabaseStatus.Notes = "Backup failed. Verify service account access to $SharedPath."
                                        $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                        continue
                                    }

                                    $backupCollection += $backupTmpResult
                                }
                            }
                            Write-Message -Level Verbose -Message "Reuse = $ReuseSourceFolderStructure."
                            try {
                                $msg = $null
                                if ($miRestore) {
                                    $restoreResultTmp = $backupTmpResult | Restore-DbaDatabase -SqlInstance $destServer -DatabaseName $destinationDbName -TrustDbBackupHistory -WithReplace:$WithReplace -EnableException -AzureCredential $AzureCredential
                                } else {
                                    $restoreResultTmp = $backupTmpResult | Restore-DbaDatabase -SqlInstance $destServer -DatabaseName $destinationDbName -ReuseSourceFolderStructure:$ReuseSourceFolderStructure -NoRecovery:$NoRecovery -TrustDbBackupHistory -WithReplace:$WithReplace -Continue:$Continue -EnableException -ReplaceDbNameInFile -AzureCredential $AzureCredential -KeepCDC:$KeepCDC -KeepReplication:$KeepReplication
                                }
                            } catch {
                                $msg = $_.Exception.InnerException.InnerException.InnerException.InnerException.Message
                                Stop-Function -Message "Failure attempting to restore $dbName to $destinstance" -Exception $_.Exception.InnerException.InnerException.InnerException.InnerException
                            }
                            $restoreResult = $restoreResultTmp.RestoreComplete

                            if ($restoreResult -eq $true) {
                                Write-Message -Level Verbose -Message "Successfully restored $dbName to $destinstance."
                                $copyDatabaseStatus.Status = "Successful"
                            } else {
                                if ($ReuseSourceFolderStructure) {
                                    Write-Message -Level Verbose -Message "Failed to restore $dbName to $destinstance. You specified -ReuseSourceFolderStructure. Does the exact same destination directory structure exist?"
                                    Write-Message -Level Verbose -Message "Aborting routine for this database."

                                    $copyDatabaseStatus.Status = "Failed"
                                    $copyDatabaseStatus.Notes = "Failed to restore. ReuseSourceFolderStructure was specified, verify same directory structure exist on destination."
                                    $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                    continue
                                } else {
                                    Write-Message -Level Verbose -Message "Failed to restore $dbName to $destinstance. Aborting routine for this database."

                                    $copyDatabaseStatus.Status = "Failed"
                                    if (-not $msg) {
                                        $msg = "Failed to restore database"
                                    }
                                    $copyDatabaseStatus.Notes = $msg
                                    $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                    continue
                                }
                            }
                            if (-not $NoBackupCleanUp -and $Destination.Count -eq 1) {
                                foreach ($backupFile in ($backupTmpResult.BackupPath)) {
                                    try {
                                        Write-Message -Level Verbose -Message "Deleting $backupFile."
                                        Remove-Item $backupFile -ErrorAction Stop
                                    } catch {
                                        try {
                                            Write-Message -Level Verbose -Message "Trying alternate SQL method to delete $backupFile."
                                            $sql = "EXEC master.sys.xp_delete_file 0, '$backupFile'"
                                            Write-Message -Level Debug -Message $sql
                                            $null = $sourceServer.Query($sql)
                                        } catch {
                                            Write-Message -Level Verbose -Message "Cannot delete backup file $backupFile."

                                            # Set NoBackupCleanup so that there's a warning at the end
                                            $NoBackupCleanup = $true
                                        }
                                    }
                                }
                            }
                        }

                        if ($SetSourceReadOnly) {
                            If ($Pscmdlet.ShouldProcess($destServer.Name, "Set $dbName to read-write after source was set to read only")) {
                                try {
                                    $null = Set-DbaDbState -SqlInstance $destServer -Database $dbName -ReadWrite -EnableException -Force
                                } catch {
                                    Stop-Function -Message "Couldn't set $dbName to read-write on $($destserver.Name)" -ErrorRecord $_
                                }
                            }
                        }

                        $dbFinish = Get-Date
                        if ($NoRecovery -eq $false) {
                            If ($Pscmdlet.ShouldProcess($destServer.Name, "Setting db owner to $dbowner for $destinationDbName")) {
                                # needed because the newly restored database doesn't show up
                                $destServer.Databases.Refresh()
                                $dbOwner = $sourceServer.Databases[$dbName].Owner
                                if ($null -eq $dbOwner -or $destServer.Logins.Name -notcontains $dbOwner) {
                                    $dbOwner = Get-SaLoginName -SqlInstance $destServer
                                }
                                try {
                                    $null = $destServer.Query("ALTER DATABASE [$destinationDbName] SET READ_WRITE")
                                } catch {
                                    Stop-Function -Message "Failure setting $destinationDbName to read-write on destination server" -ErrorRecord $_
                                }
                            }
                        }
                    }

                    if ($DetachAttach) {

                        $copyDatabaseStatus.Type = "Database (DetachAttach)"

                        $sourceFileStructure = New-Object System.Collections.Specialized.StringCollection
                        foreach ($file in $fileStructure.Databases[$dbName].Source.Values) {
                            $null = $sourceFileStructure.Add($file.Physical)
                        }

                        $dbOwner = $sourceServer.Databases[$dbName].Owner

                        if ($null -eq $dbOwner -or $destServer.Logins.Name -notcontains $dbOwner) {
                            $dbOwner = Get-SaLoginName -SqlInstance $destServer
                        }

                        if ($Pscmdlet.ShouldProcess($destinstance, "Detach $dbName from $source and attach, then update dbowner")) {
                            $migrationResult = Start-SqlDetachAttach $sourceServer $destServer $fileStructure $dbName

                            $dbFinish = Get-Date

                            if ($reattach -eq $true) {
                                $sourceServer.Databases.Refresh()
                                $destServer.Databases.Refresh()
                                $result = Mount-SqlDatabase $sourceServer $dbName $sourceFileStructure $dbOwner

                                if ($result -eq $true) {
                                    $sourceServer.Databases[$dbName].DatabaseOwnershipChaining = $sourceDbOwnerChaining
                                    $sourceServer.Databases[$dbName].Trustworthy = $sourceDbTrustworthy
                                    $sourceServer.Databases[$dbName].BrokerEnabled = $sourceDbBrokerEnabled
                                    $sourceServer.Databases[$dbName].Alter()

                                    if ($SetSourceReadOnly -or $sourceDbReadOnly) {
                                        try {
                                            $result = Set-DbaDbState -SqlInstance $sourceServer -Database $dbName -ReadOnly -EnableException
                                        } catch {
                                            Stop-Function -Message "Couldn't set database to read-only" -ErrorRecord $_
                                        }
                                    }
                                    Write-Message -Level Verbose -Message "Successfully reattached $dbName to $source."
                                } else {
                                    Write-Message -Level Verbose -Message "Could not reattach $dbName to $source."
                                    $copyDatabaseStatus.Status = "Failed"
                                    $copyDatabaseStatus.Notes = "Could not reattach database to $source"
                                    $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                }
                            }

                            if ($migrationResult -eq $true) {
                                Write-Message -Level Verbose -Message "Successfully attached $dbName to $destinstance."
                                $copyDatabaseStatus.Status = "Successful"
                            } else {
                                Write-Message -Level Verbose -Message "Failed to attach $dbName to $destinstance. Aborting routine for this database."

                                $copyDatabaseStatus.Status = "Failed"
                                $copyDatabaseStatus.Notes = "Failed to attach database to destination"
                                $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                                continue
                            }
                        }
                    }
                    $NewDatabase = Get-DbaDatabase -SqlInstance $destServer -database $destinationDbName

                    $propfailures = @()

                    # restore potentially lost settings
                    if ($destServer.VersionMajor -ge 9 -and $NoRecovery -eq $false) {
                        if ($sourceDbOwnerChaining -ne $NewDatabase.DatabaseOwnershipChaining) {
                            if ($Pscmdlet.ShouldProcess($destinstance, "Updating DatabaseOwnershipChaining on $destinationDbName")) {
                                try {
                                    $NewDatabase.DatabaseOwnershipChaining = $sourceDbOwnerChaining
                                    $NewDatabase.Alter()
                                    Write-Message -Level Verbose -Message "Successfully updated DatabaseOwnershipChaining for $sourceDbOwnerChaining on $destinationDbName on $destinstance."
                                } catch {
                                    Write-Message -Level Warning -Message "Failed to update DatabaseOwnershipChaining for $sourceDbOwnerChaining on $destinationDbName on $destinstance."
                                    $propfailures += "Ownership chaining"
                                }
                            }
                        }

                        if ($sourceDbTrustworthy -ne $NewDatabase.Trustworthy) {
                            if ($Pscmdlet.ShouldProcess($destinstance, "Updating Trustworthy on $destinationDbName")) {
                                try {
                                    $NewDatabase.Trustworthy = $sourceDbTrustworthy
                                    $NewDatabase.Alter()
                                    Write-Message -Level Verbose -Message "Successfully updated Trustworthy to $sourceDbTrustworthy for $destinationDbName on $destinstance"
                                } catch {
                                    Write-Message -Level Warning -Message "Failed to update Trustworthy to $sourceDbTrustworthy for $destinationDbName on $destinstance."
                                    $propfailures += "Trustworthy"
                                }
                            }
                        }

                        if ($sourceDbBrokerEnabled -ne $NewDatabase.BrokerEnabled) {
                            if ($Pscmdlet.ShouldProcess($destinstance, "Updating BrokerEnabled on $destinationDbName")) {
                                try {
                                    $NewDatabase.BrokerEnabled = $sourceDbBrokerEnabled
                                    $NewDatabase.Alter()
                                    Write-Message -Level Verbose -Message "Successfully updated BrokerEnabled to $sourceDbBrokerEnabled for $destinationDbName on $destinstance."
                                } catch {
                                    try {
                                        Write-Message -Level Verbose -Message "Updating BrokerEnabled to $sourceDbBrokerEnabled for $destinationDbName on $destinstance failed so we try to regenerate the broker identifier."
                                        $quotedDatabaseName = $destserver.Query("SELECT QUOTENAME('$($destinationDbName.Replace("'", "''"))') AS quotename").quotename
                                        $null = $destserver.Query("ALTER DATABASE $quotedDatabaseName SET NEW_BROKER WITH ROLLBACK IMMEDIATE")
                                        $NewDatabase.BrokerEnabled = $sourceDbBrokerEnabled
                                        $null = $NewDatabase.Alter()
                                        Write-Message -Level Verbose -Message "Successfully updated BrokerEnabled to $sourceDbBrokerEnabled for $destinationDbName on $destinstance."
                                    } catch {
                                        Write-Message -Level Warning -Message "Failed to update BrokerEnabled to $sourceDbBrokerEnabled for $destinationDbName on $destinstance."
                                        $propfailures += "Message broker"
                                    }
                                }
                            }
                        }
                    }

                    if ($sourceDbReadOnly -ne $NewDatabase.ReadOnly -and -not $NoRecovery) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Updating ReadOnly status on $destinationDbName")) {
                            try {
                                if ($sourceDbReadOnly) {
                                    $result = Set-DbaDbState -SqlInstance $destserver -Database $destinationDbName -ReadOnly -EnableException
                                } else {
                                    $result = Set-DbaDbState -SqlInstance $destserver -Database $destinationDbName -ReadWrite -EnableException
                                }
                            } catch {
                                Write-Message -Level Verbose -Message "Failed to update ReadOnly status on $destinationDbName."
                                $propfailures = "Read only"
                            }
                        }
                    }

                    if ($Pscmdlet.ShouldProcess("console", "Outputting object")) {
                        if ($propfailures.Count -gt 0) {
                            $propfailure = $propfailures -join ", "
                            $copyDatabaseStatus.Notes = "Failed to apply the following properties: $propfailure"
                        }

                        $copyDatabaseStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }

                    if ($SetSourceOffline -and $copyDatabaseStatus.Status -eq "Successful" -and $sourceServer.databases[$dbName].status -notlike '*offline*') {
                        if ($Pscmdlet.ShouldProcess($source, "Setting $dbName offline")) {
                            Set-DbaDbState -SqlInstance $sourceServer -Database $dbName -Offline -Force
                        }
                    }

                    $dbTotalTime = $dbFinish - $dbStart
                    $dbTotalTime = ($dbTotalTime.ToString().Split(".")[0])

                    Write-Message -Level Verbose -Message "Finished: $dbFinish."
                    Write-Message -Level Verbose -Message "Elapsed time: $dbTotalTime."

                } # end db by db processing
            }
        }
    }
    end {
        if (Test-FunctionInterrupt) {
            return
        }
        if (-not $NoBackupCleanUp -and $Destination.Count -gt 1) {
            foreach ($backupFile in ($backupCollection.BackupPath)) {
                try {
                    if (Test-Path $backupFile -ErrorAction Stop) {
                        Write-Message -Level Verbose -Message "Deleting $backupFile."
                        Remove-Item $backupFile -ErrorAction Stop
                    }
                } catch {
                    try {
                        Write-Message -Level Verbose -Message "Trying alternate SQL method to delete $backupFile."
                        $sql = "EXEC master.sys.xp_delete_file 0, '$backupFile'"
                        Write-Message -Level Debug -Message $sql
                        $null = $sourceServer.Query($sql)
                    } catch {
                        Write-Message -Level Verbose -Message "Cannot delete backup file $backupFile."
                    }
                }
            }
        }
        if (Test-FunctionInterrupt) {
            return
        }
        if ($null -ne $elapsed) {
            $totalTime = ($elapsed.Elapsed.toString().Split(".")[0])

            Write-Message -Level Verbose -Message "`nDatabase migration finished"
            Write-Message -Level Verbose -Message "Migration started: $started"
            Write-Message -Level Verbose -Message "Migration completed: $(Get-Date)"
            Write-Message -Level Verbose -Message "Total Elapsed time: $totalTime"

            if ($SharedPath -and $NoBackupCleanup) {
                Write-Message -Level Verbose -Message "Backups still exist at $SharedPath."
            }
        } else {
            Write-Message -Level Verbose -Message "No work was done, as we stopped during setup phase"
        }
    }
}