function Get-DbaAgentJob {
    <#
    .SYNOPSIS
        Gets SQL Agent Job information for each instance(s) of SQL Server.

    .DESCRIPTION
        The Get-DbaAgentJob returns connected SMO object for SQL Agent Job information for each instance(s) of SQL Server.

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

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Job, Agent
        Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com

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
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $jobs = $server.JobServer.Jobs

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
                Add-Member -Force -InputObject $agentJob -MemberType NoteProperty -Name ComputerName -value $agentJob.Parent.Parent.ComputerName
                Add-Member -Force -InputObject $agentJob -MemberType NoteProperty -Name InstanceName -value $agentJob.Parent.Parent.ServiceName
                Add-Member -Force -InputObject $agentJob -MemberType NoteProperty -Name SqlInstance -value $agentJob.Parent.Parent.DomainInstanceName

                Select-DefaultView -InputObject $agentJob -Property ComputerName, InstanceName, SqlInstance, Name, Category, OwnerLoginName, CurrentRunStatus, CurrentRunRetryAttempt, 'IsEnabled as Enabled', LastRunDate, LastRunOutcome, HasSchedule, OperatorToEmail, 'DateCreated as CreateDate'
            }
        }
    }
}
