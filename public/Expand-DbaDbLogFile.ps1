function Expand-DbaDbLogFile {
    <#
    .SYNOPSIS
        Grows transaction log files using calculated increment sizes to prevent excessive Virtual Log File (VLF) fragmentation.

    .DESCRIPTION
        This function intelligently grows transaction log files to target sizes while minimizing Virtual Log File (VLF) fragmentation. It calculates optimal increment sizes based on your SQL Server version and target log size, then grows the log in controlled chunks instead of letting autogrowth create excessive VLFs.

        Too many VLFs create serious performance problems: slow transaction log backups, delayed database recovery during startup, and in extreme cases, degraded insert/update/delete performance. This command helps you proactively size your log files or fix existing VLF fragmentation issues.

        References:
        http://www.sqlskills.com/blogs/kimberly/transaction-log-vlfs-too-many-or-too-few/
        http://blogs.msdn.com/b/saponsqlserver/archive/2012/02/22/too-many-virtual-log-files-vlfs-can-cause-slow-database-recovery.aspx
        http://www.brentozar.com/blitz/high-virtual-log-file-vlf-count/

        In order to get rid of this fragmentation we need to grow the file taking the following into consideration:
        - How many VLFs are created when we perform a grow operation or when an auto-grow is invoked?

        Note: In SQL Server 2014 this algorithm has changed (http://www.sqlskills.com/blogs/paul/important-change-vlf-creation-algorithm-sql-server-2014/)

        Attention:
        We are growing in MB instead of GB because of known issue prior to SQL 2012:
        More detail here:
        http://www.sqlskills.com/BLOGS/PAUL/post/Bug-log-file-growth-broken-for-multiples-of-4GB.aspx
        and
        http://connect.microsoft.com/SqlInstance/feedback/details/481594/log-growth-not-working-properly-with-specific-growth-sizes-vlfs-also-not-created-appropriately
        or
        https://connect.microsoft.com/SqlInstance/feedback/details/357502/transaction-log-file-size-will-not-grow-exactly-4gb-when-filegrowth-4gb

        Understanding related problems:
        http://www.sqlskills.com/blogs/kimberly/transaction-log-vlfs-too-many-or-too-few/
        http://blogs.msdn.com/b/saponsqlserver/archive/2012/02/22/too-many-virtual-log-files-vlfs-can-cause-slow-database-recovery.aspx
        http://www.brentozar.com/blitz/high-virtual-log-file-vlf-count/

        Known bug before SQL Server 2012
        http://www.sqlskills.com/BLOGS/PAUL/post/Bug-log-file-growth-broken-for-multiples-of-4GB.aspx
        http://connect.microsoft.com/SqlInstance/feedback/details/481594/log-growth-not-working-properly-with-specific-growth-sizes-vlfs-also-not-created-appropriately
        https://connect.microsoft.com/SqlInstance/feedback/details/357502/transaction-log-file-size-will-not-grow-exactly-4gb-when-filegrowth-4gb

        How it works?
        The transaction log will grow in chunks until it reaches the desired size.
        Example: If you have a log file with 8192MB and you say that the target size is 81920MB (80GB) it will grow in chunks of 8192MB until it reaches 81920MB. 8192 -> 16384 -> 24576 ... 73728 -> 81920

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Database
        Specifies which databases to expand transaction log files for. Accepts wildcards for pattern matching.
        If not specified, all accessible databases on the instance will be processed. Use this when you need to target specific databases instead of processing the entire instance.

    .PARAMETER TargetLogSize
        Sets the final size you want the transaction log to reach, specified in megabytes.
        This should be large enough to handle your typical transaction volume plus growth buffer. Common values range from 1GB (1024MB) for smaller databases to 10GB+ for high-transaction systems.

    .PARAMETER IncrementSize
        Controls the size of each growth operation in megabytes during the expansion process.
        If not specified, the function calculates an optimal increment size based on your target size and SQL Server version to minimize VLF fragmentation. Only specify this if you need to override the intelligent defaults.

    .PARAMETER LogFileId
        Targets a specific transaction log file by its file ID number when databases have multiple log files.
        Use this when you need to expand secondary log files instead of the primary log file. Get the file ID from sys.database_files or SSMS properties.

    .PARAMETER ShrinkLogFile
        Shrinks the transaction log to the ShrinkSize before expanding it to the target size.
        This removes excessive VLF fragmentation by first reducing the log, then growing it with optimal increment sizes. Requires transaction log backups and cannot be used with Simple recovery model databases.

    .PARAMETER ShrinkSize
        Sets the intermediate size in megabytes to shrink the log file to before re-expanding.
        This should be small enough to remove VLF fragmentation but large enough to handle active transactions. Typical values are 10-100MB depending on transaction activity.

    .PARAMETER BackupDirectory
        Sets the directory path where transaction log backups will be created during the shrink process.
        Transaction log backups are required to shrink log files, so this directory must be accessible to the SQL Server service account. Defaults to the instance's default backup directory if not specified.

    .PARAMETER ExcludeDiskSpaceValidation
        Skips the automatic disk space validation that normally ensures sufficient free space exists before expanding log files.
        Use this when you're confident about available disk space but PowerShell remoting isn't available to check drive capacity, or when working with network storage that may not report correctly.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER ExcludeDatabase
        Specifies databases to skip during the expansion process when processing all databases on an instance.
        Use this to exclude system databases, read-only databases, or databases with specific requirements from batch log file expansion operations.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Storage, LogFile
        Author: Claudio Silva (@ClaudioESSilva)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: ALTER DATABASE permission
        Limitations: Freespace cannot be validated on the directory where the log file resides in SQL Server 2005.
        This script uses Get-DbaDiskSpace dbatools command to get the TLog's drive free space

    .LINK
        https://dbatools.io/Expand-DbaDbLogFile

    .EXAMPLE
        PS C:\> Expand-DbaDbLogFile -SqlInstance sqlcluster -Database db1 -TargetLogSize 50000

        Grows the transaction log for database db1 on sqlcluster to 50000 MB and calculates the increment size.

    .EXAMPLE
        PS C:\> Expand-DbaDbLogFile -SqlInstance sqlcluster -Database db1, db2 -TargetLogSize 10000 -IncrementSize 200

        Grows the transaction logs for databases db1 and db2 on sqlcluster to 1000MB and sets the growth increment to 200MB.

    .EXAMPLE
        PS C:\> Expand-DbaDbLogFile -SqlInstance sqlcluster -Database db1 -TargetLogSize 10000 -LogFileId 9

        Grows the transaction log file  with FileId 9 of the db1 database on sqlcluster instance to 10000MB.

    .EXAMPLE
        PS C:\> Expand-DbaDbLogFile -SqlInstance sqlcluster -Database (Get-Content D:\DBs.txt) -TargetLogSize 50000

        Grows the transaction log of the databases specified in the file 'D:\DBs.txt' on sqlcluster instance to 50000MB.

    .EXAMPLE
        PS C:\> Expand-DbaDbLogFile -SqlInstance SqlInstance -Database db1,db2 -TargetLogSize 100 -IncrementSize 10 -ShrinkLogFile -ShrinkSize 10 -BackupDirectory R:\MSSQL\Backup

        Grows the transaction logs for databases db1 and db2 on SQL server SQLInstance to 100MB, sets the incremental growth to 10MB, shrinks the transaction log to 10MB and uses the directory R:\MSSQL\Backup for the required backups.

    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Default')]
    param (
        [parameter(Position = 1, Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [parameter(Position = 3)]
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [parameter(Position = 4)]
        [object[]]$ExcludeDatabase,
        [parameter(Position = 5, Mandatory)]
        [int]$TargetLogSize,
        [parameter(Position = 6)]
        [int]$IncrementSize = -1,
        [parameter(Position = 7)]
        [int]$LogFileId = -1,
        [parameter(Position = 8, ParameterSetName = 'Shrink', Mandatory)]
        [switch]$ShrinkLogFile,
        [parameter(Position = 9, ParameterSetName = 'Shrink', Mandatory)]
        [int]$ShrinkSize,
        [parameter(Position = 10, ParameterSetName = 'Shrink')]
        [AllowEmptyString()]
        [string]$BackupDirectory,
        [switch]$ExcludeDiskSpaceValidation,
        [switch]$EnableException
    )

    begin {
        Write-Message -Level Verbose -Message "Set ErrorActionPreference to Inquire."
        $ErrorActionPreference = 'Inquire'

        #Convert MB to KB (SMO works in KB)
        Write-Message -Level Verbose -Message "Convert variables MB to KB (SMO works in KB)."
        [int]$TargetLogSizeKB = $TargetLogSize * 1024
        [int]$LogIncrementSize = $IncrementSize * 1024
        [int]$ShrinkSizeKB = $ShrinkSize * 1024
        [int]$SuggestLogIncrementSize = 0
        [bool]$LogByFileID = if ($LogFileId -eq -1) {
            $false
        } else {
            $true
        }

        #Set base information
        Write-Message -Level Verbose -Message "Initialize the instance '$SqlInstance'."

        try {
            $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
        }

        if ($ShrinkLogFile -eq $true) {
            if ($BackupDirectory.length -eq 0) {
                $backupdirectory = $server.Settings.BackupDirectory
            }

            $pathexists = Test-DbaPath -SqlInstance $server -Path $backupdirectory

            if ($pathexists -eq $false) {
                Stop-Function -Message "Backup directory does not exist."
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        try {

            [datetime]$initialTime = Get-Date

            #control the iteration number
            $databaseProgressbar = 0;

            Write-Message -Level Verbose -Message "Resolving FullComputerName name."
            # We don't have windows credentials here, so Resolve-DbaNetworkName has to respect that and work like Resolve-NetBiosName did before.
            $resolvedComputerName = Resolve-DbaComputerName -ComputerName $SqlInstance

            $databases = $server.Databases | Where-Object IsAccessible
            Write-Message -Level Verbose -Message "Number of databases found: $($databases.Count)."
            if ($Database) {
                $databases = $databases | Where-Object Name -In $Database
            }
            if ($ExcludeDatabase) {
                $databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
            }

            #go through all databases
            Write-Message -Level Verbose -Message "Processing...foreach database..."
            foreach ($db in $databases) {
                $dbName = $db.Name

                Write-Message -Level Verbose -Message "Working on $dbName."
                $databaseProgressbar += 1

                #set step to reutilize on logging operations
                [string]$step = "$databaseProgressbar/$($Databases.Count)"

                if ($db) {
                    Write-Progress `
                        -Id 1 `
                        -Activity "Using database: $dbName on Instance: '$SqlInstance'" `
                        -PercentComplete ($databaseProgressbar / $Databases.Count * 100) `
                        -Status "Processing - $databaseProgressbar of $($Databases.Count)"

                    #Validate which file will grow
                    if ($LogByFileID) {
                        $logfile = $db.LogFiles.ItemById($LogFileId)
                    } else {
                        $logfile = $db.LogFiles[0]
                    }

                    $numLogfiles = $db.LogFiles.Count

                    Write-Message -Level Verbose -Message "$step - Use log file: $logfile."
                    $currentSize = $logfile.Size
                    $currentSizeMB = $currentSize / 1024

                    #Get the number of VLFs
                    $initialVLFCount = Measure-DbaDbVirtualLogFile -SqlInstance $server -Database $dbName

                    Write-Message -Level Verbose -Message "$step - Log file current size: $([System.Math]::Round($($currentSize/1024.0), 2)) MB "
                    [long]$requiredSpace = ($TargetLogSizeKB - $currentSize)

                    if ($ExcludeDiskSpaceValidation -eq $false) {
                        Write-Message -Level Verbose -Message "Verifying if sufficient space exists ($([System.Math]::Round($($requiredSpace / 1024.0), 2))MB) on the volume to perform this task."

                        [long]$TotalTLogFreeDiskSpaceKB = 0
                        Write-Message -Level Verbose -Message "Get TLog drive free space"

                        try {
                            # That would need a Credential, but we don't have one...
                            [object]$AllDrivesFreeDiskSpace = Get-DbaDiskSpace -ComputerName $resolvedComputerName | Select-Object Name, SizeInKB

                            #Verify path using Split-Path on $logfile.FileName in backwards. This way we will catch the LUNs. Example: "K:\Log01" as LUN name. Need to add final backslash if not there
                            $DrivePath = Split-Path $logfile.FileName -parent
                            $DrivePath = if (!($DrivePath.EndsWith("\"))) { "$DrivePath\" }
                            else { $DrivePath }
                            Do {
                                if ($AllDrivesFreeDiskSpace | Where-Object { $DrivePath -eq "$($_.Name)" }) {
                                    $TotalTLogFreeDiskSpaceKB = ($AllDrivesFreeDiskSpace | Where-Object { $DrivePath -eq $_.Name }).SizeInKB
                                    $match = $true
                                    break
                                } else {
                                    $match = $false
                                    $DrivePath = Split-Path $DrivePath -parent
                                    $DrivePath = if (!($DrivePath.EndsWith("\"))) { "$DrivePath\" }
                                    else { $DrivePath }
                                }

                            }
                            while (!$match -or ([string]::IsNullOrEmpty($DrivePath)))

                            Write-Message -Level Verbose -Message "Total TLog Free Disk Space in MB: $([System.Math]::Round($($TotalTLogFreeDiskSpaceKB / 1024.0), 2))"

                        } catch {
                            #Could not validate the disk space. Will ask if we want to continue.
                            $TotalTLogFreeDiskSpaceKB = 0
                        }

                        if (($TotalTLogFreeDiskSpaceKB -le 0) -or ([string]::IsNullOrEmpty($TotalTLogFreeDiskSpaceKB))) {
                            $title = "Choose increment value for database '$dbName':"
                            $message = "Cannot validate freespace on drive where the log file resides. Do you wish to continue? (Y/N)"
                            $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will continue"
                            $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Will exit"
                            $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
                            $result = $host.ui.PromptForChoice($title, $message, $options, 0)
                            #no
                            if ($result -eq 1) {
                                Write-Message -Level Warning -Message "You have cancelled the execution"
                                return
                            }
                        } elseif ($requiredSpace -gt $TotalTLogFreeDiskSpaceKB) {
                            Write-Message -Level Verbose -Message "There is not enough space on volume to perform this task. `r`n" `
                                "Available space: $([System.Math]::Round($($TotalTLogFreeDiskSpaceKB / 1024.0), 2))MB;`r`n" `
                                "Required space: $([System.Math]::Round($($requiredSpace / 1024.0), 2))MB;"
                            return
                        }
                    }

                    if ($currentSize -ige $TargetLogSizeKB -and ($ShrinkLogFile -eq $false)) {
                        Write-Message -Level Verbose -Message "$step - [INFO] The T-Log file '$logfile' size is already equal or greater than target size - No action required."
                    } else {
                        Write-Message -Level Verbose -Message "$step - [OK] There is sufficient free space to perform this task."

                        # If SQL Server version is greater or equal to 2012
                        if ($server.Version.Major -ge "11") {
                            switch ($TargetLogSize) {
                                { $_ -le 64 } { $SuggestLogIncrementSize = 64 }
                                { $_ -ge 64 -and $_ -lt 256 } { $SuggestLogIncrementSize = 256 }
                                { $_ -ge 256 -and $_ -lt 1024 } { $SuggestLogIncrementSize = 512 }
                                { $_ -ge 1024 -and $_ -lt 4096 } { $SuggestLogIncrementSize = 1024 }
                                { $_ -ge 4096 -and $_ -lt 8192 } { $SuggestLogIncrementSize = 2048 }
                                { $_ -ge 8192 -and $_ -lt 16384 } { $SuggestLogIncrementSize = 4096 }
                                { $_ -ge 16384 } { $SuggestLogIncrementSize = 8192 }
                            }
                        }
                        # 2008 R2 or under
                        else {
                            switch ($TargetLogSize) {
                                { $_ -le 64 } { $SuggestLogIncrementSize = 64 }
                                { $_ -ge 64 -and $_ -lt 256 } { $SuggestLogIncrementSize = 256 }
                                { $_ -ge 256 -and $_ -lt 1024 } { $SuggestLogIncrementSize = 512 }
                                { $_ -ge 1024 -and $_ -lt 4096 } { $SuggestLogIncrementSize = 1024 }
                                { $_ -ge 4096 -and $_ -lt 8192 } { $SuggestLogIncrementSize = 2048 }
                                { $_ -ge 8192 -and $_ -lt 16384 } { $SuggestLogIncrementSize = 4000 }
                                { $_ -ge 16384 } { $SuggestLogIncrementSize = 8000 }
                            }

                            if (($IncrementSize % 4096) -eq 0) {
                                Write-Message -Level Verbose -Message "Your instance version is below SQL 2012, remember the known BUG mentioned on HELP. `r`nUse Get-Help Expand-DbaTLogFileResponsibly to read help`r`nUse a different value for incremental size.`r`n"
                                return
                            }
                        }
                        Write-Message -Level Verbose -Message "Instance $server version: $($server.Version.Major) - Suggested TLog increment size: $($SuggestLogIncrementSize)MB"

                        # Shrink Log File to desired size before re-growth to desired size (You need to remove as many VLF's as possible to ensure proper growth)
                        $ShrinkSize = $ShrinkSizeKB / 1024
                        if ($ShrinkLogFile -eq $true) {
                            if ($db.RecoveryModel -eq [Microsoft.SqlServer.Management.Smo.RecoveryModel]::Simple) {
                                Write-Message -Level Warning -Message "Database '$dbName' is in Simple RecoveryModel which does not allow log backups. Do not specify -ShrinkLogFile and -ShrinkSize parameters."
                                Continue
                            }

                            try {
                                $sql = "SELECT last_log_backup_lsn FROM sys.database_recovery_status WHERE database_id = DB_ID('$dbName')"
                                $sqlResult = $server.ConnectionContext.ExecuteWithResults($sql);

                                if ($sqlResult.Tables[0].Rows[0]["last_log_backup_lsn"] -is [System.DBNull]) {
                                    Write-Message -Level Warning -Message "First, you need to make a full backup before you can do Tlog backup on database '$dbName' (last_log_backup_lsn is null)."
                                    Continue
                                }
                            } catch {
                                Stop-Function -Message "Can't execute SQL on $server. `r`n $($_)" -Continue
                            }

                            If ($Pscmdlet.ShouldProcess($($server.name), "Backing up TLog for $dbName")) {
                                Write-Message -Level Verbose -Message "We are about to backup the Tlog for database '$dbName' to '$backupdirectory' and shrink the log."
                                Write-Message -Level Verbose -Message "Starting Size = $currentSizeMB."

                                $DefaultCompression = $server.Configuration.DefaultBackupCompression.ConfigValue

                                if ($currentSizeMB -gt $ShrinkSize) {
                                    $backupRetries = 1
                                    Do {
                                        try {
                                            $percent = $null
                                            $backup = New-Object Microsoft.SqlServer.Management.Smo.Backup
                                            $backup.Action = [Microsoft.SqlServer.Management.Smo.BackupActionType]::Log
                                            $backup.BackupSetDescription = "Transaction Log backup of " + $dbName
                                            $backup.BackupSetName = $dbName + " Backup"
                                            $backup.Database = $dbName
                                            $backup.MediaDescription = "Disk"
                                            $dt = Get-Date -format yyyyMMddHHmmssms
                                            $null = $backup.Devices.AddDevice($backupdirectory + "\" + $dbName + "_db_" + $dt + ".trn", 'File')
                                            if ($DefaultCompression -eq $true) {
                                                $backup.CompressionOption = 1
                                            } else {
                                                $backup.CompressionOption = 0
                                            }
                                            $null = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
                                                Write-Progress -id 2 -ParentId 1 -activity "Backing up $dbName to $server" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
                                            }
                                            $backup.add_PercentComplete($percent)
                                            $backup.PercentCompleteNotification = 10
                                            $backup.add_Complete($complete)
                                            Write-Progress -id 2 -ParentId 1 -activity "Backing up $dbName to $server" -percentcomplete 0 -Status ([System.String]::Format("Progress: {0} %", 0))
                                            $backup.SqlBackup($server)
                                            Write-Progress -id 2 -ParentId 1 -activity "Backing up $dbName to $server" -status "Complete" -Completed
                                            $logfile.Shrink($ShrinkSize, [Microsoft.SqlServer.Management.SMO.ShrinkMethod]::TruncateOnly)
                                            $logfile.Refresh()
                                        } catch {
                                            Write-Progress -id 1 -activity "Backup" -status "Failed" -completed
                                            Stop-Function -Message "Backup failed for database" -ErrorRecord $_ -Target $dbName -Continue
                                            Continue
                                        }

                                    }
                                    while (($logfile.Size / 1024) -gt $ShrinkSize -and ++$backupRetries -lt 6)

                                    $currentSize = $logfile.Size
                                    Write-Message -Level Verbose -Message "TLog backup and truncate for database '$dbName' finished. Current TLog size after $backupRetries backups is $($currentSize/1024)MB"
                                }
                            }
                        }

                        # SMO uses values in KB
                        $SuggestLogIncrementSize = $SuggestLogIncrementSize * 1024

                        # If default, use $SuggestedLogIncrementSize
                        if ($IncrementSize -eq -1) {
                            $LogIncrementSize = $SuggestLogIncrementSize
                        } else {
                            if ($LogIncrementSize -lt $SuggestLogIncrementSize) {
                                Write-Message -Level Warning -Message "The input value for increment size is $([System.Math]::Round($LogIncrementSize / 1024, 0))MB, which is less than the suggested value of $($SuggestLogIncrementSize / 1024)MB."
                            }
                        }

                        #start growing file
                        If ($Pscmdlet.ShouldProcess($($server.name), "Starting log growth. Increment chunk size: $($LogIncrementSize/1024)MB for database '$dbName'")) {
                            Write-Message -Level Verbose -Message "Starting log growth. Increment chunk size: $($LogIncrementSize/1024)MB for database '$dbName'"

                            Write-Message -Level Verbose -Message "$step - While current size less than target log size."

                            while ($currentSize -lt $TargetLogSizeKB) {

                                Write-Progress `
                                    -Id 2 `
                                    -ParentId 1 `
                                    -Activity "Growing file $logfile on '$dbName' database" `
                                    -PercentComplete ($currentSize / $TargetLogSizeKB * 100) `
                                    -Status "Remaining - $([System.Math]::Round($($($TargetLogSizeKB - $currentSize) / 1024.0), 2)) MB"

                                Write-Message -Level Verbose -Message "$step - Verifying if the log can grow or if it's already at the desired size."
                                if (($TargetLogSizeKB - $currentSize) -lt $LogIncrementSize) {
                                    Write-Message -Level Verbose -Message "$step - Log size is lower than the increment size. Setting current size equals $TargetLogSizeKB."
                                    $currentSize = $TargetLogSizeKB
                                } else {
                                    Write-Message -Level Verbose -Message "$step - Grow the $logfile file in $([System.Math]::Round($($LogIncrementSize / 1024.0), 2)) MB"
                                    $currentSize += $LogIncrementSize
                                }

                                #When -WhatIf Switch, do not run
                                if ($PSCmdlet.ShouldProcess("$step - File will grow to $([System.Math]::Round($($currentSize/1024.0), 2)) MB", "This action will grow the file $logfile on database $dbName to $([System.Math]::Round($($currentSize/1024.0), 2)) MB .`r`nDo you wish to continue?", "Perform grow")) {
                                    Write-Message -Level Verbose -Message "$step - Set size $logfile to $([System.Math]::Round($($currentSize/1024.0), 2)) MB"
                                    $logfile.size = $currentSize

                                    Write-Message -Level Verbose -Message "$step - Applying changes"
                                    $logfile.Alter()
                                    Write-Message -Level Verbose -Message "$step - Changes have been applied"

                                    #Will put the info like VolumeFreeSpace up to date
                                    $logfile.Refresh()
                                }
                            }

                            Write-Message -Level Verbose -Message "`r`n$step - [OK] Growth process for logfile '$logfile' on database '$dbName', has been finished."

                            Write-Message -Level Verbose -Message "$step - Grow $logfile log file on $dbName database finished."
                        }
                    }
                }
                #else verifying existence
                else {
                    Write-Message -Level Verbose -Message "Database '$dbName' does not exist on instance '$SqlInstance'."
                }

                #Get the number of VLFs
                $currentVLFCount = Measure-DbaDbVirtualLogFile -SqlInstance $server -Database $dbName

                [PSCustomObject]@{
                    ComputerName    = $server.ComputerName
                    InstanceName    = $server.ServiceName
                    SqlInstance     = $server.DomainInstanceName
                    Database        = $dbName
                    DatabaseID      = $db.ID
                    ID              = $logfile.ID
                    Name            = $logfile.Name
                    LogFileCount    = $numLogfiles
                    InitialSize     = [dbasize]($currentSizeMB * 1024 * 1024)
                    CurrentSize     = [dbasize]($TargetLogSize * 1024 * 1024)
                    InitialVLFCount = $initialVLFCount.Total
                    CurrentVLFCount = $currentVLFCount.Total
                } | Select-DefaultView -ExcludeProperty LogFileCount
            } #foreach database
        } catch {
            Stop-Function -Message "Logfile $logfile on database $dbName not processed. Error: $($_.Exception.Message). Line Number:  $($_InvocationInfo.ScriptLineNumber)" -Continue
        }
    }

    end {
        Write-Message -Level Verbose -Message "Process finished $((Get-Date) - ($initialTime))"
    }
}