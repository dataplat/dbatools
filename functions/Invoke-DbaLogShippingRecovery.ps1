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

        .NOTES
            Tags: LogShipping
            Author: Sander Stad (@sqlstad, sqlstad.nl)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Invoke-DbaLogShippingRecovery

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

            Write-Message -Message "Connecting to Sql Server" -Level Output
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

        # Try to get the agent service details
        try {
            # Get the service details
            $agentStatus = $server.Query("SELECT COUNT(*) as AgentCount FROM master.dbo.sysprocesses WITH (nolock) WHERE Program_Name LIKE 'SQLAgent%'")

            if ($agentStatus.AgentCount -lt 1) {
                Stop-Function -Message "The agent service is not in a running state. Please start the service." -ErrorRecord $_ -Target $sqlinstance
                return
            }
        }
        catch {
            Stop-Function -Message "Unable to get SQL Server Agent Service status" -ErrorRecord $_ -Target $sqlinstance
            return
        }
    }

    process {

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

                        # Start the job to get the latest files
                        if ($PSCmdlet.ShouldProcess($sqlinstance, ("Starting copy job $($ls.copyjob)"))) {
                            Write-Message -Message "Starting copy job $($ls.copyjob)" -Level Verbose
                            try {
                                Start-DbaAgentJob -SqlInstance $sqlinstance -SqlCredential $SqlCredential -Job $ls.copyjob
                            }
                            catch {
                                Stop-Function -Message "Something went wrong starting the copy job.`n$($_)" -ErrorRecord $_ -Target $sqlinstance
                            }

                            Write-Message -Message "Copying files to $($ls.backup_destination_directory)" -Level Verbose

                            Write-Message -Message "Waiting for the copy action to complete.." -Level Verbose

                            # Get the job status
                            $jobStatus = Get-DbaAgentJob -SqlInstance $sqlinstance -Job $ls.copyjob | Select-Object CurrentRunStatus, LastRunOutCome

                            while ($jobStatus.CurrentRunStatus -ne 'Idle') {
                                # Sleep for while to let the files be copied
                                Start-Sleep -Seconds $Delay

                                # Get the job status
                                $jobStatus = Get-DbaAgentJob -SqlInstance $sqlinstance -Job $ls.copyjob | Select-Object CurrentRunStatus, LastRunOutCome
                            }

                            # Check the lat outcome of the job
                            if ($jobStatus.LastRunOutcome -eq 'Failed') {
                                Stop-Function -Message "The copy job for database $db failed. Please check the error log."
                                return
                            }

                            Write-Message -Message "Copying of backup files finished" -Level Verbose
                        } # if should process

                        # Disable the log shipping copy job on the secondary instance
                        if ($PSCmdlet.ShouldProcess($sqlinstance, "Disabling copy job $($ls.copyjob)")) {
                            try {
                                Write-Message -Message "Disabling copy job $($ls.copyjob)" -Level Verbose
                                Set-DbaAgentJob -SqlInstance $SqlInstance -Job $ls.copyjob -Disabled
                            }
                            catch {
                                Stop-Function -Message "Something went wrong disabling the copy job.`n$($_)" -ErrorRecord $_ -Target $sqlinstance
                            }
                        }

                        # Start the restore job
                        if ($PSCmdlet.ShouldProcess($sqlinstance, ("Starting restore job " + $ls.restorejob))) {
                            Write-Message -Message "Starting restore job $($ls.restorejob)" -Level Verbose
                            try {
                                Start-DbaAgentJob -SqlInstance $sqlinstance -SqlCredential $SqlCredential -Job $ls.restorejob
                            }
                            catch {
                                Stop-Function -Message "Something went wrong starting the restore job.`n$($_)" -ErrorRecord $_ -Target $sqlinstance
                            }

                            Write-Message -Message "Waiting for the restore action to complete.." -Level Verbose

                            # Get the job status
                            $jobStatus = Get-DbaAgentJob -SqlInstance $sqlinstance -Job $ls.restorejob | Select-Object CurrentRunStatus, LastRunOutCome

                            while ($jobStatus.CurrentRunStatus -ne 'Idle') {
                                # Sleep for while to let the files be copied
                                Start-Sleep -Seconds $Delay

                                # Get the job status
                                $jobStatus = Get-DbaAgentJob -SqlInstance $sqlinstance -Job $ls.restorejob | Select-Object CurrentRunStatus, LastRunOutCome
                            }

                            # Check the lat outcome of the job
                            if ($jobStatus.LastRunOutcome -eq 'Failed') {
                                Stop-Function -Message "The restore job for database $db failed. Please check the error log."
                                return
                            }
                        }

                        # Disable the log shipping restore job on the secondary instance
                        if ($PSCmdlet.ShouldProcess($sqlinstance, "Disabling restore job $($ls.restorejob)")) {
                            try {
                                Write-Message -Message ("Disabling restore job " + $ls.restorejob) -Level Verbose
                                Set-DbaAgentJob -SqlInstance $SqlInstance -Job $ls.restorejob -Disabled
                            }
                            catch {
                                Stop-Function -Message "Something went wrong disabling the restore job.`n$($_)" -ErrorRecord $_ -Target $sqlinstance
                            }

                        }

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

                        Write-Message -Message ("Finished Recovery for $secondarydb") -Level Output

                        # Reset the log ship details
                        $logshipping_details = $null

                    } # database in restorable mode
                } # foreach ls details
            } # ls details are not null
        } # foreach database
    } # process
}