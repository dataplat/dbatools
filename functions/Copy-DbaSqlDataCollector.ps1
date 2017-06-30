function Copy-DbaSqlDataCollector {
	<#
		.SYNOPSIS
			Migrates user SQL Data Collector collection sets. SQL Data Collector configuration is on the agenda, but it's hard.

		.DESCRIPTION
			By default, all data collector objects are migrated. If the object already exists on the destination, it will be skipped unless -Force is used.

			The -CollectionSet parameter is autopopulated for command-line completion and can be used to copy only specific objects.

		.PARAMETER Source
			Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

		.PARAMETER SourceSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Destination
			Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

		.PARAMETER DestinationSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER CollectionSet
			The collection set(s) to process - this list is auto populated from the server. If unspecified, all collection sets will be processed.

		.PARAMETER ExcludeCollectionSet
			The collection set(s) to exclude - this list is auto populated from the server

		.PARAMETER NoServerReconfig
			Upcoming parameter to enable server reconfiguration

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.PARAMETER Force
			If collection sets exists on destination server, it will be dropped and recreated.

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Migration,DataCollection
			Author: Chrissy LeMaire (@cl), netnerds.net
			Requires: sysadmin access on SQL Servers

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Copy-DbaSqlDataCollector

		.EXAMPLE
			Copy-DbaSqlDataCollector -Source sqlserver2014a -Destination sqlcluster

			Copies all Data Collector Objects and Configurations from sqlserver2014a to sqlcluster, using Windows credentials.

		.EXAMPLE
			Copy-DbaSqlDataCollector -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

			Copies all Data Collector Objects and Configurations from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

		.EXAMPLE
			Copy-DbaSqlDataCollector -Source sqlserver2014a -Destination sqlcluster -WhatIf

			Shows what would happen if the command were executed.

		.EXAMPLE
			Copy-DbaSqlDataCollector -Source sqlserver2014a -Destination sqlcluster -CollectionSet 'Server Activity', 'Table Usage Analysis'

			Copies two Collection Sets, Server Activity and Table Usage Analysis, from sqlserver2014a to sqlcluster.
	#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Source,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SourceSqlCredential,
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Destination,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$DestinationSqlCredential,
		[object[]]$CollectionSet,
		[object[]]$ExcludeCollectionSet,
		[switch]$NoServerReconfig,
		[switch]$Force,
		[switch]$Silent
	)

	begin {

		if ([System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.Collector") -eq $null) {
			throw "SMO version is too old. To migrate collection sets, you must have SQL Server Management Studio 2008 R2 or higher installed."
		}

		$sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

		$source = $sourceServer.DomainInstanceName
		$destination = $destServer.DomainInstanceName

		if ($sourceServer.VersionMajor -lt 10 -or $destServer.VersionMajor -lt 10) {
			throw "Collection Sets are only supported in SQL Server 2008 and above. Quitting."
		}

	}
	process {

		if ($NoServerReconfig -eq $false) {
			Write-Warning "Server reconfiguration not yet supported. Only Collection Set migration will be migrated at this time."
			$NoServerReconfig = $true
		}

		$sourceSqlConn = $sourceServer.ConnectionContext.SqlConnectionObject
		$sourceSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $sourceSqlConn
		$sourceStore = New-Object Microsoft.SqlServer.Management.Collector.CollectorConfigStore $sourceSqlStoreConnection

		$destSqlConn = $destServer.ConnectionContext.SqlConnectionObject
		$destSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $destSqlConn
		$destStore = New-Object Microsoft.SqlServer.Management.Collector.CollectorConfigStore $destSqlStoreConnection

		$configDb = $sourceStore.ScriptAlter().GetScript() | Out-String

		$configDb = $configDb -replace [Regex]::Escape("'$source'"), "'$destReplace'"

		if (!$NoServerReconfig) {
			if ($Pscmdlet.ShouldProcess($destination, "Attempting to modify Data Collector configuration")) {
				try {
					$sql = "Unknown at this time"
					$destServer.ConnectionContext.ExecuteNonQuery($sql)
					$destStore.Alter()
				}
				catch {
					Write-Exception $_
				}
			}
		}

		if ($destStore.Enabled -eq $false) {
			Write-Warning "The Data Collector must be setup initially for Collection Sets to be migrated. "
			Write-Warning "Setup the Data Collector and try again."
			return
		}

		$storeCollectionSets = $sourceStore.CollectionSets | Where-Object { $_.IsSystem -eq $false }
		if ($CollectionSet) {
			$storeCollectionSets = $storeCollectionSets | Where-Object Name -In $CollectionSet
		}
		if ($ExcludeCollectionSet) {
			$storeCollectionSets = $storeCollectionSets | Where-Object Name -NotIn $ExcludeCollectionSet
		}

		Write-Output "Migrating collection sets"
		foreach ($set in $storeCollectionSets) {
			$collectionName = $set.Name
			if ($destStore.CollectionSets[$collectionName] -ne $null) {
				if ($force -eq $false) {
					Write-Warning "Collection Set '$collectionName' was skipped because it already exists on $destination"
					Write-Warning "Use -Force to drop and recreate"
					continue
				}
				else {
					if ($Pscmdlet.ShouldProcess($destination, "Attempting to drop $collectionName")) {
						Write-Verbose "Collection Set '$collectionName' exists on $destination"
						Write-Verbose "Force specified. Dropping $collectionName."

						try {
							$destStore.CollectionSets[$collectionName].Drop()
						}
						catch {
							Write-Exception "Unable to drop: $_  Moving on."
							continue
						}
					}
				}
			}

			if ($Pscmdlet.ShouldProcess($destination, "Migrating collection set $collectionName")) {
				try {
					$sql = $set.ScriptCreate().GetScript() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
					Write-Verbose $sql
					Write-Output "Migrating collection set $collectionName"
					$null = $destServer.ConnectionContext.ExecuteNonQuery($sql)

					if ($set.IsRunning) {
						Write-Output "Starting collection set $collectionName"
						$destStore.CollectionSets.Refresh()
						$destStore.CollectionSets[$collectionName].Start()
					}
				}
				catch {
					Write-Exception $_
				}
			}
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlDataCollector
	}
}

