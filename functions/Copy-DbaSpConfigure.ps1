function Copy-DbaSpConfigure {
	<#
		.SYNOPSIS 
			Copy-DbaSpConfigure migrates configuration values from one SQL Server to another. 

		.DESCRIPTION
			By default, all configuration values are copied. The -ConfigName parameter is autopopulated for command-line completion and can be used to copy only specific configs.

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

		.PARAMETER ConfigName
			The ConfigName(s) to process - this list is auto populated from the server. If unspecified, all ConfigNames will be processed.

		.PARAMETER ExcludeConfigName
			The ConfigName(s) to exclude - this list is auto populated from the server

		.PARAMETER WhatIf 
			Shows what would happen if the command were to run. No actions are actually performed. 

		.PARAMETER Confirm 
			Prompts you for confirmation before executing any changing operations within the command. 

		.PARAMETER Silent 
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Migration, Configure,SpConfigure
			Author: Chrissy LeMaire (@cl), netnerds.net
			Requires: sysadmin access on SQL Servers

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Copy-DbaSpConfigure 

		.EXAMPLE   
			Copy-DbaSpConfigure -Source sqlserver2014a -Destination sqlcluster

			Copies all sp_configure settings from sqlserver2014a to sqlcluster

		.EXAMPLE   
			Copy-DbaSpConfigure -Source sqlserver2014a -Destination sqlcluster -Config DefaultBackupCompression, IsSqlClrEnabled -SourceSqlCredential $cred -Force

			Updates the values for two configs, the  IsSqlClrEnabled and DefaultBackupCompression, from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

		.EXAMPLE   
			Copy-DbaSpConfigure -Source sqlserver2014a -Destination sqlcluster -WhatIf

			Shows what would happen if the command were executed.
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
		[object[]]$ConfigName,
		[object[]]$ExcludeConfigName,
		[object[]]$Silent
	)

	begin {

		$sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

		$source = $sourceServer.DomainInstanceName
		$destination = $destServer.DomainInstanceName
	}
	process {

		$destProps = $destServer.Configuration.Properties

		# crude but i suck with properties
		$lookups = $sourceServer.Configuration.PsObject.Properties.Name | Where-Object { $_ -notin "Parent", "Properties" }

		$propLookup = @()
		foreach ($lookup in $lookups) {
			$propLookup += [PSCustomObject]@{
				ShortName   = $lookup
				DisplayName = $sourceServer.Configuration.$lookup.DisplayName
				IsDynamic   = $sourceServer.Configuration.$lookup.IsDynamic
			}
		}

		foreach ($sourceProp in $sourceServer.Configuration.Properties) {
			$displayName = $sourceProp.DisplayName
			$lookup = $propLookup | Where-Object { $_.DisplayName -eq $displayName }
			
			if ($ConfigName.length -gt 0 -and $ConfigName -notcontains $lookup.ShortName) { continue }
			
			$destProp = $destProps | Where-Object { $_.DisplayName -eq $displayName }
			if ($destProp -eq $null) {
				Write-Warning "Configuration option '$displayName' does not exist on the destination instance."
				continue
			}
			
			if ($Pscmdlet.ShouldProcess($destination, "Updating $displayName")) {
				try {
					$destOldPropValue = $destProp.ConfigValue
					$destProp.ConfigValue = $sourceProp.ConfigValue
					$destServer.Configuration.Alter()
					Write-Output "Updated $($destProp.DisplayName) from $destOldPropValue to $($sourceProp.ConfigValue)"
					if ($lookup.IsDynamic -eq $false) {
						Write-Warning "Configuration option '$displayName' requires restart."	
					}
				}
				catch {
					Write-Error "Could not $($destProp.DisplayName) to $($sourceProp.ConfigValue). Feature may not be supported."
				}
			} 
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlSpConfigure
	}	
}
