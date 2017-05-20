function Test-DbaDatabaseOwner {
	<#
	.SYNOPSIS
		Checks database owners against a login to validate which databases do not match that owner.

	.DESCRIPTION
		This function will check all databases on an instance against a SQL login to validate if that
		login owns those databases or not. By default, the function will check against 'sa' for
		ownership, but the user can pass a specific login if they use something else. Only databases
		that do not match this ownership will be displayed, but if the -Detailed switch is set all
		databases will be shown.

		Best Practice reference: http://weblogs.sqlteam.com/dang/archive/2008/01/13/Database-Owner-Troubles.aspx

	.NOTES
		Original Author: Michael Fal (@Mike_Fal), http://mikefal.net

		Website: https://dbatools.io
		Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.PARAMETER SqlInstance
		SQLServer name or SMO object representing the SQL Server to connect to. This can be a
		collection and recieve pipeline input

	.PARAMETER SqlCredential
		PSCredential object to connect under. If not specified, currend Windows login will be used.

	.PARAMETER Database
		The database(s) to process - this list is autopopulated from the server. If unspecified, all databases will be processed.

	.PARAMETER Exclude
		The database(s) to exclude - this list is autopopulated from the server

	.PARAMETER TargetLogin
		Specific login that you wish to check for ownership. This defaults to 'sa' or the sysadmin name if sa was renamed.

	.PARAMETER Detailed
		Switch parameter. When declared, function will return all databases and whether or not they
		match the declared owner.

	.LINK
		https://dbatools.io/Test-DbaDatabaseOwner

	.EXAMPLE
		Test-DbaDatabaseOwner -SqlInstance localhost

		Returns all databases where the owner does not match 'sa'.

	.EXAMPLE
		Test-DbaDatabaseOwner -SqlInstance localhost -TargetLogin 'DOMAIN\account'

		Returns all databases where the owner does not match 'DOMAIN\account'. Note
		that TargetLogin must be a valid security principal that exists on the target server.
	#>
	[OutputType("System.Object[]")]
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$Exclude,
		[string]$TargetLogin,
		[Switch]$Detailed
	)

	begin {
		#connect to the instance and set return array empty
		$return = @()
	}

	process {
		foreach ($servername in $SqlInstance) {
			Write-Verbose "Connecting to $servername"
			$server = Connect-SqlInstance $servername -SqlCredential $SqlCredential

			# dynamic sa name for orgs who have changed their sa name
			if ($TargetLogin.length -eq 0) {
				$TargetLogin = ($server.logins | Where-Object { $_.id -eq 1 }).Name
			}
			
			#Validate login
			if (($server.Logins.Name) -notcontains $TargetLogin) {
				if ($SqlInstance.count -eq 1) {
					throw "Invalid login: $TargetLogin"
					return $null
				}
				else {
					Write-Warning "$TargetLogin is not a valid login on $servername. Moving on."
					Continue
				}
			}
			#use online/available dbs
			$dbs = $server.Databases

			#filter database collection based on parameters
			if ($Database.Length -gt 0) {
				$dbs = $dbs | Where-Object { $Database -contains $_.Name }
			}

			if ($Exclude.Length -gt 0) {
				$dbs = $dbs | Where-Object Name -NotIn $Exclude
			}

			#for each database, create custom object for return set.
			foreach ($db in $dbs) {
				Write-Verbose "Checking $db"
				$row = [ordered]@{
					Server       = $server.Name
					Database     = $db.Name
					DBState      = $db.Status
					CurrentOwner = $db.Owner
					TargetOwner  = $TargetLogin
					OwnerMatch   = ($db.owner -eq $TargetLogin)
				}

				#add each custom object to the return array
				$return += New-Object PSObject -Property $row
			}
		}
	}

	end {
		#return results
		if ($Detailed) {
			Write-Verbose "Returning detailed results."
			return $return
		}
		else {
			Write-Verbose "Returning default results."
			return ($return | Where-Object { $_.OwnerMatch -eq $false })
		}
	}
}

