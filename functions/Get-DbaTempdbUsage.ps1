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
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]$SqlCredential = [System.Management.Automation.PSCredential]::Empty,
		[switch]$Silent
	)
	
	process {
		foreach ($instance in $SqlInstance) {
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			if ($server.VersionMajor -le 9) {
				Stop-Function -Message "This function is only supported in SQL Server 2008 or higher." -Continue
			}
			
            $sql = "SELECT  SERVERPROPERTY('MachineName') AS ComputerName,
        ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
        SERVERPROPERTY('ServerName') AS SqlInstance,
        t.session_id AS Spid,
        r.command AS StatementCommand,
        SUBSTRING(   est.[text],
                     (r.statement_start_offset / 2) + 1,
                     ((CASE r.statement_end_offset
                            WHEN-1
                            THEN DATALENGTH(est.[text])
                            ELSE
                            r.statement_end_offset
                       END - r.statement_start_offset
                      ) / 2
                     ) + 1
                 ) AS QueryText,
        QUOTENAME(DB_NAME(r.database_id)) + N'.' + QUOTENAME(OBJECT_SCHEMA_NAME(est.objectid, est.dbid)) + N'.'
        + QUOTENAME(OBJECT_NAME(est.objectid, est.dbid)) AS ProcedureName,
        r.start_time AS StartTime,
        tdb.UserObjectAllocated * 8 AS CurrentUserAllocatedKB,
        (t.user_objects_alloc_page_count + tdb.UserObjectAllocated) * 8 AS TotalUserAllocatedKB,
        tdb.UserObjectDeallocated * 8 AS UserDeallocatedKB,
        (t.user_objects_dealloc_page_count + tdb.UserObjectDeallocated) * 8 AS TotalUserDeallocatedKB,
        tdb.InternalObjectAllocated * 8 AS InternalAllocatedKB,
        (t.internal_objects_alloc_page_count + tdb.InternalObjectAllocated) * 8 AS TotalInternalAllocatedKB,
        tdb.InternalObjectDeallocated * 8 AS InternalDeallocatedKB,
        (t.internal_objects_dealloc_page_count + tdb.InternalObjectDeallocated) * 8 AS TotalInternalDeallocatedKB,
        r.reads AS RequestedReads,
        r.writes AS RequestedWrites,
        r.logical_reads AS RequestedLogicalReads,
        r.cpu_time AS RequestedCPUTime,
        s.is_user_process AS IsUserProcess,
        s.[status] AS [Status],
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
FROM    sys.dm_db_session_space_usage AS t
INNER JOIN sys.dm_exec_sessions AS s
    ON s.session_id = t.session_id
LEFT JOIN sys.dm_exec_requests AS r
    ON r.session_id = s.session_id
LEFT JOIN
          (   SELECT    _tsu.session_id,
                        _tsu.request_id,
                        SUM(_tsu.user_objects_alloc_page_count)       AS UserObjectAllocated,
                        SUM(_tsu.user_objects_dealloc_page_count)     AS UserObjectDeallocated,
                        SUM(_tsu.internal_objects_alloc_page_count)   AS InternalObjectAllocated,
                        SUM(_tsu.internal_objects_dealloc_page_count) AS InternalObjectDeallocated
              FROM      tempdb.sys.dm_db_task_space_usage AS _tsu
              GROUP BY  _tsu.session_id,
                        _tsu.request_id
          ) AS tdb
    ON  tdb.session_id = r.session_id
   AND  tdb.request_id = r.request_id
OUTER APPLY sys.dm_exec_sql_text(r.[sql_handle]) AS est
WHERE   t.session_id != @@SPID
  AND   (tdb.UserObjectAllocated - tdb.UserObjectDeallocated + tdb.InternalObjectAllocated - tdb.InternalObjectDeallocated) != 0
OPTION (RECOMPILE);"
			
			$server.ConnectionContext.ExecuteWithResults($sql).Tables
		}
	}
}
