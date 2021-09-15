function Format-DbaBackupInformation {
    <#
    .SYNOPSIS
        Transforms the data in a dbatools BackupHistory object for a restore

    .DESCRIPTION
        Performs various mapping on Backup History, ready restoring
        Options include changing restore paths, backup paths, database name and many others

    .PARAMETER BackupHistory
        A dbatools backupHistory object, normally this will have been created using Select-DbaBackupInformation

    .PARAMETER ReplaceDatabaseName
        If a single value is provided, this will be replaced do all occurrences a database name
        If a Hashtable is passed in, each database name mention will be replaced as specified. If a database's name does not appear it will not be replace
        DatabaseName will also be replaced where it  occurs in the file paths of data and log files.
        Please note, that this won't change the Logical Names of data files, that has to be done with a separate Alter DB call

    .PARAMETER DatabaseNamePrefix
        This string will be prefixed to all restored database's name

    .PARAMETER DataFileDirectory
        This will move ALL restored files to this location during the restore

    .PARAMETER LogFileDirectory
        This will move all log files to this location, overriding DataFileDirectory

    .PARAMETER DestinationFileStreamDirectory
        This move the FileStream folder and contents to the new location, overriding DataFileDirectory

    .PARAMETER FileNamePrefix
        This string will  be prefixed to all restored files (Data and Log)

    .PARAMETER RebaseBackupFolder
        Use this to rebase where your backups are stored.

    .PARAMETER Continue
        Indicates that this is a continuing restore

    .PARAMETER DatabaseFilePrefix
        A string that will be prefixed to every file restored

    .PARAMETER DatabaseFileSuffix
        A string that will be suffixed to every file restored

    .PARAMETER ReplaceDbNameInFile
        If set, will replace the old database name with the new name if it occurs in the file name

    .PARAMETER FileMapping
        A hashtable that can be used to move specific files to a location.
        `$FileMapping = @{'DataFile1'='c:\restoredfiles\Datafile1.mdf';'DataFile3'='d:\DataFile3.mdf'}`
        And files not specified in the mapping will be restored to their original location
        This Parameter is exclusive with DestinationDataDirectory
        If specified, this will override any other file renaming/relocation options.

    .PARAMETER PathSep
        By default is Windows's style (`\`) but you can pass also, e.g., `/` for Unix's style paths

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

    .EXAMPLE
        PS C:\> $History | Format-DbaBackupInformation -ReplaceDatabaseName NewDb

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
                    if ($ReplaceDbNameInFile -eq $true) {
                        $_.PhysicalName = $_.PhysicalName -Replace $History.OriginalDatabase, $History.Database
                    }
                    Write-Message -Message " 1 PhysicalName = $($_.PhysicalName) " -Level Verbose
                    $Pname = [System.Io.FileInfo]$_.PhysicalName
                    $RestoreDir = $Pname.DirectoryName
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

                    $_.PhysicalName = $RestoreDir + $PathSep + $DatabaseFilePrefix + $Pname.BaseName + $DatabaseFileSuffix + $Pname.extension
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