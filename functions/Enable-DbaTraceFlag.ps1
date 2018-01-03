function Enable-DbaTraceFlag {
    <#
    .SYNOPSIS
        Enable Global Trace Flag(s)
    .DESCRIPTION
        The function will set one or multiple trace flags on the SQL Server instance(s) listed

    .PARAMETER SqlInstance
        Allows you to specify a comma separated list of servers to query.

    .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:
        $scred = Get-Credential, this pass this $scred object to the -SqlCredential parameter.
        Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
        To connect as a different Windows user, run PowerShell as that user.

    .PARAMETER TraceFlag
        Trace flag number(s) to enable globally

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
        https://dbatools.io/Enable-DbaTraceFlag

    .EXAMPLE
        Enable-DbaTraceFlag -SqlInstance sql2016 -TraceFlag 3226
        Enable the trace flag 3226 on SQL Server instance sql2016

    .EXAMPLE
        Enable-DbaTraceFlag -SqlInstance sql2016 -TraceFlag 1117, 1118
        Enable multiple trace flags on SQL Server instance sql2016
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

            $CurrentRunningTraceFlags = Get-DbaTraceFlag -SqlInstance $server -EnableException

            # We could combine all trace flags but the granularity is worth it
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
                If ($CurrentRunningTraceFlags.TraceFlag -contains $tf) {
                    $TraceFlagInfo.Status = 'Skipped'
                    $TraceFlagInfo.Notes = "The Trace flag is already running."
                    $TraceFlagInfo
                    Write-Message -Level Warning -Message "The Trace flag [$tf] is already running globally."
                    continue
                }

                try {
                    $query = "DBCC TRACEON ($tf, -1)"
                    $server.Query($query)
                    $server.Refresh()
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
