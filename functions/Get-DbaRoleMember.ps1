function Get-DbaRoleMember {
	<#
		.SYNOPSIS
			Get members of all roles on a Sql instance.

		.DESCRIPTION
			Get members of all roles on a Sql instance.

			Default output includes columns SQLServer, Database, Role, Member.

		.PARAMETER SQLInstance
			The SQL Server that you're connecting to.

		.PARAMETER SqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

			SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Database
			The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

		.PARAMETER ExcludeDatabase
			The database(s) to exclude - this list is auto-populated from the server

		.PARAMETER IncludeServerLevel
			Shows also information on Server Level Permissions.

		.PARAMETER NoFixedRole
			Excludes all members of fixed roles.

		.PARAMETER Silent
			If this switch is enabled, the internal messaging functions will be silenced.

		.NOTES
			Tags: Roles, Databases
			Author: Klaas Vandenberghe ( @PowerDBAKlaas )

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaRoleMember

		.EXAMPLE
			Get-DbaRoleMember -SqlInstance ServerA

			Returns a custom object displaying SQLServer, Database, Role, Member for all DatabaseRoles.

		.EXAMPLE
			Get-DbaRoleMember -SqlInstance sql2016 | Out-GridView

			Returns a grid view displaying SQLServer, Database, Role, Member for all DatabaseRoles.

		.EXAMPLE
			Get-DbaRoleMember -SqlInstance ServerA\sql987 -IncludeServerLevel

			Returns SQLServer, Database, Role, Member for both ServerRoles and DatabaseRoles.

	#>
	[CmdletBinding()]
	param (
		[parameter(Mandatory, ValueFromPipeline)]
		[Alias('SqlServer', 'ServerInstance')]
		[DbaInstance[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential]$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$ExcludeDatabase,
		[switch]$IncludeServerLevel,
		[switch]$NoFixedRole,
		[switch]$Silent
	)

	process {

		foreach ($instance in $SqlInstance) {
			Write-Message -Level Verbose -Message "Connecting to $Instance"
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Stop-Function -Message "Failure connecting to $Instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}

			if ($IncludeServerLevel) {
				Write-Message -Level Verbose -Message"Server Role Members included"
				$instRoles = $null
				Write-Message -Level Verbose -Message "Getting Server Roles on $instance"
				$instRoles = $server.Roles
				if ($NoFixedRole) {
					$instRoles = $instRoles | Where-Object IsFixedRole -eq $false
				}
				ForEach ($instRole in $instRoles) {
					Write-Message -Level Verbose -Message "Getting Server Role Members for $instRole on $instance"
					$irMembers = $null
					$irMembers = $instRole.EnumServerRoleMembers()
					ForEach ($irMem in $irMembers) {
						[PSCustomObject]@{
							ComputerName = $server.NetName
							InstanceName = $server.ServiceName
							SqlInstance = $server.DomainInstanceName
							Database    = $null
							Role        = $instRole.Name
							Member      = $irMem.ToString()
						}
					}
				}
			}

			$dbs = $server.Databases
			if ($Database) {
				$dbs = $dbs | Where-Object Name -In $Database
			}
			if ($Exclude) {
				$dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
			}

			foreach ($db in $dbs) {
				Write-Message -Level Verbose -Message "Checking accessibility of $db on $instance"

				if ($db.IsAccessible -ne $true) {
					Write-Message -Level Warning -Message "Database $db on $instance is not accessible"
					continue
				}

				$dbRoles = $db.Roles
				Write-Message -Level Verbose -Message "Getting Database Roles for $db on $instance"

				if ($NoFixedRole) {
					$dbRoles = $dbRoles | Where-Object IsFixedRole -eq $false
				}

				foreach ($dbRole in $dbRoles) {
					Write-Message -Level Verbose -Message "Getting Database Role Members for $dbRole in $db on $instance"
					$dbMembers = $dbRole.EnumMembers()
					ForEach ($dbMem in $dbMembers) {
						[PSCustomObject]@{
							ComputerName = $server.NetName
							InstanceName = $server.ServiceName
							SqlInstance = $server.DomainInstanceName
							Database    = $db.Name
							Role        = $dbRole.Name
							Member      = $dbMem.ToString()
						}
					}
				}
			}
		}
	}
}
