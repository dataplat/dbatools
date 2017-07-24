function Sync-DbaSqlLoginPermission {
	<#
		.SYNOPSIS
			Copies SQL login permission from one server to another.

		.DESCRIPTION
			Syncs only SQL Server login permissions, roles, etc. Does not add or drop logins. If a matching login does not exist on the destination, the login will be skipped.
			Credential removal not currently supported for Syncs. TODO: Application role sync

		.PARAMETER Source
			Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

		.PARAMETER SourceSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Destination
			Destination SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

		.PARAMETER DestinationSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Login
			Migrates ONLY specified logins. This list is auto-populated for tab completion. Multiple logins allowed.

		.PARAMETER ExcludeLogin
			Excludes specified logins. This list is auto-populated for tab completion.

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.PARAMETER Silent 
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Migration, Login
			Original Author: Chrissy LeMaire (@cl), netnerds.net
			Requires: sysadmin access on SQL Servers
			Limitations: Does not support Application Roles yet

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Sync-DbaSqlLoginPermission

		.EXAMPLE
			Sync-DbaSqlLoginPermission -Source sqlserver2014a -Destination sqlcluster

			Syncs only SQL Server login permissions, roles, etc. Does not add or drop logins or users. To copy logins and their permissions, use Copy-SqlLogin.

		.EXAMPLE
			Sync-DbaSqlLoginPermission -Source sqlserver2014a -Destination sqlcluster -Exclude realcajun -SourceSqlCredential $scred -DestinationSqlCredential $dcred

			Authenticates to SQL Servers using SQL Authentication.

			Copies all login permissions except for realcajun. If a login already exists on the destination, the permissions will not be migrated.

		.EXAMPLE
			Sync-DbaSqlLoginPermission -Source sqlserver2014a -Destination sqlcluster -Login realcajun, netnerds

			Copies permissions ONLY for logins netnerds and realcajun.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[DbaInstanceParameter]$Source,
		[PSCredential]
		$SourceSqlCredential,
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Destination,
		[PSCredential]
		$DestinationSqlCredential,
		[object[]]$Login,
		[object[]]$ExcludeLogin,
		[switch]$Silent
	)
	begin {
		function Sync-Only {
			[CmdletBinding()]
			param (
				[Parameter(Mandatory = $true)]
				[ValidateNotNullOrEmpty()]
				[object]$sourceServer,
				[object]$destServer,
				[array]$Logins,
				[array]$Exclude
			)

			try {
				$sa = ($destServer.Logins | Where-Object { $_.id -eq 1 }).Name
			}
			catch {
				$sa = "sa"
			}

			foreach ($sourceLogin in $sourceServer.Logins) {

				$username = $sourceLogin.Name
				$currentLogin = $sourceServer.ConnectionContext.TrueLogin

				if (!$Login -and $currentLogin -eq $username) {
					Write-Message -Level Warning -Message "Sync does not modify the permissions of the current user. Skipping."
					continue
				}

				if ($Logins -ne $null -and $Logins -notcontains $username) {
					continue
				}
				
				if ($Exclude -contains $username -or $username.StartsWith("##") -or $username -eq $sa) {
					continue
				}

				$serverName = Resolve-NetBiosName $sourceServer
				$userBase = ($username.Split("\")[0]).ToLower()
				if ($serverName -eq $userBase -or $username.StartsWith("NT ")) {
					continue
				}
				if (($destLogin = $destServer.Logins.Item($username)) -eq $null) {
					continue
				}

				Update-SqlPermissions -SourceServer $sourceServer -SourceLogin $sourceLogin -DestServer $destServer -DestLogin $destLogin
			}
		}

		if ($source -eq $destination) {
			Stop-Function -Message "Source and Destination SQL Servers are the same. Quitting."
			return
		}

		Write-Message -Level Verbose -Message "Attempting to connect to SQL Servers.."
		$sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 8
		$destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential -MinimumVersion 8

		$source = $sourceServer.DomainInstanceName
		$destination = $destServer.DomainInstanceName
	}
	process {
		if (Test-FunctionInterrupt) { return }

		if (!$Login) {
			$logins = $sourceServer.Logins.Name
		}

		Sync-Only -SourceServer $sourceServer -DestServer $destServer -Logins $logins -Exclude $ExcludeLogin
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Sync-DbaSqlLoginPermission
	}
}