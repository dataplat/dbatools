function Get-DbaAgentJob {
    <#
    .SYNOPSIS
        Retrieves SQL Server Agent job details and execution status from one or more instances.

    .DESCRIPTION
        Retrieves detailed information about SQL Server Agent jobs including their configuration, status, schedules, and execution history. This function connects to SQL instances and queries the msdb database to return job properties like owner, category, last run outcome, and current execution status. Use this to monitor job health across your environment, audit job configurations before deployments, or identify jobs associated with specific databases for maintenance planning.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Job
        The job(s) to process - this list is auto-populated from the server. If unspecified, all jobs will be processed.

    .PARAMETER ExcludeJob
        The job(s) to exclude - this list is auto-populated from the server.

    .PARAMETER ExcludeDisabledJobs
        Switch will exclude disabled jobs from the output.

    .PARAMETER Database
        Return jobs with T-SQL job steps associated with specific databases

    .PARAMETER Category
        Return jobs associated with specific category

    .PARAMETER ExcludeCategory
        Categories to exclude - jobs associated with these categories will not be returned.

    .PARAMETER IncludeExecution
        Include Execution details if the job is currently running

    .PARAMETER Type
        The type of job: MultiServer or Local. Defaults to both MultiServer and Local.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Job
        Author: Garry Bargsley (@gbargsley), blog.garrybargsley.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgentJob

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance localhost

        Returns all SQL Agent Jobs on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance localhost, sql2016

        Returns all SQl Agent Jobs for the local and sql2016 SQL Server instances

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance localhost -Job BackupData, BackupDiff

        Returns all SQL Agent Jobs named BackupData and BackupDiff from the local SQL Server instance.

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance localhost -ExcludeJob BackupDiff

        Returns all SQl Agent Jobs for the local SQL Server instances, except the BackupDiff Job.

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance localhost -ExcludeDisabledJobs

        Returns all SQl Agent Jobs for the local SQL Server instances, excluding the disabled jobs.

    .EXAMPLE
        PS C:\> $servers | Get-DbaAgentJob | Out-GridView -PassThru | Start-DbaAgentJob -WhatIf

        Find all of your Jobs from SQL Server instances in the $servers collection, select the jobs you want to start then see jobs would start if you ran Start-DbaAgentJob

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance sqlserver2014a | Where-Object Category -eq "Report Server" | Export-DbaScript -Path "C:\temp\sqlserver2014a_SSRSJobs.sql"

        Exports all SSRS jobs from SQL instance sqlserver2014a to a file.

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance sqlserver2014a -Database msdb

        Finds all jobs on sqlserver2014a that T-SQL job steps associated with msdb database
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Job,
        [string[]]$ExcludeJob,
        [string[]]$Database,
        [string[]]$Category,
        [string[]]$ExcludeCategory,
        [switch]$ExcludeDisabledJobs,
        [switch]$IncludeExecution,
        [ValidateSet("MultiServer", "Local")]
        [string[]]$Type = @("MultiServer", "Local"),
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (Test-Bound 'IncludeExecution') {
                $query = "SELECT [job].[job_id] as [JobId], [activity].[start_execution_date] AS [StartDate]
                FROM [msdb].[dbo].[sysjobs_view] as [job]
                    INNER JOIN [msdb].[dbo].[sysjobactivity] AS [activity] ON [job].[job_id] = [activity].[job_id]
                WHERE [activity].[run_requested_date] IS NOT NULL
                    AND [activity].[start_execution_date] IS NOT NULL
                    AND [activity].[stop_execution_date] IS NULL;"

                $jobExecutionResults = $server.Query($query)
            }

            $jobs = $server.JobServer.Jobs | Where-Object JobType -in $Type

            if ($Job) {
                $jobs = $jobs | Where-Object Name -In $Job
            }
            if ($ExcludeJob) {
                $jobs = $jobs | Where-Object Name -NotIn $ExcludeJob
            }
            if ($ExcludeDisabledJobs) {
                $jobs = $Jobs | Where-Object IsEnabled -eq $true
            }
            if ($Database) {
                $jobs = $jobs | Where-Object { $_.JobSteps | Where-Object DatabaseName -in $Database }
            }
            if ($Category) {
                $jobs = $jobs | Where-Object Category -in $Category
            }
            if ($ExcludeCategory) {
                $jobs = $jobs | Where-Object Category -notin $ExcludeCategory
            }

            foreach ($agentJob in $jobs) {
                $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Name', 'Category', 'OwnerLoginName', 'CurrentRunStatus', 'CurrentRunRetryAttempt', 'IsEnabled as Enabled', 'LastRunDate', 'LastRunOutcome', 'HasSchedule', 'OperatorToEmail', 'DateCreated as CreateDate'

                $currentJobId = $agentJob.JobId
                if ($currentJobId -in $jobExecutionResults.JobId) {
                    $agentJobStartDate = [DbaDateTime]($jobExecutionResults | Where-Object JobId -eq $currentJobId | Sort-Object StartDate -Descending | Select-Object -First 1).StartDate

                    Add-Member -Force -InputObject $agentJob -MemberType NoteProperty -Name StartDate -Value $agentJobStartDate
                    $defaults += 'StartDate'
                }

                Add-Member -Force -InputObject $agentJob -MemberType NoteProperty -Name ComputerName -value $agentJob.Parent.Parent.ComputerName
                Add-Member -Force -InputObject $agentJob -MemberType NoteProperty -Name InstanceName -value $agentJob.Parent.Parent.ServiceName
                Add-Member -Force -InputObject $agentJob -MemberType NoteProperty -Name SqlInstance -value $agentJob.Parent.Parent.DomainInstanceName

                Select-DefaultView -InputObject $agentJob -Property $defaults
            }
        }
    }
}