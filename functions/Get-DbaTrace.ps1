function Get-DbaTrace {
    <#
    .SYNOPSIS
        Gets a list of trace(s) from specified SQL Server Instance

    .DESCRIPTION
        This function returns a list of traces on a SQL Server instance and identifies the default trace file

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

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
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaTrace

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
            $sql = "$sql WHERE id in ($idstring)"
        }
    }
    process {
        foreach ($instance in $SqlInstance) {

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                return
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