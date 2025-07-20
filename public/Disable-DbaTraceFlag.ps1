function Disable-DbaTraceFlag {
    <#
    .SYNOPSIS
        Disable a Global Trace Flag that is currently running

    .DESCRIPTION
        The function will disable a Trace Flag that is currently running globally on the SQL Server instance(s) listed.
        These are not persisted after a restart, use Set-DbaStartupParameter to set them to persist after restarts.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER TraceFlag
        Trace flag number to disable globally

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
                        $server.Query($query)
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