function Copy-DbaSysDbUserObject {
	<#
		.SYNOPSIS
			Imports *all* user objects found in source SQL Server's master, msdb and model databases to the destination.

		.DESCRIPTION
			Imports *all* user objects found in source SQL Server's master, msdb and model databases to the destination. This is useful because many DBA's store backup/maintenance procs/tables/triggers/etc (among other things) in master or msdb.

			It is also useful for migrating objects within the model database.

		.PARAMETER Source
			Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

		.PARAMETER SourceSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$scred = Get-Credential, this pass $scred object to the param.

			Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Destination
			Destination SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

		.PARAMETER DestinationSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$dcred = Get-Credential, this pass this $dcred to the param.

			Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.PARAMETER Silent 
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Migration, SystemDatabase, UserObject

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Copy-DbaSysDbUserObject

		.EXAMPLE
		Copy-DbaSysDbUserObject $sourceserver $destserve

		Copies user objects from source to destination
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[DbaInstanceParameter]$Source,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[DbaInstanceParameter]$Destination,
		[PSCredential][System.Management.Automation.CredentialAttribute()]$SourceSqlCredential,
		[PSCredential][System.Management.Automation.CredentialAttribute()]$DestinationSqlCredential
	)
	PROCESS {
		$sourceserver = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
		if (!(Test-SqlSa -SqlInstance $sourceserver -SqlCredential $SourceSqlCredential)) { throw "Not a sysadmin on $source. Quitting." }
		if (!(Test-SqlSa -SqlInstance $destserver -SqlCredential $DestinationSqlCredential)) { throw "Not a sysadmin on $destination. Quitting." }

		$systemdbs = "master", "model", "msdb"

		foreach ($systemdb in $systemdbs) {
			$sysdb = $sourceserver.databases[$systemdb]
			$transfer = New-Object Microsoft.SqlServer.Management.Smo.Transfer $sysdb
			$transfer.CopyAllObjects = $false
			$transfer.CopyAllDatabaseTriggers = $true
			$transfer.CopyAllDefaults = $true
			$transfer.CopyAllRoles = $true
			$transfer.CopyAllRules = $true
			$transfer.CopyAllSchemas = $true
			$transfer.CopyAllSequences = $true
			$transfer.CopyAllSqlAssemblies = $true
			$transfer.CopyAllSynonyms = $true
			$transfer.CopyAllTables = $true
			$transfer.CopyAllViews = $true
			$transfer.CopyAllStoredProcedures = $true
			$transfer.CopyAllUserDefinedAggregates = $true
			$transfer.CopyAllUserDefinedDataTypes = $true
			$transfer.CopyAllUserDefinedTableTypes = $true
			$transfer.CopyAllUserDefinedTypes = $true
			$transfer.CopyAllUserDefinedFunctions = $true
			$transfer.CopyAllUsers = $true
			$transfer.PreserveDbo = $true
			$transfer.Options.AllowSystemObjects = $false
			$transfer.Options.ContinueScriptingOnError = $true
			$transfer.Options.IncludeDatabaseRoleMemberships = $true
			$transfer.Options.Indexes = $true
			$transfer.Options.Permissions = $true
			$transfer.Options.WithDependencies = $false

			Write-Output "Copying from $systemdb"
			try {
				$sqlQueries = $transfer.scriptTransfer()

				foreach ($query in $sqlQueries) {
					Write-Verbose $query
					if ($PSCmdlet.ShouldProcess($destserver, $query)) {
						try {
							$destserver.Databases[$systemdb].ExecuteNonQuery($query)
						}
						catch {
							# This usually occurs if there are existing objects in destination
						}
					}
				}
			}
			catch {
				Write-Output "Exception caught."
			}
		}
		Write-Output "Migrating user objects in system databases finished"
	}
	END {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlSysDbUserObjects
	}
}