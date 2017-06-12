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
		[object[]]$CMSGroup,
		[object[]]$ExcludeCMSGroup,
		[switch]$SwitchServerName,
		[switch]$Force,
		[switch]$Silent
	)
	begin {
		function Invoke-ParseServerGroup {
			[cmdletbinding()]
			param (
				[object]$sourceGroup,
				[object]$destinationGroup,
				[switch]$SwitchServerName
			)
			if ($destinationGroup.Name -eq "DatabaseEngineServerGroup" -and $sourceGroup.Name -ne "DatabaseEngineServerGroup") {
				$currentServerGroup = $destinationGroup
				$groupName = $sourceGroup.Name
				$destinationGroup = $destinationGroup.ServerGroups[$groupName]

				$copyDestinationGroupStatus = [pscustomobject]@{
					SourceServer        = $sourceServer.Name
					DestinationServer   = $destServer.Name
					Name                = $destinationGroup
					Type                = "Create Destination Group"
					Status              = $null
					DateTime            = [sqlcollective.dbatools.Utility.DbaDateTime](Get-Date)
				}

				if ($null -ne $destinationGroup) {
					if ($force -eq $false) {
						$copyDestinationGroupStatus.Status = "Skipped"
						$copyDestinationGroupStatus
						Write-Message -Level Warning -Message "Destination group $groupName exists at destination. Use -Force to drop and migrate."
						continue
					}
					if ($Pscmdlet.ShouldProcess($destination, "Dropping group $groupName")) {
						try {
							Write-Message -Level Verbose -Message "Dropping group $groupName"
							$destinationGroup.Drop()
						}
						catch {
							$copyDestinationGroupStatus.Status = "Failed"
							$copyDestinationGroupStatus

							Stop-Function -Message "Issue dropping group" -Target $groupName -InnerErrorRecord $_ -Continue
						}
					}
				}

				if ($Pscmdlet.ShouldProcess($destination, "Creating group $groupName")) {
					Write-Message -Level Verbose -Message "Creating group $($sourceGroup.Name)"
					$destinationGroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($currentServerGroup, $sourceGroup.Name)
					$destinationGroup.Create()

					$copyDestinationGroupStatus.Status = "Successful"
					$copyDestinationGroupStatus
				}
			}

			# Add Servers
			foreach ($instance in $sourceGroup.RegisteredServers) {
				$instanceName = $instance.Name
				$serverName = $instance.ServerName

				$copyInstanceStatus = [pscustomobject]@{
					SourceServer        = $sourceServer.Name
					DestinationServer   = $destServer.Name
					Name                = $instanceName
					Type                = "Add Instance"
					Status              = $null
					DateTime            = [sqlcollective.dbatools.Utility.DbaDateTime](Get-Date)
				}

				if ($serverName.ToLower() -eq $toCmStore.DomainInstanceName.ToLower()) {
					if ($SwitchServerName) {
						$serverName = $fromCmStore.DomainInstanceName
						$instanceName = $fromCmStore.DomainInstanceName
						Write-Message -Level Verbose -Message "SwitchServerName was used and new CMS equals current server name. $($toCmStore.DomainInstanceName.ToLower()) changed to $serverName."
					}
					else {
						$copyInstanceStatus.Status = "Skipped"
						$copyInstanceStatus

						Write-Message -Level Warning -Message "$serverName is Central Management Server. Add prohibited. Skipping."
						continue
					}
				}

				if ($destinationGroup.RegisteredServers.Name -contains $instanceName) {
					if ($force -eq $false) {
						$copyInstanceStatus.Status = "Skipped"
						$copyInstanceStatus

						Write-Message -Level Warning -Message "Instance $instanceName exists in group $groupName at destination. Use -Force to drop and migrate."
						continue
					}

					if ($Pscmdlet.ShouldProcess($destination, "Dropping instance $instanceName from $groupName and recreating")) {
						try {
							Write-Message -Level Verbose -Message "Dropping instance $instance from $groupName"
							$destinationGroup.RegisteredServers[$instanceName].Drop()
						}
						catch {
							$copyInstanceStatus.Status = "Failed"
							$copyInstanceStatus

							Stop-Function -Message "Issue dropping instance from group" -Target $instanceName -InnerErrorRecord $_ -Continue
						}
					}
				}

				if ($Pscmdlet.ShouldProcess($destination, "Copying $instanceName")) {
					$newServer = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($destinationGroup, $instanceName)
					$newServer.ServerName = $serverName
					$newServer.Description = $instance.Description

					if ($serverName -ne $fromCmStore.DomainInstanceName) {
						$newServer.SecureConnectionString = $instance.SecureConnectionString.ToString()
						$newServer.ConnectionString = $instance.ConnectionString.ToString()
					}

					try {
						$newServer.Create()

						$copyInstanceStatus.Status = "Successful"
						$copyInstanceStatus
					}
					catch {
						$copyInstanceStatus.Status = "Failed"
						$copyInstanceStatus
						if ($_.Exception -match "same name") {
							Stop-Function -Message "Could not add Switched Server instance name." -Target $instanceName -InnerErrorRecord $_ -Continue
						}
						else {
							Stop-Function -Message "Failed to add $serverName" -Target $instanceName -InnerErrorRecord $_ -Continue
						}
					}
					Write-Message -Level Verbose -Message "Added Server $serverName as $instanceName to $($destinationGroup.Name)"
				}
			}

			# Add Groups
			foreach ($fromSubGroup in $sourceGroup.ServerGroups) {
				$fromSubGroupName = $fromSubGroup.Name
				$toSubGroup = $destinationGroup.ServerGroups[$fromSubGroupName]

				$copyGroupStatus = [pscustomobject]@{
					SourceServer      = $sourceServer.Name
					DestinationServer = $destServer.Name
					Name              = $fromSubGroupName
					Type              = "Add Group"
					Status            = $null
					DateTime          = [sqlcollective.dbatools.Utility.DbaDateTime](Get-Date)
				}

				if ($null -ne $toSubGroup) {
                    if ($force -eq $false) {
                        $copyGroupStatus.Status = "Skipped"
                        $copyGroupStatus
						
						Write-Message -Level Warning -Message "Subgroup $fromSubGroupName exists at destination. Use -Force to drop and migrate."
						continue
					}

					if ($Pscmdlet.ShouldProcess($destination, "Dropping subgroup $fromSubGroupName recreating")) {
                        try {
                            Write-Message -Level Verbose -Message "Dropping subgroup $fromSubGroupName"
                            $toSubGroup.Drop()
                        }
                        catch {
                            $copyGroupStatus.Status = "Failed"
                            $copyGroupStatus
							
                            Stop-Function -Message "Issue dropping subgroup" -Target $toSubGroup -InnerErrorRecord $_ -Continue
                        }
					}
				}

                if ($Pscmdlet.ShouldProcess($destination, "Creating group $($fromSubGroup.Name)")) {
                    Write-Message -Level Verbose -Message "Creating group $($fromSubGroup.Name)"
                    $toSubGroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($destinationGroup, $fromSubGroup.Name)
                    $toSubGroup.create()
					
                    $copyGroupStatus.Status = "Successful"
					$copyGroupStatus
                }

				Invoke-ParseServerGroup -sourceGroup $fromSubGroup -destinationgroup $toSubGroup -SwitchServerName $SwitchServerName
			}
		}

		$sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

		$source = $sourceServer.DomainInstanceName
		$destination = $destServer.DomainInstanceName

		if ($sourceServer.VersionMajor -lt 10 -or $destServer.VersionMajor -lt 10) {
			throw "Central Management Server is only supported in SQL Server 2008 and above. Quitting."
		}
	}

	process {
		Write-Message -Level Verbose -Message "Connecting to Central Management Servers"

		try {
			$fromCmStore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($sourceServer.ConnectionContext.SqlConnectionObject)
			$toCmStore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($destServer.ConnectionContext.SqlConnectionObject)
		}
		catch {
			throw "Cannot access Central Management Servers"
		}

		$stores = $fromCmStore.DatabaseEngineServerGroup
		if ($CMSGroup) {
			$stores = $stores | Where-Object GroupName -In $CMSGroup
		}
		if ($ExcludeCMSGroup) {
			$stores = $stores | Where-Object GroupName -NotIn $ExcludeCMSGroup
		}
		$stores = @();
		foreach ($groupName in $CMSGroup) {
			$stores += $fromCmStore.DatabaseEngineServerGroup.ServerGroups[$groupName]
		}

		foreach ($store in $stores) {
			Invoke-ParseServerGroup -sourceGroup $store -destinationgroup $toCmStore.DatabaseEngineServerGroup -SwitchServerName $SwitchServerName
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlCentralManagementServer
	}
}
