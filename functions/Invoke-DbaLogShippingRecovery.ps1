function Invoke-DbaLogShippingRecovery {
    <#
    .SYNOPSIS
        Invoke-DbaLogShippingRecovery recovers log shipped databases to a normal state to act upon a migration or disaster.

    .DESCRIPTION
        By default all the databases for a particular instance are recovered.
        If the database is in the right state, either standby or recovering, the process will try to recover the database.

        At first the function will check if the backup source directory can still be reached.
        If so it will look up the last transaction log backup for the database. If that backup file is not the last copied file the log shipping copy job will be started.
        If the directory cannot be reached for the function will continue to the restoring process.
        After the copy job check is performed the job is disabled to prevent the job to run.

        For the restore the log shipping status is checked in the msdb database.
        If the last restored file is not the same as the last file name found, the log shipping restore job will be executed.
        After the restore job check is performed the job is disabled to prevent the job to run

        The last part is to set the database online by restoring the databases with recovery

    .PARAMETER SqlInstance
        SQL Server name or SMO object representing the SQL Server to connect to

    .PARAMETER Database
        Database to perform the restore for. This value can also be piped enabling multiple databases to be recovered.
        If this value is not supplied all databases will be recovered.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER NoRecovery
        Allows you to choose to not restore the database to a functional state (Normal) in the final steps of the process.
        By default the database is restored to a functional state (Normal).

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        Use this parameter to force the function to continue and perform any adjusting actions to successfully execute

    .PARAMETER Delay
        Set the delay in seconds to wait for the copy and/or restore jobs.
        By default the delay is 5 seconds

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .EXAMPLE
        Invoke-DbaLogShippingRecovery -SqlServer server1

        Recovers all the databases on the instance that are enabled for log shipping

    .EXAMPLE
        Invoke-DbaLogShippingRecovery -SqlServer server1 -SqlCredential $cred -Verbose

        Recovers all the databases on the instance that are enabled for log shipping using a credential

    .EXAMPLE
        Invoke-DbaLogShippingRecovery -SqlServer server1 -database db_logship -Verbose

        Recovers the database "db_logship" to a normal status

    .EXAMPLE
        db1, db2, db3, db4 | Invoke-DbaLogShippingRecovery -SqlServer server1 -Verbose

        Recovers the database db1, db2, db3, db4 to a normal status

    .EXAMPLE
        Invoke-DbaLogShippingRecovery -SqlServer server1 -WhatIf

        Shows what would happen if the command were executed.

    .NOTES
        Author: Sander Stad (@sqlstad, sqlstad.nl)
        Tags: Log Shipping, Recovery

        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaLogShippingRecovery
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param
    (
        [Parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [object]$SqlInstance,
        [Parameter(ValueFromPipeline = $true)]
        [object[]]$Database,
        [PSCredential]$SqlCredential,
        [switch]$NoRecovery,
        [Alias('Silent')]
        [switch]$EnableException,
        [switch]$Force,
        [int]$Delay = 5
    )

    begin {
        if (!$sqlinstance -and $database.Count -lt 1) {
            # You can prolly do this with
            Stop-Function -Message "You must pipe an SMO database object or specify SqlInstance"
            return
        }

        if ($sqlinstance) {
            # Check the instance if it is a named instance
            $servername, $instancename = $sqlinstance.Split("\")

            if ($null -eq $instancename) {
                $instancename = "MSSQLSERVER"
            }

            Write-Message -Message "Attempting to connect to Sql Server" -Level Output
            try {
                $server = Connect-SqlInstance -SqlInstance $sqlinstance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance
            }

            if ($Force -and (!$database -or $database.Count -lt 1)) {
                $database = $server.databases
            }
            elseif (-not $Force -and (!$database -or $database.Count -lt 1)) {
                Stop-Function -Message "Please enter one or more databases to recover from log shipping" -Target $instance
            }
            else {
                $databases = $server.databases | Where-Object Name -in $database
            }
        }
    }

    process {
        # Try to get the agent service details
        try {
            # Start the service
            $agentservice = Get-DbaSqlService -ComputerName $servername | Where-Object {($_.ComputerName -eq $servername) -and ($_.DisplayName -eq "SQL Server Agent ($instancename)")}
        }
        catch {
            # Stop the function when the service was unable to start
            Stop-Function -Message "Unable to start SQL Server Agent Service" -ErrorRecord $_ -Target $sqlinstance
            return
        }

        # Check if the service is running
        if ($agentservice.State -ne 'Running') {

            if ($Force) {
                try {
                    Start-DbaSqlService -ComputerName $servername -InstanceName $instancename -Type Agent -Credential $SqlCredential
                }
                catch {
                    # Stop the function when the service was unable to start
                    Stop-Function -Message "Unable to start SQL Server Agent Service" -ErrorRecord $_ -Target $sqlinstance
                    return
                }
            }
            # If the force switch and the silent switch are not set
            elseif (!$Force -and !$EnableException) {
                # Set up the parts for the user choice
                $Title = "SQL Server Agent is not running"
                $Info = "Do you want to start the SQL Server Agent service?"

                $Options = [System.Management.Automation.Host.ChoiceDescription[]] @("&Start", "&Quit")
                [int]$Defaultchoice = 0
                $choice = $host.UI.PromptForChoice($Title, $Info, $Options, $Defaultchoice)

                # Check the given option
                if ($choice -eq 0) {
                    try {
                        # Start the service
                        Start-DbaSqlService -ComputerName $servername -InstanceName $instancename -Type Agent -Credential $SqlCredential
                    }
                    catch {
                        # Stop the function when the service was unable to start
                        Stop-Function -Message "Unable to start SQL Server Agent Service" -ErrorRecord $_ -Target $sqlinstance
                        return
                    }
                }
                else {
                    Stop-Function -Message "The SQL Server Agent service needs to be started to be able to recover the databases" -ErrorRecord $_ -Target $sqlinstance
                    return
                }
            }
            # If the force switch it not set and the silent switch is set
            elseif (!$Force -and $EnableException) {
                Stop-Function -Message "The SQL Server Agent service needs to be started to be able to recover the databases" -ErrorRecord $_ -Target $sqlinstance
                return
            }
            # If nothing else matches and the agent service is not started
            else {
                Stop-Function -Message "The SQL Server Agent service needs to be started to be able to recover the databases" -ErrorRecord $_ -Target $sqlinstance
                return
            }

        }

        Write-Message -Message "Started Log Shipping Recovery" -Level Output

        # Loop through all the databases
        foreach ($db in $databases) {
            # Query for retrieving the log shipping information
            $query = "SELECT lss.primary_server, lss.primary_database, lsd.secondary_database, lss.backup_source_directory,
            lss.backup_destination_directory, lss.last_copied_file, lss.last_copied_date,
            lsd.last_restored_file, sj1.name AS 'copyjob', sj2.name AS 'restorejob'
        FROM msdb.dbo.log_shipping_secondary AS lss
            INNER JOIN msdb.dbo.log_shipping_secondary_databases AS lsd ON lsd.secondary_id = lss.secondary_id
            INNER JOIN msdb.dbo.sysjobs AS sj1 ON sj1.job_id = lss.copy_job_id
            INNER JOIN msdb.dbo.sysjobs AS sj2 ON sj2.job_id = lss.restore_job_id
        WHERE lsd.secondary_database = '$($db.Name)'"

            # Retrieve the log shipping information from the secondary instance
            try {
                Write-Message -Message "Retrieving log shipping information from the secondary instance" -Level Verbose
                $logshipping_details = $server.Query($query)
            }
            catch {
                Stop-Function -Message "Error retrieving the log shipping details: $($_.Exception.Message)" -ErrorRecord $_ -Target $sqlinstance
                return
            }

            # Check if there are any databases to recover
            if ($null -eq $logshipping_details) {
                Stop-Function -Message "The database $db is not configured as a secondary database for log shipping." -Continue
            }
            else {
                # Loop through each of the log shipped databases
                foreach ($ls in $logshipping_details) {
                    $secondarydb = $ls.secondary_database

                    # Check if the database is in the right state
                    if ($server.Databases[$secondarydb].Status -notin ('Normal, Standby', 'Standby', 'Restoring')) {
                        Stop-Function -Message "The database $db doesn't have the right status to be recovered" -Continue
                    }
                    else {
                        Write-Message -Message "Started Recovery for $secondarydb" -Level Verbose

                        # Get the last file from the backup source directory
                        <# !!!! set credentials !!! #>
                        $latestBackupSource = Get-ChildItem -Path $ls.backup_source_directory -filter ("*" + $ls.primary_database + "*") | Where-Object { ($_.Extension -eq '.trn') } | Sort-Object LastWriteTime -Descending | Select-Object -First 1

                        # Get al the backup files from the destination directory
                        <# !!!! set credentials !!! #>
                        $latestBackupDest = Get-ChildItem -Path $ls.backup_destination_directory -filter ("*" + $ls.primary_database + "*") | Where-Object { ($_.Extension -eq '.trn') } | Sort-Object LastWriteTime -Descending | Select-Object -First 1

                        # Check if source and destination directory are in sync
                        if ($latestBackupSource.Name -ne $latestBackupDest.Name) {
                            # Check if the backup source directory can be reached
                            if (Test-DbaSqlPath -SqlInstance $SqlInstance -Path $ls.backup_source_directory -SqlCredential $SqlCredential) {

                                # Check if the latest file is also the latest copied file
                                if ($latestBackupSource.Name -ne ([string]$ls.last_copied_file).Split('\')[-1]) {
                                    Write-Message -Message "Backup destination is not up-to-date" -Level Verbose

                                    # Start the job to get the latest files
                                    if ($PSCmdlet.ShouldProcess($sqlinstance, ("Starting copy job $($ls.copyjob)"))) {
                                        Write-Message -Message "Starting copy job $($ls.copyjob)" -Level Verbose
                                        try {
                                            $server.JobServer.Jobs[$ls.copyjob].Start()
                                        }
                                        catch {
                                            Stop-Function -Message "Something went wrong starting the restore job.`n$($_)" -ErrorRecord $_ -Target $sqlinstance
                                        }

                                        Write-Message -Message "Copying files to $($ls.backup_destination_directory)" -Level Verbose

                                        # Check if the file has been copied
                                        $query = "SELECT last_copied_file FROM msdb.dbo.log_shipping_secondary WHERE primary_database = '$($ls.primary_database)' AND last_copied_file IS NOT NULL "
                                        $latestcopy = $server.Query($query)

                                        Write-Message -Message "Waiting for the copy action to complete.." -Level Verbose

                                        while (($latestBackupSource.Name -ne ([string]$latestcopy.last_copied_file).Split('\')[-1])) {
                                            # Sleep for while to let the files be copied
                                            Start-Sleep -Seconds $Delay

                                            # Again get the latest file to check if the process can continue
                                            $latestcopy = $server.Query($query)
                                        }

                                        # Again get the latest file to check if the process can continue
                                        $latestcopy = $server.Query($query)

                                        # Check the lat outcome of the job
                                        if ($server.JobServer.Jobs[$ls.copyjob].LastRunOutcome -eq 'Failed') {
                                            Stop-Function -Message "The copy job for database $db failed. Please check the error log." -Continue
                                        }

                                        Write-Message -Message "Copying of backup files finished" -Level Verbose
                                    } # if should process
                                } # if latest file name
                            } # if backup directory test
                            else {
                                Stop-Function -Message "Couldn't reach the backup source directory. Continuing..." -Continue
                            }
                        } # check latest backup file is already in directory


                        # Disable the log shipping copy job on the secondary instance
                        if ($PSCmdlet.ShouldProcess($sqlinstance, "Disabling copy job $($ls.copyjob)")) {
                            try {
                                Write-Message -Message "Disabling copy job $($ls.copyjob)" -Level Verbose
                                $server.JobServer.Jobs[$ls.copyjob].IsEnabled = $false
                                $server.JobServer.Jobs[$ls.copyjob].Alter()
                            }
                            catch {
                                Stop-Function -Message "Something went wrong disabling the copy job.`n$($_)" -ErrorRecord $_ -Target $sqlinstance
                            }
                        }

                        # Check if the file has been copied
                        $query = "SELECT last_restored_file FROM msdb.dbo.log_shipping_secondary_databases WHERE secondary_database = '$secondarydb' AND last_restored_file IS NOT NULL"
                        $latestrestore = $server.Query($query)

                        # Check if the last copied file is newer than the last restored file
                        if ((([string]$latestcopy.last_copied_file).Split('\')[-1] -ne ([string]$latestrestore.last_restored_file).Split('\')[-1]) -or ($null -eq ([string]$latestcopy.last_copied_file).Split('\')[-1])) {
                            Write-Message -Message "Restore is not up-to-date" -Level Verbose

                            # Start the restore job
                            if ($PSCmdlet.ShouldProcess($sqlinstance, ("Starting restore job " + $ls.restorejob))) {
                                Write-Message -Message "Starting restore job $($ls.restorejob)" -Level Verbose
                                try {
                                    $server.JobServer.Jobs[$ls.restorejob].Start()
                                }
                                catch {
                                    Stop-Function -Message "Something went wrong starting the restore job.`n$($_)" -ErrorRecord $_ -Target $sqlinstance
                                }

                                Write-Message -Message "Waiting for the restore action to complete.." -Level Verbose

                                while ($latestBackupSource.Name -ne [string]($latestrestore.last_restored_file).Split('\')[-1]) {
                                    # Sleep for while to let the files be copied
                                    Start-Sleep -Seconds $Delay

                                    # Again get the latest file to check if the process can continue
                                    $latestrestore = $server.Query($query)
                                }

                                # Again get the latest file to check if the process can continue
                                $latestrestore = $server.Query($query)

                                # Check the lat outcome of the job
                                if ($server.JobServer.Jobs[$ls.restorejob].LastRunOutcome -eq 'Failed') {
                                    Stop-Function -Message "The restore job for database $db failed. Please check the error log." -Continue
                                }
                            }
                        }

                        # Disable the log shipping restore job on the secondary instance
                        if ($PSCmdlet.ShouldProcess($sqlinstance, "Disabling restore job $($ls.restorejob)")) {
                            try {
                                Write-Message -Message ("Disabling restore job " + $ls.restorejob) -Level Verbose
                                $server.JobServer.Jobs[$ls.restorejob].IsEnabled = $false
                                $server.JobServer.Jobs[$ls.restorejob].Alter()
                            }
                            catch {
                                Stop-Function -Message "Something went wrong disabling the restore job.`n$($_)" -ErrorRecord $_ -Target $sqlinstance
                            }

                        }

                        # Check for the last time if everything is up-to-date
                        if ($latestBackupSource.Name -eq [string]($latestrestore.last_restored_file).Split('\')[-1]) {
                            # Check if the database needs to recovered to its normal state
                            if ($NoRecovery -eq $false) {
                                if ($PSCmdlet.ShouldProcess($secondarydb, "Restoring database with recovery")) {
                                    Write-Message -Message "Restoring the database to it's normal state" -Level Verbose
                                    $query = "RESTORE DATABASE [$secondarydb] WITH RECOVERY"
                                    $server.Query($query)
                                }
                            }
                            else {
                                Write-Message -Message "Skipping restore with recovery" -Level Output
                            }
                        }

                        Write-Message -Message ("Finished Recovery for $secondarydb") -Level Output

                        # Reset the log ship details
                        $logshipping_details = $null

                    } # database in restorable mode
                } # foreach ls details
            } # ls details are not null
        } # foreach database
    } # process
}