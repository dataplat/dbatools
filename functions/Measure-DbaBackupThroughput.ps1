function Measure-DbaBackupThroughput
{
<#
.SYNOPSIS
Determines how quickly SQL Server is backing up databases to media.

.DESCRIPTION
Returns backup history details for some or all databases on a SQL Server. 

Output looks like this
SqlInstance     : sql2016
Database        : SharePoint_Config
AvgThroughputMB : 1.07
AvgSizeMB       : 24.17
AvgDuration     : 00:00:01.1000000
MinThroughputMB : 0.02
MaxThroughputMB : 2.26
MinBackupDate   : 8/6/2015 10:22:01 PM
MaxBackupDate   : 6/19/2016 12:57:45 PM
BackupCount     : 10

.PARAMETER SqlInstance
SqlInstance name or SMO object representing the SQL Server to connect to.
This can be a collection and receive pipeline input.

.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, current Windows login will be used.

.PARAMETER Type
By default, this command measures the speed of Full backups. You can also specify Log or Differential.

.PARAMETER Since
Datetime object used to narrow the results to a date

.PARAMETER Last
Measure only the last backup


.NOTES
Tags: DisasterRecovery, Backup
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.	

.LINK
https://dbatools.io/Measure-DbaBackupThroughput

.EXAMPLE
Measure-DbaBackupThroughput -SqlInstance sql2016

Parses every backup in msdb's backuphistory for stats on all databases

.EXAMPLE
Measure-DbaBackupThroughput -SqlInstance sql2016 -Databases AdventureWorks2014

Parses every backup in msdb's backuphistory for stats on AdventureWorks2014
	
.EXAMPLE
Measure-DbaBackupThroughput -SqlInstance sql2005 -Last

Processes the last full, diff and log backups every backup for all databases on sql2005
	
.EXAMPLE
Measure-DbaBackupThroughput -SqlInstance sql2005 -Last -Type Log
	
Processes the last log backups every backup for all databases on sql2005

.EXAMPLE
Measure-DbaBackupThroughput -SqlInstance sql2016 -Since (Get-Date).AddDays(-7)
	
Gets backup calculations for the last week
	
.EXAMPLE
Measure-DbaBackupThroughput -SqlInstance sql2016 -Since (Get-Date).AddDays(-365) -Databases bigoldb
	
Gets backup calculations, limited to the last year and only the bigoldb database

#>
	[CmdletBinding()]
	param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "Instance", "SqlServer")]
		[object[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]$SqlCredential,
		[datetime]$Since,
		[switch]$Last,
		[ValidateSet("Full", "Log", "Differential")]
		[string]$Type = "Full"
	)
	
	DynamicParam { if ($SqlInstance) { return Get-ParamSqlDatabases -SqlServer $SqlInstance[0] -SqlCredential $SqlCredential } }
	
	BEGIN
	{
		$databases = $psboundparameters.Databases
		
		if ($Since)
		{
			$Since = $Since.ToString("yyyy-MM-dd HH:mm:ss")
		}
	}
	process
	{
		foreach ($instance in $SqlInstance)
		{
			try
			{
				Write-Verbose "Connecting to $instance"
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlcredential
			}
			catch
			{
				Write-Warning "Failed to connect to $instance"
				continue
			}
			
			if (!$databases) { $databases = $server.databases.name }
						
			foreach ($database in $databases)
			{
				Write-Verbose "Getting backup history for $database"
				
				$allhistory = @()
				
				# Splatting didnt work
				if ($since)
				{	
					$histories = Get-DbaBackupHistory -SqlServer $server -Databases $database -Since $since | Where-Object Type -eq $Type
				}
				else
				{
					$histories = Get-DbaBackupHistory -SqlServer $server -Databases $database -Last:$last | Where-Object Type -eq $Type
				}
				
				foreach ($history in $histories)
				{
					$timetaken = New-TimeSpan -Start $history.Start -End $history.End
					
					if ($timetaken.TotalMilliseconds -eq 0)
					{
						$throughput = $history.TotalSizeMB
					}
					else
					{
						$throughput = $history.TotalSizeMB % $timetaken.TotalSeconds + 1
					}
					
					Add-Member -InputObject $history -MemberType Noteproperty -Name MBps -value $throughput
					
					$allhistory += $history | Select-Object ComputerName, InstanceName, SqlInstance, Database, MBps, TotalSizeMB, Start, End
				}
				
				foreach ($db in ($allhistory | Sort-Object Database | Group-Object Database))
				{
					$measuremb = $db.Group.MBps | Measure-Object -Average -Minimum -Maximum
					$measurestart = $db.Group.Start | Measure-Object -Minimum
					$measureend = $db.Group.End | Measure-Object -Maximum
					$measuresize = $db.Group.TotalSizeMB | Measure-Object -Average
					$avgduration = $db.Group | ForEach-Object { New-TimeSpan -Start $_.Start -End $_.End } | Measure-Object -Average TotalSeconds
					
					$date = Get-Date
					
					[pscustomobject]@{
						ComputerName = $db.Group.ComputerName | Select-Object -First 1
						InstanceName = $db.Group.InstanceName | Select-Object -First 1
						SqlInstance = $db.Group.SqlInstance | Select-Object -First 1
						Database = $db.Name
						AvgThroughputMB = [System.Math]::Round($measuremb.Average, 2)
						AvgSizeMB = [System.Math]::Round($measuresize.Average, 2)
						AvgDuration = New-TimeSpan -Start $date -End $date.AddSeconds($avgduration.Average)
						MinThroughputMB = [System.Math]::Round($measuremb.Minimum, 2)
						MaxThroughputMB = [System.Math]::Round($measuremb.Maximum, 2)
						MinBackupDate = $measurestart.Minimum
						MaxBackupDate = $measureend.Maximum
						BackupCount = $db.Count
					} | Select-DefaultView -ExcludeProperty ComputerName, InstanceName
				}
			}
		}
	}
}
