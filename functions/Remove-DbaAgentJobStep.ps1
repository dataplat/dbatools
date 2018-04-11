#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Remove-DbaAgentJobStep {
    <#
        .SYNOPSIS
            Removes a step from the specified SQL Agent job.

        .DESCRIPTION
            Removes a job step from a SQL Server Agent job.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.
        
        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Job
            The name of the job.

        .PARAMETER StepName
            The name of the job step.

        .PARAMETER Mode
            Default: Strict
            How strict does the command take lesser issues?
            Strict: Interrupt if the configuration already has the same value as the one specified.
            Lazy:   Silently skip over instances that already have this configuration at the specified value.

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Sander Stad (@sqlstad, sqlstad.nl)
            Tags: Agent, Job, Job Step

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Remove-DbaAgentJobStep

        .EXAMPLE
            Remove-DbaAgentJobStep -SqlInstance sql1 -Job Job1 -StepName Step1

            Remove 'Step1' from job 'Job1' on sql1.

        .EXAMPLE
            Remove-DbaAgentJobStep -SqlInstance sql1 -Job Job1, Job2, Job3 -StepName Step1

            Remove the job step from multiple jobs.

        .EXAMPLE
            Remove-DbaAgentJobStep -SqlInstance sql1, sql2, sql3 -Job Job1 -StepName Step1

            Remove the job step from the job on multiple servers.

        .EXAMPLE
            sql1, sql2, sql3 | Remove-DbaAgentJobStep -Job Job1 -StepName Step1

            Remove the job step from the job on multiple servers using pipeline.
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
        [DbaMode]$Mode = (Get-DbaConfigValue -Name 'message.mode.default' -Fallback "Strict"),
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($j in $Job) {
                Write-Message -Level Verbose -Message "Processing job $j"
                # Check if the job exists
                if ($Server.JobServer.Jobs.Name -notcontains $j) {
                    switch ($Mode) {
                        'Lazy' {
                            Write-Message -Level Verbose -Message "Job $j doesn't exists on $instance." -Target $instance
                        }
                        'Strict' {
                            Stop-Function -Message "Job $j doesnn't exist on $instance." -Continue -ContinueLabel main -Target $instance -Category InvalidData
                        }
                    }
                }
                else {
                    # Check if the job step exists
                    if ($Server.JobServer.Jobs[$j].JobSteps.Name -notcontains $StepName) {
                        switch ($Mode) {
                            'Lazy' {
                                Write-Message -Level Verbose -Message "Step $StepName doesn't exist for $job on $instance." -Target $instance
                            }
                            'Strict' {
                                Stop-Function -Message "Step $StepName doesn't exist for $job on $instance." -Continue -ContinueLabel main -Target $instance -Category InvalidData
                            }
                        }
                    }
                    else {
                        # Execute
                        if ($PSCmdlet.ShouldProcess($instance, "Removing the job step $StepName for job $j")) {
                            try {
                                $JobStep = $Server.JobServer.Jobs[$j].JobSteps[$StepName]
                                Write-Message -Level SomewhatVerbose -Message "Removing the job step $StepName for job $j."
                                $JobStep.Drop()
                            }
                            catch {
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
