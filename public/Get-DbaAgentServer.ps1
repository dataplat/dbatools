function Get-DbaAgentServer {
    <#
    .SYNOPSIS
        Retrieves SQL Server Agent service configuration and status information

    .DESCRIPTION
        Returns detailed SQL Server Agent configuration including service state, logging levels, job history settings, and service accounts. This is essential for auditing Agent configurations across multiple instances, troubleshooting job failures, and documenting environment settings for compliance or migration planning. The function provides a standardized view of Agent properties that would otherwise require connecting to each instance individually through SSMS.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Job, Agent
        Author: Claudio Silva (@claudioessilva), claudioessilva.eu

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgentServer

    .EXAMPLE
        PS C:\> Get-DbaAgentServer -SqlInstance localhost

        Returns SQL Agent Server on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaAgentServer -SqlInstance localhost, sql2016

        Returns SQL Agent Servers for the localhost and sql2016 SQL Server instances

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $jobServer = $server.JobServer

            $defaultView = 'ComputerName', 'InstanceName', 'SqlInstance', 'AgentDomainGroup', 'AgentLogLevel', 'AgentMailType', 'AgentShutdownWaitTime', 'ErrorLogFile', 'IdleCpuDuration', 'IdleCpuPercentage', 'IsCpuPollingEnabled', 'JobServerType', 'LoginTimeout', 'JobHistoryIsEnabled', 'MaximumHistoryRows', 'MaximumJobHistoryRows', 'MsxAccountCredentialName', 'MsxAccountName', 'MsxServerName', 'Name', 'NetSendRecipient', 'ServiceAccount', 'ServiceStartMode', 'SqlAgentAutoStart', 'SqlAgentMailProfile', 'SqlAgentRestart', 'SqlServerRestart', 'State', 'SysAdminOnly'

            Add-Member -Force -InputObject $jobServer -MemberType NoteProperty -Name ComputerName -Value $jobServer.Parent.ComputerName
            Add-Member -Force -InputObject $jobServer -MemberType NoteProperty -Name InstanceName -value $jobServer.Parent.ServiceName
            Add-Member -Force -InputObject $jobServer -MemberType NoteProperty -Name SqlInstance -Value $jobServer.Parent.DomainInstanceName
            Add-Member -Force -InputObject $jobServer -MemberType ScriptProperty -Name JobHistoryIsEnabled -Value { switch ( $this.MaximumHistoryRows ) { -1 { $false } default { $true } } }

            Select-DefaultView -InputObject $jobServer -Property $defaultView
        }
    }
}