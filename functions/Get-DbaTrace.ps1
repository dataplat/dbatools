function Get-DbaTrace {
    <#
        .SYNOPSIS
        Gets a list of trace(s) from specified SQL Server Instance

        .DESCRIPTION
        This function returns a list of Traces on a SQL Server Instance and identify the default Trace File

        .PARAMETER SqlInstance
        A SQL Server instance to connect to

        .PARAMETER SqlCredential
        A credential to use to connect to the SQL Instance rather than using Windows Authentication

        .PARAMETER Id
        The id(s) of the Trace

        .PARAMETER Default
        Switch that will only return the information for the default system trace

        .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
        Tags: Security, Trace

        Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com

        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: MIT https://opensource.org/licenses/MIT

        .EXAMPLE
        Get-DbaTrace -SqlInstance sql2016

        Lists all the tracefiles on the sql2016 SQL Server.

        .EXAMPLE
        Get-DbaTrace -SqlInstance sql2016 -Default

        Lists the default trace information on the sql2016 SQL Server.

#>
    [CmdletBinding()]
    Param (
        [parameter(Position = 0, Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int[]]$Id,
        [switch]$Default,
        [switch][Alias('Silent')]
        $EnableException
    )
    begin {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Alias Get-DbaTraceFile
        
        # A Microsoft.SqlServer.Management.Trace.TraceServer class exists but is buggy
        # and requires x86 PowerShell. So we'll go with T-SQL.
        $sql = "SELECT id, status, path, max_size, stop_time, max_files, is_rowset, is_rollover, is_shutdown, is_default, buffer_count, buffer_size, file_position, reader_spid, start_time, last_event_time, event_count, dropped_event_count FROM sys.traces"
        
        if ($Id) {
            $idstring = $Id -join ","
            $sql = "$sql WHERE id in ($idstring)"
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                return
            }
            
            try {
                $results = $server.Query($sql)
            }
            catch {
                Stop-Function -Message "Issue collecting trace data on $server" -Target $server -ErrorRecord $_
            }
            
            if ($Default) {
                $results = $results | Where-Object { $_.is_default }
            }
            
            foreach ($row in $results) {
                if ($row.Path.ToString().Length -gt 0) {
                    $remotefile = Join-AdminUnc -servername $server.NetName -filepath $row.path
                }
                else {
                    $remotefile = $null
                }
                
                [PSCustomObject]@{
                    ComputerName             = $server.NetName
                    InstanceName             = $server.ServiceName
                    SqlInstance              = $server.DomainInstanceName
                    Id                       = $row.id
                    Status                   = $row.status
                    IsRunning                = ($row.status -eq 1)
                    Path                     = $row.path
                    RemotePath               = $remotefile
                    MaxSize                  = $row.max_size
                    StopTime                 = $row.stop_time
                    MaxFiles                 = $row.max_files
                    IsRowset                 = $row.is_rowset
                    IsRollover               = $row.is_rollover
                    IsShutdown               = $row.is_shutdown
                    IsDefault                = $row.is_default
                    BufferCount              = $row.buffer_count
                    BufferSize               = $row.buffer_size
                    FilePosition             = $row.file_position
                    ReaderSpid               = $row.reader_spid
                    StartTime                = $row.start_time
                    LastEventTime            = $row.last_event_time
                    EventCount               = $row.event_count
                    DroppedEventCount        = $row.dropped_event_count
                    Parent                   = $server
                    SqlCredential            = $SqlCredential
                } | Select-DefaultView -ExcludeProperty Parent, RemotePath, RemoStatus, SqlCredential
            }
        }
    }
}