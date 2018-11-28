function Set-DbaAgentServer {
    <#
    .SYNOPSIS
        Set-DbaAgentServer updates properties of a SQL Agent Server.

    .DESCRIPTION
        Set-DbaAgentServer updates properties in the SQL Server Server with parameters supplied.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

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
        The Agent Shutdown Wait Time value of the server agent.

    .PARAMETER DatabaseMailProfile
        The Database Mail Profile to be used. Must exists on database mail profiles.

    .PARAMETER ErrorLogFile
        Error log file location

    .PARAMETER IdleCpuDuration
        Idle CPU Duration value to be used

    .PARAMETER IdleCpuPercentage
        Idle CPU Percentage value to be used

    .PARAMETER IsCpuPollingEnabled
        Enable the Polling. If you want to set it to false you should use -IsCpuPollingEnabled:$false

    .PARAMETER LocalHostAlias
        The value for Local Host Alias configuration

    .PARAMETER LoginTimeout
        The value for Login Timeout configuration

    .PARAMETER MaximumHistoryRows
        Indicates the Maximum job history log size (in rows). If you want to turn it off use the value -1

    .PARAMETER MaximumJobHistoryRows
        Indicates the Maximum job history rows per job. If you want to turn it off use the value 0

    .PARAMETER NetSendRecipient
        The Net send recipient value

    .PARAMETER ReplaceAlertTokensEnabled
        Enable the Token replacement property. If you want to set it to false you should use -ReplaceAlertTokensEnabled:$false

    .PARAMETER SaveInSentFolder
        Specify if a Copy of the sent messages is save in the Sent Items folder. If you want to set it to false you should use -SaveInSentFolder:$false

    .PARAMETER SqlAgentAutoStart
        Enable the SQL Agent Auto Start. If you want to set it to false you should use -SqlAgentAutoStart:$false

    .PARAMETER SqlAgentMailProfile
        The SQL Server Agent Mail Profile to be used. Must exists on database mail profiles.

    .PARAMETER SqlAgentRestart
        Enable the SQL Agent Restart. If you want to set it to false you should use -SqlAgentRestart:$false

    .PARAMETER SqlServerRestart
        Enable the SQL Server Restart. If you want to set it to false you should use -SqlServerRestart:$false

    .PARAMETER WriteOemErrorLog
        Enable the Write OEM Error Log. If you want to set it to false you should use -WriteOemErrorLog:$false

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
        PS C:\> Set-DbaAgentServer -SqlInstance sql1 -IsCpuPollingEnabled

        Enable the CPU Polling configurations.

    .EXAMPLE
        PS C:\> Set-DbaAgentServer -SqlInstance sql1, sql2, sql3 -AgentLogLevel 'Errors, Warnings'

        Set the agent log level to Errors and Warnings on multiple servers.

    .EXAMPLE
        PS C:\> Set-DbaAgentServer -SqlInstance sql1 -IsCpuPollingEnabled:$false

        Disable the CPU Polling configurations.

    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
    param (
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.JobServer[]]$InputObject,
        [ValidateSet(1, "Errors", 2, "Warnings", 3, "Errors, Warnings", 4, "Informational", 5, "Errors, Informational", 6, "Warnings, Informational", 7, "All")]
        [object]$AgentLogLevel,
        [ValidateSet(0, "SqlAgentMail", 1, "DatabaseMail")]
        [object]$AgentMailType,
        [int]$AgentShutdownWaitTime,
        [string]$DatabaseMailProfile,
        [string]$ErrorLogFile,
        [int]$IdleCpuDuration,
        [int]$IdleCpuPercentage,
        [switch]$IsCpuPollingEnabled,
        [string]$LocalHostAlias,
        [int]$LoginTimeout,
        [int]$MaximumHistoryRows,
        [int]$MaximumJobHistoryRows,
        [string]$NetSendRecipient,
        [switch]$ReplaceAlertTokensEnabled,
        [switch]$SaveInSentFolder,
        [switch]$SqlAgentAutoStart,
        [string]$SqlAgentMailProfile,
        [switch]$SqlAgentRestart,
        [switch]$SqlServerRestart,
        [switch]$WriteOemErrorLog,
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
    }
    process {

        if (Test-FunctionInterrupt) { return }

        if ((-not $InputObject) -and (-not $SqlInstance)) {
            Stop-Function -Message "You must specify an Instance or pipe in results from another command" -Target $sqlinstance
            return
        }

        foreach ($instance in $sqlinstance) {
            # Try connecting to the instance
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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

            if (-not ($null -eq $IsCpuPollingEnabled)) {
                Write-Message -Message "Setting agent server IsCpuPollingEnabled to $IsCpuPollingEnabled" -Level Verbose
                $jobServer.IsCpuPollingEnabled = $IsCpuPollingEnabled
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

            if ($MaximumJobHistoryRows) {
                Write-Message -Message "Setting agent server MaximumJobHistoryRows to $MaximumJobHistoryRows" -Level Verbose
                $jobServer.MaximumJobHistoryRows = $MaximumJobHistoryRows
            }

            if ($NetSendRecipient) {
                Write-Message -Message "Setting agent server NetSendRecipient to $NetSendRecipient" -Level Verbose
                $jobServer.NetSendRecipient = $NetSendRecipient
            }

            if (-not ($null -eq $ReplaceAlertTokensEnabled)) {
                Write-Message -Message "Setting agent server ReplaceAlertTokensEnabled to $ReplaceAlertTokensEnabled" -Level Verbose
                $jobServer.ReplaceAlertTokensEnabled = $ReplaceAlertTokensEnabled
            }

            if (-not ($null -eq $SaveInSentFolder)) {
                Write-Message -Message "Setting agent server SaveInSentFolder to $SaveInSentFolder" -Level Verbose
                $jobServer.SaveInSentFolder = $SaveInSentFolder
            }

            if (-not ($null -eq $SqlAgentAutoStart)) {
                Write-Message -Message "Setting agent server SqlAgentAutoStart to $SqlAgentAutoStart" -Level Verbose
                $jobServer.SqlAgentAutoStart = $SqlAgentAutoStart
            }

            if (-not ($null -eq $SqlAgentMailProfile)) {
                Write-Message -Message "Setting agent server SqlAgentMailProfile to $SqlAgentMailProfile" -Level Verbose
                $jobServer.SqlAgentMailProfile = $SqlAgentMailProfile
            }

            if (-not ($null -eq $SqlAgentRestart)) {
                Write-Message -Message "Setting agent server SqlAgentRestart to $SqlAgentRestart" -Level Verbose
                $jobServer.SqlAgentRestart = $SqlAgentRestart
            }

            if (-not ($null -eq $SqlServerRestart)) {
                Write-Message -Message "Setting agent server SqlServerRestart to $SqlServerRestart" -Level Verbose
                $jobServer.SqlServerRestart = $SqlServerRestart
            }

            if (-not ($null -eq $WriteOemErrorLog)) {
                Write-Message -Message "Setting agent server WriteOemErrorLog to $WriteOemErrorLog" -Level Verbose
                $jobServer.WriteOemErrorLog = $WriteOemErrorLog
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