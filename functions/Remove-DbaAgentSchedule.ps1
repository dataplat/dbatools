function Remove-DbaAgentSchedule {
    <#
    .SYNOPSIS
        Remove-DbaAgentSchedule removes a job schedule.

    .DESCRIPTION
        Remove-DbaAgentSchedule removes a job in the SQL Server Agent.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Schedule
        The name of the job schedule.

    .PARAMETER ScheduleUid
        The unique identifier of the schedule

    .PARAMETER InputObject
        A collection of schedule (such as returned by Get-DbaAgentSchedule), to be removed.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        The force parameter will ignore some errors in the parameters and assume defaults.
        It will also remove the any present schedules with the same name for the specific job.

    .NOTES
        Tags: Agent, Job, Schedule
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaAgentSchedule

    .EXAMPLE
        PS C:\> Remove-DbaAgentSchedule -SqlInstance sql1 -Schedule weekly

        Remove the schedule weekly

    .EXAMPLE
        PS C:\> Remove-DbaAgentSchedule -SqlInstance sql1 -Schedule weekly -Force

        Remove the schedule weekly from the job even if the schedule is being used by another job.

    .EXAMPLE
        PS C:\> Remove-DbaAgentSchedule -SqlInstance sql1 -Schedule daily, weekly

        Remove multiple schedule

    .EXAMPLE
        PS C:\> Remove-DbaAgentSchedule -SqlInstance sql1, sql2, sql3 -Schedule daily, weekly
        Remove the schedule on multiple servers for multiple schedules

    .EXAMPLE
        sql1, sql2, sql3 | Remove-DbaAgentSchedule -Schedule daily, weekly
        Remove the schedule on multiple servers using pipe line

    .EXAMPLE
        Get-DbaAgentSchedule -SqlInstance sql1 -Schedule sched1, sched2, sched3 | Remove-DbaAgentSchedule

        Remove the schedules using a pipeline

    .EXAMPLE
        Remove-DbaAgentSchedule -SqlInstance sql1, sql2, sql3 -ScheduleUid 'bf57fa7e-7720-4936-85a0-87d279db7eb7'

        Remove the schedules usingthe schdule uid

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = "instance")]
        [DbaInstanceParameter[]]$SqlInstance,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [Parameter(ParameterSetName = "instance")]
        [ValidateNotNullOrEmpty()]
        [Alias("Schedules", "Name")]
        [string[]]$Schedule,
        [Alias("Uid")]
        [string[]]$ScheduleUid,
        [Parameter(ValueFromPipeline, Mandatory, ParameterSetName = "schedules")]
        [Microsoft.SqlServer.Management.Smo.Agent.ScheduleBase[]]$InputObject,
        [switch]$EnableException,
        [switch]$Force
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }

    process {

        foreach ($instance in $SqlInstance) {
            # Try connecting to the instance
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (-not ($InputObject -or $Schedule -or $ScheduleUid)) {
                Stop-Function -Message "Please enter the schedule or schedule uid"
            }

            $InputObject += $server.JobServer.SharedSchedules

            if ($Schedule) {
                $InputObject = $InputObject | Where-Object Name -in $Schedule
            }

            if ($ScheduleUid) {
                $InputObject = $InputObject | Where-Object ScheduleUid -in $ScheduleUid
            }

        } # foreach object instance

        foreach ($currentSchedule in $InputObject) {
            $server = $currentSchedule.Parent.Parent

            if (-not $server) {
                $server = $currentSchedule.Parent
            }

            $server.JobServer.SharedSchedules.Refresh()
            $scheduleName = $currentSchedule.Name
            $jobCount = $server.JobServer.SharedSchedules[$currentSchedule].JobCount

            # Check if the schedule is shared among other jobs
            if ($jobCount -ge 1 -and -not $Force) {
                Stop-Function -Message "The schedule $scheduleName is shared connected to one or more jobs. If removal is neccesary use -Force." -Target $instance -Continue
            }

            # Remove the job schedule
            if ($PSCmdlet.ShouldProcess($instance, "Removing schedule $currentSchedule on $instance")) {
                # Loop through each of the schedules and drop them
                Write-Message -Message "Removing schedule $scheduleName on $instance" -Level Verbose

                #Check if jobs use the schedule
                if ($jobCount -ge 1) {
                    # Get the job object
                    $smoSchedules = $server.JobServer.SharedSchedules | Where-Object { ($_.Name -eq $currentSchedule.Name) }

                    Write-Message -Message "Schedule $scheduleName is used in one or more jobs. Removing it for each job." -Level Verbose

                    # Loop through each if the schedules
                    foreach ($smoSchedule in ($smoSchedules)) {

                        # Get the job ids
                        $jobGuids = $Server.JobServer.SharedSchedules[$smoSchedule].EnumJobReferences()

                        if (($jobCount -gt 1 -and $Force) -or $jobCount -eq 1) {

                            # Loop though each of the jobs
                            foreach ($guid in $jobGuids) {
                                # Get the job object
                                $smoJob = $Server.JobServer.GetJobByID($guid)

                                # Get the job schedule
                                $jobSchedules = $Server.JobServer.Jobs[$smoJob].JobSchedules | Where-Object { $_.Name -eq $smoSchedule }

                                foreach ($jobSchedule in ($jobSchedules)) {
                                    try {
                                        Write-Message -Message "Removing the schedule $jobSchedule for job $smoJob" -Level Verbose

                                        $jobSchedule.Drop()
                                    } catch {
                                        Stop-Function -Message "Failure" -Target $instance -ErrorRecord $_ -Continue
                                    }
                                }
                            }
                        }
                    }
                }

                Write-Message -Message "Removing schedules that are not being used by other jobs." -Level Verbose
                $server.JobServer.SharedSchedules.Refresh()
                # Get the schedules
                $smoSchedules = $server.JobServer.SharedSchedules | Where-Object { ($_.Name -eq $currentSchedule.Name) -and ($_.JobCount -eq 0) }

                # Remove the schedules that have no jobs
                foreach ($smoSchedule in $smoSchedules) {
                    try {
                        $smoSchedule.Drop()
                    } catch {
                        Stop-Function -Message "Something went wrong removing the schedule" -Target $instance -ErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
    end {
        Write-Message -Message "Finished removing jobs schedule(s)." -Level Verbose
    }
}
