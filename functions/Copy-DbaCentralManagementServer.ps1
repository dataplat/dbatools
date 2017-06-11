function Copy-DbaCentralManagementServer {
	<#
		.SYNOPSIS
			Migrates SQL Server Central Management groups and server instances from one SQL Server to another.

		.DESCRIPTION
			Copy-DbaCentralManagementServer copies all groups, subgroups, and server instances from one SQL Server to another.

		.PARAMETER Source
			The SQL Server Central Management Server you are migrating from.

		.PARAMETER SourceSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Destination
			The SQL Server Central Management Server you are migrating to.

		.PARAMETER DestinationSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER CMSGroup
			This is an auto-populated array that contains your Central Management Server top-level groups on $Source. You can specify one, many or none.
			If -CMSGroup is not specified, the Copy-DbaCentralManagementServer script will migrate all groups in your Central Management Server. Note this variable is only populated by top level groups.

		.PARAMETER ExcludeCMSGroup
			The CMSGroup(s) to exclude - this list is auto populated from the server.

		.PARAMETER SwitchServerName
			Central Management Server does not allow you to add a shared registered server with the same name as the Configuration Server. If you wish to change all migrating instance names of $Destination to $Source, use this switch.

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.PARAMETER Force
			Drops and recreates the CMS if it exists

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Migration
			Author: Chrissy LeMaire (@cl), netnerds.net
			Requires: sysadmin access on SQL Servers

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Copy-DbaCentralManagementServer

		.EXAMPLE
			Copy-DbaCentralManagementServer -Source sqlserver2014a -Destination sqlcluster

			In the above example, all groups, subgroups, and server instances are copied from sqlserver's Central Management Server to sqlcluster's Central Management Server.

		.EXAMPLE
			Copy-DbaCentralManagementServer -Source sqlserver2014a -Destination sqlcluster -ServerGroup Group1,Group3

			In the above example, top level Group1 and Group3, along with its subgroups and server instances are copied from sqlserver to sqlcluster.

		.EXAMPLE
			Copy-DbaCentralManagementServer -Source sqlserver2014a -Destination sqlcluster -ServerGroup Group1,Group3 -SwitchServerName -SourceSqlCredential $SourceSqlCredential -DestinationSqlCredential $DestinationSqlCredential

			In the above example, top level Group1 and Group3, along with its subgroups and server instances are copied from sqlserver to sqlcluster. When adding sql instances to sqlcluster, if the server name of the migrating instance is "sqlcluster", it will be switched to "sqlserver". If SwitchServerName is not specified, "sqlcluster" will be skipped.
	#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Source,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SourceSqlCredential,
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Destination,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$DestinationSqlCredential,
		[object[]]CMSGroup,
		[object[]]$ExcludeCMSGroup,
		[switch]$SwitchServerName,
		[switch]$Force
	)
	begin {
		function Parse-ServerGroup($sourceGroup, $destinationgroup, $SwitchServerName) {
			if ($destinationgroup.name -eq "DatabaseEngineServerGroup" -and $sourceGroup.name -ne "DatabaseEngineServerGroup") {
				$currentservergroup = $destinationgroup
				$groupname = $sourceGroup.name
				$destinationgroup = $destinationgroup.ServerGroups[$groupname]

				if ($destinationgroup -ne $null) {
					if ($force -eq $false) {
						Write-Warning "Destination group $groupname exists at destination. Use -Force to drop and migrate."
						continue
					}

					If ($Pscmdlet.ShouldProcess($destination, "Dropping group $groupname")) {
						try {
							Write-Verbose "Dropping Alert $alertname"
							$destinationgroup.Drop()
						}
						catch {
							Write-Exception $_
							continue
						}
					}
				}

				If ($Pscmdlet.ShouldProcess($destination, "Creating group $groupname")) {
					Write-Output "Creating group $($sourceGroup.name)"
					$destinationgroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($currentservergroup, $sourcegroup.name)
					$destinationgroup.Create()
				}
			}

			# Add Servers
			foreach ($instance in $sourceGroup.RegisteredServers) {
				$instancename = $instance.name
				$servername = $instance.ServerName

				if ($servername.ToLower() -eq $tocmstore.DomainInstanceName.ToLower()) {
					if ($SwitchServerName) {
						$servername = $fromcmstore.DomainInstanceName
						$instancename = $fromcmstore.DomainInstanceName
						Write-Output "SwitchServerName was used and new CMS equals current server name. $($tocmstore.DomainInstanceName.ToLower()) changed to $servername."
					}
					else {
						Write-Warning "$servername is Central Management Server. Add prohibited. Skipping."
						continue
					}
				}

				if ($destinationgroup.RegisteredServers.name -contains $instancename) {
					if ($force -eq $false) {
						Write-Warning "Instance $instancename exists in group $groupname at destination. Use -Force to drop and migrate."
						continue
					}

					If ($Pscmdlet.ShouldProcess($destination, "Dropping instance $instancename from $groupname and recreating")) {
						try {
							Write-Verbose "Dropping Alert $alertname"
							$destinationgroup.RegisteredServers[$instancename].Drop()
						}
						catch {
							Write-Exception $_
							continue
						}
					}
				}

				if ($Pscmdlet.ShouldProcess($destination, "Copying $instancename")) {
					$newserver = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($destinationgroup, $instancename)
					$newserver.ServerName = $servername
					$newserver.Description = $instance.Description

					if ($servername -ne $fromcmstore.DomainInstanceName) {
						$newserver.SecureConnectionString = $instance.SecureConnectionString.tostring()
						$newserver.ConnectionString = $instance.ConnectionString.tostring()
					}

					try {
						$newserver.Create()
					}
					catch {
						if ($_.Exception -match "same name") {
							Write-Error "Could not add Switched Server instance name."
							continue
						}
						else {
							Write-Error "Failed to add $servername"
						}
					}
					Write-Output "Added Server $servername as $instancename to $($destinationgroup.name)"
				}
			}

			# Add Groups
			foreach ($fromsubgroup in $sourceGroup.ServerGroups) {
				$fromsubgroupname = $fromsubgroup.name
				$tosubgroup = $destinationgroup.ServerGroups[$fromsubgroupname]

				if ($tosubgroup -ne $null) {

					if ($force -eq $false) {
						Write-Warning "Subgroup $fromsubgroupname exists at destination. Use -Force to drop and migrate."
						continue
					}

					If ($Pscmdlet.ShouldProcess($destination, "Dropping subgroup $fromsubgroupname recreating")) {
						try {
							Write-Verbose "Dropping subgroup $fromsubgroupname"
							$tosubgroup.Drop()
						}
						catch {
							Write-Exception $_
							continue
						}
					}
				}

				If ($Pscmdlet.ShouldProcess($destination, "Creating group $($fromsubgroup.name)")) {
					Write-Output "Creating group $($fromsubgroup.name)"
					$tosubgroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($destinationgroup, $fromsubgroup.name)
					$tosubgroup.create()
				}

				Parse-ServerGroup -sourceGroup $fromsubgroup -destinationgroup $tosubgroup -SwitchServerName $SwitchServerName
			}
		}

		$sourceserver = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName

		if ($sourceserver.versionMajor -lt 10 -or $destserver.versionMajor -lt 10) {
			throw "Central Management Server is only supported in SQL Server 2008 and above. Quitting."
		}
	}

	process {
		Write-Output "Connecting to Central Management Servers"

		try {
			$fromcmstore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($sourceserver.ConnectionContext.SqlConnectionObject)
			$tocmstore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($destserver.ConnectionContext.SqlConnectionObject)
		}
		catch {
			throw "Cannot access Central Management Servers"
		}

		if ($CMSGroup -eq $null) {
			$stores = $fromcmstore.DatabaseEngineServerGroup
		}
		else {
			$stores = @(); foreach ($groupname in $CMSGroup) { $stores += $fromcmstore.DatabaseEngineServerGroup.ServerGroups[$groupname] }
		}

		foreach ($store in $stores) {
			Parse-ServerGroup -sourceGroup $store -destinationgroup $tocmstore.DatabaseEngineServerGroup -SwitchServerName $SwitchServerName
		}
	}

	end {
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) {
			Write-Output "Central Management Server migration finished"
		}
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlCentralManagementServer
	}
}
