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
			Tags: Migration, Configure, SpConfigure
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
			Copy-DbaSpConfigure -Source sqlserver2014a -Destination sqlcluster -ConfigName DefaultBackupCompression, IsSqlClrEnabled -SourceSqlCredential $cred -Force

			Updates the values for two configs, the  IsSqlClrEnabled and DefaultBackupCompression, from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

		.EXAMPLE
			Copy-DbaSpConfigure -Source sqlserver2014a -Destination sqlcluster -ExcludeConfigName DefaultBackupCompression, IsSqlClrEnabled

			Updates all configs except for IsSqlClrEnabled and DefaultBackupCompression, from sqlserver2014a to sqlcluster.

		.EXAMPLE
			Copy-DbaSpConfigure -Source sqlserver2014a -Destination sqlcluster -WhatIf

			Shows what would happen if the command were executed.
	#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Source,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SourceSqlCredential = [System.Management.Automation.PSCredential]::Empty,
		[parameter(Mandatory = $true)]
		[DbaInstanceParameter]$Destination,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$DestinationSqlCredential = [System.Management.Automation.PSCredential]::Empty,
		[object[]]$ConfigName,
		[object[]]$ExcludeConfigName,
		[switch]$Silent
	)

	begin {

		$sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

		$source = $sourceServer.DomainInstanceName
		$destination = $destServer.DomainInstanceName
	}
	process {

		$sourceProps = Get-DbaSpConfigure -SqlInstance $sourceServer
		$destProps = Get-DbaSpConfigure -SqlInstance $destServer

		foreach ($sourceProp in $sourceProps) {
			$displayName = $sourceProp.DisplayName
			$sConfigName = $sourceProp.ConfigName
			$sConfiguredValue = $sourceProp.ConfiguredValue
			$requiresRestart = $sourceProp.IsDynamic

			$copySpConfigStatus = [pscustomobject]@{
				SourceServer      = $sourceServer.Name
				DestinationServer = $destServer.Name
				Name              = $sConfigName
				Type              = $null
				Status            = $null
				Notes             = $null
				DateTime          = [DbaDateTime](Get-Date)
			}

			if ($ConfigName -and $sConfigName -notin $ConfigName -or $sConfigName -in $ExcludeConfigName ) {
				continue
			}

			$destProp = $destProps | Where-Object ConfigName -eq $sConfigName
			if (!$destProp) {
				Write-Message -Level Warning -Message "Configuration $sConfigName ('$displayName') does not exist on the destination instance."

				$copySpConfigStatus.Status = "Skipped"
				$copySpConfigStatus.Notes = "Configuration does not exist on destination"
				$copySpConfigStatus
				continue
			}

			if ($Pscmdlet.ShouldProcess($destination, "Updating $sConfigName [$displayName]")) {
				try {
					$destOldConfigValue = $destProp.ConfiguredValue

					$result = Set-DbaSpConfigure -SqlInstance $destServer -ConfigName $sConfigName -Value $sConfiguredValue -Silent -Mode 'Lazy'
					if ($result) {
						Write-Message -Level Verbose -Message "Updated $($destProp.ConfigName) ($($destProp.DisplayName)) from $destOldConfigValue to $sConfiguredValue"
					}

					if ($requiresRestart -eq $false) {
						Write-Message -Level Warning -Message "Configuration option $sConfigName ($displayName) requires restart."
						$copySpConfigStatus.Notes = "Requires restart"
					}
					$copySpConfigStatus.Status = "Successful"
					$copySpConfigStatus
				}
				catch {
					$copySpConfigStatus.Status = "Failed"
					$copySpConfigStatus.Notes = $_.Exception
					$copySpConfigStatus

					Stop-Function -Message "Could not set $($destProp.ConfigName) to $sConfiguredValue." -Target $sConfigName -ErrorRecord $_
				}
			}
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlSpConfigure
	}
}