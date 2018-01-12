#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Remove-DbaAgentSchedule {
    <#
.SYNOPSIS
Remove-DbaAgentJobSchedule removes a job schedule.

.DESCRIPTION
Remove-DbaAgentJobSchedule removes a a job in the SQL Server Agent.

.PARAMETER SqlInstance
SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Schedule
The name of the job schedule.

.PARAMETER ScheduleCollection
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
Author: Sander Stad (@sqlstad, sqlstad.nl)
Tags: Agent, Job, Schedule

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Remove-DbaAgentJobSchedule

.EXAMPLE
Remove-DbaAgentSchedule -SqlInstance sql1 -Schedule weekly
Remove the schedule weekly

.EXAMPLE
Remove-DbaAgentSchedule -SqlInstance sql1 -Schedule weekly -Force
Remove the schedule weekly from the job even if the schedule is being used by another job.

.EXAMPLE
Remove-DbaAgentSchedule -SqlInstance sql1 -Schedule daily, weekly
Remove multiple schedule

.EXAMPLE
Remove-DbaAgentSchedule -SqlInstance sql1, sql2, sql3 -Schedule daily, weekly
Remove the schedule on multiple servers for multiple schedules

.EXAMPLE
sql1, sql2, sql3 | Remove-DbaAgentSchedule -Schedule daily, weekly
Remove the schedule on multiple servers using pipe line

.EXAMPLE
Get-DbaAgentSchedule -SqlInstance sql1 -Schedule sched1, sched2, sched3 | Remove-DbaAgentSchedule

Remove the schedules using a pipeline

#>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]

    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = "instance")]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [System.Management.Automation.PSCredential]
        $SqlCredential,
        [Parameter(Mandatory = $true, ParameterSetName = "instance")]
        [ValidateNotNullOrEmpty()]
        [Alias("Schedules")]
        [object[]]$Schedule,
        [Parameter(ValueFromPipeline, Mandatory, ParameterSetName = "schedules")]
        [Microsoft.SqlServer.Management.Smo.Agent.ScheduleBase[]]$ScheduleCollection,
        [switch][Alias('Silent')]$EnableException,

        [switch]$Force
    )

    process {

        foreach ($instance in $sqlinstance) {
            # Try connecting to the instance
            Write-Message -Message "Attempting to connect to $instance" -Level Verbose
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $ScheduleCollection += $server.JobServer.SharedSchedules | Where-Object { $_.Name -in $Schedule }

        } # foreach object instance

        foreach ($s in $ScheduleCollection) {

            if ($Server.JobServer.SharedSchedules.Name -contains $s.Name) {
                # Get job count
                $jobCount = $Server.JobServer.SharedSchedules[$s].JobCount

                # Check if the schedule is shared among other jobs
                if ($jobCount -ge 1 -and -not $Force) {
                    Stop-Function -Message "The schedule $s is shared connected to one or more jobs. If removal is neccesary use -Force." -Target $instance -Continue
                }

                # Remove the job schedule
                if ($PSCmdlet.ShouldProcess($instance, "Removing schedule $s on $instance")) {
                    # Loop through each of the schedules and drop them
                    Write-Message -Message "Removing schedule $s on $instance" -Level Verbose

                    #Check if jobs use the schedule
                    if ($jobCount -ge 1) {
                        # Get the job object
                        $smoSchedules = $server.JobServer.SharedSchedules | Where-Object {($_.Name -eq $s.Name)}

                        Write-Message -Message "Schedule $sched is used in one or more jobs. Removing it for each job." -Level Verbose

                        # Loop through each if the schedules
                        foreach ($smoSchedule in $smoSchedules) {

                            # Get the job ids
                            $jobGuids = $Server.JobServer.SharedSchedules[$smoSchedule].EnumJobReferences()

                            if (($jobCount -gt 1 -and $Force) -or $jobCount -eq 1) {

                                # Loop though each of the jobs
                                foreach ($guid in $jobGuids) {
                                    # Get the job object
                                    $smoJob = $Server.JobServer.GetJobByID($guid)

                                    # Get the job schedule
                                    $jobSchedules = $Server.JobServer.Jobs[$smoJob].JobSchedules | Where-Object {$_.Name -eq $smoSchedule}

                                    foreach ($jobSchedule in $jobSchedules) {
                                        try {
                                            Write-Message -Message "Removing the schedule $jobSchedule for job $smoJob" -Level Verbose

                                            $jobSchedule.Drop()
                                        }
                                        catch {
                                            Stop-Function -Message  "Something went wrong removing the job schedule" -Target $instance -ErrorRecord $_ -Continue
                                        }
                                    }
                                } # foreach guid
                            } # if jobcount

                        } # foreach smoschedule
                    } # if jobcount ge 1

                    Write-Message -Message "Removing schedules that are not being used by other jobs." -Level Verbose

                    # Get the schedules
                    $smoSchedules = $server.JobServer.SharedSchedules | Where-Object {($_.Name -eq $s.Name) -and ($_.JobCount -eq 0)}

                    # Remove the schedules that have no jobs
                    foreach ($smoSchedule in $smoSchedules) {
                        try {
                            $smoSchedule.Drop()
                        }
                        catch {
                            Stop-Function -Message  "Something went wrong removing the schedule" -Target $instance -ErrorRecord $_ -Continue
                        }
                    } # foreach schedule
                } # should process
            } # if contains schedule
            else {
                Stop-Function -Message "Schedule $s is not present on instance $instance" -Target $instance -Continue
            }
        } #foreach object schedule

    } # process

    end {
        Write-Message -Message "Finished removing jobs schedule(s)." -Level Verbose
    }
}