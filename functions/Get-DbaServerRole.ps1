function Get-DbaServerRole {
	<#
		.SYNOPSIS
			Gets list of server-level roles and members

		.DESCRIPTION
			The SQL Server instance. Server version must be SQL Server version 2005 or higher.

		.PARAMETER SqlInstance
			SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and recieve pipeline input to allow  the function to be executed against multiple SQL Server instances.

		.PARAMETER SqlCredential
			Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

			$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

			Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

			To connect as a different Windows user, run PowerShell as that user.

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
	#>
	[CmdletBinding()]
	param (
		[Parameter(Position= 0, Mandatory= $true, ValueFromPipeline= $true)]
		[DbaInstance[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[object[]]$ServerRole,
		[object[]]$ExcludeServerRole,
		[Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
		[object[]]$Login,
		[switch]$IsMember,
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

			foreach ($role in $roles) {
				$members = $role.EnumMemberNames()

				if ($members) {
					foreach ($member in $members) {
						if ($Login -and $member -ne $Login) { continue }
						if ($Login -and $IsMember -and $ServerRole) {
							$roleMember = [PSCustomObject]@{
								ComputerName = $server.NetName
								Instance     = $server.ServiceName
								SqlInstance  = $server.DomainInstanceName
								Role         = $role.Name
								IsMember     = $null
							}

							if ($member -eq $Login) {
								$roleMember.IsMember = $true
							}
						}

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

		} #end foreach instance
	} #end process
} #end function