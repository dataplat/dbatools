
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

.PARAMETER Job
The name of the job. 

.PARAMETER ScheduleName
The name of the job schedule. 

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.

.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.PARAMETER Force
The force parameter will ignore some errors in the parameters and assume defaults.
It will also remove the any present schedules with the same name for the specific job.

.NOTES 
Original Author: Sander Stad (@sqlstad, sqlstad.nl)
Tags: Agent, Job, Job Step
	
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Remove-DbaAgentJobSchedule

.EXAMPLE   
Remove-DbaAgentSchedule -SqlInstance sql1 -Job Job1 -ScheduleName weekly
Remove the job schedule weekly from the job

.EXAMPLE   
Remove-DbaAgentSchedule -SqlInstance sql1 -Job Job1 -ScheduleName weekly -Force 
Remove the job schedule weekly from the job even if the schedule is being used by another job.

.EXAMPLE   
Remove-DbaAgentSchedule -SqlInstance sql1 -Job Job1, Job2, Job3 -ScheduleName 'daily' 
Remove the job schedule for multiple jobs

.EXAMPLE   
Remove-DbaAgentSchedule -SqlInstance sql1, sql2, sql3 -Job Job1, Job2, Job3 -ScheduleName 'daily' 
Remove the job schedule on multiple servers for multiple jobs

.EXAMPLE   
sql1, sql2, sql3 | Remove-DbaAgentSchedule -Job Job1, Job2, Job3 -ScheduleName 'daily' 
Remove the job schedule on multiple servers using pipe line

#>  

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
    
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [object[]]$SqlInstance,
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$SqlCredential,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Job,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScheduleName,
        [Parameter(Mandatory = $false)]
        [switch]$Silent,
        [Parameter(Mandatory = $false)]
        [switch]$Force
    ) 

    process {

        foreach ($instance in $sqlinstance) {
            # Try connecting to the instance
            Write-Message -Message "Attempting to connect to $instance" -Level Output
            try {
                $Server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Could not connect to Sql Server instance $instance" -Target $instance -InnerRecord $_ -Continue
            }

            foreach ($j in $Job) {

                # Check if the job exists
                if ($Server.JobServer.Jobs.Name -notcontains $j) {
                    Write-Message -Message "Job $j doesn't exists on $instance" -Level Warning
                }
                else {
                    # Check if the job step exists
                    if ($Server.JobServer.Jobs[$j].JobSchedules[$ScheduleName].Name -notcontains $ScheduleName) {
                        Write-Message -Message "Step $ScheduleName doesn't exists for job $j" -Level Warning
                    }
                    elseif (-not $Force -and ($Server.JobServer.Jobs[$j].JobSchedules[$ScheduleName].JobCount -gt 1)) {
                        Stop-Function -Message "The schedule $ScheduleName is shared among other jobs. If removal is neccesary use -Force." -Target $instance -Continue
                    }
                    else {
                        # Get the job schedule
                        try {
                            $JobSchedule = $Server.JobServer.Jobs[$j].JobSchedules[$ScheduleName][0]
                        }
                        catch {
                            Stop-Function -Message "Something went wrong creating the job schedule. `n$($_.Exception.Message)" -Target $instance -InnerRecord $_ -Continue
                        }

                        # Execute 
                        if ($PSCmdlet.ShouldProcess($instance, "Removing the schedule $ScheduleName for job $j")) {
                            try {
                                Write-Message -Message "Removing the job schedule $ScheduleName for job $j" -Level Output

                                $JobSchedule.Drop()
                            }
                            catch {
                                Stop-Function -Message  "Something went wrong removing the job schedule. `n$($_.Exception.Message)" -Target $instance -InnerRecord $_ -Continue
                            }
                        }
                    }
                }

            } # foreach object job
        } # foreach object instance
    } # process

    end {
        Write-Message -Message "Finished removing jobs schedule(s)." -Level Output
    }
}