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

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Agent.JobServer

        Returns one JobServer object per instance. The object represents the SQL Server Agent configuration for that instance.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name (service name)
        - SqlInstance: The full SQL Server instance name (computer\instance or computer for default instance)
        - AgentDomainGroup: The Active Directory domain group for SQL Server Agent
        - AgentLogLevel: The verbosity level for SQL Server Agent error log (Errors, Warnings, Informational, etc.)
        - AgentMailType: The mail system used by SQL Server Agent (SqlAgentMail or DatabaseMail)
        - AgentShutdownWaitTime: The number of seconds SQL Server waits for Agent to shut down during restart
        - ErrorLogFile: Full path to the SQL Server Agent error log file
        - IdleCpuDuration: The number of seconds CPU must remain below threshold to be considered idle (seconds)
        - IdleCpuPercentage: The CPU usage percentage threshold below which CPU is considered idle (percent)
        - IsCpuPollingEnabled: Boolean indicating if CPU idle condition monitoring is enabled
        - JobServerType: The role of the server in SQL Server Agent topology (Master, Target, etc.)
        - LoginTimeout: The timeout period for Agent connections to SQL Server (seconds)
        - JobHistoryIsEnabled: Boolean indicating if job history collection is enabled (computed from MaximumHistoryRows)
        - MaximumHistoryRows: The maximum number of job history rows to retain in MSDB; -1 for unlimited
        - MaximumJobHistoryRows: The maximum number of history rows to retain per individual job
        - MsxAccountCredentialName: The credential name for Multi-Server Administration master account
        - MsxAccountName: The login account for Multi-Server Administration
        - MsxServerName: The name of the Multi-Server Administration master server
        - Name: The name of the JobServer instance
        - NetSendRecipient: The recipient for legacy net send notifications from SQL Server Agent
        - ServiceAccount: The user account running the SQL Server Agent service
        - ServiceStartMode: The startup mode of the SQL Server Agent service (Automatic, Manual, Disabled)
        - SqlAgentAutoStart: Boolean indicating if SQL Server Agent starts automatically with SQL Server
        - SqlAgentMailProfile: The name of the legacy SQL Agent Mail profile for notifications
        - SqlAgentRestart: Boolean indicating if SQL Server Agent automatically restarts if stopped unexpectedly
        - SqlServerRestart: Boolean indicating if SQL Server Agent can restart the SQL Server service
        - State: The current state of the SQL Server Agent service (Running, Stopped, etc.)
        - SysAdminOnly: Boolean indicating if only sysadmin-level users can access SQL Server Agent

        Additional properties available (from SMO JobServer object):
        - AlertCategories: Collection of alert categories configured on this instance
        - Alerts: Collection of alerts configured on this instance
        - AlertSystem: The alert system configuration object
        - DatabaseEngineEdition: The edition of SQL Server Database Engine (Enterprise, Standard, Express, etc.)
        - DatabaseEngineType: The type of Database Engine (Standalone, SqlAzureDatabase, etc.)
        - DatabaseMailProfile: The name of the Database Mail profile used for alerts and notifications
        - ExecutionManager: The job execution manager object
        - HostLoginName: The login name of the host running SQL Server Agent
        - JobCategories: Collection of job categories configured on this instance
        - Jobs: Collection of SQL Server Agent jobs configured on this instance
        - LocalHostAlias: The alias SQL Server Agent uses to reference the local server
        - OperatorCategories: Collection of operator categories configured on this instance
        - Operators: Collection of database mail operators configured on this instance
        - Parent: The parent SQL Server object
        - ProxyAccounts: Collection of proxy accounts configured for job step execution
        - ReplaceAlertTokensEnabled: Boolean indicating if alert notification tokens are replaced with actual values
        - SaveInSentFolder: Boolean indicating if copies of agent notifications are saved to Database Mail sent items
        - ServerVersion: The version of SQL Server
        - SharedSchedules: Collection of shared job schedules configured on this instance
        - TargetServerGroups: Collection of target server groups for Multi-Server Administration
        - TargetServers: Collection of target servers for Multi-Server Administration
        - WriteOemErrorLog: Boolean indicating if SQL Server Agent writes errors to the Windows Application Event Log

        All properties from the SMO JobServer object are accessible via Select-Object * even though only the default properties are displayed without explicit column selection.

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