function Invoke-DbaCycleErrorLog {
    <#
        .SYNOPSIS
            Cycles the current instance or agent log.

        .DESCRIPTION
            Cycles the current error log for the instance (SQL Server) and/or SQL Server Agent.

        .PARAMETER SqlInstance
            The SQL Server instance holding the databases to be removed.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $cred = Get-Credential, this pass this $cred to the param.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

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
            Tags: Log, Cycle
            Author: Shawn Melton (@wsmelton | http://blog.wsmelton.info)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Invoke-DbaCycleLog

        .EXAMPLE
            Invoke-DbaCycleLog -SqlInstance sql2016 -Type agent

            Cycles the current error log for the SQL Server Agent on SQL Server instance sql2016

        .EXAMPLE
            Invoke-DbaCycleLog -SqlInstance sql2016 -Type instance

            Cycles the current error log for the SQL Server instance on SQL Server instance sql2016

        .EXAMPLE
            Invoke-DbaCycleLog -SqlInstance sql2016

            Cycles the current error log for both SQL Server instance and SQL Server Agent on SQL Server instance sql2016
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [ValidateSet('instance', 'agent')]
        [string]$Type,
        [switch][Alias('Silent')]$EnableException
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
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $logs = $logToCycle -join ','
                if ($Pscmdlet.ShouldProcess($server, "Cycle the log(s): $logs")) {
                    $null = $server.Query($sql)
                    [pscustomobject]@{
                        ComputerName = $server.NetName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        LogType      = $logToCycle
                        IsSuccessful = $true
                        Notes        = $null
                    }
                }
            }
            catch {
                [pscustomobject]@{
                    ComputerName = $server.NetName
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
