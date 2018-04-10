#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#

function Read-DbaBackupHeader {
    <#
        .SYNOPSIS
            Reads and displays detailed information about a SQL Server backup.

        .DESCRIPTION
            Reads full, differential and transaction log backups. An online SQL Server is required to parse the backup files and the path specified must be relative to that SQL Server.

        .PARAMETER SqlInstance
            The SQL Server instance to use for parsing the backup files.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

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
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Read-DbaBackupHeader

        .EXAMPLE
            Read-DbaBackupHeader -SqlInstance sql2016 -Path S:\backups\mydb\mydb.bak

            Logs into sql2016 using Windows authentication and reads the local file on sql2016, S:\backups\mydb\mydb.bak.

            If you are running this command on a workstation and connecting remotely, remember that sql2016 cannot access files on your own workstation.

        .EXAMPLE
            Read-DbaBackupHeader -SqlInstance sql2016 -Path \\nas\sql\backups\mydb\mydb.bak, \\nas\sql\backups\otherdb\otherdb.bak

            Logs into sql2016 and reads two backup files - mydb.bak and otherdb.bak. The SQL Server service account must have rights to read this file.

        .EXAMPLE
            Read-DbaBackupHeader -SqlInstance . -Path C:\temp\myfile.bak -Simple

            Logs into the local workstation (or computer) and shows simplified output about C:\temp\myfile.bak. The SQL Server service account must have rights to read this file.

        .EXAMPLE
            $backupinfo = Read-DbaBackupHeader -SqlInstance . -Path C:\temp\myfile.bak
            $backupinfo.FileList

            Displays detailed information about each of the datafiles contained in the backupset.

        .EXAMPLE
            Read-DbaBackupHeader -SqlInstance . -Path C:\temp\myfile.bak -FileList

            Also returns detailed information about each of the datafiles contained in the backupset.

        .EXAMPLE
            "C:\temp\myfile.bak", "\backupserver\backups\myotherfile.bak" | Read-DbaBackupHeader -SqlInstance sql2016

            Similar to running Read-DbaBackupHeader -SqlInstance sql2016 -Path "C:\temp\myfile.bak", "\backupserver\backups\myotherfile.bak"

        .EXAMPLE
            Get-ChildItem \\nas\sql\*.bak | Read-DbaBackupHeader -SqlInstance sql2016

            Gets a list of all .bak files on the \\nas\sql share and reads the headers using the server named "sql2016". This means that the server, sql2016, must have read access to the \\nas\sql share.

        .EXAMPLE
            Read-DbaBackupHeader -Path https://dbatoolsaz.blob.core.windows.net/azbackups/restoretime/restoretime_201705131850.bak
            -AzureCredential AzureBackupUser

            Gets the backup header information from the SQL Server backup file stored at https://dbatoolsaz.blob.core.windows.net/azbackups/restoretime/restoretime_201705131850.bak on Azure
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", '')]
    <# AzureCredential is utilized in this command is not a formal Credential object. #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstance]$SqlInstance,
        [PsCredential]$SqlCredential,
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]$Path,
        [switch]$Simple,
        [switch]$FileList,
        [string]$AzureCredential,
        [Alias('Silent')]
        [switch]$EnableException
    )

    begin {
        Write-Message -Level InternalComment -Message "Starting reading headers"
        try {
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        }
        catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            return
        }
        $getHeaderScript = {
            Param (
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

            $mb = $dataTable.Columns.Add("BackupSizeMB", [int])
            $mb.Expression = "BackupSize / 1024 / 1024"
            $gb = $dataTable.Columns.Add("BackupSizeGB")
            $gb.Expression = "BackupSizeMB / 1024"

            if ($null -eq $dataTable.Columns['CompressedBackupSize']) {
                $formula = "0"
            }
            else {
                $formula = "CompressedBackupSize / 1024 / 1024"
            }

            $cmb = $dataTable.Columns.Add("CompressedBackupSizeMB", [int])
            $cmb.Expression = $formula
            $cgb = $dataTable.Columns.Add("CompressedBackupSizeGB")
            $cgb.Expression = "CompressedBackupSizeMB / 1024"

            $null = $dataTable.Columns.Add("SqlVersion")

            $null = $dataTable.Columns.Add("BackupPath")
            
            foreach ($row in $dataTable) {
                $row.BackupPath = $Path
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
            }
            else {
                $pathStrings += $pathItem
            }
        }
        #Group by filename
        $pathGroup = $pathStrings | Group-Object -NoElement | Select-Object -ExpandProperty Name
        
        $pathCount = ($pathGroup | Measure-Object).Count
        Write-Message -Level Verbose -Message "$pathCount unique files to scan."
        Write-Message -Level Verbose -Message "Checking accessibility for all the files."
                
        $testPath = Test-DbaSqlPath -SqlInstance $server -Path $pathGroup
        
        #Setup initial session state
        $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        #Create Runspace pool, min - 1, max - 10 sessions: there is internal SQL Server queue for the restore operations. 10 threads seem to perform best
        $runspacePool = [runspacefactory]::CreateRunspacePool(1, 10, $InitialSessionState, $Host)
        $runspacePool.Open()

        $threads = @()
        
        foreach ($file in $pathGroup) {
            if ($file -like 'http*') {
                $deviceType = 'URL'
            }
            else {
                $deviceType = 'FILE'
            }
            if ($pathCount -eq 1) {
                $fileExists = $testPath
            }
            else {
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
            }
            else {
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
                        }
                        else {
                            Stop-Function -Message "Unable to read $($thread.file), check credential $AzureCredential and network connectivity." -Target $thread.file -ErrorRecord $thread.thread.Streams.Error -Continue
                        }
                    }
                    #Process the result of this thread

                    $dbVersion = $dataTable[0].DatabaseVersion

                    foreach ($row in $dataTable) {
                        $row.SqlVersion = (Convert-DbVersionToSqlVersion $dbVersion)
                        if ($row.BackupName -eq "*** INCOMPLETE ***") {
                            Stop-Function -Message "$($thread.file) appears to be from a new version of SQL Server than $SqlInstance, skipping" -Target $thread.file -Continue
                        }
                    }
                    if ($Simple) {
                        $dataTable | Select-Object DatabaseName, BackupFinishDate, RecoveryModel, BackupSizeMB, CompressedBackupSizeMB, DatabaseCreationDate, UserName, ServerName, SqlVersion, BackupPath
                    }
                    elseif ($FileList) {
                        $dataTable.filelist
                    }
                    else {
                        $dataTable
                    }

                    $thread.thread.Dispose()
                }
            }
            Start-Sleep -Milliseconds 50
        }
        #Close the runspace pool
        $runspacePool.Close()
    }
}
