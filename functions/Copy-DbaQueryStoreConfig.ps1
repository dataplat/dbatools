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

.PARAMETER SourceSqlCredential
Credential object used to connect to the source SQL Server as a different user.

.PARAMETER Destination
The target server where the databases reside on which you want to enfore the copied Query Store configuration from the SourceDatabase.

.PARAMETER DestinationDatabase
The databases that will recieve a copy of the Query Store configuration of the SourceDatabase.

.PARAMETER Exclude
Copy Query Store configuration for all but these specific databases.

.NOTES
Author: Enrico van de Laar ( @evdlaar )

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
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[object[]]$Source,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[object[]]$SourceDatabase,
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
			$server = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
			
		}
		catch
		{
			Write-Warning "Can't connect to $Source."
			continue
		}
		
		# Grab the Query Store configuration from the SourceDatabase through the Get-DbaQueryStoreConfig function
		$SourceQSConfig = Get-DbaQueryStoreConfig -SqlServer $server -Databases $SourceDatabase
		
	}
	
	PROCESS
	{
		if (!$DestinationDatabase -and !$exclude -and !$alldatabases)
		{
			Write-Warning "You must specify databases to execute against using either -DestinationDatabase, -Exclude or -AllDatabases"
			continue
		}
		
		Write-Verbose "Connecting to target: $Destination"
		try
		{
			$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $Credential
			
		}
		catch
		{
				Write-Warning "Can't connect to $Destination."
				continue
		}
		
		if ($sourceserver.VersionMajor -lt 13)
		{
			Write-Warning "The source SQL Server Instance ($source) has a lower SQL Server version than SQL Server 2016. Skipping server."
			continue
		}
		
		if ($destserver.VersionMajor -lt 13)
		{
			Write-Warning "The SQL Server Instance ($destination) has a lower SQL Server version than SQL Server 2016. Skipping server."
			continue
		}
		
		# We have to exclude all the system databases since they cannot have the Query Store feature enabled
		$dbs = $destserver.Databases | Where-Object { $_.IsSystemObject -eq $false }
		
		if ($DestinationDatabase.count -gt 0)
		{
			$dbs = $dbs | Where-Object { $databases -contains $_.Name }
		}
		
		if ($Exclude.count -gt 0)
		{
			$dbs = $dbs | Where-Object { $databases -notcontains $_.Name }
		}
		
		
		foreach ($db in $dbs)
		{
			$result = $null
			Write-Verbose "Processing target database: $db on $destination"
			
			if ($db.IsAccessible -eq $false)
			{
				Write-Warning "The database $db on server $destination is not accessible. Skipping database."
				continue
			}
			
			Write-Verbose "Executing Set-DbaQueryStoreConfig"
			# Set the Query Store configuration through the Set-DbaQueryStoreConfig function
			Set-DbaQueryStoreConfig -SqlInstance $Destination -SqlCredential $DestinationSqlCredential -Databases $($db.name) -State $SourceQSConfig.ActualState -FlushInterval $SourceQSConfig.FlushInterval -CollectionInterval $SourceQSConfig.CollectionInterval -MaxSize $SourceQSConfig.MaxSize -CaptureMode $SourceQSConfig.CaptureMode -CleanupMode $SourceQSConfig.CleanupMode -StaleQueryThreshold $SourceQSConfig.StaleQueryThreshold -WhatIf:$whatif
		}
	}
}