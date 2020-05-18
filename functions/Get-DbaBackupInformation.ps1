function Get-DbaBackupInformation {
    <#
    .SYNOPSIS
        Scan backup files and creates a set, compatible with Restore-DbaDatabase

    .DESCRIPTION
        Upon being passed a list of potential backups files this command will scan the files, select those that contain SQL Server
        backup sets. It will then filter those files down to a set

        The function defaults to working on a remote instance. This means that all paths passed in must be relative to the remote instance.
        XpDirTree will be used to perform the file scans

        Various means can be used to pass in a list of files to be considered. The default is to non recursively scan the folder
        passed in.

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
        If this switch is set, then Files will be parsed as locally files. This can cause failures if the running user can see files that the parsing SQL Instance cannot

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

    .PARAMETER AzureCredential
        The name of the SQL Server credential to be used if restoring from an Azure hosted backup

    .PARAMETER Import
        When specified along with a path the command will import a previously exported BackupHistory object from an xml file.

    .PARAMETER EnableException
        Replaces user friendly yellow warnings with bloody red exceptions of doom!
        Use this if you want the function to throw terminating errors you want to catch.

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

    #>
    [CmdletBinding( DefaultParameterSetName = "Create")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "", Justification = "For Parameter AzureCredential")]
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
        [switch]$DirectoryRecurse,
        [switch]$EnableException,
        [switch]$MaintenanceSolution,
        [switch]$IgnoreLogBackup,
        [switch]$IgnoreDiffBackup,
        [string]$ExportPath,
        [string]$AzureCredential,
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
                $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $SqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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
            if ($Path[0] -match 'http') { $NoXpDirTree = $true }
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
                            $Files += Get-XpDirTreeRestoreFile -Path $f -SqlInstance $server
                        }
                    } else {
                        Write-Message -Message "Testing a folder $f" -Level Verbose
                        $Files += $Check = Get-XpDirTreeRestoreFile -Path $f -SqlInstance $server
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
                            $Files += Get-XpDirTreeRestoreFile -Path $f\FULL -SqlInstance $server -NoRecurse
                            $Files += Get-XpDirTreeRestoreFile -Path $f\DIFF -SqlInstance $server -NoRecurse
                            $Files += Get-XpDirTreeRestoreFile -Path $f\LOG -SqlInstance $server -NoRecurse
                        } else {
                            Write-Message -Level VeryVerbose -Message "File"
                            $Files += $f
                        }
                    }
                }
            }

            if ($True -eq $MaintenanceSolution -and $True -eq $IgnoreLogBackup) {
                Write-Message -Level Verbose -Message "Skipping Log Backups as requested"
                $Files = $Files | Where-Object { $_.FullName -notlike '*\LOG\*' }
            }

            if ($True -eq $MaintenanceSolution -and $True -eq $IgnoreDiffBackup) {
                Write-Message -Level Verbose -Message "Skipping Differential Backups as requested"
                $Files = $Files | Where-Object { $_.FullName -notlike '*\DIFF\*' }
            }

            if ($Files.Count -gt 0) {
                Write-Message -Level Verbose -Message "Reading backup headers of $($Files.Count) files"
                $FileDetails = Read-DbaBackupHeader -SqlInstance $server -Path $Files -AzureCredential $AzureCredential
            }

            $groupDetails = $FileDetails | Group-Object -Property BackupSetGUID

            foreach ($group in $groupDetails) {
                $dbLsn = $group.Group[0].DatabaseBackupLSN
                if (-not $dbLsn) {
                    $dbLsn = 0
                }
                $description = $group.Group[0].BackupTypeDescription
                if (-not $description) {
                    $header = Read-DbaBackupHeader -SqlInstance $server -Path $Path | Select-Object -First 1
                    $description = switch ($header.BackupType) {
                        1 { "Full" }
                        2 { "Differential" }
                        3 { "Log" }
                    }
                }
                $historyObject = New-Object Sqlcollaborative.Dbatools.Database.BackupHistory
                $historyObject.ComputerName = $group.Group[0].MachineName
                $historyObject.InstanceName = $group.Group[0].ServiceName
                $historyObject.SqlInstance = $group.Group[0].ServerName
                $historyObject.Database = $group.Group[0].DatabaseName
                $historyObject.UserName = $group.Group[0].UserName
                $historyObject.Start = [DateTime]$group.Group[0].BackupStartDate
                $historyObject.End = [DateTime]$group.Group[0].BackupFinishDate
                $historyObject.Duration = ([DateTime]$group.Group[0].BackupFinishDate - [DateTime]$group.Group[0].BackupStartDate)
                $historyObject.Path = [string[]]$group.Group.BackupPath
                $historyObject.FileList = ($group.Group.FileList | Select-Object Type, LogicalName, PhysicalName -Unique)
                $historyObject.TotalSize = ($group.Group.BackupSize.Byte | Measure-Object -Sum).Sum
                $HistoryObject.CompressedBackupSize = ($group.Group.CompressedBackupSize.Byte | Measure-Object -Sum).Sum
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