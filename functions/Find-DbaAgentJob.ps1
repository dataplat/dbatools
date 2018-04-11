function Find-DbaAgentJob {
    <#
        .SYNOPSIS
            Find-DbaAgentJob finds agent job/s that fit certain search filters.

        .DESCRIPTION
            This command filters SQL Agent jobs giving the DBA a list of jobs that may need attention or could possibly be options for removal.

        .PARAMETER SqlInstance
            The SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.

        .PARAMETER JobName
            Filter agent jobs to only the name(s) you list.
            Supports regular expression (e.g. MyJob*) being passed in.

        .PARAMETER ExcludeJobName
            Allows you to enter an array of agent job names to ignore

        .PARAMETER StepName
            Filter based on StepName.
            Supports regular expression (e.g. MyJob*) being passed in.

        .PARAMETER LastUsed
            Find all jobs that havent ran in the INT number of previous day(s)

        .PARAMETER IsDisabled
            Find all jobs that are disabled

        .PARAMETER IsFailed
            Find all jobs that have failed

        .PARAMETER IsNotScheduled
            Find all jobs with no schedule assigned

        .PARAMETER IsNoEmailNotification
            Find all jobs without email notification configured

        .PARAMETER Category
            Filter based on agent job categories

        .PARAMETER Owner
            Filter based on owner of the job/s

        .PARAMETER Since
            Datetime object used to narrow the results to a date

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Agent, Job
            Author: Stephen Bennett (https://sqlnotesfromtheunderground.wordpress.com/)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Find-DbaAgentJob

        .EXAMPLE
            Find-DbaAgentJob -SqlInstance Dev01 -JobName backup*

            Returns all agent job(s) that have backup in the name

        .EXAMPLE
            Find-DbaAgentJob -SqlInstance Dev01, Dev02 -JobName Mybackup

            Returns all agent job(s) that are named exactly Mybackup

        .EXAMPLE
            Find-DbaAgentJob -SqlInstance Dev01 -LastUsed 10

            Returns all agent job(s) that have not ran in 10 days

        .EXAMPLE
            Find-DbaAgentJob -SqlInstance Dev01 -IsDisabled -IsNoEmailNotification -IsNotScheduled

            Returns all agent job(s) that are either disabled, have no email notification or don't have a schedule. returned with detail

        .EXAMPLE
            $servers | Find-DbaAgentJob -IsFailed | Start-DbaAgentJob

            Finds all failed job then starts them. Consider using a -WhatIf at the end of Start-DbaAgentJob to see what it'll do first

        .EXAMPLE
            Find-DbaAgentJob -SqlInstance Dev01 -LastUsed 10 -Exclude "Yearly - RollUp Workload", "SMS - Notification"

            Returns all agent jobs that havent ran in the last 10 ignoring jobs "Yearly - RollUp Workload" and "SMS - Notification"

        .EXAMPLE
            Find-DbaAgentJob -SqlInstance Dev01 -Category "REPL-Distribution", "REPL-Snapshot" -Detailed | Format-Table -AutoSize -Wrap

            Returns all job/s on Dev01 that are in either category "REPL-Distribution" or "REPL-Snapshot" with detailed output

        .EXAMPLE
            Find-DbaAgentJob -SqlInstance Dev01, Dev02 -IsFailed -Since '7/1/2016 10:47:00'

            Returns all agent job(s) that have failed since July of 2016 (and still have history in msdb)

        .EXAMPLE
            Get-DbaRegisteredServer -SqlInstance CMSServer -Group Production | Find-DbaAgentJob -Disabled -IsNotScheduled | Format-Table -AutoSize -Wrap

            Queries CMS server to return all SQL instances in the Production folder and then list out all agent jobs that have either been disabled or have no schedule.
    #>
    [CmdletBinding()]
    Param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer", "SqlServers")]
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
        [Alias('Silent')]
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
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $jobs = $server.JobServer.jobs
            $output = @()

            if ($IsFailed) {
                Write-Message -Level Verbose -Message "Checking for failed jobs."
                $output += $jobs | Where-Object LastRunOutcome -eq "Failed"
            }

            if ($JobName) {
                Write-Message -Level Verbose -Message "Retrieving jobs by their name."
                $output += Get-JobList -SqlInstance $server -JobFilter $JobName
            }

            if ($StepName) {
                Write-Message -Level Verbose -Message "Retrieving jobs by their step names."
                $output += Get-JobList -SqlInstance $server -StepFilter $StepName
            }

            if ($LastUsed) {
                $DaysBack = $LastUsed * -1
                $SinceDate = (Get-date).AddDays($DaysBack)
                Write-Message -Level Verbose -Message "Finding job/s not ran in last $LastUsed days"
                $output += $jobs | Where-Object { $_.LastRunDate -le $SinceDate }
            }

            if ($IsDisabled) {
                Write-Message -Level Verbose -Message "Finding job/s that are disabled"
                $output += $jobs | Where-Object IsEnabled -eq $false
            }

            if ($IsNotScheduled) {
                Write-Message -Level Verbose -Message "Finding job/s that have no schedule defined"
                $output += $jobs | Where-Object HasSchedule -eq $false
            }
            if ($IsNoEmailNotification) {
                Write-Message -Level Verbose -Message "Finding job/s that have no email operator defined"
                $output += $jobs | Where-Object { [string]::IsNullOrEmpty($_.OperatorToEmail) -eq $true }
            }

            if ($Category) {
                Write-Message -Level Verbose -Message "Finding job/s that have the specified category defined"
                $output += $jobs | Where-Object { $Category -contains $_.Category }
            }

            if ($Owner) {
                Write-Message -Level Verbose -Message "Finding job/s with owner critera"
                if ($Owner -match "-") {
                    $OwnerMatch = $Owner -replace "-", ""
                    Write-Message -Level Verbose -Message "Checking for jobs that NOT owned by: $OwnerMatch"
                    $output += $server.JobServer.jobs | Where-Object { $OwnerMatch -notcontains $_.OwnerLoginName }
                }
                else {
                    Write-Message -Level Verbose -Message "Checking for jobs that are owned by: $owner"
                    $output += $server.JobServer.jobs | Where-Object { $Owner -contains $_.OwnerLoginName }
                }
            }

            if ($Exclude) {
                Write-Message -Level Verbose -Message "Excluding job/s based on Exclude"
                $output = $output | Where-Object { $Exclude -notcontains $_.Name }
            }

            if ($Since) {
                #$Since = $Since.ToString("yyyy-MM-dd HH:mm:ss")
                Write-Message -Level Verbose -Message "Getting only jobs whose LastRunDate is greater than or equal to $since"
                $output = $output | Where-Object { $_.LastRunDate -ge $since }
            }

            $jobs = $output | Select-Object -Unique

            foreach ($job in $jobs) {
                Add-Member -Force -InputObject $job -MemberType NoteProperty -Name ComputerName -value $server.NetName
                Add-Member -Force -InputObject $job -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $job -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                Add-Member -Force -InputObject $job -MemberType NoteProperty -Name JobName -value $job.Name


                Select-DefaultView -InputObject $job -Property ComputerName, InstanceName, SqlInstance, Name, Category, OwnerLoginName, CurrentRunStatus, CurrentRunRetryAttempt, 'IsEnabled as Enabled', LastRunDate, LastRunOutcome, DateCreated, HasSchedule, OperatorToEmail, 'DateCreated as CreateDate'
            }
        }
    }
}
