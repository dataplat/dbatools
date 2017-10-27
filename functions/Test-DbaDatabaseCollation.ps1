function Test-DbaDatabaseCollation {
	<#
		.SYNOPSIS
			Compares Database Collations to Server Collation

		.DESCRIPTION
			Compares Database Collations to Server Collation

		.PARAMETER SqlInstance
			The SQL Server that you're connecting to.

		.PARAMETER Credential
			Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

			$scred = Get-Credential, then pass $scred object to the -Credential parameter.

			Windows Authentication will be used if Credential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Database
			Specifies the database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.
		
		.PARAMETER ExcludeDatabase
			Specifies the database(s) to exclude from processing. Options for this list are auto-populated from the server.
		
		.PARAMETER Detailed
			If this switch is enabled, full details about database & server collations and whether they match is returned.

		.NOTES
			Tags: 
			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Test-DbaDatabaseCollation

		.EXAMPLE
			Test-DbaDatabaseCollation -SqlInstance sqlserver2014a

			Returns server name, database name and true/false if the collations match for all databases on sqlserver2014a.

		.EXAMPLE
			Test-DbaDatabaseCollation -SqlInstance sqlserver2014a -Database db1, db2

			Returns server name, database name and true/false if the collations match for the db1 and db2 databases on sqlserver2014a.

		.EXAMPLE
			Test-DbaDatabaseCollation -SqlInstance sqlserver2014a, sql2016 -Detailed -Exclude db1

			Returns detailed information for database and server collations for all databases except db1 on sqlserver2014a and sql2016.

		.EXAMPLE
			Get-DbaRegisteredServer -SqlInstance sql2016 | Test-DbaDatabaseCollation

			Returns db/server collation information for every database on every server listed in the Central Management Server on sql2016.
	#>
	[CmdletBinding()]
	[OutputType("System.Collections.ArrayList")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$Credential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$ExcludeDatabase,
		[switch]$Detailed
	)

	begin {
		$collection = New-Object System.Collections.ArrayList

	}

	process {
		foreach ($servername in $SqlInstance) {
			try {
				$server = Connect-SqlInstance -SqlInstance $servername -SqlCredential $Credential
			}
			catch {
				if ($SqlInstance.count -eq 1) {
					throw $_
				}
				else {
					Write-Message -Level Warning -Message  "Can't connect to $servername. Moving on."
					Continue
				}
			}

			$dbs = $server.Databases

			if ($Database) {
				$dbs = $dbs | Where-Object { $Database -contains $_.Name }
			}

			if ($ExcludeDatabase) {
				$dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
			}

			foreach ($db in $dbs) {
				Write-Message -Level Verbose -Message "Processing $($db.name) on $servername."
				$null = $collection.Add([PSCustomObject]@{
						Server            = $server.name
						ServerCollation   = $server.collation
						Database          = $db.name
						DatabaseCollation = $db.collation
						IsEqual           = $db.collation -eq $server.collation
					})
			}
		}
	}

	end {
		if ($detailed) {
			return $collection
		}

		if ($Database.count -eq 1) {
			if ($SqlInstance.count -eq 1) {
				return $collection.IsEqual
			}
			else {
				return ($collection | Select-Object Server, isEqual)
			}
		}
		else {
			return ($collection | Select-Object Server, Database, IsEqual)
		}
	}
}

