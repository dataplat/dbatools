function Remove-DbaDatabaseSafely {
    <#
    .SYNOPSIS
        Removes databases after creating verified backups and testing restore procedures.

    .DESCRIPTION
        Performs a comprehensive database removal workflow that validates database integrity, creates verified backups, and tests restore procedures before permanently removing databases. This function runs DBCC CHECKDB to verify database health, creates a checksummed backup to a specified location, generates a SQL Agent job for automated restore testing, drops the original database, executes the restore job to verify backup integrity, performs another DBCC check on the restored database, and finally removes the test database.

        This process ensures that removed databases have reliable, tested backups that can be restored if needed later. The automated restore job remains available for future recovery operations, making this ideal for database decommissioning, environment cleanup, or compliance scenarios where you need proof that backups are valid before removing production data.

        With huge thanks to Grant Fritchey and his verify your backups video. Take a look, it's only 3 minutes long. http://sqlps.io/backuprant

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Specifies the SQL Server instance where the SQL Agent restore job will be created and executed. Defaults to the same server as SqlInstance if not specified.
        Use this when you want to test database backups on a different server than where the original database exists, which is a best practice for backup validation.

    .PARAMETER DestinationSqlCredential
        Credentials for connecting to the destination SQL Server instance when different from SqlCredential. Accepts PowerShell credentials (Get-Credential).
        Use this when the destination server requires different authentication than the source server, common in cross-domain or different security context scenarios.

    .PARAMETER Database
        Specifies one or more databases to safely remove with validated backups. Accepts multiple database names as an array.
        Use this to target specific databases for removal, ensuring each gets a verified backup before deletion.

    .PARAMETER NoDbccCheckDb
        Skips the initial DBCC CHECKDB integrity check before creating the backup, reducing processing time.
        Use this only when you're confident about database integrity or when time constraints outweigh the risk of backing up a corrupt database.
        The function still runs DBCC on the restored test database, but corruption detection happens after backup creation.

    .PARAMETER BackupFolder
        Specifies the directory path where final database backups will be stored before deletion. Must be accessible by both source and destination server service accounts.
        Use a UNC path (like \\SERVER1\BACKUPS\) when source and destination servers are different, or a local path when using the same server for both operations.

    .PARAMETER JobOwner
        Sets the owner account for the SQL Agent restore job that gets created. Defaults to the 'sa' login.
        Specify a different owner when you need the job to run under specific security context or when 'sa' is disabled in your environment.

    .PARAMETER UseDefaultFilePaths
        Forces the restore operation to use the destination server's default file paths instead of the original database file locations.
        Use this when the destination server has a different drive structure or when you want to follow the destination server's file organization standards.

    .PARAMETER CategoryName
        Sets the SQL Agent job category for the restore jobs that are created. Defaults to 'Rationalisation'.
        Use a custom category name to organize these restoration jobs separately from other maintenance jobs in SQL Agent.

    .PARAMETER BackupCompression
        Controls backup compression behavior with values: Default, On, or Off. Default uses the server's backup compression configuration setting.
        Use 'On' to force compression for smaller backup files and reduced network traffic, or 'Off' when compression overhead outweighs benefits.

    .PARAMETER AllDatabases
        Removes all user databases from the source server, excluding system databases. Primarily used for server decommissioning scenarios.
        Use with caution and always specify a different Destination server to avoid removing databases from the same server that will test their backups.

    .PARAMETER ReuseSourceFolderStructure
        Maintains the original database file paths and folder structure during the test restore operation on the destination server.
        Use this when you need to preserve specific drive layouts or when the destination server has matching drive structure to the source.

    .PARAMETER Force
        Continues the database removal process even when DBCC integrity checks detect corruption. Creates backups and jobs with 'DBCCERROR' naming to identify them.
        Use this only in emergency situations when you must remove a corrupt database and accept the risk of having potentially unusable backups.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Delete
        Author: Rob Sewell (@SQLDBAWithBeard), sqldbawithabeard.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDatabaseSafely

    .EXAMPLE
        PS C:\> Remove-DbaDatabaseSafely -SqlInstance 'Fade2Black' -Database RideTheLightning -BackupFolder 'C:\MSSQL\Backup\Rationalised - DO NOT DELETE'

        Performs a DBCC CHECKDB on database RideTheLightning on server Fade2Black. If there are no errors, the database is backup to the folder C:\MSSQL\Backup\Rationalised - DO NOT DELETE. Then, an Agent job to restore the database from that backup is created. The database is then dropped, the Agent job to restore it run, a DBCC CHECKDB run against the restored database, and then it is dropped again.

        Any DBCC errors will be written to your documents folder

    .EXAMPLE
        PS C:\> $Database = 'DemoNCIndex','RemoveTestDatabase'
        PS C:\> Remove-DbaDatabaseSafely -SqlInstance 'Fade2Black' -Database $Database -BackupFolder 'C:\MSSQL\Backup\Rationalised - DO NOT DELETE'

        Performs a DBCC CHECKDB on two databases, 'DemoNCIndex' and 'RemoveTestDatabase' on server Fade2Black. Then, an Agent job to restore each database from those backups is created. The databases are then dropped, the Agent jobs to restore them run, a DBCC CHECKDB run against the restored databases, and then they are dropped again.

        Any DBCC errors will be written to your documents folder

    .EXAMPLE
        PS C:\> Remove-DbaDatabaseSafely -SqlInstance 'Fade2Black' -Destination JusticeForAll -Database RideTheLightning -BackupFolder '\\BACKUPSERVER\BACKUPSHARE\MSSQL\Rationalised - DO NOT DELETE'

        Performs a DBCC CHECKDB on database RideTheLightning on server Fade2Black. If there are no errors, the database is backup to the folder \\BACKUPSERVER\BACKUPSHARE\MSSQL\Rationalised - DO NOT DELETE . Then, an Agent job is created on server JusticeForAll to restore the database from that backup is created. The database is then dropped on Fade2Black, the Agent job to restore it on JusticeForAll is run, a DBCC CHECKDB run against the restored database, and then it is dropped from JusticeForAll.

        Any DBCC errors will be written to your documents folder

    .EXAMPLE
        PS C:\> Remove-DbaDatabaseSafely -SqlInstance IronMaiden -Database $Database -Destination TheWildHearts -BackupFolder Z:\Backups -NoDbccCheckDb -JobOwner 'THEBEARD\Rob'

        For the databases $Database on the server IronMaiden a DBCC CHECKDB will not be performed before backing up the databases to the folder Z:\Backups. Then, an Agent job is created on server TheWildHearts with a Job Owner of THEBEARD\Rob to restore each database from that backup using the instance's default file paths. The database(s) is(are) then dropped on IronMaiden, the Agent job(s) run, a DBCC CHECKDB run on the restored database(s), and then the database(s) is(are) dropped.

    .EXAMPLE
        PS C:\> Remove-DbaDatabaseSafely -SqlInstance IronMaiden -Database $Database -Destination TheWildHearts -BackupFolder Z:\Backups

        The databases $Database on the server IronMaiden will be backed up the to the folder Z:\Backups. Then, an Agent job is created on server TheWildHearts with a Job Owner of THEBEARD\Rob to restore each database from that backup using the instance's default file paths. The database(s) is(are) then dropped on IronMaiden, the Agent job(s) run, a DBCC CHECKDB run on the restored database(s), and then the database(s) is(are) dropped.

        If there is a DBCC Error, the function  will continue to perform rest of the actions and will create an Agent job with 'DBCCERROR' in the name and a Backup file with 'DBCCError' in the name.

    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "Default", ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias('Name')]
        [object[]]$Database,
        [DbaInstanceParameter]$Destination = $SqlInstance,
        [PSCredential]$DestinationSqlCredential,
        [Alias("NoCheck")]
        [switch]$NoDbccCheckDb,
        [parameter(Mandatory)]
        [string]$BackupFolder,
        [string]$CategoryName = 'Rationalisation',
        [string]$JobOwner,
        [switch]$AllDatabases,
        [ValidateSet("Default", "On", "Off")]
        [string]$BackupCompression = 'Default',
        [switch]$ReuseSourceFolderStructure,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        if (!$AllDatabases -and !$Database) {
            Stop-Function -Message "You must specify at least one database. Use -Database or -AllDatabases."
            return
        }

        try {
            $sourceserver = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
            return
        }

        if (-not $Destination) {
            $Destination = $SqlInstance
            $DestinationSqlCredential = $SqlCredential
        }

        if ($SqlInstance -ne $Destination) {
            try {
                $destserver = Connect-DbaInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Destination
                return
            }

            $sourcenb = $sourceserver.ComputerName
            $destnb = $destserver.ComputerName

            if ($BackupFolder.StartsWith("\\") -eq $false -and $sourcenb -ne $destnb) {
                Stop-Function -Message "Backup folder must be a network share if the source and destination servers are not the same." -Target $backupFolder
                return
            }
        } else {
            $destserver = $sourceserver
        }

        $source = $sourceserver.DomainInstanceName
        $destination = $destserver.DomainInstanceName

        if (!$jobowner) {
            $jobowner = Get-SqlSaLogin -SqlInstance $destserver
        }

        if ($alldatabases -or !$Database) {
            $database = ($sourceserver.databases | Where-Object { $_.IsSystemObject -eq $false -and ($_.Status -match 'Offline') -eq $false }).Name
        }

        if (!(Test-DbaPath -SqlInstance $destserver -Path $backupFolder)) {
            $serviceAccount = $destserver.ServiceAccount
            Stop-Function -Message "Can't access $backupFolder Please check if $serviceAccount has permissions." -Target $backupFolder
            return
        }

        #TODO: Test
        $jobname = "Rationalised Final Database Restore for $dbName"
        $jobStepName = "Restore the $dbName database from Final Backup"

        if (!($destserver.Logins | Where-Object { $_.Name -eq $jobowner })) {
            Stop-Function -Message "$destination does not contain the login $jobowner - Please fix and try again - Aborting." -Target $jobowner
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) {
            return
        }

        $start = Get-Date

        try {
            $destInstanceName = $destserver.InstanceName

            if ($destserver.EngineEdition -match "Express") {
                Write-Message -Level Warning -Message "$destInstanceName is Express Edition which does not support SQL Server Agent."
                return
            }

            if ($destInstanceName -eq '') {
                $destInstanceName = "MSSQLSERVER"
            }
            $agentService = Get-DbaService -ComputerName $destserver.ComputerName -InstanceName $destInstanceName -Type Agent -EnableException

            if ($agentService.State -ne 'Running') {
                Stop-Function -Message "SQL Server Agent is not running. Please start the service."
                return
            } else {
                Write-Message -Level Verbose -Message "SQL Server Agent $($agentService.Name) is running."
            }
        } catch {
            Stop-Function -Message "Failure getting SQL Agent service" -ErrorRecord $_
            return
        }

        Write-Message -Level Verbose -Message "Starting Rationalisation Script at $start."

        foreach ($dbName in $Database) {

            $db = $sourceserver.databases[$dbName]

            # The db check is needed when the number of databases exceeds 255, then it's no longer auto-populated
            if (!$db) {
                Stop-Function -Message "$dbName does not exist on $source. Aborting routine for this database." -Continue
            }

            $lastFullBckDuration = ( Get-DbaDbBackupHistory -SqlInstance $sourceserver -Database $dbName -LastFull).Duration

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
                        Stop-Function -Message "You have chosen skipping the database $dbName because of last known backup time ($lastFullBckDurationMin minutes)." -Target $dbName -Continue
                    }
                }
            } else {
                Write-Message -Level Verbose -Message "Couldn't find last full backup time for database $dbName using Get-DbaDbBackupHistory."
            }

            $jobname = "Rationalised Database Restore Script for $dbName"
            $jobStepName = "Restore the $dbName database from Final Backup"
            $checkJob = Get-DbaAgentJob -SqlInstance $destserver -Job $jobname

            if ($checkJob.count -gt 0) {
                if ($Force -eq $false) {
                    Stop-Function -Message "FAILED: The Job $jobname already exists. Have you done this before? Rename the existing job and try again or use -Force to drop and recreate." -Continue
                } else {
                    if ($Pscmdlet.ShouldProcess($dbName, "Dropping $jobname on $destination")) {
                        Write-Message -Level Verbose -Message "Dropping $jobname on $destination."
                        $checkJob.Drop()
                    }
                }
            }


            Write-Message -Level Verbose -Message "Starting Rationalisation of $dbName."
            ## if we want to Dbcc before to abort if we have a corrupt database to start with
            if ($NoDbccCheckDb -eq $false) {
                if ($Pscmdlet.ShouldProcess($dbName, "Running dbcc check on $dbName on $source")) {
                    Write-Message -Level Verbose -Message "Starting DBCC CHECKDB for $dbName on $source."
                    $dbccgood = Start-DbccCheck -server $sourceserver -dbname $dbName -table

                    if ($dbccgood -ne "Success") {
                        if ($Force -eq $false) {
                            Write-Message -Level Verbose -Message "DBCC failed for $dbName (you should check that). Aborting routine for this database."
                            continue
                        } else {
                            Write-Message -Level Verbose -Message "DBCC failed, but Force specified. Continuing."
                        }
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($source, "Backing up $dbName")) {

                Write-Message -Level Verbose -Message "Starting Backup for $dbName on $source."
                ## Take a Backup
                try {
                    $timenow = [DateTime]::Now.ToString('yyyyMMdd_HHmmss')

                    if ($Force -and $dbccgood -ne "Success") {
                        $filename = "$backupFolder\$($dbName)_DBCCERROR_$timenow.bak"
                    } else {
                        $filename = "$backupFolder\$($dbName)_Final_Before_Drop_$timenow.bak"
                    }

                    $DefaultCompression = $sourceserver.Configuration.DefaultBackupCompression.ConfigValue
                    $backupWithCompressionParams = @{
                        SqlInstance     = $SqlInstance
                        SqlCredential   = $SqlCredential
                        Database        = $dbName
                        BackupFileName  = $filename
                        CompressBackup  = $true
                        Checksum        = $true
                        EnableException = $true
                    }

                    $backupWithoutCompressionParams = @{
                        SqlInstance     = $SqlInstance
                        SqlCredential   = $SqlCredential
                        Database        = $dbName
                        BackupFileName  = $filename
                        Checksum        = $true
                        EnableException = $true
                    }
                    if ($BackupCompression -eq "Default") {
                        if ($DefaultCompression -eq 1) {
                            $null = Backup-DbaDatabase @backupWithCompressionParams
                        } else {
                            $null = Backup-DbaDatabase @backupWithoutCompressionParams
                        }
                    } elseif ($BackupCompression -eq "On") {
                        $null = Backup-DbaDatabase @backupWithCompressionParams
                    } else {
                        $null = Backup-DbaDatabase @backupWithoutCompressionParams
                    }

                } catch {
                    Stop-Function -Message "FAILED : Restore Verify Only failed for $filename on $server - aborting routine for this database. Exception: $_" -Target $filename -ErrorRecord $_ -Continue
                }
            }

            if ($Pscmdlet.ShouldProcess($destination, "Creating Automated Restore Job from Golden Backup for $dbName on $destination")) {
                Write-Message -Level Verbose -Message "Creating Automated Restore Job from Golden Backup for $dbName on $destination."
                try {
                    if ($Force -eq $true -and $dbccgood -ne "Success") {
                        $jobName = $jobname -replace "Rationalised", "DBCC ERROR"
                    }

                    ## Create a Job Category
                    if (!(Get-DbaAgentJobCategory -SqlInstance $destination -SqlCredential $DestinationSqlCredential -Category $categoryname)) {
                        $null = New-DbaAgentJobCategory -SqlInstance $destination -SqlCredential $DestinationSqlCredential -Category $categoryname -EnableException
                    }

                    try {
                        if ($Pscmdlet.ShouldProcess($destination, "Creating Agent Job $jobname on $destination")) {
                            $jobParams = @{
                                SqlInstance     = $destination
                                SqlCredential   = $DestinationSqlCredential
                                Job             = $jobname
                                Category        = $categoryname
                                Description     = "This job will restore the $dbName database using the final backup located at $filename."
                                Owner           = $jobowner
                                EnableException = $true
                            }
                            $job = New-DbaAgentJob @jobParams

                            Write-Message -Level Verbose -Message "Created Agent Job $jobname on $destination."
                        }
                    } catch {
                        Stop-Function -Message "FAILED : To Create Agent Job $jobname on $destination - aborting routine for this database." -Target $categoryname -ErrorRecord $_ -Continue
                    }

                    ## Create Job Step
                    ## Aaron's Suggestion: In the restore script, add a comment block that tells the last known size of each file in the database.
                    ## Suggestion check for disk space before restore
                    ## Create Restore Script
                    try {
                        $jobStepCommand = Restore-DbaDatabase -SqlInstance $destserver -Path $filename -OutputScriptOnly -WithReplace -EnableException

                        $jobStepParams = @{
                            SqlInstance     = $destination
                            SqlCredential   = $DestinationSqlCredential
                            Job             = $job
                            StepName        = $jobStepName
                            SubSystem       = 'TransactSql'
                            Command         = $jobStepCommand
                            Database        = 'master'
                            OnSuccessAction = 'QuitWithSuccess'
                            OnFailAction    = 'QuitWithFailure'
                            StepId          = 1
                            EnableException = $true
                        }
                        if ($Pscmdlet.ShouldProcess($destination, "Creating Agent JobStep on $destination")) {
                            $jobStep = New-DbaAgentJobStep @jobStepParams
                        }
                        $jobStartStepid = $jobStep.ID
                        Write-Message -Level Verbose -Message "Created Agent JobStep $jobStepName on $destination."
                    } catch {
                        Stop-Function -Message "FAILED : To Create Agent JobStep $jobStepName on $destination - Aborting." -Target $jobStepName -ErrorRecord $_ -Continue
                    }
                    if ($Pscmdlet.ShouldProcess($destination, "Applying Agent Job $jobname to $destination")) {
                        $job.StartStepID = $jobStartStepid
                        $job.Alter()
                    }
                } catch {
                    Stop-Function -Message "FAILED : To Create Agent Job $jobname on $destination - aborting routine for $dbName. Exception: $_" -Target $jobname -ErrorRecord $_ -Continue
                }
            }

            if ($Pscmdlet.ShouldProcess($destination, "Dropping Database $dbName on $sourceserver")) {
                ## Drop the database
                try {
                    $null = Remove-DbaDatabase -SqlInstance $sourceserver -Database $dbName -Confirm:$false -EnableException
                    Write-Message -Level Verbose -Message "Dropped $dbName Database on $source prior to running the Agent Job"
                } catch {
                    Stop-Function -Message "FAILED : To Drop database $dbName on $server - aborting routine for $dbName. Exception: $_" -Continue
                }
            }

            if ($Pscmdlet.ShouldProcess($destination, "Running Agent Job on $destination to restore $dbName")) {
                ## Run the restore job to restore it
                Write-Message -Level Verbose -Message "Starting $jobname on $destination."
                try {
                    $job.Start()
                    $job.Refresh()
                    $status = $job.CurrentRunStatus

                    while ($status -ne 'Idle') {
                        Write-Message -Level Verbose -Message "Restore Job for $dbName on $destination is $status."
                        Start-Sleep -Seconds 15
                        $job.Refresh()
                        $status = $job.CurrentRunStatus
                    }

                    Write-Message -Level Verbose -Message "Restore Job $jobname has completed on $destination."
                    Write-Message -Level Verbose -Message "Sleeping for a few seconds to ensure the next step (DBCC) succeeds."
                    Start-Sleep -Seconds 10 ## This is required to ensure the next DBCC Check succeeds
                } catch {
                    Stop-Function -Message "FAILED : Restore Job $jobname failed on $destination - aborting routine for $dbName. Exception: $_" -Continue
                }

                if ($job.LastRunOutcome -ne 'Succeeded') {
                    # LOL, love the plug.
                    Write-Message -Level Warning -Message "FAILED : Restore Job $jobname failed on $destination - aborting routine for $dbName."
                    Write-Message -Level Warning -Message "Check the Agent Job History on $destination - if you have SSMS2016 July release or later."
                    Write-Message -Level Warning -Message "Get-DbaAgentJobHistory -SqlInstance $destination -Job '$jobname'."

                    continue
                }

                $refreshRetries = 1

                $destserver.Databases.Refresh()
                $restoredDatabase = Get-DbaDatabase -SqlInstance $destserver -Database $dbName
                while ($null -eq $restoredDatabase -and $refreshRetries -lt 6) {
                    Write-Message -Level verbose -Message "Database $dbName not found! Refreshing collection."

                    #refresh database list, otherwise the next step (DBCC) can fail
                    $restoredDatabase.Parent.Databases.Refresh()

                    Start-Sleep -Seconds 1

                    $refreshRetries += 1
                }
            }

            ## Run a Dbcc No choice here
            if ($Pscmdlet.ShouldProcess($dbName, "Running Dbcc CHECKDB on $dbName on $destination")) {
                Write-Message -Level Verbose -Message "Starting Dbcc CHECKDB for $dbName on $destination."
                $dbccgood = Start-DbccCheck -server $sourceserver -dbname $dbName -table

                if ($dbccgood -ne "Success") {
                    Write-Message -Level Verbose -Message "DBCC CHECKDB finished successfully for $dbName on $servername."
                } else {
                    Write-Message -Level Verbose -Message "DBCC failed for $dbName (you should check that). Continuing."
                }
            }

            if ($Pscmdlet.ShouldProcess($dbName, "Dropping Database $dbName on $destination")) {
                ## Drop the database
                try {
                    $null = Remove-DbaDatabase -SqlInstance $destserver -Database $dbName -Confirm:$false -EnableException
                    Write-Message -Level Verbose -Message "Dropped $dbName database on $destination."
                } catch {
                    Stop-Function -Message "FAILED : To Drop database $dbName on $destination - Aborting. Exception: $_" -Target $dbName -ErrorRecord $_ -Continue
                }
            }
            Write-Message -Level Verbose -Message "Rationalisation Finished for $dbName."

            [PSCustomObject]@{
                SqlInstance     = $source
                DatabaseName    = $dbName
                JobName         = $jobname
                TestingInstance = $destination
                BackupFolder    = $backupFolder
            }
        }
    }

    end {
        if (Test-FunctionInterrupt) {
            return
        }
        if ($Pscmdlet.ShouldProcess("console", "Showing final message")) {
            $End = Get-Date
            Write-Message -Level Verbose -Message "Finished at $End."
            $Duration = $End - $start
            Write-Message -Level Verbose -Message "Script Duration: $Duration."
        }
    }
}