function Get-DbaAgentJobStep {
    <#
    .SYNOPSIS
        Gets SQL Agent Job Step information for each instance(s) of SQL Server.

    .DESCRIPTION
        The Get-DbaAgentJobStep returns connected SMO object for SQL Agent Job Step for each instance(s) of SQL Server.

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

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Job, Agent
        Author: Klaas Vandenberghe (@PowerDbaKlaas), http://powerdba.eu

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgentJobStep

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
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [object[]]$Job,
        [object[]]$ExcludeJob,
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
            Write-Message -Level Verbose -Message "Collecting jobs on $instance"
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
            Write-Message -Level Verbose -Message "Collecting job steps on $instance"
            foreach ($agentJobStep in $jobs.jobsteps) {
                Add-Member -Force -InputObject $agentJobStep -MemberType NoteProperty -Name ComputerName -value $agentJobStep.Parent.Parent.Parent.ComputerName
                Add-Member -Force -InputObject $agentJobStep -MemberType NoteProperty -Name InstanceName -value $agentJobStep.Parent.Parent.Parent.ServiceName
                Add-Member -Force -InputObject $agentJobStep -MemberType NoteProperty -Name SqlInstance -value $agentJobStep.Parent.Parent.Parent.DomainInstanceName
                Add-Member -Force -InputObject $agentJobStep -MemberType NoteProperty -Name AgentJob -value $agentJobStep.Parent.Name

                Select-DefaultView -InputObject $agentJobStep -Property ComputerName, InstanceName, SqlInstance, AgentJob, Name, SubSystem, LastRunDate, LastRunOutcome, State
            }
        }
    }
}