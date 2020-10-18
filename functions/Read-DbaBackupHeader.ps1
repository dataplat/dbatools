function Read-DbaBackupHeader {
    <#
    .SYNOPSIS
        Reads and displays detailed information about a SQL Server backup.

    .DESCRIPTION
        Reads full, differential and transaction log backups. An online SQL Server is required to parse the backup files and the path specified must be relative to that SQL Server.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Path
        Path to SQL Server backup file. This can be a full, differential or log backup file. Accepts valid filesystem paths and URLs.

    .PARAMETER Simple
        If this switch is enabled, fewer columns are returned, giving an easy overview.

    .PARAMETER FileList
        If this switch is enabled, detailed information about the files within the backup is returned.

    .PARAMETER AzureCredential
        Name of the SQL Server credential that should be used for Azure storage access.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message. This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

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
        PS C:\> Read-DbaBackupHeader -SqlInstance sql2016 -Path https://dbatoolsaz.blob.core.windows.net/azbackups/restoretime/restoretime_201705131850.bak -AzureCredential AzureBackupUser

        Gets the backup header information from the SQL Server backup file stored at https://dbatoolsaz.blob.core.windows.net/azbackups/restoretime/restoretime_201705131850.bak on Azure

    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", 'AzureCredential', Justification = "For Parameter AzureCredential")]
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [DbaInstance]$SqlInstance,
        [PsCredential]$SqlCredential,
        [parameter(Mandatory, ValueFromPipeline)]
        [object[]]$Path,
        [switch]$Simple,
        [switch]$FileList,
        [string]$AzureCredential,
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
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $SqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            return
        }
        $getHeaderScript = {
            param (
                $SqlInstance,
                $Path,
                $DeviceType,
                $AzureCredential
            )
            #Copy existing connection to create an independent TSQL session
            $server = New-Object Microsoft.SqlServer.Management.Smo.Server $SqlInstance.ConnectionContext.Copy()
            $restore = New-Object Microsoft.SqlServer.Management.Smo.Restore

            if ($DeviceType -eq 'URL') {
                $restore.CredentialName = $AzureCredential
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
            if ($file -like 'http*') {
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
                    SqlInstance     = $server
                    Path            = $file
                    AzureCredential = $AzureCredential
                    DeviceType      = $deviceType
                }
                Write-Message -Level Verbose -Message "Scanning file $file."
                #Create new runspace thread
                $thread = [powershell]::Create()
                $thread.RunspacePool = $runspacePool
                $thread.AddScript($getHeaderScript) | Out-Null
                $thread.AddParameters($argsRunPool) | Out-Null
                #Start the thread
                $handle = $thread.BeginInvoke()
                $threads += [pscustomobject]@{
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
                            Stop-Function -Message "Unable to read $($thread.file), check credential $AzureCredential and network connectivity." -Target $thread.file -ErrorRecord $thread.thread.Streams.Error -Continue
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