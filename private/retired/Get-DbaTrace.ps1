function Get-DbaTrace {
    <#
    .SYNOPSIS
        Retrieves SQL Server trace information including status, file paths, and configuration details

    .DESCRIPTION
        Queries the sys.traces system view to return detailed information about active and configured traces on a SQL Server instance. This includes trace status, file locations, buffer settings, event counts, and timing data. Commonly used for monitoring trace activity, auditing trace configurations, and locating the default system trace file for troubleshooting and compliance purposes.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Id
        Specifies the trace ID(s) to retrieve information for. Accepts single values or arrays of trace IDs.
        Use this when you need to check specific traces instead of retrieving all configured traces on the instance.

    .PARAMETER Default
        Returns only the default system trace (usually trace ID 1) which SQL Server automatically creates for auditing DDL operations.
        Use this when you need to locate the default trace file for troubleshooting schema changes, login events, or security auditing.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Trace
        Author: Garry Bargsley (@gbargsley), blog.garrybargsley.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaTrace

    .OUTPUTS
        PSCustomObject

        Returns one object per trace found on the SQL Server instance. When -Id is specified, only traces matching those IDs are returned. When -Default is specified, only the default trace is returned.

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

        The properties RemotePath, Parent, and SqlCredential are also available but excluded from default view. Use Select-Object * to access all properties.

    .EXAMPLE
        PS C:\> Get-DbaTrace -SqlInstance sql2016

        Lists all the trace files on the sql2016 SQL Server.

    .EXAMPLE
        PS C:\> Get-DbaTrace -SqlInstance sql2016 -Default

        Lists the default trace information on the sql2016 SQL Server.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int[]]$Id,
        [switch]$Default,
        [switch]$EnableException
    )
    begin {

        # A Microsoft.SqlServer.Management.Trace.TraceServer class exists but is buggy
        # and requires x86 PowerShell. So we'll go with T-SQL.
        $sql = "SELECT id, status, path, max_size, stop_time, max_files, is_rowset, is_rollover, is_shutdown, is_default, buffer_count, buffer_size, file_position, reader_spid, start_time, last_event_time, event_count, dropped_event_count FROM sys.traces"

        if ($Id) {
            $idstring = $Id -join ","
            $sql = "$sql WHERE id IN ($idstring)"
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $results = $server.Query($sql)
            } catch {
                Stop-Function -Message "Issue collecting trace data on $server" -Target $server -ErrorRecord $_
            }

            if ($Default) {
                $results = $results | Where-Object { $_.is_default }
            }

            foreach ($row in $results) {
                if ($row.Path.ToString().Length -gt 0) {
                    $remotefile = Join-AdminUnc -servername $server.ComputerName -filepath $row.path
                } else {
                    $remotefile = $null
                }

                [PSCustomObject]@{
                    ComputerName      = $server.ComputerName
                    InstanceName      = $server.ServiceName
                    SqlInstance       = $server.DomainInstanceName
                    Id                = $row.id
                    Status            = $row.status
                    IsRunning         = ($row.status -eq 1)
                    Path              = $row.path
                    RemotePath        = $remotefile
                    MaxSize           = $row.max_size
                    StopTime          = $row.stop_time
                    MaxFiles          = $row.max_files
                    IsRowset          = $row.is_rowset
                    IsRollover        = $row.is_rollover
                    IsShutdown        = $row.is_shutdown
                    IsDefault         = $row.is_default
                    BufferCount       = $row.buffer_count
                    BufferSize        = $row.buffer_size
                    FilePosition      = $row.file_position
                    ReaderSpid        = $row.reader_spid
                    StartTime         = $row.start_time
                    LastEventTime     = $row.last_event_time
                    EventCount        = $row.event_count
                    DroppedEventCount = $row.dropped_event_count
                    Parent            = $server
                    SqlCredential     = $SqlCredential
                } | Select-DefaultView -ExcludeProperty Parent, RemotePath, RemoStatus, SqlCredential
            }
        }
    }
}