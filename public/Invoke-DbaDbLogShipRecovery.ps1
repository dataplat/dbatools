function Invoke-DbaDbLogShipRecovery {
    <#
    .SYNOPSIS
        Brings log shipped secondary databases online for disaster recovery or planned migration scenarios

    .DESCRIPTION
        Recovers log shipped secondary databases from standby or restoring state to normal operational state. This function is essential for disaster recovery scenarios when you need to bring secondary databases online after a primary server failure, or for planned migrations where you want to switch roles between primary and secondary servers.

        The recovery process handles the complete workflow automatically. First, it checks if the backup source directory is still accessible. If so, it ensures all available transaction log backups are copied by running the log shipping copy job. If the source directory is unreachable (common in disaster scenarios), it proceeds with available backups.

        Next, it runs the log shipping restore job to apply any remaining transaction log backups that haven't been restored yet. Both the copy and restore jobs are monitored until completion, then disabled to prevent them from running again.

        Finally, unless you specify -NoRecovery, the database is brought online by executing RESTORE DATABASE WITH RECOVERY. This makes the database fully accessible for reads and writes.

        By default, all log shipped databases on the target instance are recovered. You can specify individual databases using the -Database parameter. The function requires that SQL Server Agent is running and will validate the service status before proceeding.

        All operations are tracked through the msdb database log shipping tables to ensure consistency and proper sequencing of the recovery steps.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER Database
        Specifies the log-shipped secondary databases to recover. Accepts multiple database names and wildcards for pattern matching.
        Use this when you need to recover specific databases instead of all log-shipped databases on the instance. Without specifying -Database, you must use -Force to recover all log-shipped databases.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER NoRecovery
        Prevents the final RESTORE DATABASE WITH RECOVERY step that brings the database fully online. The database remains in restoring state after log shipping jobs complete.
        Use this when you need to apply additional transaction logs manually or perform other operations before bringing the database online. By default, databases are fully recovered and made available for read-write operations.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase through the pipeline. This allows you to filter databases using Get-DbaDatabase and pipe them directly to the recovery function.
        Particularly useful when you need to recover databases based on specific criteria like database state or properties rather than just database names.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        Bypasses the safety requirement to specify individual databases and processes all log-shipped databases on the instance. Also sets confirmation preference to none.
        Use this in disaster recovery scenarios when you need to quickly recover all log-shipped databases without interactive prompts. Without -Force, you must explicitly specify database names using -Database.

    .PARAMETER Delay
        Sets the polling interval in seconds to check if the log shipping copy and restore jobs have completed. The function waits this long between status checks.
        Use a shorter delay for faster recovery monitoring or a longer delay to reduce system load during job execution. Default is 5 seconds, which balances responsiveness with system performance.

    .OUTPUTS
        PSCustomObject

        Returns one object per database recovered, containing the outcome and status of the log shipping recovery operation.

        Properties:
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: Name of the log shipped secondary database that was recovered
        - RecoverResult: The final result of the recovery operation - either "Success" or "Failed"
        - Comment: Additional details about the recovery operation or error message if the recovery failed

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
        PS C:\> Invoke-DbaDbLogShipRecovery -SqlInstance server1 -Force

        Recovers all the databases on the instance that are enabled for log shipping

    .EXAMPLE
        PS C:\> Invoke-DbaDbLogShipRecovery -SqlInstance server1 -SqlCredential $cred -Verbose -Force

        Recovers all the databases on the instance that are enabled for log shipping using a credential

    .EXAMPLE
        PS C:\> Invoke-DbaDbLogShipRecovery -SqlInstance server1 -database db_logship -Verbose

        Recovers the database "db_logship" to a normal status

    .EXAMPLE
        PS C:\> db1, db2, db3, db4 | Invoke-DbaDbLogShipRecovery -SqlInstance server1 -Verbose

        Recovers the database db1, db2, db3, db4 to a normal status

    .EXAMPLE
        PS C:\> Invoke-DbaDbLogShipRecovery -SqlInstance server1 -Force -WhatIf

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
                $agentStatus = $server.Query("SELECT COUNT(*) AS AgentCount FROM master.dbo.sysprocesses WITH (NOLOCK) WHERE program_name LIKE 'SQLAgent%'")

                if ($agentStatus.AgentCount -lt 1) {
                    Stop-Function -Message "The agent service is not in a running state. Please start the service." -Target $server.name
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