function Measure-DbaBackupThroughput
{
<#
.SYNOPSIS
Determines how quickly SQL Server is backing up databases to media.

.DESCRIPTION
Returns backup history details for some or all databases on a SQL Server. 

Output looks like this
Server        : sql2016
Database      : db1
MinThroughput : 1.26
MaxThroughput : 18.26
AvgThroughput : 12.81
AvgSizeMB     : 18.26
MinBackupDate : 1/30/2017 3:30:11 AM
MaxBackupDate : 1/30/2017 4:20:50 PM
BackupCount   : 159

.PARAMETER SqlInstance
SqlInstance name or SMO object representing the SQL Server to connect to.
This can be a collection and receive pipeline input.

.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, currend Windows login will be used.

.PARAMETER Since
Datetime object used to narrow the results to a date

.NOTES 
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
Measure-DbaBackupThroughput -SqlInstance sqlserver2016a
Will fill this in

.EXAMPLE
Measure-DbaBackupThroughput -SqlInstance sqlserver2016a -Databases db1
Will fill this in
	
.EXAMPLE
Measure-DbaBackupThroughput -SqlInstance sql2016 -Since (Get-Date).AddDays(-7)
	
Gets info for last week
	
.EXAMPLE
Measure-DbaBackupThroughput -SqlInstance sql2016 -Since (Get-Date).AddDays(-365) -Databases bigoldb
	
Will fill this in

#>
	[CmdletBinding()]
	param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "Instance", "SqlServer")]
		[object[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]$SqlCredential,
		[datetime]$Since
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
			
			Write-Verbose "Getting backup history"
			
			# Ghetto, whatever - splatting didn't work
			if ($databases -and $since)
			{
				$histories = Get-DbaBackupHistory -SqlServer $server -Databases $databases -Since $since
			}
			elseif ($since)
			{
				$histories = Get-DbaBackupHistory -SqlServer $server -Since $since
			}
			elseif ($databases)
			{
				$histories = Get-DbaBackupHistory -SqlServer $server -Databases $databases
			}
			else
			{
				$histories = Get-DbaBackupHistory -SqlServer $server
			}
			
			$agghistories = @()
			
			foreach ($history in $histories)
			{
				$timetaken = New-TimeSpan –Start $history.Start –End $history.End
				
				if ($timetaken.TotalMilliseconds -eq 0)
				{
					$throughput = $history.TotalSizeMB
				}
				else
				{
					$throughput = $history.TotalSizeMB % $timetaken.TotalSeconds + 1
				}
				
				Add-Member -InputObject $history -MemberType Noteproperty -Name MBps -value $throughput
				
				$agghistories += $history | Select-Object Server, Database, MBps, TotalSizeMB, Start, End
			}
			
			$groups = $agghistories | Group-Object Database
			
			foreach ($db in $groups)
			{
				$measuremb = $db.Group.MBps | Measure-Object -Average -Minimum -Maximum
				$measurestart = $db.Group.Start | Measure-Object -Minimum
				$measureend = $db.Group.End | Measure-Object -Maximum
				$measuresize = $db.Group.TotalSizeMB | Measure-Object -Average
				
				[pscustomobject]@{
					Server = $db.Group.Server | Select-Object -First 1
					Database = $db.Name
					MinThroughput = [System.Math]::Round($measuremb.Minimum, 2)
					MaxThroughput = [System.Math]::Round($measuremb.Maximum, 2)
					AvgThroughput = [System.Math]::Round($measuremb.Average, 2)
					AvgSizeMB = [System.Math]::Round($measuresize.Average, 2)
					MinBackupDate = $measurestart.Minimum
					MaxBackupDate = $measureend.Maximum
					BackupCount = $db.Count
				}
			}
		}
	}
}