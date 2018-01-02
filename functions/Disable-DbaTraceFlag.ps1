function Disable-DbaTraceFlag {
    <#
    .SYNOPSIS
        Disable a Global Trace Flag that is currently running

    .DESCRIPTION
        The function will disable a Trace Flag that is currently running globally on the SQL Server instance(s) listed

    .PARAMETER SqlInstance
        Allows you to specify a comma separated list of servers to query.

    .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
        $cred = Get-Credential, this pass this $cred to the param.

        Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.

    .PARAMETER TraceFlag
        Trace flag number to enable globally

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: TraceFlag
        Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com

        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
        https://dbatools.io/Disable-DbaTraceFlag

    .EXAMPLE
        Disable-DbaTraceFlag -SqlInstance sql2016 -TraceFlag 3226
        Disable the globally running trace flag 3226 on SQL Server instance sql2016
#>
    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer", "SqlServers")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [int[]]$TraceFlag,
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

            $current = Get-DbaTraceFlag -SqlInstance $server -EnableException

            foreach ($tf in $TraceFlag) {
                $TraceFlagInfo = [pscustomobject]@{
                    SourceServer = $server.NetName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    TraceFlag    = $tf
                    Status       = $null
                    Notes        = $null
                    DateTime     = [DbaDateTime](Get-Date)
                }
                if ($tf -notin $current.TraceFlag) {
                    $TraceFlagInfo.Status = 'Skipped'
                    $TraceFlagInfo.Notes = "Trace Flag is not running."
                    $TraceFlagInfo
                    Write-Message -Level Warning -Message "Trace Flag $tf is not currently running on $instance"
                    continue
                }

                try {
                    $query = "DBCC TRACEOFF ($tf, -1)"
                    $server.Query($query)
                }
                catch {
                    $TraceFlagInfo.Status = "Failed"
                    $TraceFlagInfo.Notes = $_.Exception.Message
                    $TraceFlagInfo
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -Continue
                }
                $TraceFlagInfo.Status = "Successful"
                $TraceFlagInfo
            }
        }
    }
}
