function Copy-DbaAgentProxyAccount {
	<#
		.SYNOPSIS
			Copy-DbaAgentProxyAccount migrates proxy accounts from one SQL Server to another.

		.DESCRIPTION
			By default, all proxy accounts are copied. The -ProxyAccounts parameter is autopopulated for command-line completion and can be used to copy only specific proxy accounts.

			If the associated credential for the account does not exist on the destination, it will be skipped. If the proxy account already exists on the destination, it will be skipped unless -Force is used.

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

		.PARAMETER WhatIf
			Shows what would happen if the command were to run. No actions are actually performed.

		.PARAMETER Confirm
			Prompts you for confirmation before executing any changing operations within the command.

		.PARAMETER Force
			Drops and recreates the Proxy Account if it exists

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Migration, Agent
			Author: Chrissy LeMaire (@cl), netnerds.net
			Requires: sysadmin access on SQL Servers

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Copy-DbaAgentProxyAccount

		.EXAMPLE
			Copy-DbaAgentProxyAccount -Source sqlserver2014a -Destination sqlcluster

			Copies all proxy accounts from sqlserver2014a to sqlcluster, using Windows credentials. If proxy accounts with the same name exist on sqlcluster, they will be skipped.

		.EXAMPLE
			Copy-DbaAgentProxyAccount -Source sqlserver2014a -Destination sqlcluster -ProxyAccount PSProxy -SourceSqlCredential $cred -Force

			Copies a single proxy account, the PSProxy proxy account from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a proxy account with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

		.EXAMPLE
			Copy-DbaAgentProxyAccount -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

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
		[switch]$Force,
		[switch]$Silent
	)

	begin {
		$sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

		$source = $sourceServer.DomainInstanceName
		$destination = $destServer.DomainInstanceName

		if ($sourceServer.VersionMajor -lt 9 -or $destServer.VersionMajor -lt 9) {
			throw "Server ProxyAccounts are only supported in SQL Server 2005 and above. Quitting."
		}

		$serverProxyAccounts = $sourceServer.JobServer.ProxyAccounts
		$destProxyAccounts = $destServer.JobServer.ProxyAccounts
	}
	process {
		foreach ($proxyAccount in $serverProxyAccounts) {
			$proxyName = $proxyAccount.Name

			$copyAgentProxyAccountStatus = [pscustomobject]@{
				SourceServer        = $sourceServer.Name
				DestinationServer   = $destServer.Name
				Name                = $null
				Type                = $null
				Status              = $null
				DateTime            = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
			}

			if ($proxyAccounts.Length -gt 0 -and $proxyAccounts -notcontains $proxyName) {
				continue
			}

			# Proxy accounts rely on Credential accounts
			$credentialName = $proxyAccount.CredentialName
			$copyAgentProxyAccountStatus.Name = $credentialName
			$copyAgentProxyAccountStatus.Type = "Credential"
			if ($null -eq $destServer.Credentials[$CredentialName]) {
				$copyAgentProxyAccountStatus.Status = "skippped"
				$copyAgentProxyAccountStatus
				Write-Message -Level Warning -Message "Associated credential account, $CredentialName, does not exist on $destination. Skipping migration of $proxyName."
				continue
			}

			if ($destProxyAccounts.Name -contains $proxyName) {
				$copyAgentProxyAccountStatus.Name = $proxyName
				$copyAgentProxyAccountStatus.Type = "ProxyAccount"

				if ($force -eq $false) {
					$copyAgentProxyAccountStatus.Status = "Skipped"
					$copyAgentProxyAccountStatus
					Write-Message -Level Warning -Message "Server proxy account $proxyName exists at destination. Use -Force to drop and migrate."
					continue
				}
				else {
					if ($Pscmdlet.ShouldProcess($destination, "Dropping server proxy account $proxyName and recreating")) {
						try {
							Write-Message -Level Verbose -Message "Dropping server proxy account $proxyName"
							$destServer.JobServer.ProxyAccounts[$proxyName].Drop()
						}
						catch {
							$copyAgentProxyAccountStatus.Status = "Failed"
							$copyAgentProxyAccountStatus
							Stop-Function -Message "Issue dropping proxy account" -Target $proxyName -InnerErrorRecord $_ -Continue
						}
					}
				}
			}

			if ($Pscmdlet.ShouldProcess($destination, "Creating server proxy account $proxyName")) {
				$copyAgentProxyAccountStatus.Name = $proxyName
				$copyAgentProxyAccountStatus.Type = "ProxyAccount"

				try {
					Write-Message -Level Verbose -Message "Copying server proxy account $proxyName"
					$sql = $proxyAccount.Script() | Out-String
					Write-Message -Level Debug -Message $sql
					$destServer.Query($sql)

					$copyAgentProxyAccountStatus.Status = "Succesful"
					$copyAgentProxyAccountStatus
				}
				catch {
					$exceptionstring = $_.Exception.InnerException.ToString()
					if ($exceptionstring -match 'subsystem') {
						$copyAgentProxyAccountStatus.Status = "Skipping"
						$copyAgentProxyAccountStatus

						Write-Message -Level Warning -Message "One or more subsystems do not exist on the destination server. Skipping that part."
					}
					else {
						$copyAgentProxyAccountStatus.Status = "Failed"
						$copyAgentProxyAccountStatus

						Stop-Function -Message "Issue creating proxy account" -Target $proxyName -InnerErrorRecord $_
					}
				}
			}
		}
	}
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlProxyAccount
	}
}
