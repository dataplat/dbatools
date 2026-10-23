function Enable-DbaTraceFlag {
    <#
    .SYNOPSIS
        Enables one or more trace flags globally on SQL Server instances

    .DESCRIPTION
        Activates trace flags at the global level using DBCC TRACEON, affecting all connections and sessions on the target SQL Server instances.
        Commonly used for troubleshooting performance issues, enabling specific SQL Server behaviors, or applying recommended trace flags for your environment.
        Changes take effect immediately but are lost after a SQL Server restart - use Set-DbaStartupParameter to make trace flags persistent across restarts.
        The function automatically checks for already-enabled trace flags to prevent duplicate operations.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER TraceFlag
        Specifies one or more trace flag numbers to enable globally across all sessions on the SQL Server instance.
        Use specific trace flag numbers like 3226 (suppress backup log messages), 1117/1118 (tempdb optimization), or 4199 (query optimizer fixes).
        Multiple trace flags can be specified as an array to enable several flags in a single operation.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Returns one object per trace flag operation, indicating the result of enabling each trace flag.

        Properties:
        - SourceServer: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name (service name)
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - TraceFlag: The trace flag number that was enabled or attempted
        - Status: The operation status (Successful, Skipped, or Failed)
          - Successful: Trace flag was successfully enabled
          - Skipped: Trace flag was already enabled globally
          - Failed: An error occurred while enabling the trace flag
        - Notes: Additional information about the operation result or error message
        - DateTime: Timestamp when the operation was executed

    .NOTES
        Tags: Diagnostic, TraceFlag, DBCC
        Author: Garry Bargsley (@gbargsley), blog.garrybargsley.com

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
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
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
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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
                if ($Pscmdlet.ShouldProcess($instance, "Enabling flag '$tf'")) {
                    try {
                        $query = "DBCC TRACEON($tf, -1)"
                        $null = $server.Query($query)
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
}