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

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Agent.Job

        Returns one Job object for each SQL Server Agent job that is currently executing (not in Idle state).
        When no jobs are running, the command returns nothing.

        Default display properties (via Get-DbaAgentJob with Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - Name: The name of the Agent job
        - CurrentRunStatus: Current execution status (Executing, Idle, Suspended, etc.)
        - IsEnabled: Boolean indicating if the job is enabled
        - LastRunOutcome: Result of the most recent execution (Succeeded, Failed, Cancelled, etc.)
        - LastRunDate: DateTime of the most recent job execution
        - NextRunDate: DateTime scheduled for the next execution
        - Owner: The login that owns the job
        - CreateDate: DateTime when the job was created
        - Description: Text description of the job's purpose

        Additional properties available from the base SMO Agent.Job object via Select-Object *:
        - JobID: Unique identifier (GUID) for the job
        - EventLogLevel: Logging level for event log (Never, OnSuccess, OnFailure, Always)
        - EmailLevel: Email notification level (Never, OnSuccess, OnFailure, Always)
        - NetSendLevel: Network send notification level (Never, OnSuccess, OnFailure, Always)
        - NetsendOperatorName: Name of operator for network send notifications
        - EmailOperatorName: Name of operator for email notifications
        - OperatorToNetSend: Operator configured for network send notifications
        - StartStepID: Step number where execution begins
        - Category: The category/classification of the job
        - DeleteLevel: When to delete job history (Never, OnSuccess, OnFailure, Always)
        - TargetServers: Collection of target servers for multi-server jobs
        - HasSchedule: Boolean indicating if the job has any schedules assigned

        All properties from the base SMO Agent.Job object are accessible using Select-Object *.

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