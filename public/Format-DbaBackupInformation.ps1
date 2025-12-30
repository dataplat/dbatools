function Format-DbaBackupInformation {
    <#
    .SYNOPSIS
        Modifies backup history metadata to prepare database restores with different names, paths, or locations

    .DESCRIPTION
        Takes backup history objects from Select-DbaBackupInformation and transforms them for restore scenarios where you need to change database names, file locations, or backup paths. This is essential for disaster recovery situations where you're restoring to different servers, renaming databases, or moving files to new storage locations. The function handles all the metadata transformations needed so you don't have to manually edit restore paths and database references before running Restore-DbaDatabase.

    .PARAMETER BackupHistory
        Backup history objects from Select-DbaBackupInformation that contain metadata about database backups.
        Use this to pass backup information that needs to be modified for restore operations to different locations or with different names.

    .PARAMETER ReplaceDatabaseName
        Changes the database name in backup history to prepare for restoring with a different name. Pass a single string to rename one database, or a hashtable to map multiple old names to new names.
        Use this when restoring databases to different environments or creating copies with new names.
        Database names in file paths are also updated, but logical file names require separate ALTER DATABASE commands after restore.

    .PARAMETER DatabaseNamePrefix
        Adds a prefix to all database names during the restore operation. The prefix is applied after any name replacements from ReplaceDatabaseName.
        Use this to create standardized naming conventions like adding environment identifiers (Dev_, Test_, etc.) to restored databases.

    .PARAMETER DataFileDirectory
        Sets the destination directory for all data files during restore. This overrides the original file locations stored in the backup.
        Use this when restoring to servers with different drive configurations or when consolidating database files to specific storage locations.

    .PARAMETER LogFileDirectory
        Sets the destination directory specifically for transaction log files during restore. This takes precedence over DataFileDirectory for log files only.
        Use this to place log files on separate storage from data files for performance optimization or storage management requirements.

    .PARAMETER DestinationFileStreamDirectory
        Sets the destination directory for FileStream data files during restore. This takes precedence over DataFileDirectory for FileStream files only.
        Use this when databases contain FileStream data that needs to be stored on specific storage optimized for large file handling.

    .PARAMETER DatabaseFilePrefix
        Adds a prefix to the physical file names of all restored database files (both data and log files).
        Use this to avoid file name conflicts when restoring to servers that already have files with the same names.

    .PARAMETER RebaseBackupFolder
        Changes the path where SQL Server will look for backup files during the restore operation.
        Use this when backup files have been moved to a different location since the backup was created, such as copying backups to a disaster recovery site.

    .PARAMETER Continue
        Marks this as part of an ongoing restore sequence that will have additional transaction log backups applied later.
        Use this when performing point-in-time recovery scenarios where you need to restore a full backup followed by multiple log backups.

    .PARAMETER DatabaseFileSuffix
        Adds a suffix to the physical file names of all restored database files (both data and log files).
        Use this to create unique file names when restoring multiple copies of the same database or to add version identifiers to restored files.

    .PARAMETER ReplaceDbNameInFile
        Replaces occurrences of the original database name within physical file names with the new database name.
        Use this in combination with ReplaceDatabaseName to ensure file names match the new database name and avoid confusion during restore operations.

    .PARAMETER FileMapping
        Maps specific logical file names to custom physical file paths during restore. Use hashtable format like @{'LogicalName1'='C:\NewPath\file1.mdf'}.
        Use this when you need granular control over where individual database files are restored, overriding directory-based parameters.
        Files not specified in the mapping retain their original locations, and this parameter takes precedence over all other file location settings.

    .PARAMETER PathSep
        Specifies the path separator character for file paths. Defaults to backslash (\) for Windows.
        Use forward slash (/) when working with Linux SQL Server instances or when backup history contains Unix-style paths.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DisasterRecovery, Backup, Restore
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Format-DbaBackupInformation

    .OUTPUTS
        Dataplat.Dbatools.Database.BackupHistory

        Returns the modified backup history objects with updated metadata for restore operations. The same number of objects that were passed in are returned, with any requested modifications applied.

        Default properties (from input backup history object):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The database name (modified if -ReplaceDatabaseName or -DatabaseNamePrefix was used)
        - UserName: The user who performed the backup
        - Start: DateTime when the backup started
        - End: DateTime when the backup completed
        - Duration: TimeSpan of the backup operation
        - Path: Array of backup file paths (modified if -RebaseBackupFolder was used)
        - FileList: Array of file objects containing Type, LogicalName, PhysicalName, and Size (modified if -DataFileDirectory, -LogFileDirectory, -DestinationFileStreamDirectory, -DatabaseFilePrefix, -DatabaseFileSuffix, -ReplaceDbNameInFile, or -FileMapping was used)
        - TotalSize: Total size of the backup in bytes
        - CompressedBackupSize: Size of compressed backup in bytes
        - Type: Backup type (Database, Database Differential, or Transaction Log)
        - BackupSetId: Unique identifier for the backup set (GUID)
        - DeviceType: Type of backup device (typically Disk)
        - FullName: Array of full paths to backup files (modified if -RebaseBackupFolder was used)
        - Position: Position of the backup within the device
        - FirstLsn: First Log Sequence Number in this backup
        - DatabaseBackupLsn: Log Sequence Number of the database backup
        - CheckpointLSN: Checkpoint Log Sequence Number
        - LastLsn: Last Log Sequence Number in this backup
        - SoftwareVersionMajor: Major version of SQL Server that created the backup
        - RecoveryModel: Database recovery model at time of backup
        - IsCopyOnly: Boolean indicating if this is a copy-only backup

        Additional properties added by this function:
        - OriginalDatabase: String containing the original database name before any replacements or prefixes
        - OriginalFileList: Object array containing the original FileList before any path modifications
        - OriginalFullName: String array containing the original backup file paths before rebasing
        - IsVerified: Boolean indicating if the backup has been verified (initialized to $False)

        All properties from the input backup history objects are preserved and accessible, with selective properties modified based on the parameters specified.

    .EXAMPLE
        PS C:\> $History | Format-DbaBackupInformation -ReplaceDatabaseName NewDb -ReplaceDbNameInFile

        Changes as database name references to NewDb, both in the database name and any restore paths. Note, this will fail if the BackupHistory object contains backups for more than 1 database

    .EXAMPLE
        PS C:\> $History | Format-DbaBackupInformation -ReplaceDatabaseName @{'OldB'='NewDb';'ProdHr'='DevHr'}

        Will change all occurrences of original database name in the backup history (names and restore paths) using the mapping in the hashtable.
        In this example any occurrence of OldDb will be replaced with NewDb and ProdHr with DevPR

    .EXAMPLE
        PS C:\> $History | Format-DbaBackupInformation -DataFileDirectory 'D:\DataFiles\' -LogFileDirectory 'E:\LogFiles\

        This example with change the restore path for all data files (everything that is not a log file) to d:\datafiles
        And all Transaction Log files will be restored to E:\Logfiles

    .EXAMPLE
        PS C:\> $History | Format-DbaBackupInformation -RebaseBackupFolder f:\backups

        This example changes the location that SQL Server will look for the backups. This is useful if you've moved the backups to a different location

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [object[]]$BackupHistory,
        [object]$ReplaceDatabaseName,
        [switch]$ReplaceDbNameInFile,
        [string]$DataFileDirectory,
        [string]$LogFileDirectory,
        [string]$DestinationFileStreamDirectory,
        [string]$DatabaseNamePrefix,
        [string]$DatabaseFilePrefix,
        [string]$DatabaseFileSuffix,
        [string]$RebaseBackupFolder,
        [switch]$Continue,
        [hashtable]$FileMapping,
        [string]$PathSep = '\',
        [switch]$EnableException
    )
    begin {

        Write-Message -Message "Starting" -Level Verbose
        if ($null -ne $ReplaceDatabaseName) {
            if ($ReplaceDatabaseName -is [string] -or $ReplaceDatabaseName.ToString() -ne 'System.Collections.Hashtable') {
                Write-Message -Message "String passed in for DB rename" -Level Verbose
                $ReplaceDatabaseNameType = 'single'
            } elseif ($ReplaceDatabaseName -is [HashTable] -or $ReplaceDatabaseName.ToString() -eq 'System.Collections.Hashtable' ) {
                Write-Message -Message "Hashtable passed in for DB rename" -Level Verbose
                $ReplaceDatabaseNameType = 'multi'
            } else {
                Write-Message -Message "ReplacemenDatabaseName is $($ReplaceDatabaseName.Gettype().ToString()) - $ReplaceDatabaseName" -level Verbose
            }
        }
        if ((Test-Bound -Parameter DataFileDirectory) -and $DataFileDirectory.EndsWith($PathSep)) {
            $DataFileDirectory = $DataFileDirectory -Replace '.$'
        }
        if ((Test-Bound -Parameter DestinationFileStreamDirectory) -and $DestinationFileStreamDirectory.EndsWith($PathSep) ) {
            $DestinationFileStreamDirectory = $DestinationFileStreamDirectory -Replace '.$'
        }
        if ((Test-Bound -Parameter LogFileDirectory) -and $LogFileDirectory.EndsWith($PathSep) ) {
            $LogFileDirectory = $LogFileDirectory -Replace '.$'
        }
        if ((Test-Bound -Parameter RebaseBackupFolder) -and $RebaseBackupFolder.EndsWith($PathSep) ) {
            $RebaseBackupFolder = $RebaseBackupFolder -Replace '.$'
        }
    }


    process {

        foreach ($History in $BackupHistory) {
            if ("OriginalDatabase" -notin $History.PSobject.Properties.name) {
                $History | Add-Member -Name 'OriginalDatabase' -Type NoteProperty -Value $History.Database
            }
            if ("OriginalFileList" -notin $History.PSobject.Properties.name) {
                $History | Add-Member -Name 'OriginalFileList' -Type NoteProperty -Value ''
                $History | ForEach-Object { $_.OriginalFileList = $_.FileList }
            }
            if ("OriginalFullName" -notin $History.PSobject.Properties.name) {
                $History | Add-Member -Name 'OriginalFullName' -Type NoteProperty -Value $History.FullName
            }
            if ("IsVerified" -notin $History.PSobject.Properties.name) {
                $History | Add-Member -Name 'IsVerified' -Type NoteProperty -Value $False
            }
            switch ($History.Type) {
                'Full' { $History.Type = 'Database' }
                'Differential' { $History.Type = 'Database Differential' }
                'Log' { $History.Type = 'Transaction Log' }
            }


            if ($ReplaceDatabaseNameType -eq 'single' -and $ReplaceDatabaseName -ne '' ) {
                $History.Database = $ReplaceDatabaseName
                Write-Message -Message "New DbName (String) = $($History.Database)" -Level Verbose
            } elseif ($ReplaceDatabaseNameType -eq 'multi') {
                if ($null -ne $ReplaceDatabaseName[$History.Database]) {
                    $History.Database = $ReplaceDatabaseName[$History.Database]
                    Write-Message -Message "New DbName (Hash) = $($History.Database)" -Level Verbose
                }
            }
            $History.Database = $DatabaseNamePrefix + $History.Database

            $History.FileList | ForEach-Object {
                if ($null -ne $FileMapping ) {
                    if ($null -ne $FileMapping[$_.LogicalName]) {
                        $_.PhysicalName = $FileMapping[$_.LogicalName]
                    }
                } else {
                    Write-Message -Message " 1 PhysicalName = $($_.PhysicalName) " -Level Verbose

                    # Instead of using [System.IO.FileInfo] which has cross-platform issues,
                    # manually parse the path using both separators to handle Windows paths on Linux and vice versa
                    $originalPath = $_.PhysicalName

                    # Get just the filename by splitting on both separators
                    $fileName = $originalPath -split '[/\\]' | Select-Object -Last 1
                    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                    $extension = [System.IO.Path]::GetExtension($fileName)

                    # Handle MacOS returning full path for BaseName
                    $baseName = $baseName.Split($PathSep)[-1]

                    if ($ReplaceDbNameInFile -eq $true) {
                        $baseName = $baseName -Replace $History.OriginalDatabase, $History.Database
                    }

                    # Determine restore directory based on file type
                    $RestoreDir = $null
                    if ($_.Type -eq 'D' -or $_.FileType -eq 'D') {
                        if ('' -ne $DataFileDirectory) {
                            $RestoreDir = $DataFileDirectory
                        }
                    } elseif ($_.Type -eq 'L' -or $_.FileType -eq 'L') {
                        if ('' -ne $LogFileDirectory) {
                            $RestoreDir = $LogFileDirectory
                        } elseif ('' -ne $DataFileDirectory) {
                            $RestoreDir = $DataFileDirectory
                        }
                    } elseif ($_.Type -eq 'S' -or $_.FileType -eq 'S') {
                        if ('' -ne $DestinationFileStreamDirectory) {
                            $RestoreDir = $DestinationFileStreamDirectory
                        } elseif ('' -ne $DataFileDirectory) {
                            $RestoreDir = $DataFileDirectory
                        }
                    }

                    # Fallback to extracting directory from original path if no destination specified
                    if ($null -eq $RestoreDir) {
                        $RestoreDir = $originalPath -replace '[/\\][^/\\]+$', ''
                    }

                    $_.PhysicalName = $RestoreDir + $PathSep + $DatabaseFilePrefix + $baseName + $DatabaseFileSuffix + $extension
                    Write-Message -Message "PhysicalName = $($_.PhysicalName) " -Level Verbose
                }
            }
            if ('' -ne $RebaseBackupFolder -and $History.FullName[0] -notmatch 'http') {
                Write-Message -Message 'Rebasing backup files' -Level Verbose

                for ($j = 0; $j -lt $History.fullname.count; $j++) {
                    $file = [System.IO.FileInfo]($History.fullname[$j])
                    $History.fullname[$j] = $RebaseBackupFolder + $PathSep + $file.BaseName + $file.Extension
                }

            }

            $History
        }
    }
}