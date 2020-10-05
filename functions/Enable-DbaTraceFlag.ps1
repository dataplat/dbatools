function Enable-DbaTraceFlag {
    <#
    .SYNOPSIS
        Enable Global Trace Flag(s)

    .DESCRIPTION
        The function will set one or multiple trace flags on the SQL Server instance(s) listed.
        These are not persisted after a restart, use Set-DbaStartupParameter to set them to persist after restarts.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER TraceFlag
        Trace flag number(s) to enable globally

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: TraceFlag, DBCC
        Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Enable-DbaTraceFlag

    .EXAMPLE
        PS C:\> Enable-DbaTraceFlag -SqlInstance sql2016 -TraceFlag 3226

        Enable the trace flag 3226 on SQL Server instance sql2016

    .EXAMPLE
        PS C:\> Enable-DbaTraceFlag -SqlInstance sql2016 -TraceFlag 1117, 1118

        Enable multiple trace flags on SQL Server instance sql2016
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [int[]]$TraceFlag,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $CurrentRunningTraceFlags = Get-DbaTraceFlag -SqlInstance $server -EnableException

            # We could combine all trace flags but the granularity is worth it
            foreach ($tf in $TraceFlag) {
                $TraceFlagInfo = [PSCustomObject]@{
                    SourceServer = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    TraceFlag    = $tf
                    Status       = $null
                    Notes        = $null
                    DateTime     = [DbaDateTime](Get-Date)
                }
                if ($CurrentRunningTraceFlags.TraceFlag -contains $tf) {
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
                } catch {
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
