Function Copy-DbaQueryStoreConfig
{
<#
.SYNOPSIS
Copies the configuration of a Query Store enabled database and sets the copied configuration on other databases.
	
.DESCRIPTION
Copies the configuration of a Query Store enabled database and sets the copied configuration on other databases.
	
.PARAMETER Source
The SQL Server that you're connecting to.

.PARAMETER SourceDatabase
The database from which you want to copy the Query Store configuration.

.PARAMETER SourceSqlCredential
Credential object used to connect to the source SQL Server as a different user.

.PARAMETER DestinationSqlCredential
Credential object used to connect to the destination SQL Server as a different user.

.PARAMETER Destination
The target server where the databases reside on which you want to enfore the copied Query Store configuration from the SourceDatabase.

.PARAMETER DestinationDatabase
The databases that will recieve a copy of the Query Store configuration of the SourceDatabase.

.PARAMETER AllDatabases
Set copied Query Store configuration on all databases on the destination server.	
	
.PARAMETER Exclude
Copy Query Store configuration for all but these specific databases.

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
https://dbatools.io/Copy-QueryStoreConfig

.EXAMPLE
Copy-DbaQueryStoreConfig -Source ServerA\SQL -SourceDatabase AdventureWorks -Destination ServerB\SQL -AllDatabases

Copy the Query Store configuration of the AdventureWorks database in the ServerA\SQL Instance and apply it on all user databases in the ServerB\SQL Instance.

.EXAMPLE
Copy-DbaQueryStoreConfig -Source ServerA\SQL -SourceDatabase AdventureWorks -Destination ServerB\SQL -DestinationDatabase WorldWideTraders

Copy the Query Store configuration of the AdventureWorks database in the ServerA\SQL Instance and apply it to the WorldWideTraders database in the ServerB\SQL Instance.
	
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[object[]]$Source,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[object]$SourceDatabase,
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[object[]]$Destination,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[object[]]$DestinationDatabase,
		[object[]]$Exclude,
		[switch]$AllDatabases
	)
	
	BEGIN
	{
		
		Write-Verbose "Connecting to source: $Source"
		try
		{
			$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
			
		}
		catch
		{
			Write-Warning "Can't connect to $Source."
			break
		}
		
		# Grab the Query Store configuration from the SourceDatabase through the Get-DbaQueryStoreConfig function
		$SourceQSConfig = Get-DbaQueryStoreConfig -SqlServer $sourceserver -Databases $SourceDatabase
		
	}
	
	PROCESS
	{
		if (!$DestinationDatabase -and !$exclude -and !$alldatabases)
		{
			Write-Warning "You must specify databases to execute against using either -DestinationDatabase, -Exclude or -AllDatabases"
			continue
		}
		
		foreach ($destinationserver in $Destination)
		{
			
			Write-Verbose "Connecting to destination: $Destination"
			try
			{
				$destserver = Connect-SqlServer -SqlServer $destinationserver -SqlCredential $DestinationSqlCredential
				
			}
			catch
			{
				Write-Warning "Can't connect to $destinationserver."
				continue
			}
			
			# We have to exclude all the system databases since they cannot have the Query Store feature enabled
			$dbs = $destserver.Databases | Where-Object { $_.IsSystemObject -eq $false }
			
			if ($DestinationDatabase.count -gt 0)
			{
				$dbs = $dbs | Where-Object { $DestinationDatabase -contains $_.Name }
			}
			
			if ($Exclude.count -gt 0)
			{
				$dbs = $dbs | Where-Object { $exclude -notcontains $_.Name }
			}
			
			if ($dbs.count -eq 0)
			{
				Write-Warning "No matching databases found. Check the spelling and try again."
				return
			}
			
			foreach ($db in $dbs)
			{
				Write-Verbose "Processing destination database: $db on $destination"
				
				if ($db.IsAccessible -eq $false)
				{
					Write-Warning "The database $db on server $destination is not accessible. Skipping database."
					continue
				}
				
				Write-Verbose "Executing Set-DbaQueryStoreConfig"
				# Set the Query Store configuration through the Set-DbaQueryStoreConfig function
				Set-DbaQueryStoreConfig -SqlInstance $Destination -SqlCredential $DestinationSqlCredential -Databases $($db.name) -State $SourceQSConfig.ActualState -FlushInterval $SourceQSConfig.FlushInterval -CollectionInterval $SourceQSConfig.CollectionInterval -MaxSize $SourceQSConfig.MaxSize -CaptureMode $SourceQSConfig.CaptureMode -CleanupMode $SourceQSConfig.CleanupMode -StaleQueryThreshold $SourceQSConfig.StaleQueryThreshold
			}
		}
	}
}