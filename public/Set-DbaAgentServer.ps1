function Set-DbaAgentServer {
    <#
    .SYNOPSIS
        Configures SQL Server Agent service properties and operational settings

    .DESCRIPTION
        Modifies SQL Server Agent configuration settings including logging levels, mail profiles, CPU monitoring thresholds, job history retention, and service restart behaviors. Use this to standardize agent configurations across multiple instances, set up proper alerting and monitoring thresholds, or configure job history retention policies to prevent MSDB bloat.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Accepts SQL Server Agent JobServer objects from Get-DbaAgentServer for pipeline operations.
        Use this when you need to configure multiple agent servers from a filtered list or modify settings on specific instances already retrieved.

    .PARAMETER AgentLogLevel
        Controls the verbosity of SQL Server Agent logging in the agent error log.
        Use 'Errors' for production environments to minimize log size, 'Errors, Warnings' for standard monitoring, or 'All' when troubleshooting agent job failures.
        Higher logging levels help diagnose job execution issues but increase log file growth.

    .PARAMETER AgentMailType
        Specifies whether SQL Server Agent uses legacy SQL Agent Mail or the newer Database Mail for notifications.
        Use 'DatabaseMail' for modern installations as SQL Agent Mail is deprecated and requires MAPI configuration.
        Database Mail provides better security, reliability, and doesn't require Outlook or Exchange MAPI on the server.

    .PARAMETER AgentShutdownWaitTime
        Sets how long (in seconds) SQL Server waits for SQL Server Agent to shut down during service restart.
        Increase this value if you have long-running jobs that need more time to complete gracefully during shutdown.
        Default is typically 15 seconds; values between 5-600 seconds are supported.

    .PARAMETER DatabaseMailProfile
        Specifies which Database Mail profile SQL Server Agent uses for sending job notifications and alerts.
        The profile must already exist in the instance's Database Mail configuration before setting this value.
        Use this to ensure agent notifications use the correct SMTP settings and sender address for your environment.

    .PARAMETER ErrorLogFile
        Sets the file path where SQL Server Agent writes its error log.
        Change this when you need agent logs stored in a specific location for centralized monitoring or compliance requirements.
        Ensure the SQL Server Agent service account has write permissions to the specified path.

    .PARAMETER IdleCpuDuration
        Defines how long (in seconds) the CPU must remain below the idle threshold before SQL Server Agent considers the server idle.
        Use this with CpuPolling to schedule jobs only when the server isn't busy with other workloads.
        Values range from 20 seconds to 24 hours (86400 seconds); typical values are 600-1800 seconds for production servers.

    .PARAMETER IdleCpuPercentage
        Sets the CPU usage percentage threshold below which SQL Server Agent considers the server idle.
        Configure this to prevent resource-intensive maintenance jobs from running during peak usage periods.
        Values between 10-100 percent; commonly set to 10-25% for production servers to ensure adequate idle detection.

    .PARAMETER CpuPolling
        Enables or disables CPU idle condition monitoring for job scheduling.
        Enable this to allow jobs with idle CPU conditions to run only when server CPU usage is low.
        Useful for scheduling maintenance tasks like index rebuilds or backups that should avoid peak usage periods.

    .PARAMETER LocalHostAlias
        Specifies an alias that SQL Server Agent uses to refer to the local server in job steps and notifications.
        Set this when the server has multiple network names or when you want job notifications to reference a specific hostname.
        Commonly used in clustered environments or when the server is accessed by different DNS names.

    .PARAMETER LoginTimeout
        Sets the timeout (in seconds) for SQL Server Agent connections to SQL Server instances.
        Increase this value if agent jobs frequently fail due to connection timeouts, especially in slow network environments.
        Values range from 5-45 seconds; default is typically 30 seconds.

    .PARAMETER MaximumHistoryRows
        Controls the total number of job history rows retained in MSDB before old entries are purged.
        Set this to prevent MSDB growth from excessive job history; typical values are 10000-100000 rows depending on job frequency.
        Use -1 to disable limits (not recommended for production) or work with MaximumJobHistoryRows to control per-job retention.

    .PARAMETER MaximumJobHistoryRows
        Sets the maximum number of history rows retained per individual job.
        Prevents any single job from consuming too much history space; typical values are 100-1000 rows per job.
        Use 0 to disable per-job limits when MaximumHistoryRows is set to -1, or set both parameters to control overall history retention.

    .PARAMETER NetSendRecipient
        Specifies the network recipient for legacy net send notifications from SQL Server Agent.
        This feature is deprecated and rarely used in modern environments; Database Mail is the preferred notification method.
        Only configure this if you have legacy monitoring systems that still rely on net send messages.

    .PARAMETER ReplaceAlertTokens
        Controls whether SQL Server Agent replaces tokens in alert notification messages with actual values.
        Enable this to include dynamic information like error details, job names, or server information in alert emails.
        Tokens like $(ESCAPE_SQUOTE(A-ERR)) get replaced with actual error text when notifications are sent.

    .PARAMETER SaveInSentFolder
        Controls whether copies of agent notification emails are saved to the Database Mail sent items.
        Enable this for audit trails and troubleshooting notification delivery issues.
        Disable to reduce Database Mail storage usage if you don't need to track sent notifications.

    .PARAMETER SqlAgentAutoStart
        Controls whether SQL Server Agent service starts automatically when SQL Server starts.
        Enable this on production servers to ensure scheduled jobs and monitoring continue after server restarts.
        Disable only in development environments where automatic job execution isn't desired.

    .PARAMETER SqlAgentMailProfile
        Specifies the legacy SQL Agent Mail profile for notifications (deprecated feature).
        Only used when AgentMailType is set to 'SqlAgentMail'; DatabaseMailProfile is preferred for modern installations.
        The profile must exist in the SQL Agent Mail configuration, which requires MAPI setup.

    .PARAMETER SqlAgentRestart
        Controls whether SQL Server Agent automatically restarts if it stops unexpectedly.
        Enable this on production servers to ensure continuous job scheduling and monitoring after agent failures.
        The agent will attempt to restart itself if the service terminates abnormally.

    .PARAMETER SqlServerRestart
        Controls whether SQL Server Agent can restart the SQL Server service if it stops unexpectedly.
        Enable this in environments where automatic SQL Server recovery is desired, but use caution on production systems.
        This setting allows the agent to restart the database engine service automatically.

    .PARAMETER WriteOemErrorLog
        Controls whether SQL Server Agent writes errors to the Windows Application Event Log.
        Enable this to integrate agent errors with centralized Windows event monitoring and alerting systems.
        Useful for environments that rely on Windows Event Log for monitoring and don't use SQL-specific monitoring tools.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Server
        Author: Claudio Silva (@claudioessilva), claudioessilva.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaAgentServer

    .EXAMPLE
        PS C:\> Set-DbaAgentServer -SqlInstance sql1 -MaximumHistoryRows 10000 -MaximumJobHistoryRows 100

        Changes the job history retention to 10000 rows with an maximum of 100 rows per job.

    .EXAMPLE
        PS C:\> Set-DbaAgentServer -SqlInstance sql1 -CpuPolling Enabled

        Enable the CPU Polling configurations.

    .EXAMPLE
        PS C:\> Set-DbaAgentServer -SqlInstance sql1, sql2, sql3 -AgentLogLevel 'Errors, Warnings'

        Set the agent log level to Errors and Warnings on multiple servers.

    .EXAMPLE
        PS C:\> Set-DbaAgentServer -SqlInstance sql1 -CpuPolling Disabled

        Disable the CPU Polling configurations.

    .EXAMPLE
        PS C:\> Set-DbaAgentServer -SqlInstance sql1 -MaximumJobHistoryRows 1000 -MaximumHistoryRows 10000

        Set the max history limitations. This is the equivalent to calling:  EXEC msdb.dbo.sp_set_sqlagent_properties @jobhistory_max_rows=10000, @jobhistory_max_rows_per_job=1000

    .EXAMPLE
        PS C:\> Set-DbaAgentServer -SqlInstance sql1 -MaximumJobHistoryRows 0 -MaximumHistoryRows -1

        Disable the max history limitations. This is the equivalent to calling:  EXEC msdb.dbo.sp_set_sqlagent_properties @jobhistory_max_rows=-1, @jobhistory_max_rows_per_job=0

    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.JobServer[]]$InputObject,
        [ValidateSet(1, "Errors", 2, "Warnings", 3, "Errors, Warnings", 4, "Informational", 5, "Errors, Informational", 6, "Warnings, Informational", 7, "All")]
        [object]$AgentLogLevel,
        [ValidateSet(0, "SqlAgentMail", 1, "DatabaseMail")]
        [object]$AgentMailType,
        [ValidateRange(5, 600)][int]$AgentShutdownWaitTime,
        [string]$DatabaseMailProfile,
        [string]$ErrorLogFile,
        [ValidateRange(20, 86400)][int]$IdleCpuDuration,
        [ValidateRange(10, 100)][int]$IdleCpuPercentage,
        [ValidateSet("Enabled", "Disabled")]
        [string]$CpuPolling,
        [string]$LocalHostAlias,
        [ValidateRange(5, 45)][int]$LoginTimeout,
        [int]$MaximumHistoryRows, # validated in the begin block
        [int]$MaximumJobHistoryRows, # validated in the begin block
        [string]$NetSendRecipient,
        [ValidateSet("Enabled", "Disabled")]
        [string]$ReplaceAlertTokens,
        [ValidateSet("Enabled", "Disabled")]
        [string]$SaveInSentFolder,
        [ValidateSet("Enabled", "Disabled")]
        [string]$SqlAgentAutoStart,
        [string]$SqlAgentMailProfile,
        [ValidateSet("Enabled", "Disabled")]
        [string]$SqlAgentRestart,
        [ValidateSet("Enabled", "Disabled")]
        [string]$SqlServerRestart,
        [ValidateSet("Enabled", "Disabled")]
        [string]$WriteOemErrorLog,
        [switch]$EnableException
    )

    begin {
        # Check of the agent mail type is of type string and set the integer value
        if (($AgentMailType -notin 0, 1) -and ($null -ne $AgentMailType)) {
            $AgentMailType = switch ($AgentMailType) { "SqlAgentMail" { 0 } "DatabaseMail" { 1 } }
        }

        # Check of the agent log level is of type string and set the integer value
        if (($AgentLogLevel -notin 0, 1) -and ($null -ne $AgentLogLevel)) {
            $AgentLogLevel = switch ($AgentLogLevel) { "Errors" { 1 } "Warnings" { 2 } "Errors, Warnings" { 3 } "Informational" { 4 } "Errors, Informational" { 5 } "Warnings, Informational" { 6 } "All" { 7 } }
        }

        if ($PSBoundParameters.ContainsKey("MaximumHistoryRows") -and ($MaximumHistoryRows -ne -1 -and $MaximumHistoryRows -notin 2..999999)) {
            Stop-Function -Message "You must specify a MaximumHistoryRows value of -1 (i.e. turn off max history) or a value between 2 and 999999. See the command description for examples."
            return
        }

        if ($PSBoundParameters.ContainsKey("MaximumJobHistoryRows") -and ($MaximumJobHistoryRows -ne 0 -and $MaximumJobHistoryRows -notin 2..999999)) {
            Stop-Function -Message "You must specify a MaximumJobHistoryRows value of 0 (i.e. turn off max history) or a value between 2 and 999999. See the command description for examples."
            return
        }
    }
    process {

        if (Test-FunctionInterrupt) { return }

        if ((-not $InputObject) -and (-not $SqlInstance)) {
            Stop-Function -Message "You must specify an Instance or pipe in results from another command" -Target $SqlInstance
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $server.JobServer.Refresh()
            $InputObject += $server.JobServer
        }

        foreach ($jobServer in $InputObject) {
            $server = $jobServer.Parent

            #region job server options
            # Settings the options for the job server
            if ($AgentLogLevel) {
                Write-Message -Message "Setting Agent log level to $AgentLogLevel" -Level Verbose
                $jobServer.AgentLogLevel = $AgentLogLevel
            }

            if ($AgentMailType) {
                Write-Message -Message "Setting Agent Mail Type to $AgentMailType" -Level Verbose
                $jobServer.AgentMailType = $AgentMailType
            }

            if ($AgentShutdownWaitTime) {
                Write-Message -Message "Setting Agent Shutdown Wait Time to $AgentShutdownWaitTime" -Level Verbose
                $jobServer.AgentShutdownWaitTime = $AgentShutdownWaitTime
            }

            if ($DatabaseMailProfile) {
                if ($DatabaseMailProfile -in (Get-DbaDbMail -SqlInstance $server).Profiles.Name) {
                    Write-Message -Message "Setting Database Mail Profile to $DatabaseMailProfile" -Level Verbose
                    $jobServer.DatabaseMailProfile = $DatabaseMailProfile
                } else {
                    Write-Message -Message "Database mail profile not found on $server" -Level Warning
                }
            }

            if ($ErrorLogFile) {
                Write-Message -Message "Setting agent server ErrorLogFile to $ErrorLogFile" -Level Verbose
                $jobServer.ErrorLogFile = $ErrorLogFile
            }

            if ($IdleCpuDuration) {
                Write-Message -Message "Setting agent server IdleCpuDuration to $IdleCpuDuration" -Level Verbose
                $jobServer.IdleCpuDuration = $IdleCpuDuration
            }

            if ($IdleCpuPercentage) {
                Write-Message -Message "Setting agent server IdleCpuPercentage to $IdleCpuPercentage" -Level Verbose
                $jobServer.IdleCpuPercentage = $IdleCpuPercentage
            }

            if ($CpuPolling) {
                Write-Message -Message "Setting agent server IsCpuPollingEnabled to $IsCpuPollingEnabled" -Level Verbose
                $jobServer.IsCpuPollingEnabled = if ($CpuPolling -eq "Enabled") { $true } else { $false }
            }

            if ($LocalHostAlias) {
                Write-Message -Message "Setting agent server LocalHostAlias to $LocalHostAlias" -Level Verbose
                $jobServer.LocalHostAlias = $LocalHostAlias
            }

            if ($LoginTimeout) {
                Write-Message -Message "Setting agent server LoginTimeout to $LoginTimeout" -Level Verbose
                $jobServer.LoginTimeout = $LoginTimeout
            }

            if ($MaximumHistoryRows) {
                Write-Message -Message "Setting agent server MaximumHistoryRows to $MaximumHistoryRows" -Level Verbose
                $jobServer.MaximumHistoryRows = $MaximumHistoryRows
            }

            if ($PSBoundParameters.ContainsKey("MaximumJobHistoryRows")) {
                Write-Message -Message "Setting agent server MaximumJobHistoryRows to $MaximumJobHistoryRows" -Level Verbose
                $jobServer.MaximumJobHistoryRows = $MaximumJobHistoryRows
            }

            if ($NetSendRecipient) {
                Write-Message -Message "Setting agent server NetSendRecipient to $NetSendRecipient" -Level Verbose
                $jobServer.NetSendRecipient = $NetSendRecipient
            }

            if ($ReplaceAlertTokens) {
                Write-Message -Message "Setting agent server ReplaceAlertTokensEnabled to $ReplaceAlertTokens" -Level Verbose
                $jobServer.ReplaceAlertTokensEnabled = if ($ReplaceAlertTokens -eq "Enabled") { $true } else { $false }
            }

            if ($SaveInSentFolder) {
                Write-Message -Message "Setting agent server SaveInSentFolder to $SaveInSentFolder" -Level Verbose
                $jobServer.SaveInSentFolder = if ($SaveInSentFolder -eq "Enabled") { $true } else { $false }
            }

            if ($SqlAgentAutoStart) {
                Write-Message -Message "Setting agent server SqlAgentAutoStart to $SqlAgentAutoStart" -Level Verbose
                $jobServer.SqlAgentAutoStart = if ($SqlAgentAutoStart -eq "Enabled") { $true } else { $false }
            }

            if ($SqlAgentMailProfile) {
                Write-Message -Message "Setting agent server SqlAgentMailProfile to $SqlAgentMailProfile" -Level Verbose
                $jobServer.SqlAgentMailProfile = $SqlAgentMailProfile
            }

            if ($SqlAgentRestart) {
                Write-Message -Message "Setting agent server SqlAgentRestart to $SqlAgentRestart" -Level Verbose
                $jobServer.SqlAgentRestart = if ($SqlAgentRestart -eq "Enabled") { $true } else { $false }
            }

            if ($SqlServerRestart) {
                Write-Message -Message "Setting agent server SqlServerRestart to $SqlServerRestart" -Level Verbose
                $jobServer.SqlServerRestart = if ($SqlServerRestart -eq "Enabled") { $true } else { $false }
            }

            if ($WriteOemErrorLog) {
                Write-Message -Message "Setting agent server WriteOemErrorLog to $WriteOemErrorLog" -Level Verbose
                $jobServer.WriteOemErrorLog = if ($WriteOemErrorLog -eq "Enabled") { $true } else { $false }
            }

            #endregion server agent options

            # Execute
            if ($PSCmdlet.ShouldProcess($SqlInstance, "Changing the agent server")) {
                try {
                    Write-Message -Message "Changing the agent server" -Level Verbose

                    # Change the agent server
                    $jobServer.Alter()
                } catch {
                    Stop-Function -Message "Something went wrong changing the agent server" -ErrorRecord $_ -Target $instance -Continue
                }

                Get-DbaAgentServer -SqlInstance $server | Where-Object Name -eq $jobServer.name
            }
        }
    }
    end {
        Write-Message -Message "Finished changing agent server(s)" -Level Verbose
    }
}