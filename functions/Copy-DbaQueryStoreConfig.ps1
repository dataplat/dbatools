function Copy-DbaQueryStoreConfig {
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

	.PARAMETER Exclude
		Copy Query Store configuration for all but these specific databases.

	.PARAMETER AllDatabases
		Set copied Query Store configuration on all databases on the destination server.

	.PARAMETER Silent
		Use this switch to disable any kind of verbose messages

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

		Website: https://dbatools.io
		Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

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
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[object]$Source,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[object]$SourceDatabase,
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[object[]]$Destination,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[object[]]$DestinationDatabase,
		[object[]]$Exclude,
		[switch]$AllDatabases,
		[switch]$Silent
	)

	BEGIN {

		Write-Message -Message "Connecting to source: $Source" -Level Verbose
		try {
			$sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		}
		catch {
			Stop-Function -Message "Can't connect to $Source." -InnerErrorRecord $_ -Target $Source
		}
	}

	PROCESS {
		if (Test-FunctionInterrupt) {
			return
		}
		# Grab the Query Store configuration from the SourceDatabase through the Get-DbaQueryStoreConfig function
		$SourceQSConfig = Get-DbaQueryStoreConfig -SqlInstance $sourceServer -Databases $SourceDatabase

		if (!$DestinationDatabase -and !$Exclude -and !$AllDatabases) {
			Stop-Function -Message "You must specify databases to execute against using either -DestinationDatabase, -Exclude or -AllDatabases" -Continue
		}

		foreach ($destinationServer in $Destination) {

			Write-Message -Message "Connecting to destination: $Destination" -Level Verbose
			try {
				$destServer = Connect-SqlInstance -SqlInstance $destinationServer -SqlCredential $DestinationSqlCredential
			}
			catch {
				Stop-Function -Message "Can't connect to $destinationServer." -InnerErrorRecord $_ -Target $desitnationServer -Continue
			}

			# We have to exclude all the system databases since they cannot have the Query Store feature enabled
			$dbs = Get-DbaDatabase -SqlInstance $destServer -NoSystemDb

			if ($DestinationDatabase.count -gt 0) {
				$dbs = $dbs | Where-Object { $DestinationDatabase -contains $_.Name }
			}

			if ($Exclude.count -gt 0) {
				$dbs = $dbs | Where-Object { $exclude -notcontains $_.Name }
			}

			if ($dbs.count -eq 0) {
				Stop-Function -Message "No matching databases found. Check the spelling and try again." -Continue
			}

			foreach ($db in $dbs) {
				# skipping the database if the source and destination are the same instance
				if (($sourceServer.Name -eq $destinationServer) -and ($SourceDatabase -eq $db.Name)) {
					continue
				}
				Write-Message -Message "Processing destination database: $db on $destinationServer" -Level Verbose
				$copyQueryStoreStatus = [pscustomobject]@{
					SourceServer = $sourceServer.name
					SourceDatabase = $SourceDatabase
					DestinationServer = $destinationServer
					DestinationDatabase = $db.name
					Name = "QueryStore Configuration"
					Status = $null
					DateTime = [sqlcollective.dbatools.Utility.DbaDateTime](Get-Date)
				}

				if ($db.IsAccessible -eq $false) {
					$copyQueryStoreStatus.Status = "Skipped"
					Stop-Function -Message "The database $db on server $destinationServer is not accessible. Skipping database." -Continue
				}

				Write-Message -Message "Executing Set-DbaQueryStoreConfig" -Level Verbose
				# Set the Query Store configuration through the Set-DbaQueryStoreConfig function
				try {
					$null = Set-DbaQueryStoreConfig -SqlInstance $destinationServer -SqlCredential $DestinationSqlCredential `
					-Databases $db.name `
					-State $SourceQSConfig.ActualState `
					-FlushInterval $SourceQSConfig.FlushInterval `
					-CollectionInterval $SourceQSConfig.CollectionInterval `
					-MaxSize $SourceQSConfig.MaxSize `
					-CaptureMode $SourceQSConfig.CaptureMode `
					-CleanupMode $SourceQSConfig.CleanupMode `
					-StaleQueryThreshold $SourceQSConfig.StaleQueryThreshold
					$copyQueryStoreStatus.Status = "Successful"
				}
				catch {
					$copyQueryStoreStatus.Status = "Failed"
					Stop-Function -Message "Issue setting QueryStore on $db" -Target $db -InnerErrorRecord $_ -Continue
				}
					$copyQueryStoreStatus
			}
		}
	}
}