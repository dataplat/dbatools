Function Get-DbaQueryExecutionTime
{
<# 
.SYNOPSIS 
Displays Stored Procedures and Ad hoc queries with the highest execution times.  Works on SQL Server 2008 and above.

.DESCRIPTION 
Quickly find slow query executions within a database.  Results will include stored procedures and individual SQL statements.

.PARAMETER SqlInstance
Allows you to specify a comma separated list of servers to query.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$cred = Get-Credential, this pass this $cred to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER MaxResultsPerDb
Allows you to limit the number of results returned, as many systems can have very large amounts of query plans.  Default value is 100 results.

.PARAMETER MinExecs
Allows you to limit the scope to queries that have been executed a minimum number of time. Default value is 100 executions.

.PARAMETER MinExecMs
Allows you to limit the scope to queries with a specified average execution time.  Default value is 500 (ms).

.PARAMETER NoSystemDb
Allows you to suppress output on system databases

.NOTES 
Author: Brandon Abshire, netnerds.net
Tags: Query, Performance

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK 
https://dbatools.io/Get-DbaQueryExecutionTime

.EXAMPLE   
Get-DbaQueryExecutionTime -SqlServer sql2008, sqlserver2012
Return the top 100 slowest stored procedures or statements for servers sql2008 and sqlserver2012.

.EXAMPLE   
Get-DbaQueryExecutionTime -SqlServer sql2008 -Database TestDB
Return the top 100 slowest stored procedures or statements on server sql2008 for only the TestDB database.

.EXAMPLE   
Get-DbaQueryExecutionTime -SqlServer sql2008 -Database TestDB -MaxResultsPerDb 100 -MinExecs 200 -MinExecMs 1000
Return the top 100 slowest stored procedures or statements on server sql2008 for only the TestDB database, 
limiting results to queries with more than 200 total executions and an execution time over 1000ms or higher.


#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer", "SqlServers")]
		[string[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[parameter(Position = 1, Mandatory = $false)]
		[int]$MaxResultsPerDb = 100,
		[parameter(Position = 2, Mandatory = $false)]
		[int]$MinExecs = 100,
		[parameter(Position = 3, Mandatory = $false)]
		[int]$MinExecMs = 500,
		[parameter(Position = 4, Mandatory = $false)]
		[switch]$NoSystemDb
	)
	
	DynamicParam
	{
		if ($SqlInstance)
		{
			return Get-ParamSqlDatabases -SqlServer $SqlInstance[0] -SqlCredential $SqlCredential
		}
	}
	
	BEGIN
	{
		
		$databases = $psboundparameters.Databases
		$exclude = $psboundparameters.Exclude
		$MaxResultsPerDb = $psboundparameters.MaxResultsPerDb
		$MinExecs = $psboundparameters.MinExecs
		$MinExecMs = $psboundparameters.MinExecMs
		
		
		$sql = ";With StatsCTE AS 
            (
			    SELECT 
                    DB_NAME() as DatabaseName, 
                    (total_worker_time / execution_count) / 1000 AS AvgExec_ms ,
                    execution_count ,
                    max_worker_time / 1000 AS MaxExec_ms ,
                    OBJECT_NAME(object_id) as ProcName,
                    object_id,
                    type_desc,
                    cached_time,
                    last_execution_time,
                    total_worker_time / 1000 as total_worker_time_ms,
                    total_elapsed_time / 1000 as total_elapsed_time_ms,
                    OBJECT_NAME(object_id) as SQLText,
			        OBJECT_NAME(object_id) as full_statement_text
                FROM    sys.dm_exec_procedure_stats
                WHERE   database_id = DB_ID()"
		
		If ($MinExecs) { $sql += "`n AND execution_count >= " + $MinExecs }
		If ($MinExecMs) { $sql += "`n AND (total_worker_time / execution_count) / 1000 >= " + $MinExecMs }
		
		$sql += "`n UNION
            SELECT
		        DB_NAME() as DatabaseName, 
                ( qs.total_worker_time / qs.execution_count ) / 1000 AS AvgExec_ms ,
                qs.execution_count ,
                qs.max_worker_time / 1000 AS MaxExec_ms ,
                OBJECT_NAME(st.objectid) as ProcName,
                   st.objectid as [object_id],
                   'STATEMENT' as type_desc,
                   '1901-01-01 00:00:00' as cached_time,
                    qs.last_execution_time,
                    qs.total_worker_time / 1000 as total_worker_time_ms,
                    qs.total_elapsed_time / 1000 as total_elapsed_time_ms,
                    SUBSTRING(st.text, (qs.statement_start_offset/2)+1, 50) + '...' AS SQLText,
			        SUBSTRING(st.text, (qs.statement_start_offset/2)+1,   
				        ((CASE qs.statement_end_offset  
				          WHEN -1 THEN DATALENGTH(st.text)  
				         ELSE qs.statement_end_offset  
				         END - qs.statement_start_offset)/2) + 1) AS full_statement_text
            FROM    sys.dm_exec_query_stats qs
            CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) as pa
            CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) as st
            WHERE st.dbid = DB_ID() OR (pa.attribute = 'dbid' and pa.value = DB_ID())"
		
		If ($MinExecs) { $sql += "`n AND execution_count >= " + $MinExecs }
		If ($MinExecMs) { $sql += "`n AND (total_worker_time / execution_count) / 1000 >= " + $MinExecMs }
		
		If ($MaxResultsPerDb) { $sql += ")`n SELECT TOP " + $MaxResultsPerDb }
		Else
		{
			$sql += ")
                        SELECT "
		}
		
		$sql += "`n     DatabaseName,
	                    AvgExec_ms,
	                    execution_count,
	                    MaxExec_ms,
	                    ProcName,
	                    object_id,
	                    type_desc,
	                    cached_time,
	                    last_execution_time,
	                    total_worker_time_ms,
	                    total_elapsed_time_ms,
                        SQLText,
	                    full_statement_text
                    FROM StatsCTE "
		
		If ($MinExecs -or $MinExecMs)
		{
			$sql += "`n WHERE `n"
			
			If ($MinExecs)
			{
				$sql += " execution_count >= " + $MinExecs
			}
			
			If ($MinExecMs -gt 0 -and $MinExecs)
			{
				$sql += "`n AND AvgExec_ms >= " + $MinExecMs
			}
			elseif ($MinExecMs)
			{
				$sql += "`n AvgExecs_ms >= " + $MinExecMs
			}
		}
		
		
		$sql += "`n ORDER BY AvgExec_ms DESC"
	}
	
	PROCESS
	{
		if (!$MaxResultsPerDb -and !$MinExecs -and !$MinExecMs)
		{
			Write-Warning "Results may take time, depending on system resources and size of buffer cache."
			Write-Warning "Consider limiting results using -MaxResultsPerDb, -MinExecs and -MinExecMs parameters."
		}
		
		foreach ($instance in $SqlInstance)
		{
			Write-Verbose "Attempting to connect to $instance"
			try
			{
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $SqlCredential
			}
			catch
			{
				Write-Warning "Can't connect to $instance or access denied. Skipping."
				continue
			}
			
			if ($server.versionMajor -lt 10)
			{
				Write-Warning "This function does not support versions lower than SQL Server 2008 (v10). Skipping server $instance."
				
				Continue
			}
			
			
			$dbs = $server.Databases
			
			if ($databases.count -gt 0)
			{
				$dbs = $dbs | Where-Object { $databases -contains $_.Name }
			}
			
			if ($NoSystemDb)
			{
				$dbs = $dbs | Where-Object { $_.IsSystemObject -eq $false }
			}
			
			if ($exclude.count -gt 0)
			{
				$dbs = $dbs | Where-Object { $exclude -notcontains $_.Name }
			}
			
			foreach ($db in $dbs)
			{
				Write-Verbose "Processing $db on $instance"
				
				if ($db.IsAccessible -eq $false)
				{
					Write-Warning "The database $db is not accessible. Skipping database."
					Continue
				}
				
				foreach ($row in $db.ExecuteWithResults($sql).Tables[0])
				{
					[PSCustomObject]@{
						ComputerName = $server.NetName
						InstanceName = $server.ServiceName
						SqlInstance = $server.DomainInstanceName
						Database = $row.DatabaseName
						ProcName = $row.ProcName
						ObjectID = $row.object_id
						Type_Desc = $row.type_desc
						Executions = $row.Execution_Count
						AvgExec_ms = $row.AvgExec_ms
						MaxExec_ms = $row.MaxExec_ms
						Cached_Time = $row.cached_time
						Last_Exec_Time = $row.last_execution_time
						Total_Worker_Time_ms = $row.total_worker_time_ms
						Total_Elapsed_Time_ms = $row.total_elapsed_time_ms
						SQLText = $row.SQLText
						Full_Statement_Text = $row.full_statement_text
					} | Select-DefaultView -ExcludeProperty Full_Statement_Text
				}
			}
		}
	}
}
