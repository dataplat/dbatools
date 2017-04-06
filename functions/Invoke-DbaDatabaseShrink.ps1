Function Invoke-DbaDatabaseShrink
{
<#
.SYNOPSIS
Shrinks all files in a database
	
.DESCRIPTION
Shrinks all files in a database.
	
IMPORTANT NOTE: Databases should be shrunk only when completely necessary. This is a command that should rarely be used.
	
Many awesome SQL people have written about why you should not shrink your data files, and Paul Randal's post is a great one:
	
	http://www.sqlskills.com/blogs/paul/why-you-should-not-shrink-your-data-files/

However, there are some cases where a database will need to be shrunk. In the event that you must shrink your database, note that 
you should run DBCC INDEXDEFRAG or ALTER INDEX ... REORGANIZE after the shrink is complete.
	
.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
SqlCredential object used to connect to the SQL Server as a different user.

.PARAMETER Databases
Shrink specific databases.

.PARAMETER Exclude
Shrink all databases on the connected server except databases entered through this parameter.

.PARAMETER AllUserDatabases
Run command against all user databases	
	
.PARAMETER PercentFreeSpace
Specifies how much to reduce the database in percent.

.PARAMETER ShrinkMethod
Specifies the method that is used to shrink the database
	
		Default	
			Data in pages located at the end of a file is moved to pages earlier in the file. Files are truncated to reflect allocated space.
		EmptyFile	
			Migrates all of the data from the referenced file to other files in the same filegroup. (DataFile and LogFile objects only).
		NoTruncate	
			Data in pages located at the end of a file is moved to pages earlier in the file.
		TruncateOnly	
			Data distribution is not affected. Files are truncated to reflect allocated space, recovering free space at the end of any file.

.PARAMETER WhatIf
Shows what would happen if the command were to run
	
.PARAMETER Confirm
Prompts for confirmation of every step. For example:

Are you sure you want to perform this action?
Performing the operation "Shrink database" on target "pubs on SQL2016\VNEXT".
[Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.NOTES
Tags: Shrink, Database
dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
https://dbatools.io/Invoke-DbaDatabaseShrink

.EXAMPLE
Invoke-DbaDatabaseShrink -SqlInstance sql2016 -Databases Northwind,pubs,Adventureworks2014

Shrinks Northwind, pubs and Adventureworks2014 to have as little free space as possible.

.EXAMPLE
Invoke-DbaDatabaseShrink -SqlInstance sql2014 -Databases Adventureworks2014 -PercentFreeSpace 50

Shrinks Adventureworks2014 to have 50% free space. So let's say Adventureworks2014 was 1GB and it's using 100MB space. The database free space would be reduced to 50MB.

.EXAMPLE
Invoke-DbaDatabaseShrink -SqlInstance sql2012 -AllUserDatabase

Shrinks all databases on SQL2012 (not ideal for production)

#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[PsCredential]$SqlCredential,
		[switch]$AllUserDatabases,
		[ValidateRange(0, 99)]
		[int]$PercentFreeSpace = 0,
		[ValidateSet('Default', 'EmptyFile', 'NoTruncate', 'TruncateOnly')]
		[string]$ShrinkMethod = "Default",
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
				indexstats.avg_fragmentation_in_percent
				FROM sys.dm_db_index_physical_stats (DB_ID(), NULL, NULL, NULL, NULL) AS indexstats
				INNER JOIN sys.tables dbtables on dbtables.[object_id] = indexstats.[object_id]
				INNER JOIN sys.schemas dbschemas on dbtables.[schema_id] = dbschemas.[schema_id]
				INNER JOIN sys.indexes AS dbindexes ON dbindexes.[object_id] = indexstats.[object_id]
				AND indexstats.index_id = dbindexes.index_id
				WHERE indexstats.database_id = DB_ID()
				ORDER BY indexstats.avg_fragmentation_in_percent desc"
	}
	
	PROCESS
	{
		if (!$databases -and !$exclude -and !$AllUserDatabases)
		{
			Stop-Function -Message "You must specify databases to execute against using either -Databases, -Exclude or -AllUserDatabases" -Continue
		}
		
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
			
			# We have to exclude all the system databases since they cannot have the Query Store feature enabled
			$dbs = $server.Databases | Where-Object { $_.IsSystemObject -eq $false }
			
			if ($databases)
			{
				$dbs = $dbs | Where-Object { $databases -contains $_.Name }
			}
			
			if ($exclude)
			{
				$dbs = $dbs | Where-Object { $exclude -notcontains $_.Name }
			}
			
			foreach ($db in $dbs)
			{
				Write-Message -Level Verbose -Message "Processing $db on $instance"
				
				if ($db.IsAccessible -eq $false)
				{
					Write-Message -Level Warning -Message "The database $db on server $instance is not accessible. Skipping database."
					Continue
				}
				
				$startingsize = $db.Size
				$spaceAvailableMB = $db.SpaceAvailable/1024
				$spaceused = $startingsize - $spaceAvailableMB
				$desiredSpaceAvailable = ($PercentFreeSpace * $spaceused)/100
				
				Write-Message -Level Verbose -Message "Starting Size (MB): $startingsize"
				Write-Message -Level Verbose -Message "Starting Freespace (MB): $([int]$spaceavailableMB)"
				Write-Message -Level Verbose -Message "Desired Freespace (MB): $([int]$desiredSpaceAvailable)"
				
				if (($db.SpaceAvailable/1024) -le $desiredSpaceAvailable)
				{
					Write-Message -Level Warning -Message "Space Available ($spaceavailableMB) is less than or equal to the desired outcome ($desiredSpaceAvailable)"
				}
				else
				{
					if ($Pscmdlet.ShouldProcess("$db on $instance", "Shrinking from $([int]$startingsize) MB to $([int]$desiredSpaceAvailable) MB"))
					{
						if ($db.Tables.Indexes.Name -and $server.VersionMajor -gt 8)
						{
							Write-Message -Level Verbose -Message "Getting average fragmentation"
							$startingfrag = (Invoke-Sqlcmd2 -ServerInstance $instance -Credential $SqlCredential -Query $sql -Database $db.name | Select-Object -ExpandProperty avg_fragmentation_in_percent | Measure-Object -Average).Average
						}
						else
						{
							$startingfrag = $null
						}
						
						Write-Message -Level Verbose -Message "Starting shrink"
						$start = Get-Date
						$db.Shrink($PercentFreeSpace, $ShrinkMethod)
						$db.Refresh()
						$db.RecalculateSpaceUsage()
						$end = Get-Date
						$dbsize = $db.Size
						Write-Message -Level Verbose -Message "Final size: $([int]$dbsize) MB"
						
						if ($db.Tables.Indexes.Name -and $server.VersionMajor -gt 8)
						{
							Write-Message -Level Verbose -Message "Refreshing indexes and getting average fragmentation"
							$endingdefrag = (Invoke-Sqlcmd2 -ServerInstance $instance -Credential $SqlCredential -Query $sql -Database $db.name | Select-Object -ExpandProperty avg_fragmentation_in_percent | Measure-Object -Average).Average
						}
						else
						{
							$endingdefrag = $null
						}
						
						$timespan = New-TimeSpan -Start $start -End $end
						$ts = [timespan]::fromseconds($timespan.TotalSeconds)
						$elapsed = "{0:HH:mm:ss}" -f ([datetime]$ts.Ticks)
					}
				}
				
				#$db.TruncateLog()
				
				if ($Pscmdlet.ShouldProcess("$db on $instance", "Showing results"))
				{
					$db.Refresh()
					$db.RecalculateSpaceUsage()
					[pscustomobject]@{
						ComputerName = $server.NetName
						InstanceName = $server.ServiceName
						SqlInstance = $server.DomainInstanceName
						Database = $db.name
						Start = $start
						End = $end
						Elapsed = $elapsed
						CurrentlyAllocatedMB = [math]::Round($startingsize, 2)
						CurrentlyUsedMB = [math]::Round($spaceused, 2)
						FinalSizeMB = [math]::Round($db.size, 2)
						CurrentlyAvailableMB = [math]::Round($spaceavailableMB, 2)
						DesiredAvailableMB = [math]::Round($desiredSpaceAvailable, 2)
						FinalAvailableMB = [math]::Round(($db.SpaceAvailable/1024), 2)
						StartingIndexFragmentationAvg = [math]::Round($startingfrag, 1)
						EndingIndexFragmentationAvg = [math]::Round($endingdefrag, 1)
						Notes = "Database shrinks can cause massive index fragmentation and negatively impact performance. You should now run DBCC INDEXDEFRAG or ALTER INDEX ... REORGANIZE"
					}
				}
			}
		}
	}
}