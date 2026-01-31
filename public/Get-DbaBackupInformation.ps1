function Get-DbaBackupInformation {
    <#
    .SYNOPSIS
        Scans backup files and reads their headers to create structured backup history objects for restore operations

    .DESCRIPTION
        Reads the headers of SQL Server backup files to extract metadata and creates BackupHistory objects compatible with Restore-DbaDatabase. This eliminates the need to manually track backup chains and file locations when planning database restores.

        The function identifies valid SQL Server backup files from a given path, reads their headers using the SQL Server instance, and organizes them into backup sets. It handles full, differential, and log backups, automatically determining backup types, LSN chains, and file dependencies.

        By default, the function uses xp_dirtree to scan remote paths accessible to the SQL Server instance. This means paths must be accessible from the SQL Server service account. The -NoXpDirTree switch allows scanning local files instead.

        Special support is included for Ola Hallengren maintenance solution backup folder structures, which can significantly speed up scanning of organized backup directories.

    .PARAMETER Path
        Path to SQL Server backup files.

        Paths passed in as strings will be scanned using the desired method, default is a non recursive folder scan
        Accepts multiple paths separated by ','

        Or it can consist of FileInfo objects, such as the output of Get-ChildItem or Get-Item. This allows you to work with
        your own file structures as needed

    .PARAMETER SqlInstance
        The SQL Server instance to be used to read the headers of the backup files

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER DatabaseName
        An array of Database Names to filter by. If empty all databases are returned.

    .PARAMETER SourceInstance
        If provided only backup originating from this destination will be returned. This SQL instance will not be connected to or involved in this work

    .PARAMETER NoXpDirTree
        If specified, this switch will cause the files to be parsed as local files to the SQL Server Instance provided. Errors may be observed when the SQL Server Instance cannot access the files being parsed.

    .PARAMETER NoXpDirRecurse
        If specified, this switch changes xp_dirtree behavior to not recurse the folder structure.

    .PARAMETER DirectoryRecurse
        If specified the provided path/directory will be traversed (only applies if not using XpDirTree)

    .PARAMETER Anonymise
        If specified we will output the results with ComputerName, InstanceName, Database, UserName, Paths, and Logical and Physical Names hashed out
        This options is mainly for use if we need you to submit details for fault finding to the dbatools team

    .PARAMETER ExportPath
        If specified the output will export via CliXml format to the specified file. This allows you to store the backup history object for later usage, or move it between computers

    .PARAMETER NoClobber
        If specified will stop Export from overwriting an existing file, the default is to overwrite

    .PARAMETER PassThru
        When data is exported the cmdlet will return no other output, this switch means it will also return the normal output which can be then piped into another command

    .PARAMETER MaintenanceSolution
        This switch tells the function that the folder is the root of a Ola Hallengren backup folder

    .PARAMETER IgnoreLogBackup
        This switch only works with the MaintenanceSolution switch. With an Ola Hallengren style backup we can be sure that the LOG folder contains only log backups and skip it.
        For all other scenarios we need to read the file headers to be sure.

    .PARAMETER IgnoreDiffBackup
        This switch only works with the MaintenanceSolution switch. With an Ola Hallengren style backup we can be sure that the DIFF folder contains only differential backups and skip it.
        For all other scenarios we need to read the file headers to be sure.

    .PARAMETER StorageCredential
        The name of the SQL Server credential to be used if restoring from cloud storage (Azure Blob Storage or S3-compatible object storage).
        For Azure, this is typically a credential with access to the storage account.
        For S3, this should be a credential created with Identity 'S3 Access Key' matching the S3 URL path.

    .PARAMETER Import
        When specified along with a path the command will import a previously exported BackupHistory object from an xml file.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        Dataplat.Dbatools.Database.BackupHistory

        Returns one BackupHistory object per backup set (group of files from the same backup operation). This object contains all necessary information to restore databases using Restore-DbaDatabase and supports being piped directly into that command.

        The object includes the following properties:

        - ComputerName: The computer name where the backup originated from (SQL Server host)
        - InstanceName: The SQL Server instance name where the backup was taken
        - SqlInstance: The full SQL Server instance name (ComputerName\InstanceName)
        - Database: The name of the database that was backed up
        - UserName: The Windows/SQL login that performed the backup
        - Start: DateTime of when the backup started
        - End: DateTime of when the backup finished
        - Duration: TimeSpan representing the duration of the backup operation
        - Type: String indicating the backup type (Full, Differential, or Log)
        - Path: String array of file paths containing the backup files
        - FullName: Array of backup file paths (same as Path)
        - FileList: Array of PSCustomObjects containing backup file details with properties: Type (MDF/LDF/NDF), LogicalName, PhysicalName, Size
        - TotalSize: Total size of the backup in bytes
        - CompressedBackupSize: Size of the compressed backup in bytes
        - BackupSetId: GUID uniquely identifying this backup set
        - Position: Position of the backup within the device
        - DeviceType: The type of backup device (typically 'Disk')
        - FirstLsn: BigInt representing the first log sequence number in the backup
        - DatabaseBackupLsn: BigInt representing the database backup LSN for log backups
        - CheckpointLSN: BigInt representing the checkpoint LSN
        - LastLsn: BigInt representing the last log sequence number in the backup
        - SoftwareVersionMajor: Major version of SQL Server that created the backup
        - RecoveryModel: The recovery model of the database (Simple, Full, or BulkLogged)
        - IsCopyOnly: Boolean indicating if this is a copy-only backup

        When -Anonymise is specified, the following properties are hashed: ComputerName, InstanceName, SqlInstance, Database, UserName, Path, FullName, and file logical/physical names in FileList.

        When -Import is specified, the BackupHistory object is deserialized from the exported CliXml file, preserving all properties for later use with Restore-DbaDatabase.

    .NOTES
        Tags: DisasterRecovery, Backup, Restore
        Author: Chrissy LeMaire (@cl) | Stuart Moore (@napalmgram)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaBackupInformation

    .EXAMPLE
        PS C:\> Get-DbaBackupInformation -SqlInstance Server1 -Path c:\backups\ -DirectoryRecurse

        Will use the Server1 instance to recursively read all backup files under c:\backups, and return a dbatools BackupHistory object

    .EXAMPLE
        PS C:\> Get-DbaBackupInformation -SqlInstance Server1 -Path c:\backups\ -DirectoryRecurse -ExportPath c:\store\BackupHistory.xml
        PS C:\> robocopy c:\store\ \\remoteMachine\C$\store\ BackupHistory.xml
        PS C:\> Get-DbaBackupInformation -Import -Path  c:\store\BackupHistory.xml | Restore-DbaDatabase -SqlInstance Server2 -TrustDbBackupHistory

        This example creates backup history output from server1 and copies the file to the remote machine in order to preserve backup history. It is then used to restore the databases onto server2.

    .EXAMPLE
        PS C:\> Get-DbaBackupInformation -SqlInstance Server1 -Path c:\backups\ -DirectoryRecurse -ExportPath C:\store\BackupHistory.xml -PassThru | Restore-DbaDatabase -SqlInstance Server2 -TrustDbBackupHistory

        In this example we gather backup information, export it to an xml file, and then pass it on through to Restore-DbaDatabase.
        This allows us to repeat the restore without having to scan all the backup files again

    .EXAMPLE
        PS C:\> Get-ChildItem c:\backups\ -recurse -files | Where-Object {$_.extension -in ('.bak','.trn') -and $_.LastWriteTime -gt (get-date).AddMonths(-1)} | Get-DbaBackupInformation -SqlInstance Server1 -ExportPath C:\backupHistory.xml

        This lets you keep a record of all backup history from the last month on hand to speed up refreshes

    .EXAMPLE
        PS C:\> $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\network\backups
        PS C:\> $Backups += Get-DbaBackupInformation -SqlInstance Server2 -NoXpDirTree -Path c:\backups

        Scan the unc folder \\network\backups with Server1, and then scan the C:\backups folder on
        Server2 not using xp_dirtree, adding the results to the first set.

    .EXAMPLE
        PS C:\> $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\network\backups -MaintenanceSolution

        When MaintenanceSolution is indicated we know we are dealing with the output from Ola Hallengren backup scripts. So we make sure that a FULL folder exists in the first level of Path, if not we shortcut scanning all the files as we have nothing to work with

    .EXAMPLE
        PS C:\> $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\network\backups -MaintenanceSolution -IgnoreLogBackup

        As we know we are dealing with an Ola Hallengren style backup folder from the MaintenanceSolution switch, when IgnoreLogBackup is also included we can ignore the LOG folder to skip any scanning of log backups. Note this also means they WON'T be restored

    .EXAMPLE
        PS C:\> $Backups = Get-DbaBackupInformation -SqlInstance sql2022 -Path s3://s3.us-west-2.amazonaws.com/mybucket/backups/mydb.bak -StorageCredential MyS3Credential

        Gets backup information from an S3-compatible object storage location. Requires SQL Server 2022 or higher. The credential must be configured with Identity = 'S3 Access Key' and Secret containing the access key and secret key.

    #>
    [CmdletBinding( DefaultParameterSetName = "Create")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "", Justification = "For Parameter StorageCredential")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [object[]]$Path,
        [parameter(Mandatory, ParameterSetName = "Create")]
        [DbaInstanceParameter]$SqlInstance,
        [parameter(ParameterSetName = "Create")]
        [PSCredential]$SqlCredential,
        [string[]]$DatabaseName,
        [string[]]$SourceInstance,
        [parameter(ParameterSetName = "Create")]
        [Switch]$NoXpDirTree,
        [parameter(ParameterSetName = "Create")]
        [Switch]$NoXpDirRecurse = $false,
        [parameter(ParameterSetName = "Create")]
        [switch]$DirectoryRecurse,
        [switch]$EnableException,
        [switch]$MaintenanceSolution,
        [switch]$IgnoreLogBackup,
        [switch]$IgnoreDiffBackup,
        [string]$ExportPath,
        [Alias("AzureCredential", "S3Credential")]
        [string]$StorageCredential,
        [parameter(ParameterSetName = "Import")]
        [switch]$Import,
        [switch][Alias('Anonymize')]$Anonymise,
        [Switch]$NoClobber,
        [Switch]$PassThru

    )
    begin {
        function Get-HashString {
            param(
                [String]$InString
            )

            $StringBuilder = New-Object System.Text.StringBuilder
            [System.Security.Cryptography.HashAlgorithm]::Create("md5").ComputeHash([System.Text.Encoding]::UTF8.GetBytes($InString)) | ForEach-Object {
                [Void]$StringBuilder.Append($_.ToString("x2"))
            }
            return $StringBuilder.ToString()
        }
        Write-Message -Level InternalComment -Message "Starting"
        Write-Message -Level Debug -Message "Parameters bound: $($PSBoundParameters.Keys -join ", ")"

        if (Test-Bound -ParameterName ExportPath) {
            if ($true -eq $NoClobber) {
                if (Test-Path $ExportPath) {
                    Stop-Function -Message "$ExportPath exists and NoClobber set"
                    return
                }
            }
        }
        if ($PSCmdlet.ParameterSetName -eq "Create") {
            try {
                $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
                return
            }
        }

        if ($true -eq $IgnoreLogBackup -and $true -ne $MaintenanceSolution) {
            Write-Message -Message "IgnoreLogBackup can only by used with MaintenanceSolution. Will not be used" -Level Warning
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        if ((Test-Bound -Parameter Import) -and ($true -eq $Import)) {
            foreach ($f in $Path) {
                if (Test-Path -Path $f) {
                    $groupResults += Import-Clixml -Path $f
                    foreach ($group in  $groupResults) {
                        $group.FirstLsn = [BigInt]$group.FirstLSN.ToString()
                        $group.CheckpointLSN = [BigInt]$group.CheckpointLSN.ToString()
                        $group.DatabaseBackupLsn = [BigInt]$group.DatabaseBackupLsn.ToString()
                        $group.LastLsn = [BigInt]$group.LastLsn.ToString()
                    }
                } else {
                    Write-Message -Message "$f does not exist or is unreadable" -Level Warning
                }
            }
        } else {
            $Files = @()
            $groupResults = @()
            # Detect cloud storage URLs (Azure http:// or S3 s3://)
            if ($Path[0] -match 'http' -or $Path[0] -match 's3') { $NoXpDirTree = $true }
            if ($NoXpDirTree -ne $true) {
                foreach ($f in $path) {
                    if ([System.IO.Path]::GetExtension($f).Length -gt 1) {
                        if ("FullName" -notin $f.PSObject.Properties.name) {
                            $f = $f | Select-Object *, @{ Name = "FullName"; Expression = { $f } }
                        }
                        Write-Message -Message "Testing a single file $f " -Level Verbose
                        if ((Test-DbaPath -Path $f.FullName -SqlInstance $server)) {
                            $files += $f
                        } else {
                            Write-Message -Level Verbose -Message "$server cannot 'see' file $($f.FullName)"
                        }
                    } elseif ($True -eq $MaintenanceSolution) {
                        if ($true -eq $IgnoreLogBackup -and [System.IO.Path]::GetDirectoryName($f) -like '*LOG') {
                            Write-Message -Level Verbose -Message "Skipping Log Backups as requested"
                        } else {
                            Write-Message -Level Verbose -Message "OLA - Getting folder contents"
                            try {
                                $Files += Get-XpDirTreeRestoreFile -Path $f -SqlInstance $server -NoRecurse:$NoXpDirRecurse
                            } catch {
                                Stop-Function -Message "Failure on $($server.Name)" -ErrorRecord $PSItem -Target $server.Name -Continue
                            }
                        }
                    } else {
                        Write-Message -Message "Testing a folder $f" -Level Verbose
                        try {
                            $Files += $Check = Get-XpDirTreeRestoreFile -Path $f -SqlInstance $server -NoRecurse:$NoXpDirRecurse -EnableException
                        } catch {
                            Stop-Function -Message "Failure on $($server.Name)" -ErrorRecord $PSItem -Target $server.Name -Continue
                        }
                        if ($null -eq $check) {
                            Write-Message -Message "Nothing returned from $f" -Level Verbose
                        }
                    }
                }
            } else {
                ForEach ($f in $path) {
                    Write-Message -Level VeryVerbose -Message "Not using sql for $f"
                    if ($f -is [System.IO.FileSystemInfo]) {
                        if ($f.PsIsContainer -eq $true -and $true -ne $MaintenanceSolution) {
                            Write-Message -Level VeryVerbose -Message "folder $($f.FullName)"
                            $Files += Get-ChildItem -Path $f.FullName -File -Recurse:$DirectoryRecurse
                        } elseif ($f.PsIsContainer -eq $true -and $true -eq $MaintenanceSolution) {
                            if ($IgnoreLogBackup -and $f -notlike '*LOG' ) {
                                Write-Message -Level Verbose -Message "Skipping Log backups for Maintenance backups"
                            } else {
                                $Files += Get-ChildItem -Path $f.FullName -File -Recurse:$DirectoryRecurse
                            }
                        } elseif ($true -eq $MaintenanceSolution) {
                            $Files += Get-ChildItem -Path $f.FullName -Recurse:$DirectoryRecurse
                        } else {
                            Write-Message -Level VeryVerbose -Message "File"
                            $Files += $f.FullName
                        }
                    } else {
                        if ($true -eq $MaintenanceSolution) {
                            # Use forward slashes for URLs (Azure https:// or S3 s3://), backslashes for file system paths
                            $separator = if ($f -match '^https?://' -or $f -match '^s3://') { "/" } else { "\" }
                            $Files += Get-XpDirTreeRestoreFile -Path "$f$($separator)FULL" -SqlInstance $server -NoRecurse
                            $Files += Get-XpDirTreeRestoreFile -Path "$f$($separator)DIFF" -SqlInstance $server -NoRecurse
                            $Files += Get-XpDirTreeRestoreFile -Path "$f$($separator)LOG" -SqlInstance $server -NoRecurse
                        } else {
                            Write-Message -Level VeryVerbose -Message "File"
                            $Files += $f
                        }
                    }
                }
            }

            if ($True -eq $MaintenanceSolution -and $True -eq $IgnoreLogBackup) {
                Write-Message -Level Verbose -Message "Skipping Log Backups as requested"
                $Files = $Files | Where-Object { $_.FullName -notlike '*\LOG\*' -and $_.FullName -notlike '*/LOG/*' }
            }

            if ($True -eq $MaintenanceSolution -and $True -eq $IgnoreDiffBackup) {
                Write-Message -Level Verbose -Message "Skipping Differential Backups as requested"
                $Files = $Files | Where-Object { $_.FullName -notlike '*\DIFF\*' -and $_.FullName -notlike '*/DIFF/*' }
            }

            if ($Files.Count -gt 0) {
                Write-Message -Level Verbose -Message "Reading backup headers of $($Files.Count) files"
                try {
                    $FileDetails = Read-DbaBackupHeader -SqlInstance $server -Path $Files -StorageCredential $StorageCredential -EnableException
                } catch {
                    Stop-Function -Message "Failure on $($server.Name)" -ErrorRecord $PSItem -Target $server.Name -Continue
                }
            }

            $groupDetails = $FileDetails | Group-Object -Property BackupSetGUID

            foreach ($group in $groupDetails) {
                $dbLsn = $group.Group[0].DatabaseBackupLSN
                if (-not $dbLsn) {
                    $dbLsn = 0
                }
                $description = $group.Group[0].BackupTypeDescription
                if (-not $description) {
                    try {
                        $header = Read-DbaBackupHeader -SqlInstance $server -Path $Path -EnableException | Select-Object -First 1
                    } catch {
                        Stop-Function -Message "Failure on $($server.Name)" -ErrorRecord $PSItem -Target $server.Name -Continue
                    }
                    $description = switch ($header.BackupType) {
                        1 { "Full" }
                        2 { "Differential" }
                        3 { "Log" }
                    }
                }
                $historyObject = New-Object Dataplat.Dbatools.Database.BackupHistory
                $historyObject.ComputerName = $group.Group[0].MachineName
                $historyObject.InstanceName = $group.Group[0].ServiceName
                $historyObject.SqlInstance = $group.Group[0].ServerName
                $historyObject.Database = $group.Group[0].DatabaseName
                $historyObject.UserName = $group.Group[0].UserName
                $historyObject.Start = [DateTime]$group.Group[0].BackupStartDate
                $historyObject.End = [DateTime]$group.Group[0].BackupFinishDate
                $historyObject.Duration = ([DateTime]$group.Group[0].BackupFinishDate - [DateTime]$group.Group[0].BackupStartDate)
                $historyObject.Path = [string[]]$group.Group.BackupPath
                $historyObject.FileList = ($group.Group.FileList | Select-Object Type, LogicalName, PhysicalName, @{
                        Name       = "Size"
                        Expression = { [dbasize]$PSItem.Size }
                    } -Unique)
                $historyObject.TotalSize = $group.Group[0].BackupSize.Byte
                $HistoryObject.CompressedBackupSize = $group.Group[0].CompressedBackupSize.Byte
                $historyObject.Type = $description
                $historyObject.BackupSetId = $group.group[0].BackupSetGUID
                $historyObject.DeviceType = 'Disk'
                $historyObject.FullName = $group.Group.BackupPath
                $historyObject.Position = $group.Group[0].Position
                $historyObject.FirstLsn = $group.Group[0].FirstLSN
                $historyObject.DatabaseBackupLsn = $dbLsn
                $historyObject.CheckpointLSN = $group.Group[0].CheckpointLSN
                $historyObject.LastLsn = $group.Group[0].LastLsn
                $historyObject.SoftwareVersionMajor = $group.Group[0].SoftwareVersionMajor
                $historyObject.RecoveryModel = $group.Group.RecoveryModel
                $historyObject.IsCopyOnly = $group.Group[0].IsCopyOnly
                $groupResults += $historyObject
            }
        }
        if (Test-Bound 'SourceInstance') {
            $groupResults = $groupResults | Where-Object { $_.InstanceName -in $SourceInstance }
        }

        if (Test-Bound 'DatabaseName') {
            $groupResults = $groupResults | Where-Object { $_.Database -in $DatabaseName }
        }
        if ($true -eq $Anonymise) {
            foreach ($group in $groupResults) {
                $group.ComputerName = Get-HashString -InString $group.ComputerName
                $group.InstanceName = Get-HashString -InString $group.InstanceName
                $group.SqlInstance = Get-HashString -InString $group.SqlInstance
                $group.Database = Get-HashString -InString $group.Database
                $group.UserName = Get-HashString -InString $group.UserName
                $group.Path = Get-HashString -InString  $group.Path
                $group.FullName = Get-HashString -InString $group.FullName
                $group.FileList = ($group.FileList | Select-Object Type,
                    @{Name = "LogicalName"; Expression = { Get-HashString -InString $_."LogicalName" } },
                    @{Name = "PhysicalName"; Expression = { Get-HashString -InString $_."PhysicalName" } })
            }
        }
        if ((Test-Bound -parameterName ExportPath) -and $null -ne $ExportPath) {
            $groupResults | Export-Clixml -Path $ExportPath -Depth 5 -NoClobber:$NoClobber
            if ($true -ne $PassThru) {
                return
            }
        }
        $groupResults | Sort-Object -Property End -Descending
    }
}