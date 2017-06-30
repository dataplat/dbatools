function Copy-DbaEndpoint {
	<#
		.SYNOPSIS
			Copy-DbaEndpoint migrates server endpoints from one SQL Server to another.

		.DESCRIPTION
			By default, all endpoints are copied. The -Endpoints parameter is autopopulated for command-line completion and can be used to copy only specific endpoints.

			If the endpoint already exists on the destination, it will be skipped unless -Force is used.

		.PARAMETER Source
			Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

		.PARAMETER SourceSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Destination
			Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

		.PARAMETER DestinationSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Endpoint
			The endpoint(s) to process - this list is auto populated from the server. If unspecified, all endpoints will be processed.

		.PARAMETER ExcludeEndpoint
			The endpoint(s) to exclude - this list is auto populated from the server

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.PARAMETER Force
			Drops and recreates the endpoint if it exists

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Migration, Endpoint
			Author: Chrissy LeMaire (@cl), netnerds.net
			Requires: sysadmin access on SQL Servers

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Copy-DbaEndpoint

		.EXAMPLE
			Copy-DbaEndpoint -Source sqlserver2014a -Destination sqlcluster

			Copies all server endpoints from sqlserver2014a to sqlcluster, using Windows credentials. If endpoints with the same name exist on sqlcluster, they will be skipped.

		.EXAMPLE
			Copy-DbaEndpoint -Source sqlserver2014a -SourceSqlCredential $cred -Destination sqlcluster -Endpoint tg_noDbDrop -Force

			Copies a single endpoint, the tg_noDbDrop endpoint from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If an endpoint with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

		.EXAMPLE
			Copy-DbaEndpoint -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

			Shows what would happen if the command were executed using force.
	#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Source,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SourceSqlCredential,
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Destination,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$DestinationSqlCredential,
		[object[]]$Endpoint,
		[object[]]$ExcludeEndpoint,
		[switch]$Force,
		[switch]$Silent
	)

	begin {

		$sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

		$source = $sourceServer.DomainInstanceName
		$destination = $destServer.DomainInstanceName

		if ($sourceServer.VersionMajor -lt 9 -or $destServer.VersionMajor -lt 9) {
			throw "Server Endpoints are only supported in SQL Server 2008 and above. Quitting."
		}
	}
	process {

		$serverEndpoints = $sourceServer.Endpoints | Where-Object IsSystemObject -eq $false
		$destEndpoints = $destServer.Endpoints

		foreach ($currentEndpoint in $serverEndpoints) {
			$endpointName = $currentEndpoint.Name

			$copyEndpointStatus = [pscustomobject]@{
				SourceServer        = $sourceServer.Name
				DestinationServer   = $destServer.Name
				Name                = $endpointName
				Status              = $null
				DateTime            = [DbaDateTime](Get-Date)
			}

			if ($Endpoint -and $Endpoint -notcontains $endpointName -or $ExcludeEndpoint -contains $endpointName) {
				continue
			}

			if ($destEndpoints.Name -contains $endpointName) {
				if ($force -eq $false) {
					$copyEndpointStatus.Status = "Skipped"
					$copyEndpointStatus

					Write-Message -Level Warning -Message "Server endpoint $endpointName exists at destination. Use -Force to drop and migrate."
					continue
				}
				else {
					if ($Pscmdlet.ShouldProcess($destination, "Dropping server endpoint $endpointName and recreating")) {
						try {
							Write-Message -Level Verbose -Message "Dropping server endpoint $endpointName"
							$destServer.Endpoints[$endpointName].Drop()
						}
						catch {
							$copyEndpointStatus.Status = "Failed"
							$copyEndpointStatus

							Stop-Function -Message "Issue dropping server endpoint" -Target $endpointName -InnerErrorRecord $_ -Continue
						}
					}
				}
			}

			if ($Pscmdlet.ShouldProcess($destination, "Creating server endpoint $endpointName")) {
				try {
					Write-Message -Level Verbose -Message "Copying server endpoint $endpointName"
					$destServer.ConnectionContext.ExecuteNonQuery($currentEndpoint.Script()) | Out-Null

					$copyEndpointStatus.Status = "Successful"
					$copyEndpointStatus
				}
				catch {
					$copyEndpointStatus.Status = "Failed"
					$copyEndpointStatus

					Stop-Function -Message "Issue creating server endpoint" -Target $endpointName -InnerErrorRecord $_
				}
			}
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlEndpoint
	}
}