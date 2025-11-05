function Remove-DbaAgentJob {
    <#
    .SYNOPSIS
        Removes SQL Server Agent jobs from one or more instances with options to preserve history and schedules.

    .DESCRIPTION
        Removes SQL Server Agent jobs from the target instances using the sp_delete_job system stored procedure. By default, both job history and unused schedules are deleted along with the job itself. You can optionally preserve job execution history for compliance or troubleshooting purposes, and keep unused schedules that might be reused for other jobs. This function is commonly used when decommissioning applications, cleaning up test environments, or removing obsolete maintenance jobs during server consolidation projects.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        Specifies the name of the SQL Server Agent job to remove. Accepts one or more job names.
        Use this when you know the specific job names you want to delete, rather than piping job objects.

    .PARAMETER KeepHistory
        Preserves job execution history in the msdb.dbo.sysjobhistory tables when removing the job.
        Use this when you need to retain audit trails or troubleshooting information for compliance or analysis purposes.

    .PARAMETER KeepUnusedSchedule
        Preserves job schedules that aren't used by other jobs when removing this job.
        Use this when you plan to reuse the schedule for new jobs or want to maintain schedule definitions for documentation purposes.

    .PARAMETER InputObject
        Accepts SQL Server Agent job objects from the pipeline, typically from Get-DbaAgentJob.
        Use this approach when you need to filter jobs with complex criteria before removal or when processing jobs from multiple instances.

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
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Job,
        [switch]$KeepHistory,
        [switch]$KeepUnusedSchedule,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.Job[]]$InputObject,
        [switch]$EnableException
    )
    process {
        # Check if Job parameter is bound with null, empty, or whitespace-only values
        if (Test-Bound 'Job') {
            if ($null -eq $Job -or $Job.Count -eq 0 -or ($Job | Where-Object { [string]::IsNullOrWhiteSpace($_) })) {
                Write-Message -Level Verbose -Message "The -Job parameter was explicitly provided but contains null, empty, or whitespace-only values. This may indicate an uninitialized variable. Skipping operation."
                return
            }
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($j in $Job) {
                if ($Server.JobServer.Jobs.Name -notcontains $j) {
                    Stop-Function -Message "Job $j doesn't exist on $instance." -Continue -Target $instance -Category InvalidData
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
                    $server.JobServer.Jobs.Refresh()
                    Remove-TeppCacheItem -SqlInstance $server -Type job -Name $currentJob.Name
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Name         = $currentJob.Name
                        Status       = 'Dropped'
                    }
                } catch {
                    Write-Message -Level Verbose -Message "Could not drop job $job on $server"

                    [PSCustomObject]@{
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