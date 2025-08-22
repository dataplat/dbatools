function Invoke-DbaCycleErrorLog {
    <#
    .SYNOPSIS
        Cycles the current SQL Server error log and/or SQL Agent error log to start fresh log files

    .DESCRIPTION
        Archives the current error log files and creates new ones for SQL Server instance and/or SQL Agent. This operation is typically performed during maintenance windows to manage log file sizes and establish clean baselines for troubleshooting. When cycled, the current error log becomes the archived log (errorlog.1) and a new error log starts capturing events.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Type
        The log to cycle.
        Accepts: instance or agent.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Instance, ErrorLog, Logging
        Author: Shawn Melton (@wsmelton), wsmelton.github.io

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaCycleErrorLog

    .EXAMPLE
        PS C:\> Invoke-DbaCycleLog -SqlInstance sql2016 -Type agent

        Cycles the current error log for the SQL Server Agent on SQL Server instance sql2016

    .EXAMPLE
        PS C:\> Invoke-DbaCycleLog -SqlInstance sql2016 -Type instance

        Cycles the current error log for the SQL Server instance on SQL Server instance sql2016

    .EXAMPLE
        PS C:\> Invoke-DbaCycleLog -SqlInstance sql2016

        Cycles the current error log for both SQL Server instance and SQL Server Agent on SQL Server instance sql2016

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet('instance', 'agent')]
        [string]$Type,
        [switch]$EnableException
    )

    begin {
        if (Test-Bound 'Type') {
            if ($Type -notin 'instance', 'agent') {
                Stop-Function -Message "The type provided [$Type] for $SqlInstance is not an accepted value. Please use 'Instance' or 'Agent'"
                return
            }
        }
        $logToCycle = @()
        switch ($Type) {
            'agent' {
                $sql = "EXEC msdb.dbo.sp_cycle_agent_errorlog;"
                $logToCycle = $Type
            }
            'instance' {
                $sql = "EXEC master.dbo.sp_cycle_errorlog;"
                $logToCycle = $Type
            }
            default {
                $sql = "
                    EXEC master.dbo.sp_cycle_errorlog;
                    EXEC msdb.dbo.sp_cycle_agent_errorlog;"
                $logToCycle = 'instance', 'agent'
            }
        }

    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $logs = $logToCycle -join ','
                if ($Pscmdlet.ShouldProcess($server, "Cycle the log(s): $logs")) {
                    $null = $server.Query($sql)
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        LogType      = $logToCycle
                        IsSuccessful = $true
                        Notes        = $null
                    }
                }
            } catch {
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    LogType      = $logToCycle
                    IsSuccessful = $false
                    Notes        = $_.Exception
                }
                Stop-Function -Message "Issue cycling $logs on $server" -Target $server -ErrorRecord $_ -Exception $_.Exception -Continue
            }
        }
    }
}