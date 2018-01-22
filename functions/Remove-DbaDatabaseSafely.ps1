function Remove-DbaDatabaseSafely {
    <#
        .SYNOPSIS
            Safely removes a SQL Database and creates an Agent Job to restore it.

        .DESCRIPTION
            Performs a DBCC CHECKDB on the database, backs up the database with Checksum and verify only to a final (golden) backup location, creates an Agent Job to restore from that backup, drops the database, runs the agent job to restore the database, performs a DBCC CHECKDB and drops the database.

            With huge thanks to Grant Fritchey and his verify your backups video. Take a look, it's only 3 minutes long. http://sqlps.io/backuprant

        .PARAMETER SqlInstance
            The SQL Server instance holding the databases to be removed. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

            Windows Authentication will be used if SourceSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Destination
            If specified, Agent jobs will be created on this server. By default, the jobs will be created on the server specified by SqlInstance. You must have sysadmin access and the server must be SQL Server 2000 or higher. The SQL Agent service will be started if it is not already running.

        .PARAMETER DestinationCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

            Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Database
            Specifies one or more databases to remove.

        .PARAMETER NoDbccCheckDb
            If this switch is enabled, the initial DBCC CHECK DB will be skipped. This will make the process quicker but will also allow you to create an Agent job that restores a database backup containing a corrupt database.

            A second DBCC CHECKDB is performed on the restored database so you will still be notified BUT USE THIS WITH CARE.

        .PARAMETER BackupFolder
            Specifies the path to a folder where the final backups of the removed databases will be stored. If you are using separate source and destination servers, you must specify a UNC path such as  \\SERVER1\BACKUPSHARE\

        .PARAMETER JobOwner
            Specifies the name of the account which will own the Agent jobs. By default, sa is used.

        .PARAMETER UseDefaultFilePaths
            If this switch is enabled, the default file paths for the data and log files on the instance where the database is restored will be used. By default, the original file paths will be used.

        .PARAMETER CategoryName
            Specifies the Category Name for the Agent job that is created for restoring the database(s). By default, the name is "Rationalisation".

        .PARAMETER BackupCompression
            If this switch is enabled, compression will be used for the backup regardless of the SQL Server instance setting. By default, the SQL Server instance setting for backup compression is used.

        .PARAMETER AllDatabases
            If this switch is enabled, all user databases on the server will be removed. This is useful when decommissioning a server. You should use a DestinationServer with this switch.

        .PARAMETER ReuseSourceFolderStructure
            If this switch is enabled, the source folder structure will be used when restoring instead of using the destination instance default folder structure.

        .PARAMETER Force
            If this switch is enabled, all actions will be performed even if DBCC errors are detected. An Agent job will be created with 'DBCCERROR' in the name and the backup file will have 'DBCC' in its name.

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: DisasterRecovery, Backup, Restore, Databases
            Author: Rob Sewell @SQLDBAWithBeard, sqldbawithabeard.com

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Remove-DbaDatabaseSafely

        .EXAMPLE
            Remove-DbaDatabaseSafely -SqlInstance 'Fade2Black' -Database RideTheLightning -BackupFolder 'C:\MSSQL\Backup\Rationalised - DO NOT DELETE'

            Performs a DBCC CHECKDB on database RideTheLightning on server Fade2Black. If there are no errors, the database is backup to the folder C:\MSSQL\Backup\Rationalised - DO NOT DELETE. Then, an Agent job to restore the database from that backup is created. The database is then dropped, the Agent job to restore it run, a DBCC CHECKDB run against the restored database, and then it is dropped again.

            Any DBCC errors will be written to your documents folder

        .EXAMPLE
            $Database = 'DemoNCIndex','RemoveTestDatabase'
            Remove-DbaDatabaseSafely -SqlInstance 'Fade2Black' -Database $Database -BackupFolder 'C:\MSSQL\Backup\Rationalised - DO NOT DELETE'

            Performs a DBCC CHECKDB on two databases, 'DemoNCIndex' and 'RemoveTestDatabase' on server Fade2Black. Then, an Agent job to restore each database from those backups is created. The databases are then dropped, the Agent jobs to restore them run, a DBCC CHECKDB run against the restored databases, and then they are dropped again.

            Any DBCC errors will be written to your documents folder

        .EXAMPLE
            Remove-DbaDatabaseSafely -SqlInstance 'Fade2Black' -DestinationServer JusticeForAll -Database RideTheLightning -BackupFolder '\\BACKUPSERVER\BACKUPSHARE\MSSQL\Rationalised - DO NOT DELETE'

            Performs a DBCC CHECKDB on database RideTheLightning on server Fade2Black. If there are no errors, the database is backup to the folder \\BACKUPSERVER\BACKUPSHARE\MSSQL\Rationalised - DO NOT DELETE . Then, an Agent job is created on server JusticeForAll to restore the database from that backup is created. The database is then dropped on Fade2Black, the Agent job to restore it on JusticeForAll is run, a DBCC CHECKDB run against the restored database, and then it is dropped from JusticeForAll.

            Any DBCC errors will be written to your documents folder

        .EXAMPLE
            Remove-DbaDatabaseSafely -SqlInstance IronMaiden -Database $Database -DestinationServer TheWildHearts -BackupFolder Z:\Backups -NoDbccCheckDb -UseDefaultFilePaths -JobOwner 'THEBEARD\Rob'

            For the databases $Database on the server IronMaiden a DBCC CHECKDB will not be performed before backing up the databases to the folder Z:\Backups. Then, an Agent job is created on server TheWildHearts with a Job Owner of THEBEARD\Rob to restore each database from that backup using the instance's default file paths. The database(s) is(are) then dropped on IronMaiden, the Agent job(s) run, a DBCC CHECKDB run on the restored database(s), and then the database(s) is(are) dropped.

        .EXAMPLE
            Remove-DbaDatabaseSafely -SqlInstance IronMaiden -Database $Database -DestinationServer TheWildHearts -BackupFolder Z:\Backups -UseDefaultFilePaths -ContinueAfterDbccError

            The databases $Database on the server IronMaiden will be backed up the to the folder Z:\Backups. Then, an Agent job is created on server TheWildHearts with a Job Owner of THEBEARD\Rob to restore each database from that backup using the instance's default file paths. The database(s) is(are) then dropped on IronMaiden, the Agent job(s) run, a DBCC CHECKDB run on the restored database(s), and then the database(s) is(are) dropped.

            If there is a DBCC Error, the function  will continue to perform rest of the actions and will create an Agent job with 'DBCCERROR' in the name and a Backup file with 'DBCCError' in the name.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "Default")]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]
        $SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [parameter(Mandatory = $false)]
        [DbaInstanceParameter]$Destination = $sqlinstance,
        [PSCredential]
        $DestinationCredential,
        [parameter(Mandatory = $false)]
        [Alias("NoCheck")]
        [switch]$NoDbccCheckDb,
        [parameter(Mandatory = $true)]
        [string]$BackupFolder,
        [parameter(Mandatory = $false)]
        [string]$CategoryName = 'Rationalisation',
        [parameter(Mandatory = $false)]
        [string]$JobOwner,
        [parameter(Mandatory = $false)]
        [switch]$AllDatabases,
        [ValidateSet("Default", "On", "Of")]
        [string]$BackupCompression = 'Default',
        [switch]$ReuseSourceFolderStructure,
        [switch]$Force,
        [switch][Alias('Silent')]$EnableException
    )

    begin {
        if (!$AllDatabases -and !$Database) {
            Stop-Function -Message "You must specify at least one database. Use -Database or -AllDatabases." -InnerErrorRecord $_
            return
        }

        $sourceserver = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $sqlCredential -ParameterConnection

        if (-not $destination) {
            $destination = $sqlinstance
            $DestinationCredential = $SqlCredential
        }

        if ($sqlinstance -ne $destination) {

            $destserver = Connect-SqlInstance -SqlInstance $destination -SqlCredential $DestinationCredential

            $sourcenb = $sourceserver.ComputerNamePhysicalNetBIOS
            $destnb = $sourceserver.ComputerNamePhysicalNetBIOS

            if ($BackupFolder.StartsWith("\\") -eq $false -and $sourcenb -ne $destnb) {
                Stop-Function -Message "Backup folder must be a network share if the source and destination servers are not the same." -InnerErrorRecord $_ -Target $backupFolder
                return
            }
        }
        else {
            $destserver = $sourceserver
        }

        $source = $sourceserver.DomainInstanceName
        $destination = $destserver.DomainInstanceName

        if (!$jobowner) {
            $jobowner = Get-SqlSaLogin $destserver
        }

        if ($alldatabases -or !$Database) {
            $database = ($sourceserver.databases | Where-Object { $_.IsSystemObject -eq $false -and ($_.Status -match 'Offline') -eq $false }).Name
        }

        if (!(Test-DbaSqlPath -SqlInstance $destserver -Path $backupFolder)) {
            $serviceaccount = $destserver.ServiceAccount
            Stop-Function -Message "Can't access $backupFolder Please check if $serviceaccount has permissions." -InnerErrorRecord $_ -Target $backupFolder
        }

        $jobname = "Rationalised Final Database Restore for $dbname"
        $jobStepName = "Restore the $dbname database from Final Backup"

        if (!($destserver.Logins | Where-Object { $_.Name -eq $jobowner })) {
            Stop-Function -Message "$destination does not contain the login $jobowner - Please fix and try again - Aborting." -InnerErrorRecord $_ -Target $jobowner
        }

        function Start-SqlAgent {
            <#
                .SYNOPSIS
            #>
            [CmdletBinding(SupportsShouldProcess = $true)]
            param ()
            if ($destserver.VersionMajor -eq 8) {
                $serviceName = 'MSSQLSERVER'
            }
            else {
                $instance = $destserver.InstanceName
                if ($instance.length -eq 0) { $instance = "MSSQLSERVER" }
                $serviceName = "SQL Server Agent ($instance)"
            }

            if ($Pscmdlet.ShouldProcess($destination, "Starting Sql Agent")) {
                try {
                    $ipaddr = Resolve-SqlIpAddress $destserver
                    $agentservice = Get-Service -ComputerName $ipaddr -DisplayName $serviceName

                    if ($agentservice.Status -ne 'Running') {
                        $agentservice.Start()
                        $timeout = New-Timespan -seconds 60
                        $sw = [diagnostics.stopwatch]::StartNew()
                        $agentstatus = (Get-Service -ComputerName $ipaddr -DisplayName $serviceName).Status
                        while ($AgentStatus -ne 'Running' -and $sw.elapsed -lt $timeout) {
                            $agentStatus = (Get-Service -ComputerName $ipaddr -DisplayName $serviceName).Status
                        }
                    }
                }

                catch {
                    Stop-Function -Message "Error occurred: $_" -Target $agentservice -InnerExceptionRecord $_
                    return
                }

                if ($agentservice.Status -ne 'Running') {
                    throw "Cannot start Agent Service on $destination - Aborting."
                }
            }
        }

        function Start-DbccCheck {
            <#
            .SYNOPSIS

            #>

            [CmdletBinding(SupportsShouldProcess = $true)]
            param (
                [object]$server,
                [string]$dbname
            )

            $servername = $server.name
            $db = $server.databases[$dbname]

            if ($Pscmdlet.ShouldProcess($sourceserver, "Running dbcc check on $dbname on $servername")) {
                try {
                    $null = $db.CheckTables('None')
                    Write-Message -Level Verbose -Message "DBCC CHECKDB finished successfully for $dbname on $servername."
                }

                catch {
                    Write-Message -Level Warning -Message "DBCC CHECKDB failed."
                    Stop-Function -Message "Error occured: $_" -Target $agentservice -InnerExceptionRecord $_ -Continue

                    if ($force) {
                        return $true
                    }
                    else {
                        return $false
                    }
                }
            }
        }

        function New-SqlAgentJobCategory {
            <#
                .SYNOPSIS

            #>
            [CmdletBinding(SupportsShouldProcess = $true)]
            param ([string]$categoryname,
                [object]$jobServer)

            if (!$jobServer.JobCategories[$categoryname]) {
                if ($Pscmdlet.ShouldProcess($sourceserver, "Running dbcc check on $dbname on $sourceserver")) {
                    try {
                        Write-Message -Level Verbose -Message "Creating Agent Job Category $categoryname."
                        $category = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobCategory
                        $category.Parent = $jobServer
                        $category.Name = $categoryname
                        $category.Create()
                        Write-Message -Level Verbose -Message "Created Agent Job Category $categoryname."
                    }
                    catch {
                        Stop-Function -Message "FAILED : To Create Agent Job Category - $categoryname - Aborting." -Target $categoryname -InnerExceptionRecord $_
                        return
                    }
                }
            }
        }

        function Restore-Database {
            <#
                .SYNOPSIS
                    Internal function. Restores .bak file to Sql database. Creates db if it doesn't exist. $filestructure is
                a custom object that contains logical and physical file locations.
            #>

            param (
                [Parameter(Mandatory = $true)]
                [Alias('ServerInstance', 'SqlInstance', 'SqlServer')]
                [object]$server,
                [Parameter(Mandatory = $true)]
                [ValidateNotNullOrEmpty()]
                [string]$dbname,
                [Parameter(Mandatory = $true)]
                [string]$backupfile,
                [string]$filetype = 'Database',
                [Parameter(Mandatory = $true)]
                [object]$filestructure,
                [switch]$norecovery,
                [PSCredential]$sqlCredential,
                [switch]$TSql = $false
            )

            $server = Connect-SqlInstance -SqlInstance $server -SqlCredential $sqlCredential
            $servername = $server.name
            $server.ConnectionContext.StatementTimeout = 0
            $restore = New-Object 'Microsoft.SqlServer.Management.Smo.Restore'
            $restore.ReplaceDatabase = $true

            foreach ($file in $filestructure.values) {
                $movefile = New-Object 'Microsoft.SqlServer.Management.Smo.RelocateFile'
                $movefile.LogicalFileName = $file.logical
                $movefile.PhysicalFileName = $file.physical
                $null = $restore.RelocateFiles.Add($movefile)
            }

            try {
                if ($TSql) {
                    $restore.PercentCompleteNotification = 1
                    $restore.add_Complete($complete)
                    $restore.ReplaceDatabase = $true
                    $restore.Database = $dbname
                    $restore.Action = $filetype
                    $restore.NoRecovery = $norecovery
                    $device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem
                    $device.name = $backupfile
                    $device.devicetype = 'File'
                    $restore.Devices.Add($device)
                    $restorescript = $restore.script($server)
                    return $restorescript
                }
                else {
                    $percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
                        Write-Progress -id 1 -activity "Restoring $dbname to $servername" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
                    }
                    $restore.add_PercentComplete($percent)
                    $restore.PercentCompleteNotification = 1
                    $restore.add_Complete($complete)
                    $restore.ReplaceDatabase = $true
                    $restore.Database = $dbname
                    $restore.Action = $filetype
                    $restore.NoRecovery = $norecovery
                    $device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem
                    $device.name = $backupfile
                    $device.devicetype = 'File'
                    $restore.Devices.Add($device)

                    Write-Progress -id 1 -activity "Restoring $dbname to $servername" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                    $restore.sqlrestore($server)
                    Write-Progress -id 1 -activity "Restoring $dbname to $servername" -status 'Complete' -Completed

                    return $true
                }
            }
            catch {
                Stop-Function -Message "Restore failed" -ErrorRecord $_ -Target $dbname
                return $false
            }
        }

    }
    process {
        if (Test-FunctionInterrupt) {
            return
        }
        Start-SqlAgent

        $start = Get-Date
        Write-Message -Level Verbose -Message "Starting Rationalisation Script at $start."

        foreach ($dbname in $Database) {

            $db = $sourceserver.databases[$dbname]

            # The db check is needed when the number of databases exceeds 255, then it's no longer auto-populated
            if (!$db) {
                Stop-Function -Message "$dbname does not exist on $source. Aborting routine for this database." -Continue
            }

            $lastFullBckDuration = (Get-DbaBackupHistory -SqlInstance $sourceserver -Database $dbname -LastFull).Duration

            if (-NOT ([string]::IsNullOrEmpty($lastFullBckDuration))) {
                $lastFullBckDurationSec = $lastFullBckDuration.TotalSeconds
                $lastFullBckDurationMin = [Math]::Round($lastFullBckDuration.TotalMinutes, 2)

                Write-Message -Level Verbose -Message "From the backup history the last full backup took $lastFullBckDurationSec seconds ($lastFullBckDurationMin minutes)"
                if ($lastFullBckDurationSec -gt 600) {
                    Write-Message -Level Verbose -Message "Last full backup took more than 10 minutes. Do you want to continue?"

                    # Set up the parts for the user choice
                    $Title = "Backup duration"
                    $Info = "Last full backup took more than $lastFullBckDurationMin minutes. Do you want to continue?"

                    $Options = [System.Management.Automation.Host.ChoiceDescription[]] @("&Yes", "&No (Skip)")
                    [int]$Defaultchoice = 0
                    $choice = $host.UI.PromptForChoice($Title, $Info, $Options, $Defaultchoice)
                    # Check the given option
                    if ($choice -eq 1) {
                        Stop-Function -Message "You have chosen skipping the database $dbname because of last known backup time ($lastFullBckDurationMin minutes)." -InnerErrorRecord $_ -Target $dbname -Continue
                        Continue
                    }
                }
            }
            else {
                Write-Message -Level Verbose -Message "Couldn't find last full backup time for database $dbname using Get-DbaBackupHistory."
            }

            $jobname = "Rationalised Database Restore Script for $dbname"
            $jobStepName = "Restore the $dbname database from Final Backup"
            $jobServer = $destserver.JobServer

            if ($jobServer.Jobs[$jobname].count -gt 0) {
                if ($force -eq $false) {
                    Stop-Function -Message "FAILED: The Job $jobname already exists. Have you done this before? Rename the existing job and try again or use -Force to drop and recreate." -Continue
                }
                else {
                    if ($Pscmdlet.ShouldProcess($dbname, "Dropping $jobname on $source")) {
                        Write-Message -Level Verbose -Message "Dropping $jobname on $source."
                        $jobServer.Jobs[$jobname].Drop()
                        $jobServer.Jobs.Refresh()
                    }
                }
            }


            Write-Message -Level Verbose -Message "Starting Rationalisation of $dbname."
            ## if we want to Dbcc before to abort if we have a corrupt database to start with
            if ($NoDbccCheckDb -eq $false) {
                if ($Pscmdlet.ShouldProcess($dbname, "Running dbcc check on $dbname on $source")) {
                    Write-Message -Level Verbose -Message "Starting DBCC CHECKDB for $dbname on $source."
                    $dbccgood = Start-DbccCheck -Server $sourceserver -DBName $dbname

                    if ($dbccgood -eq $false) {
                        if ($force -eq $false) {
                            Write-Message -Level Verbose -Message "DBCC failed for $dbname (you should check that).  Aborting routine for this database."
                            continue
                        }
                        else {
                            Write-Message -Level Verbose -Message "DBCC failed, but Force specified. Continuing."
                        }
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($source, "Backing up $dbname")) {
                Write-Message -Level Verbose -Message "Starting Backup for $dbname on $source."
                ## Take a Backup
                try {
                    $timenow = [DateTime]::Now.ToString('yyyyMMdd_HHmmss')
                    $backup = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Backup
                    $backup.Action = [Microsoft.SqlServer.Management.SMO.BackupActionType]::Database
                    $backup.BackupSetDescription = "Final Full Backup of $dbname Prior to Dropping"
                    $backup.Database = $dbname
                    $backup.Checksum = $True
                    if ($sourceserver.versionMajor -gt 9) {
                        $backup.CompressionOption = $BackupCompression
                    }
                    if ($force -and $dbccgood -eq $false) {

                        $filename = "$backupFolder\$($dbname)_DBCCERROR_$timenow.bak"
                    }
                    else {
                        $filename = "$backupFolder\$($dbname)_Final_Before_Drop_$timenow.bak"
                    }

                    $devicetype = [Microsoft.SqlServer.Management.Smo.DeviceType]::File
                    $backupDevice = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem($filename, $devicetype)

                    $backup.Devices.Add($backupDevice)
                    #Progress
                    $percent = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
                        Write-Progress -id 1 -activity "Backing up database $dbname on $source to $filename" -percentcomplete $_.Percent -status ([System.String]::Format("Progress: {0} %", $_.Percent))
                    }
                    $backup.add_PercentComplete($percent)
                    $backup.add_Complete($complete)
                    Write-Progress -id 1 -activity "Backing up database $dbname on $source to $filename" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
                    $backup.SqlBackup($sourceserver)
                    $null = $backup.Devices.Remove($backupDevice)
                    Write-Progress -id 1 -activity "Backing up database $dbname  on $source to $filename" -status "Complete" -Completed
                    Write-Message -Level Verbose -Message "Backup Completed for $dbname on $source."

                    Write-Message -Level Verbose -Message "Running Restore Verify only on Backup of $dbname on $source."
                    try {
                        $restoreverify = New-Object 'Microsoft.SqlServer.Management.Smo.Restore'
                        $restoreverify.Database = $dbname
                        $restoreverify.Devices.AddDevice($filename, $devicetype)
                        $result = $restoreverify.SqlVerify($sourceserver)

                        if ($result -eq $false) {
                            Write-Message -Level Warning -Message "FAILED : Restore Verify Only failed for $filename on $server - aborting routine for this database."
                            continue
                        }

                        Write-Message -Level Verbose -Message "Restore Verify Only for $filename succeeded."
                    }
                    catch {
                        Stop-Function -Message "FAILED : Restore Verify Only failed for $filename on $server - aborting routine for this database. Exception: $_" -Target $filename -InnerExceptionRecord $_ -Continue
                    }
                }
                catch {
                    Stop-Function -Message "FAILED : Restore Verify Only failed for $filename on $server - aborting routine for this database. Exception: $_" -Target $filename -InnerExceptionRecord $_ -Continue
                }
            }

            if ($Pscmdlet.ShouldProcess($destination, "Creating Automated Restore Job from Golden Backup for $dbname on $destination")) {
                Write-Message -Level Verbose -Message "Creating Automated Restore Job from Golden Backup for $dbname on $destination."
                try {
                    if ($force -eq $true -and $dbccgood -eq $false) {
                        $jobName = $jobname -replace "Rationalised", "DBCC ERROR"
                    }

                    ## Create an agent job to restore the database
                    $job = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job $jobServer, $jobname
                    $job.Name = $jobname
                    $job.OwnerLoginName = $jobowner
                    $job.Description = "This job will restore the $dbname database using the final backup located at $filename."

                    ## Create a Job Category
                    if (!$jobServer.JobCategories[$categoryname]) {
                        New-SqlAgentJobCategory -JobServer $jobServer -categoryname $categoryname
                    }

                    $job.Category = $categoryname
                    try {
                        if ($Pscmdlet.ShouldProcess($destination, "Creating Agent Job on $destination")) {
                            Write-Message -Level Verbose -Message "Created Agent Job $jobname on $destination."
                            $job.Create()
                        }
                    }
                    catch {
                        Stop-Function -Message "FAILED : To Create Agent Job $jobname on $destination - aborting routine for this database." -Target $categoryname -InnerExceptionRecord $_ -Continue
                    }

                    ## Create Job Step
                    ## Aaron's Suggestion: In the restore script, add a comment block that tells the last known size of each file in the database.
                    ## Suggestion check for disk space before restore
                    ## Create Restore Script
                    try {
                        $restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
                        $device = New-Object -TypeName Microsoft.SqlServer.Management.Smo.BackupDeviceItem $filename, 'FILE'
                        $restore.Devices.Add($device)
                        try {
                            $filelist = $restore.ReadFileList($destserver)
                        }

                        catch {
                            throw 'File list could not be determined. This is likely due to connectivity issues or tiemouts with the Sql Server, the database version is incorrect, or the Sql Server service account does not have access to the file share. Script terminating.'
                        }

                        $filestructure = Get-OfflineSqlFileStructure $destserver $dbname $filelist $ReuseSourceFolderStructure

                        $jobStepCommand = Restore-Database $destserver $dbname $filename "Database" $filestructure -TSql -ErrorAction Stop
                        $jobStep = new-object Microsoft.SqlServer.Management.Smo.Agent.JobStep $job, $jobStepName
                        $jobStep.SubSystem = 'TransactSql' # 'PowerShell'
                        $jobStep.DatabaseName = 'master'
                        $jobStep.Command = $jobStepCommand
                        $jobStep.OnSuccessAction = 'QuitWithSuccess'
                        $jobStep.OnFailAction = 'QuitWithFailure'
                        if ($Pscmdlet.ShouldProcess($destination, "Creating Agent JobStep on $destination")) {
                            $null = $jobStep.Create()
                        }
                        $jobStartStepid = $jobStep.ID
                        Write-Message -Level Verbose -Message "Created Agent JobStep $jobStepName on $destination."
                    }
                    catch {
                        Stop-Function -Message "FAILED : To Create Agent JobStep $jobStepName on $destination - Aborting." -Target $jobStepName -InnerExceptionRecord $_ -Continue
                    }
                    if ($Pscmdlet.ShouldProcess($destination, "Applying Agent Job $jobname to $destination")) {
                        $job.ApplyToTargetServer($destination)
                        $job.StartStepID = $jobStartStepid
                        $job.Alter()
                    }
                }
                catch {
                    Stop-Function -Message "FAILED : To Create Agent Job $jobname on $destination - aborting routine for $dbname. Exception: $_" -Target $jobname -InnerExceptionRecord $_ -Continue
                }
            }

            if ($Pscmdlet.ShouldProcess($destination, "Dropping Database $dbname on $sourceserver")) {
                ## Drop the database
                try {
                    # Remove-SqlDatabase is a function in SharedFunctions.ps1 that tries 3 different ways to drop a database
                    Remove-SqlDatabase -SqlInstance $sourceserver -DbName $dbname
                    Write-Message -Level Verbose -Message "Dropped $dbname Database on $source prior to running the Agent Job"
                }
                catch {
                    Stop-Function -Message "FAILED : To Drop database $dbname on $server - aborting routine for $dbname. Exception: $_" -Continue
                }
            }

            if ($Pscmdlet.ShouldProcess($destination, "Running Agent Job on $destination to restore $dbname")) {
                ## Run the restore job to restore it
                Write-Message -Level Verbose -Message "Starting $jobname on $destination."
                try {
                    $job = $destserver.JobServer.Jobs[$jobname]
                    $job.Start()
                    $job.Refresh()
                    $status = $job.CurrentRunStatus

                    while ($status -ne 'Idle') {
                        Write-Message -Level Verbose -Message "Restore Job for $dbname on $destination is $status."
                        Start-Sleep -Seconds 15
                        $job.Refresh()
                        $status = $job.CurrentRunStatus
                    }

                    Write-Message -Level Verbose -Message "Restore Job $jobname has completed on $destination."
                    Write-Message -Level Verbose -Message "Sleeping for a few seconds to ensure the next step (DBCC) succeeds."
                    Start-Sleep -Seconds 10 ## This is required to ensure the next DBCC Check succeeds
                }
                catch {
                    Stop-Function -Message "FAILED : Restore Job $jobname failed on $destination - aborting routine for $dbname. Exception: $_" -Continue
                }

                if ($job.LastRunOutcome -ne 'Succeeded') {
                    # LOL, love the plug.
                    Write-Message -Level Warning -Message "FAILED : Restore Job $jobname failed on $destination - aborting routine for $dbname."
                    Write-Message -Level Warning -Message "Check the Agent Job History on $destination - if you have SSMS2016 July release or later."
                    Write-Message -Level Warning -Message "Get-SqlAgentJobHistory -JobName $jobname -ServerInstance $destination -OutcomesType Failed."
                    continue
                }
            }

            $refreshRetries = 1

            while ($null -eq ($destserver.databases[$dbname]) -and $refreshRetries -lt 6) {
                Write-Message -Level verbose -Message "Database $dbname not found! Refreshing collection."

                #refresh database list, otherwise the next step (DBCC) can fail
                $destserver.Databases.Refresh()

                Start-Sleep -Seconds 1

                $refreshRetries += 1
            }


            ## Run a Dbcc No choice here
            if ($Pscmdlet.ShouldProcess($dbname, "Running Dbcc CHECKDB on $dbname on $destination")) {
                Write-Message -Level Verbose -Message "Starting Dbcc CHECKDB for $dbname on $destination."
                $null = Start-DbccCheck -Server $destserver -DbName $dbname
            }

            if ($Pscmdlet.ShouldProcess($dbname, "Dropping Database $dbname on $destination")) {
                ## Drop the database
                try {
                    $null = Remove-SqlDatabase -SqlInstance $sourceserver -DbName $dbname
                    Write-Message -Level Verbose -Message "Dropped $dbname database on $destination."
                }
                catch {
                    Stop-Function -Message "FAILED : To Drop database $dbname on $destination - Aborting. Exception: $_" -Target $dbname -InnerExceptionRecord $_ -Continue
                }
            }
            Write-Message -Level Verbose -Message "Rationalisation Finished for $dbname."

            [PSCustomObject]@{
                SqlInstance     = $source
                DatabaseName    = $dbname
                JobName         = $jobname
                TestingInstance = $destination
                BackupFolder    = $backupFolder
            }
        }
    }

    end {
        if ($Pscmdlet.ShouldProcess("console", "Showing final message")) {
            $End = Get-Date
            Write-Message -Level Verbose -Message "Finished at $End."
            $Duration = $End - $start
            Write-Message -Level Verbose -Message "Script Duration: $Duration."
        }

        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Remove-SqlDatabaseSafely
    }
}
