#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Remove-DbaAgentJobStep {
    <#
.SYNOPSIS
Remove-DbaAgentJobStep removes a job step.

.DESCRIPTION
Remove-DbaAgentJobStep removes a job step in the SQL Server Agent.

.PARAMETER SqlInstance
SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Job
The name of the job. Can be null if the the job id is being used.

.PARAMETER StepName
The name of the step.

.PARAMETER KeepHistory
Specifies to keep the history for the job. By default is history is deleted.

.PARAMETER KeepUnusedSchedule
Specifies to keep the schedules attached to this job if they are not attached to any other job. By default the unused schedule is deleted.

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
Tags: Agent, Job, Job Step

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Remove-DbaAgentJobStep

.EXAMPLE
Remove-DbaAgentJobStep -SqlInstance sql1 -Job Job1 -StepName Step1
Remove the job step from the job

.EXAMPLE
Remove-DbaAgentJobStep -SqlInstance sql1 -Job Job1, Job2, Job3 -StepName Step1
Remove the job step from the job for multiple jobs

.EXAMPLE
Remove-DbaAgentJobStep -SqlInstance sql1, sql2, sql3 -Job Job1 -StepName Step1
Remove the job step from the job on multiple servers


.EXAMPLE
sql1, sql2, sql3 | Remove-DbaAgentJobStep -Job Job1 -StepName Step1
Remove the job step from the job on multiple servers using pipeline

#>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(Mandatory = $false)]
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Job,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$StepName,
        [Parameter(Mandatory = $false)]
        [switch][Alias('Silent')]$EnableException
    )

    process {

        foreach ($instance in $sqlinstance) {

            # Try connecting to the instance
            Write-Message -Message "Attempting to connect to $instance" -Level Verbose
            try {
                $Server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($j in $Job) {

                # Check if the job exists
                if ($Server.JobServer.Jobs.Name -notcontains $j) {
                    Write-Message -Message "Job $j doesn't exists on $instance" -Level Warning
                }
                else {
                    # Check if the job step exists
                    if ($Server.JobServer.Jobs[$j].JobSteps.Name -notcontains $StepName) {
                        Write-Message -Message "Step $StepName doesn't exist for $job on $instance" -Level Warning
                    }
                    else {
                        # Get the job step
                        try {
                            $JobStep = $Server.JobServer.Jobs[$j].JobSteps[$StepName]
                        }
                        catch {
                            Stop-Function -Message "Something went wrong creating the job step" -Target $JobStep -Continue -ErrorRecord $_
                        }

                        # Execute
                        if ($PSCmdlet.ShouldProcess($instance, "Removing the job step $StepName for job $j")) {
                            try {
                                Write-Message -Message "Removing the job step $StepName for job $j" -Level Verbose

                                $JobStep.Drop()
                            }
                            catch {
                                Stop-Function -Message "Something went wrong removing the job step" -Target $JobStep -Continue -ErrorRecord $_
                            }
                        }
                    }
                }

            } # foreach object job
        } # foreach object instance
    } # process

    end {
        Write-Message -Message "Finished removing the jobs step(s)" -Level Verbose
    }
}
