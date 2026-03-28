function Remove-DbaAgentJobSchedule {
    <#
    .SYNOPSIS
        Detaches a schedule from a SQL Server Agent job without removing the schedule.

    .DESCRIPTION
        Detaches one or more schedules from a SQL Server Agent job without deleting the schedule itself. This is equivalent to executing sp_detach_schedule in T-SQL.

        This is particularly useful when a schedule is shared between multiple jobs and you need to stop a specific job from running on that schedule without affecting other jobs that use the same schedule. The schedule remains in SQL Server Agent and can be reattached to the job or attached to other jobs at any time.

        Use Set-DbaAgentJob with the -Schedule parameter to reattach a schedule to a job after detaching it.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        The name of the SQL Agent job(s) from which to detach the schedule. Required when using -SqlInstance.

    .PARAMETER Schedule
        The name of the schedule(s) to detach from the job. The schedule itself is not deleted; only the association between the job and schedule is removed.

    .PARAMETER InputObject
        Accepts job objects from the pipeline, typically from Get-DbaAgentJob output. Use this when you want to filter or retrieve jobs first, then pipe the results for schedule detachment.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Returns one object per detach operation, containing the result and details.

        Properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Job: The name of the job from which the schedule was detached
        - Schedule: The name of the schedule that was detached
        - ScheduleId: The numeric ID of the schedule
        - ScheduleUid: The unique GUID identifier of the schedule
        - Status: Result of the operation ("Detached" for success, or error message for failures)
        - IsDetached: Boolean indicating if the schedule was successfully detached

    .NOTES
        Tags: Agent, Job, JobSchedule, Schedule
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaAgentJobSchedule

    .EXAMPLE
        PS C:\> Remove-DbaAgentJobSchedule -SqlInstance sql1 -Job Job1 -Schedule SharedSchedule

        Detaches the schedule named 'SharedSchedule' from job 'Job1' on sql1. The schedule itself is not deleted and remains available for other jobs.

    .EXAMPLE
        PS C:\> Remove-DbaAgentJobSchedule -SqlInstance sql1 -Job Job1 -Schedule Schedule1, Schedule2

        Detaches multiple schedules from a single job on sql1.

    .EXAMPLE
        PS C:\> Remove-DbaAgentJobSchedule -SqlInstance sql1, sql2 -Job Job1 -Schedule SharedSchedule

        Detaches the schedule from job 'Job1' on multiple SQL Server instances.

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance sql1 -Job Job1 | Remove-DbaAgentJobSchedule -Schedule SharedSchedule

        Detaches the schedule 'SharedSchedule' from job 'Job1' using pipeline input.

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance sql1 | Where-Object Name -like 'Maintenance*' | Remove-DbaAgentJobSchedule -Schedule SharedSchedule

        Detaches 'SharedSchedule' from all jobs whose names start with 'Maintenance' on sql1.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Job,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Schedule,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.Job[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        $jobs = @()
    }
    process {
        foreach ($instance in $SqlInstance) {
            if (-not (Test-Bound -ParameterName Job)) {
                Stop-Function -Message "Parameter -Job is required when using -SqlInstance" -Target $instance -Continue
            }

            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($jobName in $Job) {
                if ($server.JobServer.Jobs.Name -notcontains $jobName) {
                    Stop-Function -Message "Job '$jobName' does not exist on $instance" -Target $instance -Continue
                }
                $jobs += $server.JobServer.Jobs[$jobName]
            }
        }

        foreach ($jobObject in $InputObject) {
            $jobs += $jobObject
        }
    }
    end {
        # We process in the end block to prevent "Collection was modified; enumeration operation may not execute."
        # if job objects are directly piped from Get-DbaAgentJob.
        foreach ($jobObject in $jobs) {
            $server = $jobObject.Parent.Parent

            foreach ($scheduleName in $Schedule) {
                $jobSchedule = $jobObject.JobSchedules | Where-Object { $_.Name -eq $scheduleName }

                if (-not $jobSchedule) {
                    Stop-Function -Message "Schedule '$scheduleName' is not attached to job '$($jobObject.Name)' on $($server.Name)" -Target $jobObject -Continue
                }

                $output = [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Job          = $jobObject.Name
                    Schedule     = $scheduleName
                    ScheduleId   = $jobSchedule.Id
                    ScheduleUid  = $jobSchedule.ScheduleUid
                    Status       = $null
                    IsDetached   = $false
                }

                if ($PSCmdlet.ShouldProcess($server, "Detaching schedule '$scheduleName' from job '$($jobObject.Name)'")) {
                    try {
                        Write-Message -Level Verbose -Message "Detaching schedule '$scheduleName' from job '$($jobObject.Name)' on $($server.Name)"
                        $jobSchedule.Drop($true)
                        $output.Status = "Detached"
                        $output.IsDetached = $true
                    } catch {
                        Stop-Function -Message "Failed to detach schedule '$scheduleName' from job '$($jobObject.Name)' on $($server.Name)" -ErrorRecord $_ -Target $jobObject -Continue
                        $output.Status = (Get-ErrorMessage -Record $_)
                    }
                }

                $output
            }
        }
    }
}
