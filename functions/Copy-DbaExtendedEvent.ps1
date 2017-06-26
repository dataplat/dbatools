function Copy-DbaExtendedEvent {
	<#
		.SYNOPSIS
			Migrates SQL Extended Event Sessions except the two default sessions, AlwaysOn_health and system_health.

		.DESCRIPTION
			By default, all non-system extended events are migrated. If the event already exists on the destination, it will be skipped unless -Force is used.

			The -Session parameter is autopopulated for command-line completion and can be used to copy only specific objects.

		.PARAMETER Source
			Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2008 or higher.

		.PARAMETER SourceSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Destination
			Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

		.PARAMETER DestinationSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER XeSession
			The Extended Event Session(s) to process - this list is auto populated from the server. If unspecified, all Extended Event  Sessions will be processed.

		.PARAMETER ExcludeXeSession
			The Extended Event Session(s) to exclude - this list is auto populated from the server

		.PARAMETER Force
			If sessions exists on destination server, it will be dropped and recreated.

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.PARAMETER Silent 
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Migration, ExtendedEvent, XEvent
			Author: Chrissy LeMaire (@cl), netnerds.net
			Requires: sysadmin access on SQL Servers

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Copy-DbaExtendedEvent

		.EXAMPLE
			Copy-DbaExtendedEvent -Source sqlserver2014a -Destination sqlcluster

			Copies all extended event sessions from sqlserver2014a to sqlcluster, using Windows credentials.

		.EXAMPLE
			Copy-DbaExtendedEvent -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

			Copies all extended event sessions from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

		.EXAMPLE
			Copy-DbaExtendedEvent -Source sqlserver2014a -Destination sqlcluster -WhatIf

			Shows what would happen if the command were executed.

		.EXAMPLE
			Copy-DbaExtendedEvent -Source sqlserver2014a -Destination sqlcluster -XeSession CheckQueries, MonitorUserDefinedException

			Copies two Extended Events, CheckQueries and MonitorUserDefinedException, from sqlserver2014a to sqlcluster.
	#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Source,
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Destination,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SourceSqlCredential,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$DestinationSqlCredential,
		[object[]]$XeSession,
		[object[]]$ExcludeXeSession,
		[switch]$Force,
		[switch]$Silent
	)
	begin {

		if ([System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.XEvent") -eq $null) {
			throw "SMO version is too old. To migrate Extended Events, you must have SQL Server Management Studio 2008 R2 or higher installed."
		}

		$sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

		$source = $sourceServer.DomainInstanceName
		$destination = $destServer.DomainInstanceName

		if ($sourceServer.VersionMajor -lt 10 -or $destServer.VersionMajor -lt 10) {
			throw "Extended Events are only supported in SQL Server 2008 and above. Quitting."
		}
	}
	process {

		$sourceSqlConn = $sourceServer.ConnectionContext.SqlConnectionObject
		$sourceSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $sourceSqlConn
		$sourceStore = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $sourceSqlStoreConnection

		$destSqlConn = $destServer.ConnectionContext.SqlConnectionObject
		$destSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $destSqlConn
		$destStore = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $destSqlStoreConnection

		$storeSessions = $sourceStore.Sessions | Where-Object { $_.Name -notin 'AlwaysOn_health', 'system_health' }
		if ($XeSession) {
			$storeSessions = $storeSessions | Where-Object Name -In $XeSession
		}
		if ($ExcludeXeSession) {
			$storeSessions = $storeSessions | Where-Object Name -NotIn $ExcludeXeSession
		}

		Write-Output "Migrating sessions"
		foreach ($session in $storeSessions) {
			$sessionName = $session.Name
			if ($destStore.Sessions[$sessionName] -ne $null) {
				if ($force -eq $false) {
					Write-Warning "Extended Event Session '$sessionName' was skipped because it already exists on $destination"
					Write-Warning "Use -Force to drop and recreate"
					continue
				}
				else {
					if ($Pscmdlet.ShouldProcess($destination, "Attempting to drop $sessionName")) {
						Write-Verbose "Extended Event Session '$sessionName' exists on $destination"
						Write-Verbose "Force specified. Dropping $sessionName."

						try {
							$destStore.Sessions[$sessionName].Drop()
						}
						catch {
							Write-Exception "Unable to drop: $_  Moving on."
							continue
						}
					}
				}
			}

			if ($Pscmdlet.ShouldProcess($destination, "Migrating session $sessionName")) {
				try {
					$sql = $session.ScriptCreate().GetScript() | Out-String
					
					Write-Verbose $sql
					Write-Output "Migrating session $sessionName"
					$null = $destServer.ConnectionContext.ExecuteNonQuery($sql)

					if ($session.IsRunning -eq $true) {
						$destStore.Sessions.Refresh()
						$destStore.Sessions[$sessionName].Start()
					}
				}
				catch {
					Write-Exception $_
				}
			}
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlExtendedEvent
	}
}