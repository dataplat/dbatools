Function Export-DbaExecutionPlan
{
<#
.SYNOPSIS
Exports execution plans to disk. 
	
.DESCRIPTION
Exports execution plans to disk. Can pipe from Export-DbaExecutionPlan :D
	
Thanks to 
	https://www.simple-talk.com/sql/t-sql-programming/dmvs-for-query-plan-metadata/
	and
	http://www.scarydba.com/2017/02/13/export-plans-cache-sqlplan-file/
for the idea and query.
	
.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Database
The database(s) to process - this list is autopopulated from the server. If unspecified, all databases will be processed.

.PARAMETER Exclude
The database(s) to exclude - this list is autopopulated from the server

.PARAMETER SinceCreation
Datetime object used to narrow the results to a date

.PARAMETER SinceLastExecution
Datetime object used to narrow the results to a date

.PARAMETER Path
The directory where all of the sqlxml files will be exported

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.PARAMETER PipedObject
Internal parameter

.NOTES
Tags: Performance
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Export-DbaExecutionPlan

.EXAMPLE
Export-DbaExecutionPlan -SqlInstance sqlserver2014a

Exports all execution plans for sqlserver2014a.

.EXAMPLE   
Export-DbaExecutionPlan -SqlInstance sqlserver2014a -Database db1, db2 -SinceLastExecution '7/1/2016 10:47:00'

Exports all execution plans for databases db1 and db2 on sqlserve2014a since July 1, 2016 at 10:47 AM.
	
#>
	[cmdletbinding(SupportsShouldProcess = $true, DefaultParameterSetName = "Default")]
	Param (
		[parameter(ParameterSetName = 'NotPiped', Mandatory)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[parameter(ParameterSetName = 'NotPiped')]
		[Alias("Credential")]
		[PsCredential]$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$Exclude,
		[parameter(ParameterSetName = 'Piped', Mandatory)]
		[parameter(ParameterSetName = 'NotPiped', Mandatory)]
		[string]$Path,
		[parameter(ParameterSetName = 'NotPiped')]
		[datetime]$SinceCreation,
		[parameter(ParameterSetName = 'NotPiped')]
		[datetime]$SinceLastExecution,
		[Parameter(ParameterSetName = 'Piped', Mandatory, ValueFromPipeline)]
		[object[]]$PipedObject
	)
	
	begin
	{	
		if ($SinceCreation -ne $null)
		{
			$SinceCreation = $SinceCreation.ToString("yyyy-MM-dd HH:mm:ss")
		}
		
		if ($SinceLastExecution -ne $null)
		{
			$SinceLastExecution = $SinceLastExecution.ToString("yyyy-MM-dd HH:mm:ss")
		}
		
		function Process-Object ($object)
		{
			$instancename = $object.SqlInstance
			$dbname = $object.DatabaseName
			$queryposition = $object.QueryPosition
			$sqlhandle = "0x"; $object.sqlhandle | ForEach-Object { $sqlhandle += ("{0:X}" -f $_).PadLeft(2, "0") }
			$sqlhandle = $sqlhandle.TrimStart('0x02000000').TrimEnd('0000000000000000000000000000000000000000')
			$shortname = "$instancename-$dbname-$queryposition-$sqlhandle"
			
			foreach ($queryplan in $object.BatchQueryPlanRaw)
			{
				$filename = "$path\$shortname-batch.sqlplan"
				
				try
				{
					If ($Pscmdlet.ShouldProcess("localhost", "Writing XML file to $filename"))
					{
						$queryplan.Save($filename)
					}
				}
				catch
				{
					Write-Verbose "Skipped query plan for $filename because it is null"
				}
			}
			
			foreach ($statementplan in $object.SingleStatementPlanRaw)
			{
				$filename = "$path\$shortname.sqlplan"
				
				try
				{
					If ($Pscmdlet.ShouldProcess("localhost", "Writing XML file to $filename"))
					{
						$statementplan.Save($filename)
					}
				}
				catch
				{
					Write-Verbose "Skipped statement plan for $filename because it is null"
				}
			}
			
			If ($Pscmdlet.ShouldProcess("console", "Showing output object"))
			{
				Add-Member -InputObject $object -MemberType NoteProperty -Name OutputFile -Value $filename
				Select-DefaultView -InputObject $object -Property ComputerName, InstanceName, SqlInstance, DatabaseName, SqlHandle, CreationTime, LastExecutionTime, OutputFile
			}
		}
	}
	
	PROCESS
	{
		if (!(Test-Path $Path))
		{
			$null = New-Item -ItemType Directory -Path $Path
		}
		
		if ($PipedObject)
		{
			
			foreach ($object in $pipedobject)
			{
				Process-Object $object
				return
			}
		}
		
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
				
				$select = "SELECT DB_NAME(deqp.dbid) as DatabaseName, OBJECT_NAME(deqp.objectid) as ObjectName, 
					detqp.query_plan AS SingleStatementPlan, 
					deqp.query_plan AS BatchQueryPlan,
					ROW_NUMBER() OVER ( ORDER BY Statement_Start_offset ) AS QueryPosition,
					sql_handle as SqlHandle,
					plan_handle as PlanHandle,
					creation_time as CreationTime,
					last_execution_time as LastExecutionTime"
				
				$from = " FROM sys.dm_exec_query_stats deqs
				        CROSS APPLY sys.dm_exec_text_query_plan(deqs.plan_handle,
							deqs.statement_start_offset,
							deqs.statement_end_offset) AS detqp
				        CROSS APPLY sys.dm_exec_query_plan(deqs.plan_handle) AS deqp
				        CROSS APPLY sys.dm_exec_sql_text(deqs.plan_handle) AS execText"
				
				if ($exclude.length -gt 0 -or $Database.length -gt 0 -or $SinceCreation.length -gt 0 -or $SinceLastExecution.length -gt 0 -or $ExcludeEmptyQueryPlan -eq $true)
				{
					$where = " WHERE "
				}
				
				$wherearray = @()
				
				if ($Database.length -gt 0)
				{
					$dblist = $Database -join "','"
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
								
				$datatable = $server.ConnectionContext.ExecuteWithResults($sql).Tables
				
				foreach ($row in ($datatable.Rows))
				{
					
					$sqlhandle = "0x"; $row.sqlhandle | ForEach-Object { $sqlhandle += ("{0:X}" -f $_).PadLeft(2, "0") }
					$planhandle = "0x"; $row.planhandle | ForEach-Object { $planhandle += ("{0:X}" -f $_).PadLeft(2, "0") }
					
					$object = [pscustomobject]@{
						ComputerName = $server.NetName
						InstanceName = $server.ServiceName
						SqlInstance = $server.DomainInstanceName
						DatabaseName = $row.DatabaseName
						SqlHandle = $sqlhandle
						PlanHandle = $planhandle
						SingleStatementPlan = $row.SingleStatementPlan
						BatchQueryPlan = $row.BatchQueryPlan
						QueryPosition = $row.QueryPosition
						CreationTime = $row.CreationTime
						LastExecutionTime = $row.LastExecutionTime
						BatchQueryPlanRaw = [xml]$row.BatchQueryPlan
						SingleStatementPlanRaw = [xml]$row.SingleStatementPlan
					}
					
					Process-Object $object
				}
			}
			catch
			{
				Write-Warning $_
				continue
				# Stop-Function -Message $_.Exception -Silent $Silent -InnerErrorRecord $_ -Target $filename
			}
		}
	}
}

