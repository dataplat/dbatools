function Remove-DbaAgentJobStep {
    <#
    .SYNOPSIS
        Removes specified job steps from SQL Server Agent jobs.

    .DESCRIPTION
        Removes individual job steps from SQL Server Agent jobs by step name. This function validates that both the job and step exist before attempting removal, preventing errors when cleaning up outdated or broken job steps. Useful for job maintenance tasks like removing obsolete backup steps, failed notification steps, or deprecated processes without affecting the rest of the job workflow.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        The name of the job.

    .PARAMETER StepName
        The name of the job step.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Job, JobStep
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaAgentJobStep

    .EXAMPLE
        PS C:\> Remove-DbaAgentJobStep -SqlInstance sql1 -Job Job1 -StepName Step1

        Remove 'Step1' from job 'Job1' on sql1.

    .EXAMPLE
        PS C:\> Remove-DbaAgentJobStep -SqlInstance sql1 -Job Job1, Job2, Job3 -StepName Step1

        Remove the job step from multiple jobs.

    .EXAMPLE
        PS C:\> Remove-DbaAgentJobStep -SqlInstance sql1, sql2, sql3 -Job Job1 -StepName Step1

        Remove the job step from the job on multiple servers.

    .EXAMPLE
        PS C:\> sql1, sql2, sql3 | Remove-DbaAgentJobStep -Job Job1 -StepName Step1

        Remove the job step from the job on multiple servers using pipeline.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object[]]$Job,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$StepName,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {

            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($j in $Job) {
                Write-Message -Level Verbose -Message "Processing job $j"
                # Check if the job exists
                if ($Server.JobServer.Jobs.Name -notcontains $j) {
                    Stop-Function -Message "Job $j doesnn't exist on $instance." -Continue -ContinueLabel main -Target $instance -Category InvalidData
                } else {
                    # Check if the job step exists
                    if ($Server.JobServer.Jobs[$j].JobSteps.Name -notcontains $StepName) {
                        Stop-Function -Message "Step $StepName doesn't exist for $job on $instance." -Continue -ContinueLabel main -Target $instance -Category InvalidData
                    } else {
                        # Execute
                        if ($PSCmdlet.ShouldProcess($instance, "Removing the job step $StepName for job $j")) {
                            try {
                                $JobStep = $Server.JobServer.Jobs[$j].JobSteps[$StepName]
                                Write-Message -Level SomewhatVerbose -Message "Removing the job step $StepName for job $j."
                                $JobStep.Drop()
                            } catch {
                                Stop-Function -Message "Something went wrong removing the job step" -Target $JobStep -Continue -ErrorRecord $_
                                Write-Message -Level Verbose -Message "Could not remove the job step $StepName from $j"
                            }
                        }
                    }
                }
            }
        }
    }
    end {
        Write-Message -Message "Finished removing the jobs step(s)" -Level Verbose
    }
}