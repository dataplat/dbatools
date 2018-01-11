#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#

function Read-DbaBackupHeader {
    <#
        .SYNOPSIS
            Reads and displays detailed information about a SQL Server backup

        .DESCRIPTION
            Reads full, differential and transaction log backups. An online SQL Server is required to parse the backup files and the path specified must be relative to that SQL Server.

        .PARAMETER SqlInstance
            The SQL Server instance.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.

        .PARAMETER Path
            Path to SQL Server backup file. This can be a full, differential or log backup file.
            Accepts valid filesystem paths and URLs

        .PARAMETER Simple
            Returns fewer columns for an easy overview

        .PARAMETER FileList
            Returns detailed information about the files within the backup

        .PARAMETER AzureCredential
            Name of the SQL Server credential that should be used for Azure storage access

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message. This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: DisasterRecovery, Backup, Restore
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

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
        [switch][Alias('Silent')]$EnableException
    )

    begin {
        $loopCnt = 1
        try {
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        }
        catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            return
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }
        $pathCount = $Path.Length
        Write-Message -Level Verbose -Message "$pathCount files to scan"
        foreach ($file in $Path) {
            if ($null -ne $file.FullName) {
                $file = $file.FullName
            }
            Write-Progress -Id 1 -Activity Updating -Status 'Progress' -CurrentOperation "Scanning Restore headers on File $loopCnt - $file"

            Write-Message -Level Verbose -Message "Scanning file $file"
            $restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
            if ($file -like 'http*') {
                $deviceType = 'URL'
                $restore.CredentialName = $AzureCredential
            }
            else {
                $deviceType = 'FILE'
            }
            $device = New-Object Microsoft.SqlServer.Management.Smo.BackupDeviceItem $file, $deviceType
            $restore.Devices.Add($device)
            if ((Test-DbaSqlPath -SqlInstance $server -Path $file) -or $deviceType -eq 'URL') {
                try {
                    $dataTable = $restore.ReadBackupHeader($server)
                }
                catch {
                    if ($deviceType -eq 'FILE') {
                        Stop-Function -Message "Problem found with $file" -Target $file -ErrorRecord $_ -Exception $_.Exception.InnerException.InnerException -Continue

                    }
                    else {
                        Stop-Function -Message "Unable to read $file, check credential $AzureCredential and network connectivity" -Target $file -ErrorRecord $_ -Excpetion $_.Exception.InnerException.InnerException -Continue
                    }
                }

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
                $dbVersion = $dataTable.Rows[0].DatabaseVersion

                $backupSlot = 1
                foreach ($row in $dataTable) {
                    $row.SqlVersion = (Convert-DbVersionToSqlVersion $dbVersion)
                    $row.BackupPath = $file
                    try {
                        $restore.FileNumber = $backupSlot
                        <# Select-Object does a quick and dirty conversion from datatable to PS object #>
                        $allFiles = $restore.ReadFileList($server) | Select-Object *
                    }
                    catch {
                        $shortName = Split-Path $file -Leaf
                        if (!(Test-DbaSqlPath -SqlInstance $server -Path $file)) {
                            Stop-Function -Message "File $shortName does not exist or access denied. The SQL Server service account may not have access to the source directory." -Target $file -ErrorRecord $_ -Exception $_.Exception.InnerException.InnerException -Continue
                        }
                        else {
                            Stop-Function -Message "File list for $shortName could not be determined. This is likely due to the file not existing, the backup version being incompatible or unsupported, connectivity issues or tiemouts with the SQL Server, or the SQL Server service account does not have access to the source directory." -Target $file -ErrorRecord $_ -Exception $_.Exception.InnerException.InnerException -Continue
                        }
                    }
                    $row.FileList = $allFiles
                    $backupSlot++
                }
            }
            else {
                Write-Message -Level Warning -Message "File $shortName does not exist or access denied. The SQL Server service account may not have access to the source directory."
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

            Remove-Variable dataTable -ErrorAction SilentlyContinue
        }
        $loopCnt++
    }
}
