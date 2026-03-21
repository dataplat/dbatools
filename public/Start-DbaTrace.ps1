function Start-DbaTrace {
    <#
    .SYNOPSIS
        Starts existing SQL Server traces that are currently stopped

    .DESCRIPTION
        Starts SQL Server traces that have been defined but are not currently running. This function activates traces by setting their status to 1 using sp_trace_setstatus, allowing you to begin collecting trace data for performance monitoring, auditing, or troubleshooting. The default trace cannot be started with this function - use Set-DbaSpConfigure to enable it instead.

    .PARAMETER SqlInstance
        The target SQL Server instance

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Id
        Specifies the numeric IDs of specific traces to start. When omitted, all stopped traces on the instance will be started.
        Use this when you need to start only particular traces rather than all available stopped traces.

    .PARAMETER InputObject
        Accepts trace objects from the pipeline, typically from Get-DbaTrace. This allows you to filter traces first, then start only the selected ones.
        Use this parameter when piping trace objects or when you have trace objects from a previous Get-DbaTrace command.

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

    .OUTPUTS
        PSCustomObject

        Returns one object for each trace that was started or would be started (if -WhatIf is specified).

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Id: The trace ID number
        - Status: Numeric trace status value (0=stopped, 1=running, 2=closed)
        - IsRunning: Boolean indicating if the trace is currently running
        - Path: The file path where the trace output is stored
        - MaxSize: Maximum size of the trace file in megabytes (0=unlimited)
        - StopTime: DateTime when the trace is scheduled to stop, or null if running indefinitely
        - MaxFiles: Maximum number of rollover files (0=unlimited)
        - IsRowset: Boolean indicating if trace output is written as rowset
        - IsRollover: Boolean indicating if rollover file creation is enabled
        - IsShutdown: Boolean indicating if trace will stop on server shutdown
        - IsDefault: Boolean indicating if this is the default system trace
        - BufferCount: Number of in-memory buffers allocated for the trace
        - BufferSize: Size of each buffer in kilobytes
        - FilePosition: Current file position for trace output
        - ReaderSpid: Server process ID reading the trace (SPID)
        - StartTime: DateTime when the trace was started
        - LastEventTime: DateTime of the most recent trace event
        - EventCount: Number of events captured by the trace
        - DroppedEventCount: Number of events dropped due to buffer limitations

        Additional properties available but excluded from default view:
        - RemotePath: UNC path to the trace file for remote access (null if Path is empty)
        - Parent: Reference to the Microsoft.SqlServer.Management.Smo.Server object
        - SqlCredential: The credentials used to connect to the instance

        Use Select-Object * to access all properties.

    .LINK
        https://dbatools.io/Start-DbaTrace

    .EXAMPLE
        PS C:\> Start-DbaTrace -SqlInstance sql2008

        Starts all traces on sql2008

    .EXAMPLE
        PS C:\> Start-DbaTrace -SqlInstance sql2008 -Id 1

        Starts all trace with ID 1 on sql2008

    .EXAMPLE
        PS C:\> Get-DbaTrace -SqlInstance sql2008 | Out-GridView -PassThru | Start-DbaTrace

        Starts selected traces on sql2008

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
                Stop-Function -Message "The default trace on $server cannot be started. Use Set-DbaSpConfigure to turn it on." -Continue
            }

            $sql = "EXEC sp_trace_setstatus $traceid, 1"
            if ($Pscmdlet.ShouldProcess($traceid, "Starting the TraceID on $server")) {
                try {
                    $server.Query($sql)
                    Get-DbaTrace -SqlInstance $server -Id $traceid
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -Continue
                    return
                }
            }
        }
    }
}