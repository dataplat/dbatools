function Stop-DbaTrace {
    <#
    .SYNOPSIS
        Stops running SQL Server traces using sp_trace_setstatus

    .DESCRIPTION
        Stops one or more running SQL Server traces by calling sp_trace_setstatus with a status of 0. This is useful when you need to stop traces created for troubleshooting, performance monitoring, or security auditing that are no longer needed or are impacting server performance. The function prevents you from accidentally stopping the default trace and provides guidance to use Set-DbaSpConfigure if you need to disable it. Works with trace IDs or accepts piped input from Get-DbaTrace for selective stopping of traces.

    .PARAMETER SqlInstance
        The target SQL Server instance

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Id
        Specifies the trace IDs to stop. Accepts one or more trace ID numbers as integers.
        Use this when you need to stop specific traces instead of all running traces on the instance.

    .PARAMETER InputObject
        Accepts trace objects from the pipeline, typically from Get-DbaTrace output.
        This enables selective stopping of traces by piping Get-DbaTrace results through filtering commands like Out-GridView or Where-Object.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Trace
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Stop-DbaTrace

    .EXAMPLE
        PS C:\> Stop-DbaTrace -SqlInstance sql2008

        Stops all traces on sql2008

    .EXAMPLE
        PS C:\> Stop-DbaTrace -SqlInstance sql2008 -Id 1

        Stops all trace with ID 1 on sql2008

    .EXAMPLE
        PS C:\> Get-DbaTrace -SqlInstance sql2008 | Out-GridView -PassThru | Stop-DbaTrace

        Stops selected traces on sql2008

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int[]]$Id,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (-not $InputObject -and $SqlInstance) {
            $InputObject = Get-DbaTrace -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Id $Id
        }

        foreach ($trace in $InputObject) {
            if (-not $trace.id -and -not $trace.Parent) {
                Stop-Function -Message "Input is of the wrong type. Use Get-DbaTrace." -Continue
                return
            }

            $server = $trace.Parent
            $traceid = $trace.id
            $default = Get-DbaTrace -SqlInstance $server -Default

            if ($default.id -eq $traceid) {
                Stop-Function -Message "The default trace on $server cannot be stopped. Use Set-DbaSpConfigure to turn it off." -Continue
            }

            $sql = "sys.sp_trace_setstatus $traceid, 0"

            if ($Pscmdlet.ShouldProcess($traceid, "Stopping the TraceID on $server")) {
                try {
                    $server.Query($sql)
                    $output = Get-DbaTrace -SqlInstance $server -Id $traceid
                    if (-not $output) {
                        $output = [PSCustomObject]@{
                            ComputerName      = $server.ComputerName
                            InstanceName      = $server.ServiceName
                            SqlInstance       = $server.DomainInstanceName
                            Id                = $traceid
                            Status            = $null
                            IsRunning         = $false
                            Path              = $null
                            MaxSize           = $null
                            StopTime          = $null
                            MaxFiles          = $null
                            IsRowset          = $null
                            IsRollover        = $null
                            IsShutdown        = $null
                            IsDefault         = $null
                            BufferCount       = $null
                            BufferSize        = $null
                            FilePosition      = $null
                            ReaderSpid        = $null
                            StartTime         = $null
                            LastEventTime     = $null
                            EventCount        = $null
                            DroppedEventCount = $null
                            Parent            = $server
                        } | Select-DefaultView -Property 'ComputerName', 'InstanceName', 'SqlInstance', 'Id', 'IsRunning'
                    }
                    $output
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -Continue
                    return
                }
            }
        }
    }
}