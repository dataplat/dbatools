function Invoke-DbaDbLogShipRecovery {
    <#
    .SYNOPSIS
        Invoke-DbaDbLogShipRecovery recovers log shipped databases to a normal state to act upon a migration or disaster.

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
        The target SQL Server instance or instances.

    .PARAMETER Database
        Database to perform the restore for. This value can also be piped enabling multiple databases to be recovered.
        If this value is not supplied all databases will be recovered.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER NoRecovery
        Allows you to choose to not restore the database to a functional state (Normal) in the final steps of the process.
        By default the database is restored to a functional state (Normal).

    .PARAMETER InputObject
        Allows piped input from Get-DbaDatabase

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
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbLogShipRecovery

    .EXAMPLE
        PS C:\> Invoke-DbaDbLogShipRecovery -SqlInstance server1

        Recovers all the databases on the instance that are enabled for log shipping

    .EXAMPLE
        PS C:\> Invoke-DbaDbLogShipRecovery -SqlInstance server1 -SqlCredential $cred -Verbose

        Recovers all the databases on the instance that are enabled for log shipping using a credential

    .EXAMPLE
        PS C:\> Invoke-DbaDbLogShipRecovery -SqlInstance server1 -database db_logship -Verbose

        Recovers the database "db_logship" to a normal status

    .EXAMPLE
        PS C:\> db1, db2, db3, db4 | Invoke-DbaDbLogShipRecovery -SqlInstance server1 -Verbose

        Recovers the database db1, db2, db3, db4 to a normal status

    .EXAMPLE
        PS C:\> Invoke-DbaDbLogShipRecovery -SqlInstance server1 -WhatIf

        Shows what would happen if the command were executed.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param
    (
        [DbaInstanceParameter[]]$SqlInstance,
        [string[]]$Database,
        [PSCredential]$SqlCredential,
        [switch]$NoRecovery,
        [switch]$EnableException,
        [switch]$Force,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [int]$Delay = 5
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        $stepCounter = 0
    }
    process {
        foreach ($instance in $SqlInstance) {
            if (-not $Force -and -not $Database) {
                Stop-Function -Message "You must specify a -Database or -Force for all databases" -Target $server.name
                return
            }
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        # Loop through all the databases
        foreach ($db in $InputObject) {
            $stepCounter = 0
            $server = $db.Parent
            $instance = $server.Name
            $activity = "Performing log shipping recovery for $($db.Name) on $($server.Name)"
            # Try to get the agent service details
            try {
                # Get the service details
                $agentStatus = $server.Query("SELECT COUNT(*) as AgentCount FROM master.dbo.sysprocesses WITH (nolock) WHERE Program_Name LIKE 'SQLAgent%'")

                if ($agentStatus.AgentCount -lt 1) {
                    Stop-Function -Message "The agent service is not in a running state. Please start the service." -ErrorRecord $_ -Target $server.name
                    return
                }
            } catch {
                Stop-Function -Message "Unable to get SQL Server Agent Service status" -ErrorRecord $_ -Target $server.name
                return
            }
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
                Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Retrieving log shipping information from the secondary instance"
                $logshipping_details = $server.Query($query)
            } catch {
                Stop-Function -Message "Error retrieving the log shipping details: $($_.Exception.Message)" -ErrorRecord $_ -Target $server.name
                return
            }

            # Check if there are any databases to recover
            if ($null -eq $logshipping_details) {
                Stop-Function -Message "The database $db is not configured as a secondary database for log shipping." -Continue
            } else {
                # Loop through each of the log shipped databases
                foreach ($ls in $logshipping_details) {
                    $secondarydb = $ls.secondary_database

                    $recoverResult = "Success"
                    $comment = ""
                    $jobOutputs = @()

                    # Check if the database is in the right state
                    if ($server.Databases[$secondarydb].Status -notin ('Normal, Standby', 'Standby', 'Restoring')) {
                        Stop-Function -Message "The database $db doesn't have the right status to be recovered" -Continue
                    } else {
                        Write-Message -Message "Started Recovery for $secondarydb" -Level Verbose

                        # Start the job to get the latest files
                        if ($PSCmdlet.ShouldProcess($server.name, ("Starting copy job $($ls.copyjob)"))) {
                            Write-Message -Message "Starting copy job $($ls.copyjob)" -Level Verbose

                            Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Starting copy job"
                            try {
                                $null = Start-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.copyjob
                            } catch {
                                $recoverResult = "Failed"
                                $comment = "Something went wrong starting the copy job $($ls.copyjob)"
                                Stop-Function -Message "Something went wrong starting the copy job.`n$($_)" -ErrorRecord $_ -Target $server.name
                            }

                            if ($recoverResult -ne 'Failed') {
                                Write-Message -Message "Copying files to $($ls.backup_destination_directory)" -Level Verbose

                                Write-Message -Message "Waiting for the copy action to complete.." -Level Verbose

                                # Get the job status
                                $jobStatus = Get-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.copyjob

                                while ($jobStatus.CurrentRunStatus -ne 'Idle') {
                                    # Sleep for while to let the files be copied
                                    Start-Sleep -Seconds $Delay

                                    # Get the job status
                                    $jobStatus = Get-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.copyjob
                                }

                                # Check the lat outcome of the job
                                if ($jobStatus.LastRunOutcome -eq 'Failed') {
                                    $recoverResult = "Failed"
                                    $comment = "The copy job for database $db failed. Please check the error log."
                                    Stop-Function -Message "The copy job for database $db failed. Please check the error log."
                                }

                                $jobOutputs += $jobStatus

                                Write-Message -Message "Copying of backup files finished" -Level Verbose
                            }
                        } # if should process

                        # Disable the log shipping copy job on the secondary instance
                        if ($recoverResult -ne 'Failed') {
                            Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Disabling copy job"

                            if ($PSCmdlet.ShouldProcess($server.name, "Disabling copy job $($ls.copyjob)")) {
                                try {
                                    Write-Message -Message "Disabling copy job $($ls.copyjob)" -Level Verbose
                                    $null = Set-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.copyjob -Disabled
                                } catch {
                                    $recoverResult = "Failed"
                                    $comment = "Something went wrong disabling the copy job."
                                    Stop-Function -Message "Something went wrong disabling the copy job.`n$($_)" -ErrorRecord $_ -Target $server.name
                                }
                            }
                        }

                        if ($recoverResult -ne 'Failed') {
                            # Start the restore job
                            Write-ProgressHelper -Activity $activity -StepNumber ($stepCounter++) -Message "Starting restore job"

                            if ($PSCmdlet.ShouldProcess($server.name, ("Starting restore job " + $ls.restorejob))) {
                                Write-Message -Message "Starting restore job $($ls.restorejob)" -Level Verbose
                                try {
                                    $null = Start-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.restorejob
                                } catch {
                                    $comment = "Something went wrong starting the restore job."
                                    Stop-Function -Message "Something went wrong starting the restore job.`n$($_)" -ErrorRecord $_ -Target $server.name
                                }

                                Write-Message -Message "Waiting for the restore action to complete.." -Level Verbose

                                # Get the job status
                                $jobStatus = Get-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.restorejob

                                while ($jobStatus.CurrentRunStatus -ne 'Idle') {
                                    # Sleep for while to let the files be copied
                                    Start-Sleep -Seconds $Delay

                                    # Get the job status
                                    $jobStatus = Get-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.restorejob
                                }

                                # Check the lat outcome of the job
                                if ($jobStatus.LastRunOutcome -eq 'Failed') {
                                    $recoverResult = "Failed"
                                    $comment = "The restore job for database $db failed. Please check the error log."
                                    Stop-Function -Message "The restore job for database $db failed. Please check the error log."
                                }

                                $jobOutputs += $jobStatus
                            }
                        }

                        if ($recoverResult -ne 'Failed') {
                            # Disable the log shipping restore job on the secondary instance
                            if ($PSCmdlet.ShouldProcess($server.name, "Disabling restore job $($ls.restorejob)")) {
                                try {
                                    Write-Message -Message ("Disabling restore job " + $ls.restorejob) -Level Verbose
                                    $null = Set-DbaAgentJob -SqlInstance $instance -SqlCredential $SqlCredential -Job $ls.restorejob -Disabled
                                } catch {
                                    $recoverResult = "Failed"
                                    $comment = "Something went wrong disabling the restore job."
                                    Stop-Function -Message "Something went wrong disabling the restore job.`n$($_)" -ErrorRecord $_ -Target $server.name
                                }
                            }
                        }

                        if ($recoverResult -ne 'Failed') {
                            # Check if the database needs to recovered to its normal state
                            if ($NoRecovery -eq $false) {
                                if ($PSCmdlet.ShouldProcess($secondarydb, "Restoring database with recovery")) {
                                    Write-Message -Message "Restoring the database to it's normal state" -Level Verbose
                                    try {
                                        $query = "RESTORE DATABASE [$secondarydb] WITH RECOVERY"
                                        $server.Query($query)

                                    } catch {
                                        $recoverResult = "Failed"
                                        $comment = "Something went wrong restoring the database to a normal state."
                                        Stop-Function -Message "Something went wrong restoring the database to a normal state.`n$($_)" -ErrorRecord $_ -Target $secondarydb
                                    }
                                }
                            } else {
                                $comment = "Skipping restore with recovery."
                                Write-Message -Message "Skipping restore with recovery" -Level Verbose
                            }

                            Write-Message -Message ("Finished Recovery for $secondarydb") -Level Verbose
                        }

                        # Reset the log ship details
                        $logshipping_details = $null

                        [PSCustomObject]@{
                            ComputerName  = $server.ComputerName
                            InstanceName  = $server.InstanceName
                            SqlInstance   = $server.DomainInstanceName
                            Database      = $secondarydb
                            RecoverResult = $recoverResult
                            Comment       = $comment
                        }

                    }
                }
            }
            Write-Progress -Activity $activity -Completed
            $stepCounter = 0
        }
    }
}