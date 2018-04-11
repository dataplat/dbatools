#ValidationTags#Messaging#
function Get-DbaAgentJob {
    <#
        .SYNOPSIS
            Gets SQL Agent Job information for each instance(s) of SQL Server.

        .DESCRIPTION
            The Get-DbaAgentJob returns connected SMO object for SQL Agent Job information for each instance(s) of SQL Server.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Job
            The job(s) to process - this list is auto-populated from the server. If unspecified, all jobs will be processed.

        .PARAMETER ExcludeJob
            The job(s) to exclude - this list is auto-populated from the server.

        .PARAMETER NoDisabledJobs
            Switch will exclude disabled jobs from the output.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Job, Agent
            Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaAgentJob

        .EXAMPLE
            Get-DbaAgentJob -SqlInstance localhost

            Returns all SQL Agent Jobs on the local default SQL Server instance

        .EXAMPLE
            Get-DbaAgentJob -SqlInstance localhost, sql2016

            Returns all SQl Agent Jobs for the local and sql2016 SQL Server instances

        .EXAMPLE
            Get-DbaAgentJob -SqlInstance localhost -Job BackupData, BackupDiff

            Returns all SQL Agent Jobs named BackupData and BackupDiff from the local SQL Server instance.

        .EXAMPLE
            Get-DbaAgentJob -SqlInstance localhost -ExcludeJob BackupDiff

            Returns all SQl Agent Jobs for the local SQL Server instances, except the BackupDiff Job.

        .EXAMPLE
            Get-DbaAgentJob -SqlInstance localhost -NoDisabledJobs

            Returns all SQl Agent Jobs for the local SQL Server instances, excluding the disabled jobs.

        .EXAMPLE
            $servers | Get-DbaAgentJob | Out-GridView -Passthru | Start-DbaAgentJob -WhatIf

            Find all of your Jobs from servers in the $server collection, select the jobs you want to start then see jobs would start if you ran Start-DbaAgentJob
    #>
    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Job,
        [object[]]$ExcludeJob,
        [switch]$NoDisabledJobs,
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

            $jobs = $server.JobServer.Jobs

            if ($Job) {
                $jobs = $jobs | Where-Object Name -In $Job
            }
            if ($ExcludeJob) {
                $jobs = $jobs | Where-Object Name -NotIn $ExcludeJob
            }
            if ($NoDisabledJobs) {
                $jobs = $Jobs | Where-Object IsEnabled -eq $true
            }

            foreach ($agentJob in $jobs) {
                Add-Member -Force -InputObject $agentJob -MemberType NoteProperty -Name ComputerName -value $agentJob.Parent.Parent.NetName
                Add-Member -Force -InputObject $agentJob -MemberType NoteProperty -Name InstanceName -value $agentJob.Parent.Parent.ServiceName
                Add-Member -Force -InputObject $agentJob -MemberType NoteProperty -Name SqlInstance -value $agentJob.Parent.Parent.DomainInstanceName

                Select-DefaultView -InputObject $agentJob -Property ComputerName, InstanceName, SqlInstance, Name, Category, OwnerLoginName, CurrentRunStatus, CurrentRunRetryAttempt, 'IsEnabled as Enabled', LastRunDate, LastRunOutcome, DateCreated, HasSchedule, OperatorToEmail, 'DateCreated as CreateDate'
            }
        }
    }
}