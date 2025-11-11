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
        Specifies specific SQL Agent job names to retrieve. Accepts an array of job names for targeting multiple jobs.
        Use this when you need to check status or configuration of specific jobs instead of retrieving all jobs on the instance.

    .PARAMETER ExcludeJob
        Excludes specific SQL Agent job names from the results. Accepts an array of job names to skip.
        Useful when you want most jobs except for specific ones like test jobs or jobs you're not responsible for managing.

    .PARAMETER ExcludeDisabledJobs
        Excludes disabled SQL Agent jobs from the results, showing only enabled jobs.
        Use this when focusing on active job monitoring or troubleshooting since disabled jobs won't execute.

    .PARAMETER Database
        Filters jobs to only those containing T-SQL job steps that target specific databases.
        Essential for database-specific maintenance planning or identifying which jobs will be affected by database operations like restores or migrations.

    .PARAMETER Category
        Filters jobs by their assigned category such as 'Database Maintenance', 'Report Server', or custom categories.
        Helpful for organizing job management tasks by functional area or finding jobs related to specific SQL Server features.

    .PARAMETER ExcludeCategory
        Excludes jobs from specific categories from the results. Accepts an array of category names.
        Use this to filter out jobs you don't manage, such as third-party application jobs or SSRS jobs when focusing on database maintenance.

    .PARAMETER IncludeExecution
        Adds execution start date information for currently running jobs to the output.
        Essential for troubleshooting long-running jobs or monitoring active job execution in real-time.

    .PARAMETER Type
        Specifies whether to return Local jobs, MultiServer jobs, or both. Local jobs run only on the current instance while MultiServer jobs are managed centrally.
        Use 'Local' when managing single-instance environments or 'MultiServer' when working with SQL Server multi-server administration setups.

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
                $query = "SELECT [job].[job_id] AS [JobId], [activity].[start_execution_date] AS [StartDate]
                FROM [msdb].[dbo].[sysjobs_view] AS [job]
                    INNER JOIN [msdb].[dbo].[sysjobactivity] AS [activity] ON [job].[job_id] = [activity].[job_id]
                WHERE [activity].[run_requested_date] IS NOT NULL
                    AND [activity].[start_execution_date] IS NOT NULL
                    AND [activity].[stop_execution_date] IS NULL;"

                $jobExecutionResults = $server.Query($query)
            }

            # Check if Job parameter is bound with null, empty, or whitespace-only values
            if (Test-Bound 'Job') {
                # Filter out any null/empty/whitespace values
                $Job = $Job | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

                # If all values were null/empty/whitespace, skip processing
                if ($null -eq $Job -or $Job.Count -eq 0) {
                    Write-Message -Level Verbose -Message "The -Job parameter was explicitly provided but contains only null, empty, or whitespace values. No jobs will be returned."
                    continue
                }
            }

            # Check if ExcludeJob parameter is bound with null, empty, or whitespace-only values
            if (Test-Bound 'ExcludeJob') {
                # Filter out any null/empty/whitespace values
                $ExcludeJob = $ExcludeJob | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

                # If all values were null/empty/whitespace, ignore the parameter
                if ($null -eq $ExcludeJob -or $ExcludeJob.Count -eq 0) {
                    Write-Message -Level Verbose -Message "The -ExcludeJob parameter was explicitly provided but contains only null, empty, or whitespace values. Parameter will be ignored."
                    $ExcludeJob = $null
                }
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
                $dbLookup = @{}
                foreach ($db in $Database) {
                    $dbLookup[$db] = $true
                }

                $jobs = $jobs | Where-Object {
                    foreach ($step in $_.JobSteps) {
                        if ($dbLookup.ContainsKey($step.DatabaseName)) {
                            return $true
                        }
                    }
                    return $false
                }
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