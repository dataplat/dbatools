function Copy-DbaServerAuditSpecification {
	<#
		.SYNOPSIS
			Copy-DbaServerAuditSpecification migrates server audit specifications from one SQL Server to another.

		.DESCRIPTION
			By default, all audits are copied. The -ServerAuditSpecification parameter is autopopulated for command-line completion and can be used to copy only specific audits.

			If the audit specification already exists on the destination, it will be skipped unless -Force is used.

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

		.PARAMETER ServerAuditSpecification
			The Server Audit Specification(s) to process - this list is auto populated from the server. If unspecified, all Server Audit Specifications will be processed.

		.PARAMETER ExcludeServerAuditSpecification
			The Server Audit Specification(s) to exclude - this list is auto populated from the server

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.PARAMETER Force
			Drops and recreates the Audit Specification if it exists

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Migration,ServerAudit
			Author: Chrissy LeMaire (@cl), netnerds.net
			Requires: sysadmin access on SQL Servers

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Copy-DbaServerAuditSpecification

		.EXAMPLE
			Copy-DbaServerAuditSpecification -Source sqlserver2014a -Destination sqlcluster

			Copies all server audits from sqlserver2014a to sqlcluster, using Windows credentials. If audits with the same name exist on sqlcluster, they will be skipped.

		.EXAMPLE
			Copy-DbaServerAuditSpecification -Source sqlserver2014a -Destination sqlcluster -ServerAuditSpecification tg_noDbDrop -SourceSqlCredential $cred -Force

			Copies a single audit, the tg_noDbDrop audit from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If an audit with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

		.EXAMPLE
			Copy-DbaServerAuditSpecification -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

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
		[object[]]$ServerAuditSpecification,
		[object[]]$ExcludeServerAuditSpecification,
		[switch]$Force,
		[switch]$Silent
	)

	begin {

		$sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
		$source = $sourceServer.DomainInstanceName
		$destination = $destServer.DomainInstanceName

		if (!(Test-SqlSa -SqlInstance $sourceServer -SqlCredential $SourceSqlCredential)) {
			throw "Not a sysadmin on $source. Quitting."
		}

		if (!(Test-SqlSa -SqlInstance $destServer -SqlCredential $DestinationSqlCredential)) {
			throw "Not a sysadmin on $destination. Quitting."
		}

		if ($sourceServer.versionMajor -lt 10 -or $destServer.versionMajor -lt 10) {
			throw "Server Audit Specifications are only supported in SQL Server 2008 and above. Quitting."
		}

		$serverAuditSpecs = $sourceServer.ServerAuditSpecifications
		$destAudits = $destServer.ServerAuditSpecifications
	}
	process {

		foreach ($auditSpec in $serverAuditSpecs) {
			$auditSpecName = $auditSpec.Name

			if ($auditSpecs.length -gt 0 -and $auditSpecs -notcontains $auditSpecName) {
				continue
			}

			$destServer.Audits.Refresh()

			if ($destServer.Audits.Name -notcontains $auditSpec.AuditName) {
				Write-Warning "Audit $($auditSpec.AuditName) does not exist on $Destination. Skipping $auditSpecName."
				continue
			}

			if ($destAudits.name -contains $auditSpecName) {
				if ($force -eq $false) {
					Write-Warning "Server audit $auditSpecName exists at destination. Use -Force to drop and migrate."
					continue
				}
				else {
					if ($Pscmdlet.ShouldProcess($destination, "Dropping server audit $auditSpecName and recreating")) {
						try {
							Write-Verbose "Dropping server audit $auditSpecName"
							$destServer.ServerAuditSpecifications[$auditSpecName].Drop()
						}
						catch {
							Write-Exception $_
							continue
						}
					}
				}
			}
			if ($Pscmdlet.ShouldProcess($destination, "Creating server audit $auditSpecName")) {
				try {
					Write-Output "Copying server audit $auditSpecName"
					$destServer.ConnectionContext.ExecuteNonQuery($auditSpec.Script()) | Out-Null
				}
				catch {
					Write-Exception $_
				}
			}
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlAuditSpecification
	}
}
