Function Copy-SqlDataCollector
{
<#
# not quite done yet

.SYNOPSIS

Migrates user SQL Data Collector collection sets. SQL Data Collector configuration is on the agenda, but it's hard.

.DESCRIPTION
By default, all data collector objects are migrated. If the object already exists on the destination, it will be skipped unless -Force is used. 
	
The -CollectionSets parameter is autopopulated for command-line completion and can be used to copy only specific objects.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER Source
Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

.PARAMETER Destination
Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

.PARAMETER SourceSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter. 

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER DestinationSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter. 

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Force
If collection sets exists on destination server, it will be dropped and recreated.

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Copy-SqlDataCollector

.EXAMPLE   
Copy-SqlDataCollector -Source sqlserver2014a -Destination sqlcluster

Copies all Data Collector Objects and Configurations from sqlserver2014a to sqlcluster, using Windows credentials. 

.EXAMPLE   
Copy-SqlDataCollector -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

Copies all Data Collector Objects and Configurations from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

.EXAMPLE   
Copy-SqlDataCollector -Source sqlserver2014a -Destination sqlcluster -WhatIf

Shows what would happen if the command were executed.
	
.EXAMPLE   
Copy-SqlDataCollector -Source sqlserver2014a -Destination sqlcluster -CollectionSets 'Server Activity', 'Table Usage Analysis' 

Copies two Collection Sets, Server Activity and Table Usage Analysis, from sqlserver2014a to sqlcluster.
#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[object]$Source,
		[parameter(Mandatory = $true)]
		[object]$Destination,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[switch]$NoServerReconfig,
		[switch]$Force
	)
	
	DynamicParam { if ($source) { return (Get-ParamSqlDataCollectionSets -SqlServer $Source -SqlCredential $SourceSqlCredential) } }
	
	BEGIN
	{
		if ([System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.Collector") -eq $null)
		{
			throw "SMO version is too old. To migrate collection sets, you must have SQL Server Management Studio 2008 R2 or higher installed."
		}
		
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
		# New name?
		$collectionSets = $psboundparameters.CollectionSets
		
		if ($sourceserver.versionMajor -lt 10 -or $destserver.versionMajor -lt 10)
		{
			throw "Collection Sets are only supported in SQL Server 2008 and above. Quitting."
		}
		
	}
	process
	{
		if ($NoServerReconfig -eq $false) 
		{
			Write-Warning "Server reconfiguration not yet supported. Only Collection Set migration will be migrated at this time."
			$NoServerReconfig = $true
		}
		
		$sourceSqlConn = $sourceserver.ConnectionContext.SqlConnectionObject
		$sourceSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $sourceSqlConn
		$sourceStore = New-Object Microsoft.SqlServer.Management.Collector.CollectorConfigStore $sourceSqlStoreConnection
		
		$destSqlConn = $destserver.ConnectionContext.SqlConnectionObject
		$destSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $destSqlConn
		$destStore = New-Object Microsoft.SqlServer.Management.Collector.CollectorConfigStore $destSqlStoreConnection
		
		$configdb = $sourceStore.ScriptAlter().GetScript() | Out-String
		$configdb = $configdb -replace "'$source'", "'$destination'"
		
		if (!$NoServerReconfig)
		{
			if ($Pscmdlet.ShouldProcess($destination, "Attempting to modify Data Collector configuration"))
			{
				try
				{
					$sql = "Unknown at this time"
					$destserver.ConnectionContext.ExecuteNonQuery($sql)
					$destStore.Alter()
				}
				catch 
				{ 
					Write-Exception $_ 
				}
			}
		}
		
		if ($deststore.Enabled -eq $false) {
			Write-Warning "The Data Collector must be setup initially for Collection Sets to be migrated. "
			Write-Warning "Setup the Data Collector and try again."
			return
		}
		
		$storeCollectionSets = $sourceStore.CollectionSets | Where-Object { $_.isSystem -eq $false }
		if ($collectionSets.length -gt 0) { $storeCollectionSets = $storeCollectionSets | Where-Object { $collectionSets -contains $_.Name } }
		
		Write-Output "Migrating collection sets"
		foreach ($set in $storeCollectionSets)
		{
			$collectionName = $set.name
			if ($deststore.CollectionSets[$collectionName] -ne $null)
			{
				if ($force -eq $false)
				{
					Write-Warning "Collection Set '$collectionName' was skipped because it already exists on $destination"
					Write-Warning "Use -Force to drop and recreate"
					continue
				}
				else
				{
					if ($Pscmdlet.ShouldProcess($destination, "Attempting to drop $collectionName"))
					{
						Write-Verbose "Collection Set '$collectionName' exists on $destination"
						Write-Verbose "Force specified. Dropping $collectionName."
						
						try
						{
							$deststore.CollectionSets[$collectionName].Drop()
						}
						catch
						{
							Write-Exception "Unable to drop: $_  Moving on."
							continue
						}
					}
				}
			}
			
			if ($Pscmdlet.ShouldProcess($destination, "Migrating collection set $collectionName"))
			{
				try
				{
					$sql = $set.ScriptCreate().GetScript() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
					Write-Verbose $sql
					Write-Output "Migrating collection set $collectionName"
					$null = $destserver.ConnectionContext.ExecuteNonQuery($sql)
					
					if ($set.IsRunning)
					{
						Write-Output "Starting collection set $collectionName"
						$deststore.CollectionSets.Refresh()
						$deststore.CollectionSets[$collectionName].Start()
					}
				}
				catch
				{
					Write-Exception $_
				}
			}
		}
	}
	
	end
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Data Collector migration finished" }
	}
}

