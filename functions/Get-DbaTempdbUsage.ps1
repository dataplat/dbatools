Function Get-DbaTempdbUsage {
    <#
    .SYNOPSIS
    Gets Tempdb usage for running queries.
	
    .DESCRIPTION
    This function queries DMVs for running sessions using Tempdb and returns results if those sessions have user or internal space allocated or deallocated against them.
	
    .PARAMETER SqlServer
    The SQL Instance you are querying against.

    .PARAMETER Credential
    If you want to use alternative credentials to connect to the server.

    .PARAMETER Detailed
    Returns additional information from the DMVs, such as:
    -- program_name running the session.
    -- login_time of the session.
	
    .NOTES
    dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
    Copyright (C) 2016 Chrissy LeMaire
    This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
    You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

    .LINK
    # TODO: 

    .EXAMPLE
    Get-DbaTempdbUsage -SqlServer "localhost\SQLDEV2K14"

    .EXAMPLE
    Get-DbaTempdbUsage -SqlServer "localhost\SQLDEV2K14" -Detailed

    #>
    	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string]$SqlServer,
		[object]$SqlCredential,
		[switch]$Detailed
	)
	
	BEGIN
	{
		$server = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential -RegularUser
		$computername = $server.ComputerNamePhysicalNetBIOS
	}
	
	PROCESS
	{
        if ($server.VersionMajor -le 9)
        {
            Write-Warning "This function is only supported in SQL Server 2008 or higher."
            break
        }
        
        if ($Detailed -eq $true)
        {
            $sql = 'SELECT t.session_id AS spid, r.command AS statement_command, r.start_time, t.user_objects_alloc_page_count * 8 AS user_object_allocated_space, t.user_objects_dealloc_page_count * 8 AS user_object_deallocated_space, t.internal_objects_alloc_page_count * 8 AS internal_object_allocated_space, t.internal_objects_dealloc_page_count * 8 AS internal_object_deallocated_space, r.reads AS request_reads, r.writes AS request_writes, r.logical_reads AS request_logical_reads, r.cpu_time AS request_cpu_time, s.is_user_process, s.[status], DB_NAME(s.database_id) AS originating_database_name, s.login_name, s.original_login_name, s.nt_domain , s.nt_user_name, s.[host_name], s.[program_name], s.login_time, s.last_request_start_time, s.last_request_end_time FROM sys.dm_db_session_space_usage AS t INNER JOIN sys.dm_exec_sessions AS s ON s.session_id = t.session_id INNER JOIN sys.dm_exec_requests AS r ON r.session_id = s.session_id WHERE t.user_objects_alloc_page_count + t.user_objects_dealloc_page_count + t.internal_objects_alloc_page_count + t.internal_objects_dealloc_page_count > 0'
            $datatable = $server.ConnectionContext.ExecuteWithResults($sql).Tables
            return $datatable
        }
        else 
        {
            $sql = 'SELECT t.session_id AS spid, r.command AS statement_command, r.start_time, t.user_objects_alloc_page_count * 8 AS user_object_allocated_space, t.user_objects_dealloc_page_count * 8 AS user_object_deallocated_space, t.internal_objects_alloc_page_count * 8 AS internal_object_allocated_space, t.internal_objects_dealloc_page_count * 8 AS internal_object_deallocated_space, r.reads AS request_reads, r.writes AS request_writes, r.logical_reads AS request_logical_reads, r.cpu_time AS request_cpu_time, s.is_user_process, s.[status], DB_NAME(s.database_id) AS originating_database_name, s.login_name FROM sys.dm_db_session_space_usage AS t INNER JOIN sys.dm_exec_sessions AS s ON s.session_id = t.session_id INNER JOIN sys.dm_exec_requests AS r ON r.session_id = s.session_id WHERE t.user_objects_alloc_page_count + t.user_objects_dealloc_page_count + t.internal_objects_alloc_page_count + t.internal_objects_dealloc_page_count > 0;'
            $datatable = $server.ConnectionContext.ExecuteWithResults($sql).Tables
            return $datatable
        }
	}
	
	END
	{
		$server.ConnectionContext.Disconnect()
	}
}
