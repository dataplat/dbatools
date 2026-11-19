function Disable-DbaTraceFlag {
    <#
    .SYNOPSIS
        Disables globally running trace flags on SQL Server instances

    .DESCRIPTION
        Turns off trace flags that are currently enabled globally across SQL Server instances using DBCC TRACEOFF.
        Useful when you need to disable diagnostic trace flags that were enabled for troubleshooting or testing without requiring a restart.
        Only affects flags currently running in memory - does not modify startup parameters or persistent trace flag settings.
        Use Set-DbaStartupParameter to manage trace flags that persist after restarts.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER TraceFlag
        Specifies the trace flag numbers to disable globally across all sessions on the SQL Server instance.
        Only trace flags that are currently running will be disabled - flags not currently active are skipped with a warning.
        Supports multiple trace flag numbers to disable several flags in a single operation.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Diagnostic, TraceFlag, DBCC
        Author: Garry Bargsley (@gbargsley), blog.garrybargsley.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        PSCustomObject

        Returns one object per trace flag that was processed. The object contains the status and result of the disable operation.

        Properties:
        - SourceServer: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - TraceFlag: The trace flag number that was disabled or skipped
        - Status: The result of the operation (Successful, Skipped, or Failed)
        - Notes: Additional details about the operation result or error message
        - DateTime: Timestamp of when the operation was executed

    .LINK
        https://dbatools.io/Disable-DbaTraceFlag

    .EXAMPLE
        PS C:\> Disable-DbaTraceFlag -SqlInstance sql2016 -TraceFlag 3226

        Disable the globally running trace flag 3226 on SQL Server instance sql2016

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

            $current = Get-DbaTraceFlag -SqlInstance $server -EnableException

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
                if ($tf -notin $current.TraceFlag) {
                    $TraceFlagInfo.Status = 'Skipped'
                    $TraceFlagInfo.Notes = "Trace Flag is not running."
                    $TraceFlagInfo
                    Write-Message -Level Warning -Message "Trace Flag $tf is not currently running on $instance"
                    continue
                }
                if ($Pscmdlet.ShouldProcess($instance, "Disabling flag '$tf'")) {
                    try {
                        $query = "DBCC TRACEOFF ($tf, -1)"
                        $null = $server.Query($query)
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