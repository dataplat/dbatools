function Set-DbaDatabaseOwner {
	<#
.SYNOPSIS
Sets database owners with a desired login if databases do not match that owner.

.DESCRIPTION
This function will alter database ownershipt to match a specified login if their current owner does not match the target login. By default, the target login will be 'sa', but the fuction will allow the user to specify a different login for  ownership. The user can also apply this to all databases or only to a select list of databases (passed as either a comma separated list or a string array).

Best Practice reference: http://weblogs.sqlteam.com/dang/archive/2008/01/13/Database-Owner-Troubles.aspx

.PARAMETER SqlInstance
SQLServer name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input

.PARAMETER SqlCredential
PSCredential object to connect under. If not specified, current Windows login will be used.

.PARAMETER Database
The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

.PARAMETER ExcludeDatabase
The database(s) to exclude - this list is auto-populated from the server

.PARAMETER TargetLogin
Specific login that you wish to check for ownership. This defaults to 'sa' or the sysadmin name if sa was renamed.

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.

.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.NOTES
Author: Michael Fal (@Mike_Fal), http://mikefal.net

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Set-DbaDatabaseOwner

.EXAMPLE
Set-DbaDatabaseOwner -SqlInstance localhost

Sets database owner to 'sa' on all databases where the owner does not match 'sa'.

.EXAMPLE
Set-DbaDatabaseOwner -SqlInstance localhost -TargetLogin DOMAIN\account

To set the database owner to DOMAIN\account on all databases where the owner does not match DOMAIN\account. Note that TargetLogin must be a valid security principal that exists on the target server.

.EXAMPLE
Set-DbaDatabaseOwner -SqlInstance sqlserver -Database db1, db2

Sets database owner to 'sa' on the db1 and db2 databases if their current owner does not match 'sa'.
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential]
		$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$ExcludeDatabase,
		[string]$TargetLogin,
		[switch]$Silent
	)

	process {
		foreach ($instance in $SqlInstance) {
			Write-Message -Level Verbose -Message "Connecting to $instance"
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $Credential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}

			# dynamic sa name for orgs who have changed their sa name
			if (!$TargetLogin) {
				$TargetLogin = ($server.logins | Where-Object { $_.id -eq 1 }).Name
			}

			#Validate login
			if (($server.Logins.Name) -notcontains $TargetLogin) {
				Stop-Function -Message "$TargetLogin is not a valid login on $instance. Moving on." -Continue -Silent $Silent
			}
			
			#Owner cannot be a group
			$TargetLoginObject = $server.Logins | where Name -eq $TargetLogin | select Name, LoginType
			if ($TargetLoginObject.LoginType -eq 'WindowsGroup') {
				Stop-Function -Message "$TargetLogin is a group, therefore can't be set as owner. Moving on." -Continue -Silent $Silent
			}
			
			#Get database list. If value for -Database is passed, massage to make it a string array.
			#Otherwise, use all databases on the instance where owner not equal to -TargetLogin
			#use where owner and target login do not match
			#exclude system dbs
			$dbs = $server.Databases | Where-Object {$_.Owner -ne $TargetLogin -and @('master', 'model', 'msdb', 'tempdb', 'distribution') -notcontains $_.Name}

			#filter collection based on -Databases/-Exclude parameters
			if ($Database) {
				$dbs = $dbs | Where-Object { $Database -contains $_.Name }
			}

			if ($ExcludeDatabase) {
				$dbs = $dbs | Where-Object { $ExcludeDatabase -notcontains $_.Name }
			}

			Write-Message -Level Verbose -Message "Updating $($dbs.Count) database(s)."
			foreach ($db in $dbs) {
				$dbname = $db.name
				If ($PSCmdlet.ShouldProcess($instance, "Setting database owner for $dbname to $TargetLogin")) {
					try {
						Write-Message -Level Verbose -Message "Setting database owner for $dbname to $TargetLogin on $instance"
						# Set database owner to $TargetLogin (default 'sa')
						# Ownership validations checks

						#Database is online and accessible
						if ($db.Status -ne 'Normal') {
							Write-Message -Level Warning -Message "$dbname on $instance is in a  $($db.Status) state and can not be altered. It will be skipped."
						}
						#Database is updatable, not read-only
						elseif ($db.IsUpdateable -eq $false) {
							Write-Message -Level Warning -Message "$dbname on $instance is not in an updateable state and can not be altered. It will be skipped."
						}
						#Is the login mapped as a user? Logins already mapped in the database can not be the owner
						elseif ($db.Users.name -contains $TargetLogin) {
							Write-Message -Level Warning -Message "$dbname on $instance has $TargetLogin as a mapped user. Mapped users can not be database owners."
						}
						else {
							$db.SetOwner($TargetLogin)
							[PSCustomObject]@{
								ComputerName = $server.NetName
								InstanceName = $server.ServiceName
								SqlInstance = $server.DomainInstanceName
								Database = $db
								Owner = $TargetLogin
							}
						}
					}
					catch {
						Stop-Function -Message "Failure updating owner" -ErrorRecord $_ -Target $instance -Continue
					}
				}
			}
		}
	}
}

