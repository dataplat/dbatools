function Remove-DbaAgentJob {
    <#
    .SYNOPSIS
        Remove-DbaAgentJob removes a job.

    .DESCRIPTION
        Remove-DbaAgentJob removes a job in the SQL Server Agent.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

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

    .PARAMETER InputObject
        Accepts piped input from Get-DbaAgentJob

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Job
        Author: Sander Stad (@sqlstad, sqlstad.nl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaAgentJob

    .EXAMPLE
        PS C:\> Remove-DbaAgentJob -SqlInstance sql1 -Job Job1

        Removes the job from the instance with the name Job1

    .EXAMPLE
        PS C:\> GetDbaAgentJob -SqlInstance sql1 -Job Job1 | Remove-DbaAgentJob -KeepHistory

        Removes the job but keeps the history

    .EXAMPLE
        PS C:\> Remove-DbaAgentJob -SqlInstance sql1 -Job Job1 -KeepUnusedSchedule

        Removes the job but keeps the unused schedules

    .EXAMPLE
        PS C:\> Remove-DbaAgentJob -SqlInstance sql1, sql2, sql3 -Job Job1

        Removes the job from multiple servers

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Job,
        [switch]$KeepHistory,
        [switch]$KeepUnusedSchedule,
        [DbaMode]$Mode = (Get-DbatoolsConfigValue -FullName 'message.mode.default' -Fallback "Strict"),
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.Job[]]$InputObject,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($j in $Job) {
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
                $InputObject += ($Server.JobServer.Jobs | Where-Object Name -eq $j)
            }
        }
        foreach ($currentJob in $InputObject) {
            $j = $currentJob.Name
            $server = $currentJob.Parent.Parent

            if ($PSCmdlet.ShouldProcess($instance, "Removing the job $j from $server")) {
                try {
                    $dropHistory = $dropSchedule = 1

                    if (Test-Bound -ParameterName KeepHistory) {
                        Write-Message -Level SomewhatVerbose -Message "Job history will be kept"
                        $dropHistory = 0
                    }
                    if (Test-Bound -ParameterName KeepUnusedSchedule) {
                        Write-Message -Level SomewhatVerbose -Message "Unused job schedules will be kept"
                        $dropSchedule = 0
                    }
                    Write-Message -Level SomewhatVerbose -Message "Removing job"
                    $dropJobQuery = ("EXEC dbo.sp_delete_job @job_name = '{0}', @delete_history = {1}, @delete_unused_schedule = {2}" -f $currentJob.Name.Replace("'", "''"), $dropHistory, $dropSchedule)
                    $server.Databases['msdb'].ExecuteNonQuery($dropJobQuery)
                    [pscustomobject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Name         = $currentJob.Name
                        Status       = 'Dropped'
                    }
                } catch {
                    Write-Message -Level Verbose -Message "Could not drop job $job on $server"

                    [pscustomobject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Name         = $currentJob.Name
                        Status       = "Failed. $(Get-ErrorMessage -Record $_)"
                    }
                }
            }
        }
    }
}