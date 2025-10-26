function Remove-DbaAgentJobSchedule {
    <#
    .SYNOPSIS
        Detaches shared schedules from SQL Agent jobs without deleting the schedules themselves.

    .DESCRIPTION
        Removes the association between SQL Agent jobs and their shared schedules, similar to sp_detach_schedule. This allows you to stop a job from running on a shared schedule without affecting other jobs that use the same schedule. The schedule remains available for other jobs and can be reattached later if needed. Use this when you need to temporarily or permanently prevent a specific job from running on a shared schedule while keeping the schedule intact for other jobs.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        Specifies the name of the SQL Agent job from which to detach schedules. Accepts multiple job names.
        Use this to target specific jobs when removing schedule associations.

    .PARAMETER Schedule
        Specifies the name of the schedule(s) to detach from the job. Accepts multiple schedule names.
        Use this when you know the schedule name and want to remove it from one or more jobs.

    .PARAMETER ScheduleUid
        Specifies the unique GUID identifier of the schedule to detach from the job. Accepts multiple schedule UIDs.
        Use this when you need to target an exact schedule, especially when multiple schedules share the same name.

    .PARAMETER ScheduleId
        Specifies the numeric schedule ID to detach from the job. Accepts multiple schedule IDs.
        Use this when you have the specific schedule ID number, typically obtained from Get-DbaAgentSchedule output.

    .PARAMETER InputObject
        Accepts job objects from the pipeline, typically from Get-DbaAgentJob output.
        Use this to chain job operations together or when working with job objects retrieved from other dbatools commands.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Job, Schedule
        Author: Reece Goding, Claude (AI Assistant)

        Website: https://dbatools.io
        Copyright: (c) 2025 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaAgentJobSchedule

    .EXAMPLE
        PS C:\> Remove-DbaAgentJobSchedule -SqlInstance sql1 -Job 'Job1' -Schedule 'Schedule1'

        Detaches the schedule 'Schedule1' from 'Job1'. The schedule remains available for other jobs.

    .EXAMPLE
        PS C:\> Remove-DbaAgentJobSchedule -SqlInstance sql1 -Job 'Job1' -Schedule 'Schedule1', 'Schedule2'

        Detaches multiple schedules from 'Job1'.

    .EXAMPLE
        PS C:\> Remove-DbaAgentJobSchedule -SqlInstance sql1, sql2 -Job 'Job1' -Schedule 'Schedule1'

        Detaches 'Schedule1' from 'Job1' on multiple servers.

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance sql1 -Job 'Job1' | Remove-DbaAgentJobSchedule -Schedule 'Schedule1'

        Detaches a schedule from a job using pipeline input.

    .EXAMPLE
        PS C:\> Remove-DbaAgentJobSchedule -SqlInstance sql1 -Job 'Job1' -ScheduleUid 'bf57fa7e-7720-4936-85a0-87d279db7eb7'

        Detaches a schedule using its unique identifier.

    .EXAMPLE
        PS C:\> Remove-DbaAgentJobSchedule -SqlInstance sql1 -Job 'Job1' -ScheduleId 5

        Detaches a schedule using its numeric ID.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Job,
        [object[]]$Schedule,
        [string[]]$ScheduleUid,
        [int[]]$ScheduleId,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.Job[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        # Validate that at least one schedule identifier is provided
        if (-not $Schedule -and -not $ScheduleUid -and -not $ScheduleId) {
            Stop-Function -Message "You must specify at least one schedule using -Schedule, -ScheduleUid, or -ScheduleId"
            return
        }

        # Initialize collection for jobs retrieved by name
        $jobCollection = @()
    }

    process {

        if (Test-FunctionInterrupt) { return }

        if ((-not $InputObject) -and (-not $Job)) {
            Stop-Function -Message "You must specify a job name or pipe in results from another command" -Target $SqlInstance
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($j in $Job) {

                # Check if the job exists
                if ($server.JobServer.Jobs.Name -notcontains $j) {
                    Stop-Function -Message "Job $j doesn't exist on $instance" -Target $instance -Continue
                } else {
                    # Get the job
                    try {
                        $jobObject = $server.JobServer.Jobs[$j]
                        $jobObject.Refresh()
                        $jobCollection += $jobObject
                    } catch {
                        Stop-Function -Message "Something went wrong retrieving the job" -Target $j -ErrorRecord $_ -Continue
                    }
                }
            }
        }

        # Process pipeline input
        if ($InputObject) {
            $jobCollection += $InputObject
        }

        foreach ($currentJob in $jobCollection) {
            $server = $currentJob.Parent.Parent

            # Build a list of schedules to remove based on the provided parameters
            $schedulesToRemove = @()

            if ($Schedule) {
                foreach ($scheduleName in $Schedule) {
                    $jobSchedules = $currentJob.JobSchedules | Where-Object { $_.Name -eq $scheduleName }
                    if ($jobSchedules) {
                        $schedulesToRemove += $jobSchedules
                    } else {
                        Write-Message -Message "Schedule '$scheduleName' is not attached to job '$($currentJob.Name)' on $($server.Name)" -Level Warning
                    }
                }
            }

            if ($ScheduleUid) {
                foreach ($uid in $ScheduleUid) {
                    $jobSchedules = $currentJob.JobSchedules | Where-Object { $_.ScheduleUid -eq $uid }
                    if ($jobSchedules) {
                        $schedulesToRemove += $jobSchedules
                    } else {
                        Write-Message -Message "Schedule with UID '$uid' is not attached to job '$($currentJob.Name)' on $($server.Name)" -Level Warning
                    }
                }
            }

            if ($ScheduleId) {
                foreach ($id in $ScheduleId) {
                    $jobSchedules = $currentJob.JobSchedules | Where-Object { $_.ID -eq $id }
                    if ($jobSchedules) {
                        $schedulesToRemove += $jobSchedules
                    } else {
                        Write-Message -Message "Schedule with ID '$id' is not attached to job '$($currentJob.Name)' on $($server.Name)" -Level Warning
                    }
                }
            }

            # Remove duplicates (in case the same schedule was specified multiple ways)
            $schedulesToRemove = $schedulesToRemove | Sort-Object -Property ScheduleUid -Unique

            # Remove each schedule from the job
            foreach ($jobSchedule in $schedulesToRemove) {
                if ($PSCmdlet.ShouldProcess($server.Name, "Detaching schedule '$($jobSchedule.Name)' (ID: $($jobSchedule.ID), UID: $($jobSchedule.ScheduleUid)) from job '$($currentJob.Name)'")) {
                    try {
                        Write-Message -Message "Detaching schedule '$($jobSchedule.Name)' from job '$($currentJob.Name)'" -Level Verbose

                        # Drop the job schedule association (true = keep the shared schedule)
                        $jobSchedule.Drop($true)

                        # Output the result
                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Job          = $currentJob.Name
                            Schedule     = $jobSchedule.Name
                            ScheduleId   = $jobSchedule.ID
                            ScheduleUid  = $jobSchedule.ScheduleUid
                            Status       = "Detached"
                            IsDetached   = $true
                        }
                    } catch {
                        Stop-Function -Message "Failed to detach schedule '$($jobSchedule.Name)' from job '$($currentJob.Name)' on $($server.Name)" -ErrorRecord $_ -Continue

                        # Output the failure result
                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Job          = $currentJob.Name
                            Schedule     = $jobSchedule.Name
                            ScheduleId   = $jobSchedule.ID
                            ScheduleUid  = $jobSchedule.ScheduleUid
                            Status       = (Get-ErrorMessage -Record $_)
                            IsDetached   = $false
                        }
                    }
                }
            }
        }
    }

    end {
        Write-Message -Message "Finished detaching schedule(s) from job(s)" -Level Verbose
    }
}
