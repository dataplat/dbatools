function Read-DbaBackupHeader {
    <#
    .SYNOPSIS
        Extracts backup metadata from SQL Server backup files without restoring them

    .DESCRIPTION
        Uses SQL Server's RESTORE HEADERONLY functionality to extract detailed metadata from backup files including database name, backup type, creation date, file lists, and backup size information. This lets you validate backups, plan restores, and audit backup inventory without actually performing a restore operation.

        The function can process full, differential, and transaction log backups from local file systems, network shares, and Azure blob storage. It requires an online SQL Server instance to parse the backup files since it leverages SQL Server's built-in backup reading capabilities.

        Supports multithreaded processing for improved performance when scanning multiple backup files. The backup file paths must be accessible from the target SQL Server instance, not your local workstation.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Path
        Specifies the file path to SQL Server backup files including full, differential, and transaction log backups. Supports local paths, UNC network shares, and Azure blob storage URLs.
        The backup files must be accessible from the target SQL Server instance, not your local workstation. Use this to read backup metadata without performing an actual restore.

    .PARAMETER Simple
        Returns a simplified output with only essential columns: DatabaseName, BackupFinishDate, RecoveryModel, BackupSize, CompressedBackupSize, DatabaseCreationDate, UserName, ServerName, SqlVersion, and BackupPath.
        Use this when you need a quick overview of backup files without the full 50+ columns of detailed metadata.

    .PARAMETER FileList
        Returns detailed information about each data and log file contained within the backup set, including logical names, physical paths, file sizes, and file types.
        Use this when planning restores to different locations or when you need to understand the file structure before performing a restore operation.

    .PARAMETER StorageCredential
        Specifies the name of a SQL Server credential object that contains the authentication information for accessing Azure blob storage or S3-compatible object storage.
        Required when reading backup files stored in Azure blob storage or S3. The credential must already exist on the target SQL Server instance.
        For Azure: The credential must contain valid Azure storage account keys or SAS tokens.
        For S3: The credential must use Identity = 'S3 Access Key' and Secret = 'AccessKeyID:SecretKeyID'. Requires SQL Server 2022 or higher.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        System.Data.DataRow (default output)

        Returns one object per backup set found in the backup file. When -Simple is not specified, returns the full DataTable with backup header metadata including:

        Default properties:
        - DatabaseName: Name of the database that was backed up
        - BackupFinishDate: DateTime when the backup completed
        - RecoveryModel: Database recovery model (Simple, Full, or BulkLogged)
        - BackupSize: Size of the backup (dbasize object with Byte, KB, MB, GB properties)
        - CompressedBackupSize: Size of the compressed backup if compression was used (dbasize object)
        - DatabaseCreationDate: DateTime the database was created
        - UserName: Login that performed the backup
        - ServerName: SQL Server instance name where backup was created
        - SqlVersion: SQL Server version string (e.g., "SQL Server 2016", "SQL Server 2019")
        - BackupPath: Full path to the backup file
        - FileList: Collection of backup file details (see -FileList for details)

        Additional properties from SMO Restore.ReadBackupHeader():
        - BackupType: Type of backup (Database, Differential, Log, etc.)
        - BackupName: Name given to the backup set
        - Position: Position of this backup set within the file (1 for first, 2 for second, etc.)
        - DatabaseVersion: Internal database version number
        - IsPassword: Whether the backup is password-protected (0 or 1)
        - IsCopyOnly: Whether this is a copy-only backup (0 or 1)
        - ContinuationFolk: Whether this is a continuation of a previous backup (0 or 1)
        - HasBulkLoggedData: Whether the backup contains bulk-logged operations (0 or 1)
        - IsSnapshot: Whether this is a snapshot backup (0 or 1)
        - IsDamaged: Whether the backup is marked as damaged (0 or 1)
        - StarTime: DateTime when backup started
        - CompatibilityLevel: Compatibility level of the database
        - SoftwareVendorId: Software vendor identifier
        - SoftwareVersionMajor: Major version of SQL Server that created backup
        - SoftwareVersionMinor: Minor version of SQL Server that created backup
        - SoftwareVersionBuild: Build number of SQL Server that created backup
        - MachineName: Computer name where backup was created
        - Flags: Backup flags and options
        - BindingId: Binding ID
        - RecoveryFork: Recovery fork identifier
        - Collation: Database collation
        - FamilyGuid: Family GUID for backup family tracking
        - HasBackupChecksums: Whether checksums are present (0 or 1)
        - IsSealedBackup: Whether backup is sealed/complete (0 or 1)

        System.Data.DataRow (when -Simple is specified)

        Returns one object per backup set with only essential backup metadata columns:
        - DatabaseName: Name of the database that was backed up
        - BackupFinishDate: DateTime when the backup completed
        - RecoveryModel: Database recovery model (Simple, Full, or BulkLogged)
        - BackupSize: Size of the backup (dbasize object with Byte, KB, MB, GB properties)
        - CompressedBackupSize: Size of the compressed backup (dbasize object)
        - DatabaseCreationDate: DateTime the database was created
        - UserName: Login that performed the backup
        - ServerName: SQL Server instance name
        - SqlVersion: SQL Server version string
        - BackupPath: Full path to the backup file

        System.Data.DataRow (when -FileList is specified)

        Returns detailed information about each data and log file contained within the backup set(s):
        - LogicalName: Logical name of the file as defined in the database
        - PhysicalName: Physical file path where the file is stored
        - Type: File type (D for Data, L for Log, etc.)
        - FileGroupName: Filegroup that contains this file
        - Size: Size of the file in bytes
        - MaxSize: Maximum size of the file in bytes
        - FileId: File ID number in the database
        - CreateLsn: Log sequence number when file was created
        - DropLsn: Log sequence number when file was dropped (if applicable)
        - UniqueId: Unique identifier for the file
        - ReadOnlyLsn: Log sequence number when file became read-only
        - ReadWriteLsn: Log sequence number when file became read-write
        - BackupSizeInBytes: Size of this file in the backup
        - SourceBlockSize: Original block size when file was created
        - FileGroupId: ID of the filegroup containing this file
        - LogGroupGuid: Identifier for log group
        - DifferentialBaseLsn: LSN of the differential base
        - DifferentialBaseGuid: GUID of the differential base
        - IsReadOnly: Whether the file is read-only (0 or 1)
        - IsPresent: Whether the file is present in this backup (0 or 1)
        - TdeThumbprint: Transparent Data Encryption thumbprint if applicable

    .NOTES
        Tags: DisasterRecovery, Backup, Restore
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Read-DbaBackupHeader

    .EXAMPLE
        PS C:\> Read-DbaBackupHeader -SqlInstance sql2016 -Path S:\backups\mydb\mydb.bak

        Logs into sql2016 using Windows authentication and reads the local file on sql2016, S:\backups\mydb\mydb.bak.

        If you are running this command on a workstation and connecting remotely, remember that sql2016 cannot access files on your own workstation.

    .EXAMPLE
        PS C:\> Read-DbaBackupHeader -SqlInstance sql2016 -Path \\nas\sql\backups\mydb\mydb.bak, \\nas\sql\backups\otherdb\otherdb.bak

        Logs into sql2016 and reads two backup files - mydb.bak and otherdb.bak. The SQL Server service account must have rights to read this file.

    .EXAMPLE
        PS C:\> Read-DbaBackupHeader -SqlInstance . -Path C:\temp\myfile.bak -Simple

        Logs into the local workstation (or computer) and shows simplified output about C:\temp\myfile.bak. The SQL Server service account must have rights to read this file.

    .EXAMPLE
        PS C:\> $backupinfo = Read-DbaBackupHeader -SqlInstance . -Path C:\temp\myfile.bak
        PS C:\> $backupinfo.FileList

        Displays detailed information about each of the datafiles contained in the backupset.

    .EXAMPLE
        PS C:\> Read-DbaBackupHeader -SqlInstance . -Path C:\temp\myfile.bak -FileList

        Also returns detailed information about each of the datafiles contained in the backupset.

    .EXAMPLE
        PS C:\> "C:\temp\myfile.bak", "\backupserver\backups\myotherfile.bak" | Read-DbaBackupHeader -SqlInstance sql2016  | Where-Object { $_.BackupSize.Megabyte -gt 100 }

        Reads the two files and returns only backups larger than 100 MB

    .EXAMPLE
        PS C:\> Get-ChildItem \\nas\sql\*.bak | Read-DbaBackupHeader -SqlInstance sql2016

        Gets a list of all .bak files on the \\nas\sql share and reads the headers using the server named "sql2016". This means that the server, sql2016, must have read access to the \\nas\sql share.

    .EXAMPLE
        PS C:\> Read-DbaBackupHeader -SqlInstance sql2016 -Path https://dbatoolsaz.blob.core.windows.net/azbackups/restoretime/restoretime_201705131850.bak -StorageCredential AzureBackupUser

        Gets the backup header information from the SQL Server backup file stored at https://dbatoolsaz.blob.core.windows.net/azbackups/restoretime/restoretime_201705131850.bak on Azure

    .EXAMPLE
        PS C:\> Read-DbaBackupHeader -SqlInstance sql2022 -Path s3://s3.us-west-2.amazonaws.com/mybucket/backups/mydb.bak -StorageCredential MyS3Credential

        Gets the backup header information from the SQL Server backup file stored in an AWS S3 bucket. Requires SQL Server 2022 or higher and a credential configured with S3 access keys.

    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", 'StorageCredential', Justification = "For Parameter StorageCredential")]
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [DbaInstance]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory, ValueFromPipeline)]
        [object[]]$Path,
        [switch]$Simple,
        [switch]$FileList,
        [Alias("AzureCredential", "S3Credential")]
        [string]$StorageCredential,
        [switch]$EnableException
    )

    begin {
        foreach ($p in $Path) {
            Write-Message -Level Verbose -Message "Checking: $p"
            if ([System.IO.Path]::GetExtension("$p").Length -eq 0) {
                Stop-Function -Message "Path ("$p") should be a file, not a folder" -Category InvalidArgument
                return
            }
        }
        Write-Message -Level InternalComment -Message "Starting reading headers"
        try {
            $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
            return
        }
        $getHeaderScript = {
            param (
                $SqlInstance,
                $Path,
                $DeviceType,
                $StorageCredential
            )
            #Copy existing connection to create an independent TSQL session
            $server = New-Object Microsoft.SqlServer.Management.Smo.Server $SqlInstance.ConnectionContext.Copy()
            $restore = New-Object Microsoft.SqlServer.Management.Smo.Restore

            if ($DeviceType -eq 'URL') {
                $restore.CredentialName = $StorageCredential
            }

            $device = New-Object Microsoft.SqlServer.Management.Smo.BackupDeviceItem $Path, $DeviceType
            $restore.Devices.Add($device)
            $dataTable = $restore.ReadBackupHeader($server)
            $null = $dataTable.Columns.Add("FileList", [object])
            $null = $dataTable.Columns.Add("SqlVersion")
            $null = $dataTable.Columns.Add("BackupPath")

            foreach ($row in $dataTable) {
                $row.BackupPath = $Path

                $backupsize = $row.BackupSize
                $null = $dataTable.Columns.Remove("BackupSize")
                $null = $dataTable.Columns.Add("BackupSize", [dbasize])
                if ($backupsize -isnot [dbnull]) {
                    $row.BackupSize = [dbasize]$backupsize
                }

                $cbackupsize = $row.CompressedBackupSize
                if ($dataTable.Columns['CompressedBackupSize']) {
                    $null = $dataTable.Columns.Remove("CompressedBackupSize")
                }
                $null = $dataTable.Columns.Add("CompressedBackupSize", [dbasize])
                if ($cbackupsize -isnot [dbnull]) {
                    $row.CompressedBackupSize = [dbasize]$cbackupsize
                }

                $restore.FileNumber = $row.Position
                <# Select-Object does a quick and dirty conversion from datatable to PS object #>
                $row.FileList = $restore.ReadFileList($server) | Select-Object *
            }
            $dataTable
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        #Extract fullnames from the file system objects
        $pathStrings = @()
        foreach ($pathItem in $Path) {
            if ($null -ne $pathItem.FullName) {
                $pathStrings += $pathItem.FullName
            } else {
                $pathStrings += $pathItem
            }
        }
        #Group by filename
        $pathGroup = $pathStrings | Group-Object -NoElement | Select-Object -ExpandProperty Name

        $pathCount = ($pathGroup | Measure-Object).Count
        Write-Message -Level Verbose -Message "$pathCount unique files to scan."
        Write-Message -Level Verbose -Message "Checking accessibility for all the files."

        $testPath = Test-DbaPath -SqlInstance $server -Path $pathGroup

        #Setup initial session state
        $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $defaultrunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
        #Create Runspace pool, min - 1, max - 10 sessions: there is internal SQL Server queue for the restore operations. 10 threads seem to perform best
        $runspacePool = [runspacefactory]::CreateRunspacePool(1, 10, $InitialSessionState, $Host)
        $runspacePool.Open()

        $threads = @()

        foreach ($file in $pathGroup) {
            if ($file -like 'http*' -or $file -like 's3*') {
                $deviceType = 'URL'
            } else {
                $deviceType = 'FILE'
            }
            if ($pathCount -eq 1) {
                $fileExists = $testPath
            } else {
                $fileExists = ($testPath | Where-Object FilePath -eq $file).FileExists
            }
            if ($fileExists -or $deviceType -eq 'URL') {
                #Create parameters hashtable
                $argsRunPool = @{
                    SqlInstance       = $server
                    Path              = $file
                    StorageCredential = $StorageCredential
                    DeviceType        = $deviceType
                }
                Write-Message -Level Verbose -Message "Scanning file $file."
                #Create new runspace thread
                $thread = [powershell]::Create()
                $thread.RunspacePool = $runspacePool
                $thread.AddScript($getHeaderScript) | Out-Null
                $thread.AddParameters($argsRunPool) | Out-Null
                #Start the thread
                $handle = $thread.BeginInvoke()
                $threads += [PSCustomObject]@{
                    handle      = $handle
                    thread      = $thread
                    file        = $file
                    deviceType  = $deviceType
                    isRetrieved = $false
                    started     = Get-Date
                }
            } else {
                Write-Message -Level Warning -Message "File $file does not exist or access denied. The SQL Server service account may not have access to the source directory."
            }
        }
        #receive runspaces
        while ($threads | Where-Object { $_.isRetrieved -eq $false }) {
            $totalThreads = ($threads | Measure-Object).Count
            $totalRetrievedThreads = ($threads | Where-Object { $_.isRetrieved -eq $true } | Measure-Object).Count
            Write-Progress -Id 1 -Activity Updating -Status 'Progress' -CurrentOperation "Scanning Restore headers: $totalRetrievedThreads/$totalThreads" -PercentComplete ($totalRetrievedThreads / $totalThreads * 100)
            foreach ($thread in ($threads | Where-Object { $_.isRetrieved -eq $false })) {
                if ($thread.Handle.IsCompleted) {
                    $dataTable = $thread.thread.EndInvoke($thread.handle)
                    $thread.isRetrieved = $true
                    #Check if thread had any errors
                    if ($thread.thread.HadErrors) {
                        if ($thread.deviceType -eq 'FILE') {
                            Stop-Function -Message "Problem found with $($thread.file)." -Target $thread.file -ErrorRecord $thread.thread.Streams.Error -Continue
                        } else {
                            Stop-Function -Message "Unable to read $($thread.file), check credential $StorageCredential and network connectivity." -Target $thread.file -ErrorRecord $thread.thread.Streams.Error -Continue
                        }
                    }
                    #Process the result of this thread

                    $dbVersion = $dataTable[0].DatabaseVersion
                    $SqlVersion = (Convert-DbVersionToSqlVersion $dbVersion)
                    foreach ($row in $dataTable) {
                        $row.SqlVersion = $SqlVersion
                        if ($row.BackupName -eq "*** INCOMPLETE ***") {
                            Stop-Function -Message "$($thread.file) appears to be from a new version of SQL Server than $SqlInstance, skipping" -Target $thread.file -Continue
                        }
                    }
                    if ($Simple) {
                        $dataTable | Select-Object DatabaseName, BackupFinishDate, RecoveryModel, BackupSize, CompressedBackupSize, DatabaseCreationDate, UserName, ServerName, SqlVersion, BackupPath
                    } elseif ($FileList) {
                        $dataTable.filelist
                    } else {
                        $dataTable
                    }

                    $thread.thread.Dispose()
                }
            }
            Start-Sleep -Milliseconds 500
        }
        #Close the runspace pool
        $runspacePool.Close()
        [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace = $defaultrunspace
    }
}