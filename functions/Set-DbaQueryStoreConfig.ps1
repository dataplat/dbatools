Function Set-DbaQueryStoreConfig
{
<#
.SYNOPSIS
Configure Query Store settings for a specific or multiple databases.
	
.DESCRIPTION
Configure Query Store settings for a specific or multiple databases.
	
.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
SqlCredential object used to connect to the SQL Server as a different user.

.PARAMETER Databases
Set Query Store configuration for specific databases.

.PARAMETER Exclude
Set Query Store configuration for all databases on the connected server except databases entered through this parameter.

.PARAMETER AllDatabases
Run command against all user databases	

.PARAMETER State
Set the state of the Query Store. Valid options are "ReadWrite", "ReadOnly" and "Off".

.PARAMETER FlushInterval
Set the flush to disk interval of the Query Store in seconds.

.PARAMETER CollectionInterval
Set the runtime statistics collection interval of the Query Store in minutes.

.PARAMETER MaxSize
Set the maximum size of the Query Store in MB.

.PARAMETER CaptureMode
Set the query capture mode of the Query Store. Valid options are "Auto" and "All".

.PARAMETER CleanupMode
Set the query cleanup mode policy. Valid options are "Auto" and "Off".

.PARAMETER StaleQueryThreshold
Set the stale query threshold in days.

.PARAMETER WhatIf
Shows what would happen if the command were to run
	
.PARAMETER Confirm
Prompts for confirmation of every step. For example:

Are you sure you want to perform this action?
Performing the operation "Changing Desired State" on target "pubs on SQL2016\VNEXT".
[Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):

.NOTES
Author: Enrico van de Laar ( @evdlaar )
Tags: QueryStore
dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
https://dbatools.io/Set-QueryStoreConfig

.EXAMPLE
Set-DbaQueryStoreConfig -SqlInstance ServerA\SQL -State ReadWrite -FlushInterval 600 -CollectionInterval 10 -MaxSize 100 -CaptureMode All -CleanupMode Auto -StaleQueryThreshold 100

Configure the Query Store settings for all user databases in the ServerA\SQL Instance.

.EXAMPLE
Set-DbaQueryStoreConfig -SqlInstance ServerA\SQL -FlushInterval 600

Only configure the FlushInterval setting for all Query Store databases in the ServerA\SQL Instance.

.EXAMPLE
Set-DbaQueryStoreConfig -SqlInstance ServerA\SQL -Databases AdventureWorks -State ReadWrite -FlushInterval 600 -CollectionInterval 10 -MaxSize 100 -CaptureMode all -CleanupMode Auto -StaleQueryThreshold 100

Configure the Query Store settings for the AdventureWorks database in the ServerA\SQL Instance.

.EXAMPLE
Set-DbaQueryStoreConfig -SqlInstance ServerA\SQL -Exclude AdventureWorks -State ReadWrite -FlushInterval 600 -CollectionInterval 10 -MaxSize 100 -CaptureMode all -CleanupMode Auto -StaleQueryThreshold 100

Configure the Query Store settings for all user databases except the AdventureWorks database in the ServerA\SQL Instance.
	
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[PsCredential]$SqlCredential,
		[switch]$AllDatabases,
		[ValidateSet('ReadWrite', 'ReadOnly', 'Off')]
		[string[]]$State,
		[int64]$FlushInterval,
		[int64]$CollectionInterval,
		[int64]$MaxSize,
		[ValidateSet('Auto', 'All')]
		[string[]]$CaptureMode,
		[ValidateSet('Auto', 'Off')]
		[string[]]$CleanupMode,
		[int64]$StaleQueryThreshold
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
	}
	
	PROCESS
	{
		if (!$databases -and !$exclude -and !$alldatabases)
		{
			Write-Warning "You must specify databases to execute against using either -Databases, -Exclude or -AllDatabases"
			continue
		}
		
		if (!$State -and !$FlushInterval -and !$CollectionInterval -and !$MaxSize -and !$CaptureMode -and !$CleanupMode -and !$StaleQueryThreshold)
		{
			Write-Warning "You must specify something to change."
			return
		}
		
		foreach ($instance in $SqlInstance)
		{
			Write-Verbose "Connecting to $instance"
			try
			{
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $SqlCredential
				
			}
			catch
			{
				Write-Warning "Can't connect to $instance. Moving on."
				continue
			}
			
			if ($server.VersionMajor -lt 13)
			{
				
				Write-Warning "The SQL Server Instance ($instance) has a lower SQL Server version than SQL Server 2016. Skipping server."
				continue
			}
			
			# We have to exclude all the system databases since they cannot have the Query Store feature enabled
			$dbs = $server.Databases | Where-Object { $_.IsSystemObject -eq $false }
			
			if ($databases.count -gt 0)
			{
				$dbs = $dbs | Where-Object { $databases -contains $_.Name }
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
					Write-Warning "The database $db on server $instance is not accessible. Skipping database."
					Continue
				}
				
				if ($State)
				{
					if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing DesiredState to $state"))
					{
						$db.QueryStoreOptions.DesiredState = $State
					}
				}
				
				if ($FlushInterval)
				{
					if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing DataFlushIntervalInSeconds to $FlushInterval"))
					{
						$db.QueryStoreOptions.DataFlushIntervalInSeconds = $FlushInterval
					}
				}
				
				if ($CollectionInterval)
				{
					if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing StatisticsCollectionIntervalInMinutes to $CollectionInterval"))
					{
						$db.QueryStoreOptions.StatisticsCollectionIntervalInMinutes = $CollectionInterval
					}
				}
				
				if ($MaxSize)
				{
					if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing MaxStorageSizeInMB to $MaxSize"))
					{
						$db.QueryStoreOptions.MaxStorageSizeInMB = $MaxSize
					}
				}
				
				if ($CaptureMode)
				{
					if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing QueryCaptureMode to $CaptureMode"))
					{
						$db.QueryStoreOptions.QueryCaptureMode = $CaptureMode
					}
				}
				
				if ($CleanupMode)
				{
					if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing SizeBasedCleanupMode to $CleanupMode"))
					{
						$db.QueryStoreOptions.SizeBasedCleanupMode = $CleanupMode
					}
				}
				
				if ($StaleQueryThreshold)
				{
					if ($Pscmdlet.ShouldProcess("$db on $instance", "Changing StaleQueryThresholdInDays to $StaleQueryThreshold"))
					{
						$db.QueryStoreOptions.StaleQueryThresholdInDays = $StaleQueryThreshold
					}
				}
				
				# Alter the Query Store Configuration
				if ($Pscmdlet.ShouldProcess("$db on $instance", "Altering Query Store configuration on database"))
				{
					try
					{
						$db.QueryStoreOptions.Alter()
						$db.Refresh()
					}
					catch
					{
						Write-Warning "Could not modify configuration. Error was: $_"
						continue
					}
				}
				
				
				if ($Pscmdlet.ShouldProcess("$db on $instance", "Getting results from Get-DbaQueryStoreConfig"))
				{
					# Display resulting changes
					Get-DbaQueryStoreConfig -SqlInstance $server -Databases $db.name -Verbose:$false
				}
			}
		}
	}
}