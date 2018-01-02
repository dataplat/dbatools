function Clear-DbaWaitStatistics {
    <#
    .SYNOPSIS
        Clears wait statistics

    .DESCRIPTION
        Reset the aggregated statistics - basically just executes DBCC SQLPERF (N'sys.dm_os_wait_stats', CLEAR)

    .PARAMETER SqlInstance
        Allows you to specify a comma separated list of servers to query.

    .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
        $cred = Get-Credential, this pass this $cred to the param.

        Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: WaitStatistic
        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
        https://dbatools.io/Clear-DbaWaitStatistics

    .EXAMPLE
        Clear-DbaWaitStatistics -SqlInstance sql2008, sqlserver2012
        After confirmation, clears wait stats on servers sql2008 and sqlserver2012

    .EXAMPLE
        Clear-DbaWaitStatistics -SqlInstance sql2008, sqlserver2012 -Confirm:$false
        Clears wait stats on servers sql2008 and sqlserver2012, without prompting
    #>
    [CmdletBinding(ConfirmImpact = 'High', SupportsShouldProcess)]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer", "SqlServers")]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch][Alias('Silent')]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Pscmdlet.ShouldProcess($instance, "Performing CLEAR of sys.dm_os_wait_stats")) {
                try {
                    $server.Query("DBCC SQLPERF (N'sys.dm_os_wait_stats', CLEAR);")
                    $status = "Success"
                }
                catch {
                    $status = $_.Exception
                }

                [PSCustomObject]@{
                    ComputerName = $server.NetName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Status       = $status
                }
            }
        }
    }
}