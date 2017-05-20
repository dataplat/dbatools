function Test-DbaDatabaseCompatibility {
	<#
	.SYNOPSIS
		Compares Database Compatibility level to Server Compatibility

	.DESCRIPTION
		Compares Database Compatibility level to Server Compatibility

	.PARAMETER SqlServer
		The SQL Server that you're connecting to.

	.PARAMETER Credential
		Credential object used to connect to the SQL Server as a different user

	.PARAMETER Database
		The database(s) to process - this list is autopopulated from the server. If unspecified, all databases will be processed.

	.PARAMETER Exclude
		The database(s) to exclude - this list is autopopulated from the server

	.PARAMETER Detailed
		Shows detailed information about the server and database compatibility level

	.NOTES
		Website: https://dbatools.io
		Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
		https://dbatools.io/Test-DbaDatabaseCompatibility

	.EXAMPLE
		Test-DbaDatabaseCompatibility -SqlServer sqlserver2014a

		Returns server name, databse name and true/false if the compatibility level match for all databases on sqlserver2014a

	.EXAMPLE
		Test-DbaDatabaseCompatibility -SqlServer sqlserver2014a -Database db1, db2

		Returns server name, databse name and true/false if the compatibility level match for the db1 and db2 databases on sqlserver2014a

	.EXAMPLE
		Test-DbaDatabaseCompatibility -SqlServer sqlserver2014a, sql2016 -Detailed -Exclude db1

		Lots of detailed information for database and server compatibility level for all databases except db1 on sqlserver2014a and sql2016

	.EXAMPLE
		Get-SqlRegisteredServerName -SqlServer sql2014 | Test-DbaDatabaseCompatibility

		Returns db/server compatibility information for every database on every server listed in the Central Management Server on sql2016
	#>
	[CmdletBinding()]
	[OutputType("System.Collections.ArrayList")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string[]]$SqlServer,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$Credential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$Exclude,
		[switch]$Detailed
	)

	begin {
		$collection = New-Object System.Collections.ArrayList
	}

	process {
		foreach ($servername in $SqlServer) {
			Write-Verbose "Connecting to $servername"
			try {
				$server = Connect-SqlServer -SqlServer $servername -SqlCredential $Credential
			}
			catch {
				if ($SqlServer.count -eq 1) {
					throw $_
				}
				else {
					Write-Warning "Can't connect to $servername. Moving on."
					Continue
				}
			}

			$serverversion = "Version$($server.VersionMajor)0"
			$dbs = $server.Databases

			if ($Database.count -gt 0) {
				$dbs = $dbs | Where-Object { $Database -contains $_.Name }
			}

			if ($Exclude.count -gt 0) {
				$dbs = $dbs | Where-Object Name -NotIn $Exclude
			}

			foreach ($db in $dbs) {
				Write-Verbose "Processing $($db.name) on $servername"
				$null = $collection.Add([PSCustomObject]@{
						Server                = $server.name
						ServerLevel           = $serverversion
						Database              = $db.name
						DatabaseCompatibility = $db.CompatibilityLevel
						IsEqual               = $db.CompatibilityLevel -eq $serverversion
					})
			}
		}
	}

	END {
		if ($Detailed -eq $true) {
			return $collection
		}

		if ($Database.count -eq 1) {
			if ($sqlserver.count -eq 1) {
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

