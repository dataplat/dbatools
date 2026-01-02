function Get-DbaAgentJobStep {
    <#
    .SYNOPSIS
        Retrieves detailed SQL Agent job step information including execution status and configuration from SQL Server instances.

    .DESCRIPTION
        Collects comprehensive details about SQL Agent job steps across one or more SQL Server instances. Returns information about each step's subsystem type, last execution date, outcome, and current state, which is essential for monitoring job performance and troubleshooting failed automation tasks. You can filter results by specific jobs, exclude disabled jobs, or process job objects from Get-DbaAgentJob to focus on particular maintenance routines or scheduled processes.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        Specifies which SQL Agent jobs to include by name when retrieving job steps. Accepts wildcards for pattern matching.
        Use this when you need to examine steps for specific jobs like backup routines or maintenance tasks instead of processing all jobs on the instance.

    .PARAMETER ExcludeJob
        Specifies which SQL Agent jobs to exclude by name when retrieving job steps. Accepts wildcards for pattern matching.
        Use this when you want to review most jobs but skip certain ones like test jobs or jobs that generate excessive output.

    .PARAMETER ExcludeDisabledJobs
        Filters out disabled SQL Agent jobs from the results, showing only currently active jobs.
        Use this when troubleshooting production issues or monitoring active automation to avoid reviewing steps from jobs that aren't currently running.

    .PARAMETER InputObject
        Accepts SQL Agent job objects from the pipeline, typically from Get-DbaAgentJob output.
        Use this when you want to process job steps for a pre-filtered set of jobs or when building complex pipelines that combine job filtering with step analysis.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Job
        Author: Klaas Vandenberghe (@PowerDbaKlaas), powerdba.eu

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgentJobStep

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Agent.JobStep

        Returns one SQL Agent Job Step object per step within each specified job. Each object represents a discrete step within a SQL Server Agent job with its configuration and execution details.

        Default display properties (via Select-DefaultView):
        - ComputerName: The name of the SQL Server computer where the step is located
        - InstanceName: The name of the SQL Server instance
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - AgentJob: The name of the parent SQL Agent job containing this step
        - Name: The name of the job step
        - SubSystem: The subsystem type for the step (TransactSql, PowerShell, CmdExec, AnalysisCommand, AnalysisQuery, Ssis, etc.)
        - LastRunDate: DateTime of the last execution of this step
        - LastRunOutcome: Outcome of the last execution (Succeeded, Failed, Retry, Cancelled, Unknown, etc.)
        - State: Current state of the step (Enabled, Disabled, etc.)

        Additional properties available from the SMO JobStep object (accessible via Select-Object *):
        - ID: Internal step ID number
        - CreateDate: DateTime when the step was created
        - DateLastModified: DateTime when the step was last modified
        - Command: The command or script to execute for this step
        - CommandExecutionSuccessCode: Exit code indicating success (0 for success by default)
        - DatabaseName: Database context for the step execution
        - DatabaseUserName: User context for step execution
        - Description: Step description/notes
        - IncludeStepOutput: Boolean indicating if step output is included in job history
        - IsLastStep: Boolean indicating if this is the last step in the job
        - LogToTable: Boolean indicating if output is logged to a table
        - OutputFileName: File path for step output logging
        - ProxyID: ID of the proxy account used for this step
        - RetryAttempts: Number of retry attempts if the step fails
        - RetryInterval: Interval in minutes between retry attempts

        Note: The ComputerName, InstanceName, SqlInstance, and AgentJob properties are added by the function and are not native SMO properties.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobStep -SqlInstance localhost

        Returns all SQL Agent Job Steps on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaAgentJobStep -SqlInstance localhost, sql2016

        Returns all SQL Agent Job Steps for the local and sql2016 SQL Server instances

    .EXAMPLE
        PS C:\> Get-DbaAgentJobStep -SqlInstance localhost -Job BackupData, BackupDiff

        Returns all SQL Agent Job Steps for the jobs named BackupData and BackupDiff from the local SQL Server instance.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobStep -SqlInstance localhost -ExcludeJob BackupDiff

        Returns all SQL Agent Job Steps for the local SQL Server instances, except for the BackupDiff Job.

    .EXAMPLE
        PS C:\> Get-DbaAgentJobStep -SqlInstance localhost -ExcludeDisabledJobs

        Returns all SQL Agent Job Steps for the local SQL Server instances, excluding the disabled jobs.

    .EXAMPLE
        PS C:\> $servers | Get-DbaAgentJobStep

        Find all of your Job Steps from SQL Server instances in the $servers collection

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Job,
        [string[]]$ExcludeJob,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.Job[]]$InputObject,
        [switch]$ExcludeDisabledJobs,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            Write-Message -Level Verbose -Message "Collecting jobs on $instance"
            $InputObject += $server.JobServer.Jobs
        }
    }
    end {
        if ($Job) {
            $InputObject = $InputObject | Where-Object Name -In $Job
        }
        if ($ExcludeJob) {
            $InputObject = $InputObject | Where-Object Name -NotIn $ExcludeJob
        }
        if ($ExcludeDisabledJobs) {
            $InputObject = $InputObject | Where-Object IsEnabled -eq $true
        }
        Write-Message -Level Verbose -Message "Collecting job steps on ($server.Name)"
        foreach ($agentJobStep in $InputObject.jobsteps) {
            Add-Member -Force -InputObject $agentJobStep -MemberType NoteProperty -Name ComputerName -value $agentJobStep.Parent.Parent.Parent.ComputerName
            Add-Member -Force -InputObject $agentJobStep -MemberType NoteProperty -Name InstanceName -value $agentJobStep.Parent.Parent.Parent.ServiceName
            Add-Member -Force -InputObject $agentJobStep -MemberType NoteProperty -Name SqlInstance -value $agentJobStep.Parent.Parent.Parent.DomainInstanceName
            Add-Member -Force -InputObject $agentJobStep -MemberType NoteProperty -Name AgentJob -value $agentJobStep.Parent.Name

            Select-DefaultView -InputObject $agentJobStep -Property ComputerName, InstanceName, SqlInstance, AgentJob, Name, SubSystem, LastRunDate, LastRunOutcome, State
        }
    }
}