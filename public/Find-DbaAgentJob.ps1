function Find-DbaAgentJob {
    <#
    .SYNOPSIS
        Searches and filters SQL Agent jobs across SQL Server instances using multiple criteria.

    .DESCRIPTION
        Searches SQL Agent jobs across one or more SQL Server instances using various filter criteria including job name, step name, execution status, schedule status, and notification settings. Helps DBAs identify problematic jobs that have failed, haven't run recently, are disabled, lack schedules, or missing email notifications. Useful for maintenance audits, troubleshooting job issues, and identifying cleanup candidates in environments with many automated processes.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER JobName
        Specifies agent job names to search for using exact matches or wildcard patterns.
        Supports wildcards like *backup*, MyJob*, or *ETL* to find jobs with specific naming conventions.
        Useful when you need to focus on particular job types or troubleshoot specific processes.

    .PARAMETER ExcludeJobName
        Excludes specific job names from the search results using exact name matches.
        Use this to filter out known good jobs when searching for problematic ones, like excluding maintenance jobs when looking for failed application jobs.

    .PARAMETER StepName
        Searches for jobs containing steps with specific names or patterns.
        Supports wildcards to find jobs with steps like *backup*, *index*, or *cleanup*.
        Helpful when troubleshooting issues in multi-step jobs or finding jobs that perform specific operations.

    .PARAMETER LastUsed
        Finds jobs that haven't executed successfully in the specified number of days.
        Use this to identify stale or potentially broken jobs that may need attention.
        Common values are 7, 30, or 90 days depending on job frequency and business requirements.

    .PARAMETER IsDisabled
        Finds all jobs with disabled status (not scheduled to run automatically).
        Use this during maintenance windows to identify jobs that were disabled for troubleshooting or may have been forgotten after maintenance.

    .PARAMETER IsFailed
        Finds jobs where the last execution resulted in a failure status.
        Essential for daily health checks and identifying jobs that need immediate attention.
        Combine with Since parameter to focus on recent failures or look at historical patterns.

    .PARAMETER IsNotScheduled
        Finds jobs that exist but have no schedule defined (manual execution only).
        Useful for identifying orphaned jobs, temporary jobs that should be cleaned up, or jobs awaiting proper scheduling configuration.

    .PARAMETER IsNoEmailNotification
        Finds jobs that lack email notification setup for failures or completion.
        Important for ensuring critical jobs will alert DBAs when they fail.
        Use this during compliance audits or when establishing monitoring standards.

    .PARAMETER Category
        Filters jobs by their assigned categories such as 'Database Maintenance', 'REPL-Distribution', or custom categories.
        Useful for focusing on specific types of jobs like replication jobs, maintenance tasks, or application-specific processes.
        Categories help organize and manage jobs in environments with many different job types.

    .PARAMETER Owner
        Filters jobs by their owner login name, or excludes jobs by prefixing with a dash (-).
        Use 'DOMAIN\\User' to find jobs owned by specific accounts, or '-sa' to exclude sa-owned jobs.
        Helpful for security audits, identifying jobs that may need ownership changes, or finding jobs created by specific users.

    .PARAMETER Since
        Limits results to jobs that last ran on or after the specified date and time.
        Use with IsFailed to find jobs that failed since a specific incident, or combine with other filters to focus on recent activity.
        Accepts standard datetime formats like '2023-01-01' or '2023-01-01 14:30:00'.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Job

        Returns one Job object for each job that matches the specified search criteria. Multiple jobs can be returned per instance depending on filter parameters.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: Job name
        - Category: Job category classification
        - OwnerLoginName: Login name of the job owner
        - CurrentRunStatus: Current execution status (Idle, Running, etc.)
        - CurrentRunRetryAttempt: Number of retry attempts for current execution
        - Enabled: Boolean indicating if the job is enabled (aliased from IsEnabled)
        - LastRunDate: DateTime of the most recent job execution
        - LastRunOutcome: Outcome of the last execution (Succeeded, Failed, Cancelled, etc.)
        - DateCreated: DateTime when the job was created
        - HasSchedule: Boolean indicating if the job has a schedule assigned
        - OperatorToEmail: Email operator name for notifications
        - CreateDate: DateTime when the job was created (aliased from DateCreated)

        Additional properties available (from SMO Job object):
        - JobId: Unique identifier for the job (GUID)
        - IsEnabled: Boolean indicating if the job is enabled and can be scheduled
        - JobType: Type of job (Local or MultiServer)
        - Category: Job category name
        - CategoryID: Numeric category identifier
        - Owner: Job owner name
        - OwnerLoginName: Login name of the job owner
        - Description: Job description text
        - StartStepID: ID of the first step to execute
        - EventLogLevel: Event log level for job events (OnSuccess, OnFailure, Always, Never)
        - EmailLevel: Email notification level (OnSuccess, OnFailure, OnCompletion, Never)
        - NetsendLevel: NetSend notification level (OnSuccess, OnFailure, OnCompletion, Never)
        - PageLevel: Pager notification level (OnSuccess, OnFailure, OnCompletion, Never)
        - OperatorToNetSend: Operator name for NetSend notifications
        - OperatorToPage: Operator name for pager notifications
        - LastRunDuration: Duration of last run in seconds
        - NextRunDate: DateTime when the job is scheduled to run next
        - DateModified: DateTime when the job was last modified
        - HasSchedule: Boolean indicating if the job has a schedule
        - IsRunnable: Boolean indicating if the job can be executed
        - Parent: Reference to parent JobServer SMO object

        All properties from the base SMO Job object are accessible even though only default properties are displayed without using Select-Object *.

    .NOTES
        Tags: Agent, Job, Lookup
        Author: Stephen Bennett, sqlnotesfromtheunderground.wordpress.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaAgentJob

    .EXAMPLE
        PS C:\> Find-DbaAgentJob -SqlInstance Dev01 -JobName *backup*

        Returns all agent job(s) that have backup in the name

    .EXAMPLE
        PS C:\> Find-DbaAgentJob -SqlInstance Dev01, Dev02 -JobName Mybackup

        Returns all agent job(s) that are named exactly Mybackup

    .EXAMPLE
        PS C:\> Find-DbaAgentJob -SqlInstance Dev01 -LastUsed 10

        Returns all agent job(s) that have not ran in 10 days

    .EXAMPLE
        PS C:\> Find-DbaAgentJob -SqlInstance Dev01 -IsDisabled -IsNoEmailNotification -IsNotScheduled

        Returns all agent job(s) that are either disabled, have no email notification or don't have a schedule. returned with detail

    .EXAMPLE
        PS C:\> $servers | Find-DbaAgentJob -IsFailed | Start-DbaAgentJob

        Finds all failed job then starts them. Consider using a -WhatIf at the end of Start-DbaAgentJob to see what it'll do first

    .EXAMPLE
        PS C:\> Find-DbaAgentJob -SqlInstance Dev01 -LastUsed 10 -ExcludeJobName "Yearly - RollUp Workload", "SMS - Notification"

        Returns all agent jobs that have not ran in the last 10 days ignoring jobs "Yearly - RollUp Workload" and "SMS - Notification"

    .EXAMPLE
        PS C:\> Find-DbaAgentJob -SqlInstance Dev01 -Category "REPL-Distribution", "REPL-Snapshot" | Format-Table -AutoSize -Wrap

        Returns all job/s on Dev01 that are in either category "REPL-Distribution" or "REPL-Snapshot"

    .EXAMPLE
        PS C:\> Find-DbaAgentJob -SqlInstance Dev01, Dev02 -IsFailed -Since '2016-07-01 10:47:00'

        Returns all agent job(s) on Dev01 and Dev02 that have failed since July of 2016 (and still have history in msdb)

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance CMSServer -Group Production | Find-DbaAgentJob -Disabled -IsNotScheduled | Format-Table -AutoSize -Wrap

        Queries CMS server to return all SQL instances in the Production folder and then list out all agent jobs that have either been disabled or have no schedule.

    .EXAMPLE
        $Instances = 'SQL2017N5','SQL2019N5','SQL2019N20','SQL2019N21','SQL2019N22'
        Find-DbaAgentJob -SqlInstance $Instances -JobName *backup* -IsNotScheduled

        Returns all agent job(s) wiht backup in the name, that don't have a schedule on 'SQL2017N5','SQL2019N5','SQL2019N20','SQL2019N21','SQL2019N22'
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [Alias("Name")]
        [string[]]$JobName,
        [string[]]$ExcludeJobName,
        [string[]]$StepName,
        [int]$LastUsed,
        [Alias("Disabled")]
        [switch]$IsDisabled,
        [Alias("Failed")]
        [switch]$IsFailed,
        [Alias("NoSchedule")]
        [switch]$IsNotScheduled,
        [Alias("NoEmailNotification")]
        [switch]$IsNoEmailNotification,
        [string[]]$Category,
        [string]$Owner,
        [datetime]$Since,
        [switch]$EnableException
    )
    begin {
        if ($IsFailed, [boolean]$JobName, [boolean]$StepName, [boolean]$LastUsed.ToString(), $IsDisabled, $IsNotScheduled, $IsNoEmailNotification, [boolean]$Category, [boolean]$Owner, [boolean]$ExcludeJobName -notcontains $true) {
            Stop-Function -Message "At least one search term must be specified"
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Running Scan on: $instance"

            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $output = @()

            if ($JobName) {
                Write-Message -Level Verbose -Message "Retrieving jobs by their name."
                $jobs = Get-JobList -SqlInstance $server -JobFilter $JobName
                $output = $jobs
            }

            if ($StepName) {
                Write-Message -Level Verbose -Message "Retrieving jobs by their step names."
                $jobs = Get-JobList -SqlInstance $server -StepFilter $StepName
                $output = $jobs
            }

            if ( -not ($JobName -or $StepName)) {
                Write-Message -Level Verbose -Message "Retrieving all jobs"
                $jobs = Get-JobList -SqlInstance $server
                $output = $jobs
            }

            if ($Category) {
                Write-Message -Level Verbose -Message "Finding job/s that have the specified category defined"
                $output = $jobs | Where-Object { $Category -contains $_.Category }
            }

            if ($IsFailed) {
                Write-Message -Level Verbose -Message "Checking for failed jobs."
                $output = $jobs | Where-Object LastRunOutcome -eq "Failed"
            }

            if ($LastUsed) {
                $DaysBack = $LastUsed * -1
                $SinceDate = (Get-Date).AddDays($DaysBack)
                Write-Message -Level Verbose -Message "Finding job/s not ran in last $LastUsed days"
                $output = $jobs | Where-Object { $_.LastRunDate -le $SinceDate }
            }

            if ($IsDisabled) {
                Write-Message -Level Verbose -Message "Finding job/s that are disabled"
                $output = $jobs | Where-Object IsEnabled -eq $false
            }

            if ($IsNotScheduled) {
                Write-Message -Level Verbose -Message "Finding job/s that have no schedule defined"
                $output = $jobs | Where-Object HasSchedule -eq $false
            }
            if ($IsNoEmailNotification) {
                Write-Message -Level Verbose -Message "Finding job/s that have no email operator defined"
                $output = $jobs | Where-Object { [string]::IsNullOrEmpty($_.OperatorToEmail) -eq $true }
            }

            if ($Owner) {
                Write-Message -Level Verbose -Message "Finding job/s with owner critera"
                if ($Owner -match "-") {
                    $OwnerMatch = $Owner -replace "-", ""
                    Write-Message -Level Verbose -Message "Checking for jobs that NOT owned by: $OwnerMatch"
                    $output = $jobs | Where-Object { $OwnerMatch -notcontains $_.OwnerLoginName }
                } else {
                    Write-Message -Level Verbose -Message "Checking for jobs that are owned by: $owner"
                    $output = $jobs | Where-Object { $Owner -contains $_.OwnerLoginName }
                }
            }

            if ($ExcludeJobName) {
                Write-Message -Level Verbose -Message "Excluding job/s based on Exclude"
                $output = $output | Where-Object { $ExcludeJobName -notcontains $_.Name }
            }

            if ($Since) {
                #$Since = $Since.ToString("yyyy-MM-dd HH:mm:ss")
                Write-Message -Level Verbose -Message "Getting only jobs whose LastRunDate is greater than or equal to $since"
                $output = $output | Where-Object { $_.LastRunDate -ge $since }
            }

            $jobs = $output | Select-Object -Unique

            foreach ($job in $jobs) {
                Add-Member -Force -InputObject $job -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                Add-Member -Force -InputObject $job -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $job -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                Add-Member -Force -InputObject $job -MemberType NoteProperty -Name JobName -value $job.Name


                Select-DefaultView -InputObject $job -Property ComputerName, InstanceName, SqlInstance, Name, Category, OwnerLoginName, CurrentRunStatus, CurrentRunRetryAttempt, 'IsEnabled as Enabled', LastRunDate, LastRunOutcome, DateCreated, HasSchedule, OperatorToEmail, 'DateCreated as CreateDate'
            }
        }
    }
}