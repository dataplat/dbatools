function Get-DbaServerRole {
	<#
		.SYNOPSIS
			Gets the list of server-level roles with the logins that are members of that role.

		.DESCRIPTION
			Gets the list of server-level role for SQL Server instance. Output will include the logins that are members of the server-level role(s).

		.PARAMETER SqlInstance
			The SQL Server instance. Server version must be SQL Server version 2005 or higher.

		.PARAMETER SqlCredential
			Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

			$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

			Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER ServerRole
			Server-Level role to filter results to that role only.

		.PARAMETER ExcludeServerRole
			Server-Level role to exclude from results.

		.PARAMETER ExcludeFixedRole
			Filter the fixed server-level roles. Only applies to SQL Server 2017 that supports custom server-level roles.

		.PARAMETER Login
			SQL Server login to filter results, will only return roles where the login(s) are a member.

		.PARAMETER EnableException
			By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message. This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting. Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

		.NOTES
			Tags: ServerRole, Security
			Original Author: Shawn Melton (@wsmelton)

			Website: https: //dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https: //opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaServerRole

		.EXAMPLE
			Get-DbaServerRole -SqlInstance sql2016a

			Outputs list of server-level roles and logins that are members for sql2016a instance.

		.EXAMPLE
			Get-DbaServerRole -SqlInstance sql2016a -Role sysadmin

			Outputs members of sysadmin server-level role on sql2016a instance.

		.EXAMPLE
			Get-DbaServerRole -SqlInstance sql2017a -ExcludeFixedRole

			Outputs the user server-level role(s) on sql2017a instance. A SQL Server 2017 supported feature only.

		.EXAMPLE
			Get-DbaServerRole -SqlInstance sql2016a -Login Bob

			Outputs the server-level role(s) that the login Bob is a member of on sql2016a instance.

			If Bob is not a member of any role, no output is returned.

		.EXAMPLE
			Get-DbaServerRole -SqlInstance sql2016a -Role sysadmin -Login Bob

			Outputs the server-level role sysadmin with the login Bob as a member on sql2016a instance.

			If Bob is not a member of that role, no output is returned.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Position= 0, Mandatory= $true, ValueFromPipeline= $true)]
		[DbaInstance[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[object[]]$ServerRole,
		[object[]]$ExcludeServerRole,
		[switch]$ExcludeFixedRole,
		[Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
		[object[]]$Login,
		[switch]$EnableException
	)

	process {
		foreach ($instance in $SqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}

			$roles = $server.Roles

			if ($ServerRole) {
				$roles = $roles | Where-Object Name -In $ServerRole
			}
			if ($ExcludeServerRole) {
				$roles = $roles | Where-Object Name -NotIn $ExcludeServerRole
			}
			if ($ExcludeFixedRole) {
				$roles = $roles | Where-Object IsFixedRole -eq $false
			}

			foreach ($role in $roles) {
				$members = $role.EnumMemberNames()
				if ($Login) {
					$members = $members | Where-Object {$_ -in $Login}
				}

				if ($members) {
					foreach ($member in $members) {
						Add-Member -Force -InputObject $role -MemberType NoteProperty -Name Login -Value $member
						Add-Member -Force -InputObject $role -MemberType NoteProperty -Name ComputerName -value $server.NetName
						Add-Member -Force -InputObject $role -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
						Add-Member -Force -InputObject $role -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName

						$default = 'ComputerName', 'InstanceName', 'SqlInstance', 'Id', 'Name as Role', 'IsFixedRole', 'Owner', 'Login', 'DateCreated', 'DateModified'
						Select-DefaultView -InputObject $role -Property $default
					}
				}
				if (!$members -and !$Login) {
					Add-Member -Force -InputObject $role -MemberType NoteProperty -Name ComputerName -value $server.NetName
					Add-Member -Force -InputObject $role -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
					Add-Member -Force -InputObject $role -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName

					$default = 'ComputerName', 'InstanceName', 'SqlInstance', 'Id', 'Name as Role', 'IsFixedRole', 'Owner', 'Login', 'DateCreated', 'DateModified'
					Select-DefaultView -InputObject $role -Property $default
				}
			}
		}
	}
}