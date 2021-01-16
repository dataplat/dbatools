function Set-DbaAgentServer {
    <#
    .SYNOPSIS
        Set-DbaAgentServer updates properties of a SQL Agent Server.

    .DESCRIPTION
        Set-DbaAgentServer updates properties in the SQL Server Server with parameters supplied.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Enables piping agent server objects

    .PARAMETER AgentLogLevel
        Specifies the agent log level.
        Allowed values 1, "Errors", 2, "Warnings", 3, "Errors, Warnings", 4, "Informational", 5, "Errors, Informational", 6, "Warnings, Informational", 7, "All"
        The text value can either be lowercase, uppercase or something in between as long as the text is correct.

    .PARAMETER AgentMailType
        Specifies the agent mail type.
        Allowed values 0, "SqlAgentMail", 1, "DatabaseMail"
        The text value can either be lowercase, uppercase or something in between as long as the text is correct.

    .PARAMETER AgentShutdownWaitTime
        The Agent Shutdown Wait Time value of the server agent. The accepted value range is between 5 and 600.

    .PARAMETER DatabaseMailProfile
        The Database Mail Profile to be used. Must exists on database mail profiles.

    .PARAMETER ErrorLogFile
        Error log file location

    .PARAMETER IdleCpuDuration
        Idle CPU Duration value to be used. The accepted value range is between 20 and 86400.

    .PARAMETER IdleCpuPercentage
        Idle CPU Percentage value to be used. The accepted value range is between 10 and 100.

    .PARAMETER CpuPolling
        Enable or Disable the Polling.
        Allowed values Enabled, Disabled

    .PARAMETER LocalHostAlias
        The value for Local Host Alias configuration

    .PARAMETER LoginTimeout
        The value for Login Timeout configuration. The accepted value range is between 5 and 45.

    .PARAMETER MaximumHistoryRows
        Indicates the Maximum job history log size (in rows). The acceptable value range is between 2 and 999999. To turn off the job history limitations use the value -1 and specify 0 for MaximumJobHistoryRows. See the example listed below.

    .PARAMETER MaximumJobHistoryRows
        Indicates the Maximum job history rows per job. The acceptable value range is between 2 and 999999. To turn off the job history limitations use the value 0 and specify -1 for MaximumHistoryRows. See the example listed below.

    .PARAMETER NetSendRecipient
        The Net send recipient value

    .PARAMETER ReplaceAlertTokens
        Enable or Disable the Token replacement property.
        Allowed values Enabled, Disabled

    .PARAMETER SaveInSentFolder
        Enable or Disable the copy of the sent messages is save in the Sent Items folder.
        Allowed values Enabled, Disabled

    .PARAMETER SqlAgentAutoStart
        Enable or Disable the SQL Agent Auto Start.
        Allowed values Enabled, Disabled

    .PARAMETER SqlAgentMailProfile
        The SQL Server Agent Mail Profile to be used. Must exists on database mail profiles.

    .PARAMETER SqlAgentRestart
        Enable or Disable the SQL Agent Restart.
        Allowed values Enabled, Disabled

    .PARAMETER SqlServerRestart
        Enable or Disable the SQL Server Restart.
        Allowed values Enabled, Disabled

    .PARAMETER WriteOemErrorLog
        Enable or Disable the Write OEM Error Log.
        Allowed values Enabled, Disabled

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
        Author: Cláudio Silva (@claudioessilva), https://claudioessilva.com

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
            # Try connecting to the instance
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $InputObject += $server.JobServer
            $InputObject.Refresh()
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