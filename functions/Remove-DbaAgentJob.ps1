#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Remove-DbaAgentJob {
    <#
        .SYNOPSIS
            Remove-DbaAgentJob removes a job.

        .DESCRIPTION
            Remove-DbaAgentJob removes a a job in the SQL Server Agent.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Job
            The name of the job. Can be null if the the job id is being used.

        .PARAMETER KeepHistory
            Specifies to keep the history for the job. By default history is deleted.

        .PARAMETER KeepUnusedSchedule
            Specifies to keep the schedules attached to this job if they are not attached to any other job.
            By default the unused schedule is deleted.

        .PARAMETER Mode
            Default: Strict
            How strict does the command take lesser issues?
            Strict: Interrupt if the job specified doesn't exist.
            Lazy:   Silently skip over jobs that don't exist.

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
            License: MIT https://opensource.org/licenses/MIT

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
        [DbaMode]$Mode = (Get-DbaConfigValue -Name 'message.mode.default' -Fallback "Strict"),
        [Parameter(Mandatory = $false)]
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

                if ($Server.JobServer.Jobs.Name -notcontains $j) {
                    switch ($Mode) {
                        'Lazy' {
                            Write-Message -Level Verbose -Message "Job $j doesn't exists on $instance." -Target $instance
                        }
                        'Strict' {
                            Stop-Function -Message "Job $j doesn't exist on $instance." -Continue -ContinueLabel main -Target $instance -Category InvalidData
                        }
                    }
                }
                else {
                    if ($PSCmdlet.ShouldProcess($instance, "Removing the job $j")) {
                        try {
                            $currentJob = $Server.JobServer.Jobs[$j]
                            $dropHistory = 1
                            $dropSchedule = 1
                            if (Test-Bound -ParameterName KeepHistory) {
                                Write-Message -Level SomewhatVerbose -Message "Job history will be kept"
                                $dropHistory = 0
                            }
                            if (Test-Bound -ParameterName KeepUnusedSchedule) {
                                Write-Message -Level SomewhatVerbose -Message "Unused job schedules will be kept"
                                $dropSchedule = 0
                            }
                            Write-Message -Level SomewhatVerbose -Message "Removing job"
                            $dropJobQuery = ("EXEC dbo.sp_delete_job @job_name = '{0}', @delete_history = {1}, @delete_unused_schedule = {2}" -f $currentJob.Name, $dropHistory, $dropSchedule)
                            $server.Databases['msdb'].ExecuteNonQuery($dropJobQuery)
                        }
                        catch {
                            Stop-Function -Message  "Something went wrong removing the job" -Target $instance -ErrorRecord $_ -Continue
                        }
                    }
                }
            }
        }
    }
    end {
        Write-Message -Message "Finished removing jobs(s)." -Level Verbose
    }
}