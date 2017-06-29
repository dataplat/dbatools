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

		$sourceserver = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		if (!(Test-SqlSa -SqlInstance $sourceserver -SqlCredential $SourceSqlCredential)) { throw "Not a sysadmin on $source. Quitting." }
		if (!(Test-SqlSa -SqlInstance $destserver -SqlCredential $DestinationSqlCredential)) { throw "Not a sysadmin on $destination. Quitting." }
		if ($sourceserver.versionMajor -lt 10 -or $destserver.versionMajor -lt 10) {
			throw "Server Audit Specifications are only supported in SQL Server 2008 and above. Quitting."
		}
		$serverauditspecs = $sourceserver.ServerAuditSpecifications
		$destaudits = $destserver.ServerAuditSpecifications
	}
	process {

		foreach ($auditspec in $serverauditspecs) {
			$auditspecname = $auditspec.name
			if ($auditspecs.length -gt 0 -and $auditspecs -notcontains $auditspecname) { continue }
			$destserver.Audits.Refresh()
			if ($destserver.Audits.Name -notcontains $auditspec.AuditName) {
				Write-Warning "Audit $($auditspec.AuditName) does not exist on $Destination. Skipping $auditspecname."
				continue
			}
			if ($destaudits.name -contains $auditspecname) {
				if ($force -eq $false) {
					Write-Warning "Server audit $auditspecname exists at destination. Use -Force to drop and migrate."
					continue
				}
				else {
					If ($Pscmdlet.ShouldProcess($destination, "Dropping server audit $auditspecname and recreating")) {
						try {
							Write-Verbose "Dropping server audit $auditspecname"
							$destserver.ServerAuditSpecifications[$auditspecname].Drop()
						}
						catch {
							Write-Exception $_ 							continue
						}
					}
				}
			}
			If ($Pscmdlet.ShouldProcess($destination, "Creating server audit $auditspecname")) {
				try {
					Write-Output "Copying server audit $auditspecname"
					$destserver.ConnectionContext.ExecuteNonQuery($auditspec.Script()) | Out-Null
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
