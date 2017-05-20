Function Get-DbaExecutionPlan
{
<#
.SYNOPSIS
Gets execution plans and metadata
	
.DESCRIPTION
Gets execution plans and metadata. Can pipe to Export-DbaExecutionPlan :D
	
Thanks to 
	https://www.simple-talk.com/sql/t-sql-programming/dmvs-for-query-plan-metadata/
	and
	http://www.scarydba.com/2017/02/13/export-plans-cache-sqlplan-file/
for the idea and query.
	
.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Databases
Return restore information for only specific databases. These are only the databases that currently exist on the server.
	
.PARAMETER Exclude
Return restore information for all but these specific databases

.PARAMETER SinceCreation
Datetime object used to narrow the results to a date

.PARAMETER SinceLastExecution
Datetime object used to narrow the results to a date

.PARAMETER ExcludeEmptyQueryPlan
Exclude results with empty query plan

.PARAMETER Force
Returns a ton of raw information about the execution plans
	
.NOTES
Tags: Performance
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Get-DbaExecutionPlan

.EXAMPLE
Get-DbaExecutionPlan -SqlInstance sqlserver2014a

Gets all execution plans on  sqlserver2014a

.EXAMPLE   
Get-DbaExecutionPlan -SqlInstance sqlserver2014a -Databases db1, db2 -SinceLastExecution '7/1/2016 10:47:00'

Gets all execution plans for databases db1 and db2 on sqlserve2014a since July 1, 2016 at 10:47 AM.
	
.EXAMPLE   
Get-DbaExecutionPlan -SqlInstance sqlserver2014a, sql2016 -Exclude db1 | Format-Table

Gets execution plan info for all databases except db1 on sqlserver2014a and sql2016 and makes the output pretty

.EXAMPLE   
Get-DbaExecutionPlan -SqlInstance sql2014 -Databases AdventureWorks2014, pubs -Force

Gets super detailed information for execution plans on only for AdventureWorks2014 and pubs
	
#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PsCredential]$SqlCredential,
		[datetime]$SinceCreation,
		[datetime]$SinceLastExecution,
		[switch]$ExcludeEmptyQueryPlan,
		[switch]$Force
	)
	

	
	BEGIN
	{
		# Convert from RuntimeDefinedParameter object to regular array
		$databases = $psboundparameters.Databases
		$exclude = $psboundparameters.Exclude
		
		if ($SinceCreation -ne $null)
		{
			$SinceCreation = $SinceCreation.ToString("yyyy-MM-dd HH:mm:ss")
		}
		
		if ($SinceLastExecution -ne $null)
		{
			$SinceLastExecution = $SinceLastExecution.ToString("yyyy-MM-dd HH:mm:ss")
		}
	}
	
	PROCESS
	{
		foreach ($instance in $sqlinstance)
		{
			try
			{
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $Credential
				
				if ($server.VersionMajor -lt 9)
				{
					Write-Warning "SQL Server 2000 not supported"
					continue
				}
				
				if ($force -eq $true)
				{
					$select = "SELECT * "
				}
				else
				{
					$select = "SELECT DB_NAME(deqp.dbid) as DatabaseName, OBJECT_NAME(deqp.objectid) as ObjectName, 
					detqp.query_plan AS SingleStatementPlan, 
					deqp.query_plan AS BatchQueryPlan,
					ROW_NUMBER() OVER ( ORDER BY Statement_Start_offset ) AS QueryPosition,
					sql_handle as SqlHandle,
					plan_handle as PlanHandle,
					creation_time as CreationTime,
					last_execution_time as LastExecutionTime"
				}
				
				$from = " FROM sys.dm_exec_query_stats deqs
				        CROSS APPLY sys.dm_exec_text_query_plan(deqs.plan_handle,
							deqs.statement_start_offset,
							deqs.statement_end_offset) AS detqp
				        CROSS APPLY sys.dm_exec_query_plan(deqs.plan_handle) AS deqp
				        CROSS APPLY sys.dm_exec_sql_text(deqs.plan_handle) AS execText"
				
				if ($exclude.length -gt 0 -or $databases.length -gt 0 -or $SinceCreation.length -gt 0 -or $SinceLastExecution.length -gt 0 -or $ExcludeEmptyQueryPlan -eq $true)
				{
					$where = " WHERE "
				}
				
				$wherearray = @()
				
				if ($databases.length -gt 0)
				{
					$dblist = $databases -join "','"
					$wherearray += " DB_NAME(deqp.dbid) in ('$dblist') "
				}
				
				if ($SinceCreation -ne $null)
				{
					Write-Verbose "Adding creation time"
					$wherearray += " creation_time >= '$SinceCreation' "
				}
				
				if ($SinceLastExecution -ne $null)
				{
					Write-Verbose "Adding last exectuion time"
					$wherearray += " last_execution_time >= '$SinceLastExecution' "
				}
				
				if ($exclude.length -gt 0)
				{
					$dblist = $exclude -join "','"
					$wherearray += " DB_NAME(deqp.dbid) not in ('$dblist') "
				}
				
				if ($ExcludeEmptyQueryPlan)
				{
					$wherearray += " detqp.query_plan is not null"
				}
				
				if ($where.length -gt 0)
				{
					$wherearray = $wherearray -join " and "
					$where = "$where $wherearray"
				}
				
				$sql = "$select $from $where"
				Write-Debug $sql
				
				if ($Force -eq $true)
				{
					$server.ConnectionContext.ExecuteWithResults($sql).Tables.Rows
				}
				
				$datatable = $server.ConnectionContext.ExecuteWithResults($sql).Tables
				
				foreach ($row in ($datatable.Rows))
				{
					$simple = ([xml]$row.SingleStatementPlan).ShowPlanXML.BatchSequence.Batch.Statements.StmtSimple
					$sqlhandle = "0x"; $row.sqlhandle | ForEach-Object { $sqlhandle += ("{0:X}" -f $_).PadLeft(2, "0") }
					$planhandle = "0x"; $row.planhandle | ForEach-Object { $planhandle += ("{0:X}" -f $_).PadLeft(2, "0") }
					
					[pscustomobject]@{
						ComputerName = $server.NetName
						InstanceName = $server.ServiceName
						SqlInstance = $server.DomainInstanceName
						DatabaseName = $row.DatabaseName
						ObjectName = $row.ObjectName
						QueryPosition = $row.QueryPosition
						SqlHandle = $SqlHandle
						PlanHandle = $PlanHandle
						CreationTime = $row.CreationTime
						LastExecutionTime = $row.LastExecutionTime
						StatementCondition = ([xml]$row.SingleStatementPlan).ShowPlanXML.BatchSequence.Batch.Statements.StmtCond
						StatementSimple = $simple
						StatementId = $simple.StatementId
						StatementCompId = $simple.StatementCompId
						StatementType = $simple.StatementType
						RetrievedFromCache = $simple.RetrievedFromCache
						StatementSubTreeCost = $simple.StatementSubTreeCost
						StatementEstRows = $simple.StatementEstRows
						SecurityPolicyApplied = $simple.SecurityPolicyApplied
						StatementOptmLevel = $simple.StatementOptmLevel
						QueryHash = $simple.QueryHash
						QueryPlanHash = $simple.QueryPlanHash
						StatementOptmEarlyAbortReason = $simple.StatementOptmEarlyAbortReason
						CardinalityEstimationModelVersion = $simple.CardinalityEstimationModelVersion
						ParameterizedText = $simple.ParameterizedText
						StatementSetOptions = $simple.StatementSetOptions
						QueryPlan = $simple.QueryPlan
						BatchConditionXml = ([xml]$row.BatchQueryPlan).ShowPlanXML.BatchSequence.Batch.Statements.StmtCond
						BatchSimpleXml = ([xml]$row.BatchQueryPlan).ShowPlanXML.BatchSequence.Batch.Statements.StmtSimple
						BatchQueryPlanRaw = [xml]$row.BatchQueryPlan
						SingleStatementPlanRaw = [xml]$row.SingleStatementPlan
					} | Select-DefaultView -ExcludeProperty BatchQueryPlan, SingleStatementPlan, BatchConditionXmlRaw, BatchQueryPlanRaw, SingleStatementPlanRaw
				}
			}
			catch
			{
				# Will fix this tomorrow, Fred ;)
				Write-Warning $_.Exception
			}
		}
	}
}
