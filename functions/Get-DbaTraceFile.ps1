function Get-DbaTraceFile {
	<#
.SYNOPSIS
Gets a list of trace file(s) from specied SQL Server Instance

.DESCRIPTION
This function returns a list of Trace Files on a SQL Server Instance and identify the default Trace File

.PARAMETER SqlInstance
A SQL Server instance to connect to

.PARAMETER SqlCredential
A credeial to use to conect to the SQL Instance rather than using Windows Authentication

.PARAMETER Default
Switch that will only return the information for the default system trace

.PARAMETER Silent
Use this switch to disable any kind of verbose messages
	
.NOTES
Tags: Security, Trace

Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
Get-DbaTraceFile -SqlInstance sql2016 

Lists all the tracefiles on the sql2016 SQL Server.
	
.EXAMPLE
Get-DbaTraceFile -SqlInstance sql2016 -Default

Lists the default trace information on the sql2016 SQL Server. 
	
#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory, ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$Default,
		[switch]$Silent
	)
	
	process {
		
		foreach ($instance in $sqlinstance) {
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
				return
			}
            
			$sql = "SELECT id, status, path, max_size, stop_time, max_files, is_rowset, is_rollover, is_shutdown, is_default, buffer_count, buffer_size, file_position, reader_spid, start_time, last_event_time, event_count, dropped_event_count FROM sys.traces"

			try {
				$results = $server.Query($sql)
			}
			catch {
				Stop-Function -Message "Issue collecting trace data on $server" -Target $server -ErrorRecord $_
			}
			
            if ($Default) {
				$results = $results | Where-Object { $_.is_default }
			}
		}

		foreach ($row in $results) {
			[PSCustomObject]@{
			  ComputerName  = $server.NetName
			  InstanceName  = $server.ServiceName
			  SqlInstance   = $server.DomainInstanceName
			  Id      		= $row.id
			  Status        = $row.status
			  Path      	= $row.path
			  MaxSize    	= $row.max_size
			  StopTime      = $row.stop_time
			  MaxFiles    	= $row.max_files
			  IsRowset   	= $row.is_rowset
			  IsRollover   	= $row.is_rollover
			  IsShutdown 	= $row.is_shutdown
			  IsDefault    	= $row.is_default
			  BufferCount   = $row.buffer_count
			  BufferSize    = $row.buffer_size
			  FilePosition  = $row.file_position
			  ReaderSpid    = $row.reader_spid
			  StartTime    	= $row.start_time
			  LastEventTime = $row.last_event_time
			  EventCount    = $row.event_count
			  DroppedEventCount = $row.dropped_event_count
			} 
		}
	}
}