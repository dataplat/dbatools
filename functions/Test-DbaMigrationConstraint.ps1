function Test-DbaMigrationConstraint {
	<#
	.SYNOPSIS
		Show if you can migrate the database(s) between the servers.

	.DESCRIPTION
		When you want to migrate from a higher edition to a lower one there are some features that can't be used.
		This function will validate if you have any of this features in use and will report to you.
		The validation will be made ONLY on on SQL Server 2008 or higher using the 'sys.dm_db_persisted_sku_features' dmv.

		This function only validate SQL Server 2008 versions or higher.
		The editions supported by this function are:
			- Enterprise
			- Developer
			- Evaluation
			- Standard
			- Express

		Take into account the new features introduced on SQL Server 2016 SP1 for all versions. More information at https://blogs.msdn.microsoft.com/sqlreleaseservices/sql-server-2016-service-pack-1-sp1-released/

		The -Database parameter is autopopulated for command-line completion.

	.PARAMETER Source
		Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

	.PARAMETER SourceSqlCredential
		Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

	.PARAMETER Destination
		Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

	.PARAMETER DestinationSqlCredential
		Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

		$dcred = Get-Credential, this pass this $dcred to the param.

		Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.

	.PARAMETER Database
		The database(s) to process - this list is autopopulated from the server. If unspecified, all databases will be processed.

	.PARAMETER ExcludeDatabase
		The database(s) to exclude - this list is autopopulated from the server

	.PARAMETER WhatIf
		Shows what would happen if the command were to run. No actions are actually performed.

	.PARAMETER Confirm
		Prompts you for confirmation before executing any changing operations within the command.

		$scred = Get-Credential, this pass $scred object to the param.

		Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.

	.NOTES
		Tags: Migration

		Author: Claudio Silva (@ClaudioESSilva)
		Website: https://dbatools.io
		Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
		https://dbatools.io/Test-DbaMigrationConstraint

	.EXAMPLE
		Test-DbaMigrationConstraint -Source sqlserver2014a -Destination sqlcluster

		Description

		All databases will be verified for features in use that can't be supported on the destination server

	.EXAMPLE
		Test-DbaMigrationConstraint -Source sqlserver2014a -Destination sqlcluster -SqlCredential $cred

		Description

		All databases will be verified for features in use that can't be supported on the destination server using SQL credentials for sqlserver2014a
		and Windows credentials for sqlcluster.

	.EXAMPLE
		Test-DbaMigrationConstraint -Source sqlserver2014a -Destination sqlcluster -Database db1
		Only db1 database will be verified for features in use that can't be supported on the destination server
	#>
	[CmdletBinding(DefaultParameterSetName = "DbMigration")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $True)]
		[DbaInstanceParameter]$Source,
		[PSCredential][System.Management.Automation.CredentialAttribute()]$SourceSqlCredential = [System.Management.Automation.PSCredential]::Empty,
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Destination,
		[PSCredential][System.Management.Automation.CredentialAttribute()]$DestinationSqlCredential = [System.Management.Automation.PSCredential]::Empty,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$ExcludeDatabase
	)

	begin {
		<#
			1804890536 = Enterprise
			1872460670 = Enterprise Edition: Core-based Licensing
			610778273 = Enterprise Evaluation
			284895786 = Business Intelligence
			-2117995310 = Developer
			-1592396055 = Express
			-133711905= Express with Advanced Services
			-1534726760 = Standard
			1293598313 = Web
			1674378470 = SQL Database
		#>

		$editions = @{"Enterprise" = 10; "Developer" = 10; "Evaluation" = 10; "Standard" = 5; "Express" = 1}
		$notesCanMigrate = "Database can be migrated."
		$notesCannotMigrate = "Database cannot be migrated."
	}
	process {

		Write-Output "Attempting to connect to Sql Servers.."
		$sourceserver = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

		if ($Database -eq 0) {
			$Database = $sourceserver.Databases | Where-Object isSystemObject -eq 0 | Select-Object Name, Status
		}

		if ($ExcludeDatabase) {
			$Database = $sourceserver.Databases | Where-Object Name -NotIn $ExcludeDatabase
		}

		if ($Database -gt 0) {
			if ($Database -contains "master" -or $Database -contains "msdb" -or $Database -contains "tempdb") {
				throw "Migrating system databases is not currently supported."
			}

			if ($sourceserver.versionMajor -lt 9 -and $destserver.versionMajor -gt 10) {
				throw "Sql Server 2000 databases cannot be migrated to Sql Server versions 2012 and above. Quitting."
			}

			if ($sourceserver.collation -ne $destserver.collation) {
				Write-Warning "Collation on $Source, $($sourceserver.collation) differs from the $Destination, $($destserver.collation)."
			}

			if ($sourceserver.versionMajor -gt $destserver.versionMajor) {
				#indicate that must use 'Generate Scripts' and 'Export Data' options?
				throw "You can't migrate databases from a higher version to a lower one. Quitting."
			}

			if ($sourceserver.versionMajor -lt 10) {
				throw "This function does not support versions lower than SQL Server 2008 (v10)"
			}

			#if editions differs, from higher to lower one, verify the sys.dm_db_persisted_sku_features - only available from SQL 2008 +
			if (($sourceserver.versionMajor -ge 10 -and $destserver.versionMajor -ge 10)) {
				foreach ($db in $Database) {
					if ([string]::IsNullOrEmpty($db.Status)) {
						$dbstatus = ($sourceserver.Databases | Where-Object {$_.Name -eq $db}).Status.ToString()
						$dbName = $db
					}
					else {
						$dbstatus = $db.Status.ToString()
						$dbName = $db.Name
					}

					Write-Verbose "Checking database: '$dbName'"

					if ($dbstatus.Contains("Offline") -eq $false) {
						[long]$destVersionNumber = $($destserver.VersionString).Replace(".", "")
						[string]$SourceVersion = "$($sourceServer.Edition) $($sourceServer.ProductLevel) ($($sourceserver.Version))"
						[string]$DestinationVersion = "$($destserver.Edition) $($destserver.ProductLevel) ($($destserver.Version))"
						[string]$dbFeatures = ""

						try {
							$sql = "SELECT feature_name FROM sys.dm_db_persisted_sku_features"

							$skufeatures = $sourceServer.Databases[$dbName].ExecuteWithResults($sql)

							Write-Verbose "Checking features in use..."

							if ($skufeatures.Tables[0].Rows.Count -gt 0) {
								foreach ($row in $skufeatures.Tables[0].Rows) {
									$dbFeatures += ",$($row["feature_name"])"
								}

								$dbFeatures = $dbFeatures.TrimStart(",")
							}
						}
						catch {
							Write-Warning "Can't execute SQL on $sourceserver. `r`n $($_)"
							Continue
						}

						#If SQL Server 2016 SP1 (13.0.4001.0) or higher
						if ($destVersionNumber -ge 13040010) {
							<#
								Need to verify if Edition = EXPRESS and database uses 'Change Data Capture' (CDC)
								This means that database cannot be migrated because Express edition don't have SQL Server Agent
							#>
							if ($editions.Item($destserver.Edition.ToString().Split(" ")[0]) -eq 1 -and $dbFeatures.Contains("ChangeCapture")) {
								[pscustomobject]@{
									SourceInstance      = $sourceserver.Name
									DestinationInstance = $destserver.Name
									SourceVersion       = $SourceVersion
									DestinationVersion  = $DestinationVersion
									Database            = $dbName
									FeaturesInUse       = $dbFeatures
									Notes               = "$notesCannotMigrate. Destination server edition is EXPRESS which does not support 'ChangeCapture' feature that is in use."
								}
							}
							else {
								[pscustomobject]@{
									SourceInstance      = $sourceserver.Name
									DestinationInstance = $destserver.Name
									SourceVersion       = $SourceVersion
									DestinationVersion  = $DestinationVersion
									Database            = $dbName
									FeaturesInUse       = $dbFeatures
									Notes               = $notesCanMigrate
								}
							}
						}
						#Version is lower than SQL Server 2016 SP1
						else {
							Write-Verbose "Source Server Edition: $($sourceserver.Edition) (Weight: $($editions.Item($sourceserver.Edition.ToString().Split(" ")[0])))"
							Write-Verbose "Destination Server Edition: $($destserver.Edition) (Weight: $($editions.Item($destserver.Edition.ToString().Split(" ")[0])))"

							#Check for editions. If destination edition is lower than source edition and exists features in use
							if (($editions.Item($destserver.Edition.ToString().Split(" ")[0]) -lt $editions.Item($sourceserver.Edition.ToString().Split(" ")[0])) -and (!([string]::IsNullOrEmpty($dbFeatures)))) {
								[pscustomobject]@{
									SourceInstance      = $sourceserver.Name
									DestinationInstance = $destserver.Name
									SourceVersion       = $SourceVersion
									DestinationVersion  = $DestinationVersion
									Database            = $dbName
									FeaturesInUse       = $dbFeatures
									Notes               = "$notesCannotMigrate There are features in use not available on destination instance."
								}
							}
							#
							else {
								[pscustomobject]@{
									SourceInstance      = $sourceserver.Name
									DestinationInstance = $destserver.Name
									SourceVersion       = $SourceVersion
									DestinationVersion  = $DestinationVersion
									Database            = $dbName
									FeaturesInUse       = $dbFeatures
									Notes               = $notesCanMigrate
								}
							}
						}
					}
					else {
						Write-Warning "Database '$dbName' is offline. Bring database online and re-run the command"
					}

				}
			}
			else {
				#SQL Server 2005 or under
				Write-Warning "This validation will not be made on versions lower than SQL Server 2008 (v10)"
				Write-Verbose "Source server version: $($sourceserver.versionMajor)"
				Write-Verbose "Destination server version: $($destserver.versionMajor)"
			}
		}
		else {
			Write-Output "There are no databases to validate."
		}
	}
	END {
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Test-SqlMigrationConstraint
	}
}

