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
			Tags: Migration
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
		[switch]$Force
	)

	begin {

		$sourceserver = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName

		if ($sourceserver.versionMajor -lt 9 -or $destserver.versionMajor -lt 9) {
			throw "Server Endpoints are only supported in SQL Server 2008 and above. Quitting."
		}
	}
	process {

		$serverendpoints = $sourceserver.Endpoints | Where-Object { $_.IsSystemObject -eq $false }
		$destendpoints = $destserver.Endpoints

		foreach ($endpoint in $serverendpoints) {
			$endpointname = $endpoint.name

			if ($endpoints.length -gt 0 -and $endpoints -notcontains $endpointname) { continue }

			if ($destendpoints.name -contains $endpointname) {
				if ($force -eq $false) {
					Write-Warning "Server endpoint $endpointname exists at destination. Use -Force to drop and migrate."
					continue
				}
				else {
					If ($Pscmdlet.ShouldProcess($destination, "Dropping server endpoint $endpointname and recreating")) {
						try {
							Write-Output "Dropping server endpoint $endpointname"
							$destserver.endpoints[$endpointname].Drop()
						}
						catch {
							Write-Exception $_
							continue
						}
					}
				}
			}

			If ($Pscmdlet.ShouldProcess($destination, "Creating server endpoint $endpointname")) {
				try {
					Write-Output "Copying server endpoint $endpointname"
					$destserver.ConnectionContext.ExecuteNonQuery($endpoint.Script()) | Out-Null
				}
				catch {
					Write-Exception $_
				}
			}

		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlEndpoint
	}
}
