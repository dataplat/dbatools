function Get-DbaRunningJob {
    <#
    .SYNOPSIS
        Retrieves SQL Server Agent jobs that are currently executing

    .DESCRIPTION
        This function returns SQL Server Agent jobs that are actively running at the moment you call it, filtering out any jobs in idle state.
        Use this to monitor job execution during maintenance windows, troubleshoot performance issues by identifying resource-consuming jobs, or verify that no jobs are running before performing maintenance operations.
        The function refreshes job status information to provide real-time execution details rather than cached data.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Accepts SQL Server Agent job objects piped from Get-DbaAgentJob for filtering to only running jobs.
        Use this when you need to check execution status on a specific set of jobs rather than all jobs on an instance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Job
        Author: Stephen Bennett, sqlnotesfromtheunderground.wordpress.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaRunningJob

    .EXAMPLE
        PS C:\> Get-DbaRunningJob -SqlInstance sql2017

        Returns any active jobs on sql2017

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance sql2017, sql2019 | Get-DbaRunningJob

        Returns all active jobs on multiple instances piped into the function.

    .EXAMPLE
        PS C:\> $servers | Get-DbaRunningJob

        Returns all active jobs on multiple instances piped into the function.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.Job[]]$InputObject,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Refresh JobServer information (including childs) in case $instance is an smo to get up to date information.
            $server.JobServer.Jobs.Refresh($true)
            Get-DbaAgentJob -SqlInstance $server -IncludeExecution | Where-Object CurrentRunStatus -ne 'Idle'
        }
        foreach ($job in $InputObject) {
            # Refresh job to get up to date information.
            $job.Refresh()
            $job | Where-Object CurrentRunStatus -ne 'Idle'
        }
    }
}