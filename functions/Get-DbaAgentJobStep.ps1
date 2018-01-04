function Get-DbaAgentJobStep {
    <#
        .SYNOPSIS
            Gets SQL Agent Job Step information for each instance(s) of SQL Server.

        .DESCRIPTION
            The Get-DbaAgentJobStep returns connected SMO object for SQL Agent Job Step for each instance(s) of SQL Server.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            SqlCredential object to connect as. If not specified, current Windows login will be used.

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
            Author: Klaas Vandenberghe (@PowerDbaKlaas), http://powerdba.eu

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Get-DbaAgentJobStep

        .EXAMPLE
            Get-DbaAgentJobStep -SqlInstance localhost

            Returns all SQL Agent Job Steps on the local default SQL Server instance

        .EXAMPLE
            Get-DbaAgentJobStep -SqlInstance localhost, sql2016

            Returns all SQl Agent Job Steps for the local and sql2016 SQL Server instances

        .EXAMPLE
            Get-DbaAgentJobStep -SqlInstance localhost -Job BackupData, BackupDiff

            Returns all SQL Agent Job Steps for the jobs named BackupData and BackupDiff from the local SQL Server instance.

        .EXAMPLE
            Get-DbaAgentJobStep -SqlInstance localhost -ExcludeJob BackupDiff

            Returns all SQl Agent Job Steps for the local SQL Server instances, except for the BackupDiff Job.

        .EXAMPLE
            Get-DbaAgentJobStep -SqlInstance localhost -NoDisabledJobs

            Returns all SQl Agent Job Steps for the local SQL Server instances, excluding the disabled jobs.

        .EXAMPLE
            $servers | Get-DbaAgentJobStep

            Find all of your Job Steps from servers in the $server collection
    #>
    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [object[]]$Job,
        [object[]]$ExcludeJob,
        [switch]$NoDisabledJobs,
        [switch][Alias('Silent')]$EnableException
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
            Write-Message -Level Verbose -Message "Collecting jobs on $instance"
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
            Write-Message -Level Verbose -Message "Collecting job steps on $instance"
            foreach ($agentJobStep in $jobs.jobsteps) {
                Add-Member -Force -InputObject $agentJobStep -MemberType NoteProperty -Name ComputerName -value $agentJobStep.Parent.Parent.Parent.NetName
                Add-Member -Force -InputObject $agentJobStep -MemberType NoteProperty -Name InstanceName -value $agentJobStep.Parent.Parent.Parent.ServiceName
                Add-Member -Force -InputObject $agentJobStep -MemberType NoteProperty -Name SqlInstance -value $agentJobStep.Parent.Parent.Parent.DomainInstanceName
                Add-Member -Force -InputObject $agentJobStep -MemberType NoteProperty -Name AgentJob -value $agentJobStep.Parent.Name

                Select-DefaultView -InputObject $agentJobStep -Property ComputerName, InstanceName, SqlInstance, AgentJob, Name, SubSystem, LastRunDate, LastRunOutcome, State
            }
        }
    }
}