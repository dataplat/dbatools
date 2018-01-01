#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Remove-DbaAgentJob {
    <#
.SYNOPSIS
Remove-DbaAgentJob removes a job.

.DESCRIPTION
Remove-DbaAgentJob removes a a job in the SQL Server Agent.

.PARAMETER SqlInstance
SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Job
The name of the job. Can be null if the the job id is being used.

.PARAMETER KeepHistory
Specifies to keep the history for the job. By default is history is deleted.

.PARAMETER KeepUnusedSchedule
Specifies to keep the schedules attached to this job if they are not attached to any other job.
By default the unused schedule is deleted.

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Author: Sander Stad (@sqlstad, sqlstad.nl)
Tags: Agent, Job

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Remove-DbaAgentJob

.EXAMPLE
Remove-DbaAgentJob -SqlInstance sql1 -Job Job1
Removes the job from the instance with the name Job1

.EXAMPLE
Remove-DbaAgentJob -SqlInstance sql1 -Job Job1 -KeepHistory
Removes the job but keeps the history

.EXAMPLE
Remove-DbaAgentJob -SqlInstance sql1 -Job Job1 -KeepUnusedSchedule
Removes the job but keeps the unused schedules

.EXAMPLE
Remove-DbaAgentJob -SqlInstance sql1, sql2, sql3 -Job Job1
Removes the job from multiple servers

.EXAMPLE
sql1, sql2, sql3 | Remove-DbaAgentJob -Job Job1
Removes the job from multiple servers using pipe line

#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]

    param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,

        [Parameter(Mandatory = $false)]
        [PSCredential]$SqlCredential,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Job,

        [Parameter(Mandatory = $false)]
        [switch]$KeepHistory,

        [Parameter(Mandatory = $false)]
        [switch]$KeepUnusedSchedule,

        [Parameter(Mandatory = $false)]
        [switch][Alias('Silent')]$EnableException
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

            foreach ($j in $Job) {

                # Check if the job exists
                if ($Server.JobServer.Jobs.Name -notcontains $j) {
                    Write-Message -Message "Job $j doesn't exists on $instance" -Warning
                }
                else {
                    # Get the job
                    try {
                        $currentjob = $Server.JobServer.Jobs[$j]
                    }
                    catch {
                        Stop-Function -Message "Something went wrong creating the job" -Target $instance -ErrorRecord $_ -Continue
                    }

                    # Delete the history
                    if (-not $KeepHistory) {
                        Write-Message -Message "Purging job history" -Level Verbose
                        $currentjob.PurgeHistory()
                    }

                    # Execute
                    if ($PSCmdlet.ShouldProcess($instance, "Removing the job on $instance")) {
                        try {
                            Write-Message -Message "Removing the job" -Level Verbose

                            if ($KeepUnusedSchedule) {
                                # Drop the job keeping the unused schedules
                                Write-Message -Message "Removing job keeping unused schedules" -Level Verbose
                                $currentjob.Drop($true)
                            }
                            else {
                                # Drop the job removing the unused schedules
                                Write-Message -Message "Removing job removing unused schedules" -Level Verbose
                                $currentjob.Drop($false)
                            }

                        }
                        catch {
                            Stop-Function -Message  "Something went wrong removing the job" -Target $instance -ErrorRecord $_ -Continue
                        }
                    }
                }

            } # foreach object job
        } # forech object instance
    } # process

    end {
        Write-Message -Message "Finished removing jobs(s)." -Level Verbose
    }
}