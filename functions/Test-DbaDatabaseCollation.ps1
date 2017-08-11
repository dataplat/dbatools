function Test-DbaDatabaseCollation {
	<#
	.SYNOPSIS
		Compares Database Collations to Server Collation

	.DESCRIPTION
		Compares Database Collations to Server Collation

	.PARAMETER SqlInstance
		The SQL Server that you're connecting to.

	.PARAMETER Credential
		Credential object used to connect to the SQL Server as a different user

	.PARAMETER Database
		The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

	.PARAMETER ExcludeDatabase
		The database(s) to exclude - this list is auto-populated from the server

	.PARAMETER Detailed
		Shows detailed information about the server and database collations

	.NOTES
		Website: https://dbatools.io
		Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
		https://dbatools.io/Test-DbaDatabaseCollation

	.EXAMPLE
		Test-DbaDatabaseCollation -SqlInstance sqlserver2014a

		Returns server name, databse name and true/false if the collations match for all databases on sqlserver2014a

	.EXAMPLE
		Test-DbaDatabaseCollation -SqlInstance sqlserver2014a -Database db1, db2

		Returns server name, databse name and true/false if the collations match for the db1 and db2 databases on sqlserver2014a

	.EXAMPLE
		Test-DbaDatabaseCollation -SqlInstance sqlserver2014a, sql2016 -Detailed -Exclude db1

		Lots of detailed information for database and server collations for all databases except db1 on sqlserver2014a and sql2016

	.EXAMPLE
		Get-DbaRegisteredServerName -SqlInstance sql2016 | Test-DbaDatabaseCollation

		Returns db/server collation information for every database on every server listed in the Central Management Server on sql2016
	#>
	[CmdletBinding()]
	[OutputType("System.Collections.ArrayList")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]
		$Credential,
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
					Write-Warning "Can't connect to $servername. Moving on."
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
				Write-Verbose "Processing $($db.name) on $servername"
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

