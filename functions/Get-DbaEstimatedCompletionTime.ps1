Function Get-DbaEstimatedCompletionTime
{
<#
.SYNOPSIS
Gets completion time information for queries
	
.DESCRIPTION
Gets completion time information for queries
	
.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
SqlCredential object used to connect to the SQL Server as a different user.

.PARAMETER Databases
Get queries for specific databases.

.PARAMETER Exclude
Get queries for all databases except databases entered through this parameter.

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages.

.NOTES
Tags: Database
dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
https://dbatools.io/Get-DbaEstimatedCompletionTime

.EXAMPLE
Get-DbaEstimatedCompletionTime -SqlInstance sql2016
	
Gets estimated completion times for queries performed against the entire server
	
.EXAMPLE
Get-DbaEstimatedCompletionTime -SqlInstance sql2016 | Select *
	
Gets estimated completion times for queries performed against the entire server PLUS the SQL query text of each command

.EXAMPLE
Get-DbaEstimatedCompletionTime -SqlInstance sql2016 -Databases Northwind,pubs,Adventureworks2014

Gets estimated completion times for queries performed against the Northwind, pubs, and Adventureworks2014 databases

#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[PsCredential]$SqlCredential,
		[switch]$Silent
	)
	
	DynamicParam
	{
		if ($SqlInstance)
		{
			Get-ParamSqlDatabases -SqlServer $SqlInstance[0] -SqlCredential $SqlCredential
		}
	}
	
	BEGIN
	{
		# Convert from RuntimeDefinedParameter object to regular array
		$databases = $psboundparameters.Databases
		$exclude = $psboundparameters.Exclude
		
		$sql = "SELECT
				DB_NAME(r.database_id) as [Database],
				USER_NAME(r.user_id) as [Login],
				Command,
				start_time as StartTime,
	            percent_complete as PercentComplete,
	            CAST(((DATEDIFF(s,start_time,GetDate()))/3600) as varchar) + ' hour(s), '
	                  + CAST((DATEDIFF(s,start_time,GetDate())%3600)/60 as varchar) + 'min, '
	                  + CAST((DATEDIFF(s,start_time,GetDate())%60) as varchar) + ' sec' as RunningTime,
	            CAST((estimated_completion_time/3600000) as varchar) + ' hour(s), '
	                  + CAST((estimated_completion_time %3600000)/60000 as varchar) + 'min, '
	                  + CAST((estimated_completion_time %60000)/1000 as varchar) + ' sec' as EstimatedTimeToGo,
	            dateadd(second,estimated_completion_time/1000, getdate()) as EstimatedCompletionTime,
				s.Text
				FROM sys.dm_exec_requests r
				CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) s"
	}
	
	PROCESS
	{
		foreach ($instance in $SqlInstance)
		{
			Write-Message -Level Verbose -Message "Connecting to $instance"
			try
			{
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $SqlCredential
				
			}
			catch
			{
				Stop-Function -Message "Can't connect to $instance. Moving on." -Continue
			}
			
			if ($databases)
			{
				$includedatabases = $databases -join "','"
				$sql = "$sql WHERE DB_NAME(r.database_id) in ('$includedatabases')"
			}
			
			if ($exclude)
			{
				$excludedatabases = $exclude -join "','"
				$sql = "$sql WHERE DB_NAME(r.database_id) not in ('$excludedatabases')"
			}
			
			Write-Message -Level Debug -Message $sql
			#Invoke-Sqlcmd2 -ServerInstance $instance -Credential $SqlCredential -Query $sql | Select-DefaultView -ExcludeProperty Text
			foreach ($row in (Invoke-Sqlcmd2 -ServerInstance $instance -Credential $SqlCredential -Query $sql))
			{
				<#
				$start = Get-Date "$($row.StartTime)"
				$timespan = New-TimeSpan -Start $start -End (Get-Date)
				$totalsecs = [timespan]::FromSeconds($timespan.TotalSeconds)
				$runningelapsed = "{0:HH:mm:ss}" -f ([datetime]$totalsecs.Ticks)
				
				$end = Get-Date "$($row.EstimatedCompletionTime)"
				$timespan = New-TimeSpan -Start (Get-Date) -End $end
				$totalsecs = [timespan]::fromseconds($timespan.TotalSeconds)
				$estimated = "{0:HH:mm:ss}" -f ([datetime]$totalsecs.Ticks)
				#>
				
				[pscustomobject]@{
					ComputerName = $server.NetName
					InstanceName = $server.ServiceName
					SqlInstance = $server.DomainInstanceName
					Database = $row.Database
					Login = $row.Login
					Command = $row.Command
					PercentComplete = $row.PercentComplete
					StartTime = $row.StartTime
					RunningTime = $row.RunningTime # $runningelapsed
					EstimatedTimeToGo = $row.EstimatedTimeToGo # $estimated
					EstimatedCompletionTime = $row.EstimatedCompletionTime
					Text = $row.Text
				} | Select-DefaultView -ExcludeProperty Text
			}
		}
	}
}