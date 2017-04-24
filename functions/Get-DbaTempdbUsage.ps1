Function Get-DbaTempdbUsage {
    <#
    .SYNOPSIS
    Gets Tempdb usage for running queries.
	
    .DESCRIPTION
    This function queries DMVs for running sessions using Tempdb and returns results if those sessions have user or internal space allocated or deallocated against them.
	
    .PARAMETER SqlInstance
    The SQL Instance you are querying against.

    .PARAMETER SqlCredential
    If you want to use alternative credentials to connect to the server.
	
    .PARAMETER WhatIf
	Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm 
	Prompts you for confirmation before executing any changing operations within the command.
	
    .PARAMETER Silent
	Use this switch to disable any kind of verbose messages
	
    .NOTES
    dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
    Copyright (C) 2016 Chrissy LeMaire
    This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
    You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
    .LINK
    https://dbatools.io/Get-DbaTempdbUsage
    .EXAMPLE
    Get-DbaTempdbUsage -SqlInstance localhost\SQLDEV2K14
	
	Gets tempdb usage for localhost\SQLDEV2K14
    #>
	[CmdletBinding()]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[switch]$Silent
	)
	
	process {
		foreach ($instance in $SqlInstance) {
			try {
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failed to connect to: $instance" -Continue -Target $Instance
			}
			
			if ($server.VersionMajor -le 9) {
				Stop-Function -Message "This function is only supported in SQL Server 2008 or higher." -Continue
			}
			
			$sql = "SELECT SERVERPROPERTY('MachineName') AS ComputerName, 
							       ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName, 
							       SERVERPROPERTY('ServerName') AS SqlInstance, 
							       t.session_id AS Spid, 
							       r.command AS StatementCommand, 
							       r.start_time AS StartTime, 
							       t.user_objects_alloc_page_count * 8 AS UserObjectAllocatedSpace, 
							       t.user_objects_dealloc_page_count * 8 AS UserObjectDeallocatedSpace, 
							       t.internal_objects_alloc_page_count * 8 AS InternalObjectAllocatedSpace, 
							       t.internal_objects_dealloc_page_count * 8 AS InternalObjectDeallocatedSpace, 
							       r.reads AS RequestedReads, 
							       r.writes AS RequestedWrites, 
							       r.logical_reads AS RequestedLogicalReads, 
							       r.cpu_time AS RequestedCPUTime, 
							       s.is_user_process AS IsUserProcess, 
							       s.[status] AS Status, 
							       DB_NAME(r.database_id) AS [Database], 
							       s.login_name AS LoginName, 
							       s.original_login_name AS OriginalLoginName, 
							       s.nt_domain AS NTDomain, 
							       s.nt_user_name AS NTUserName, 
							       s.[host_name] AS HostName, 
							       s.[program_name] AS ProgramName, 
							       s.login_time AS LoginTime, 
							       s.last_request_start_time AS LastRequestedStartTime, 
							       s.last_request_end_time AS LastRequestedEndTime 
							FROM sys.dm_db_session_space_usage AS t 
							INNER JOIN sys.dm_exec_sessions AS s ON s.session_id = t.session_id 
							INNER JOIN sys.dm_exec_requests AS r ON r.session_id = s.session_id
							WHERE t.user_objects_alloc_page_count + t.user_objects_dealloc_page_count + t.internal_objects_alloc_page_count + t.internal_objects_dealloc_page_count > 0"
			
			$server.ConnectionContext.ExecuteWithResults($sql).Tables
		}
	}
}
