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
		
		$sourceserver = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
		if ($sourceserver.versionMajor -lt 9 -or $destserver.versionMajor -lt 9) {
			throw "Server ProxyAccounts are only supported in SQL Server 2005 and above. Quitting."
		}
		
		$serverproxyaccounts = $sourceserver.JobServer.ProxyAccounts
		$destproxyaccounts = $destserver.JobServer.ProxyAccounts
		
	}
	process {
		
		foreach ($proxyaccount in $serverproxyaccounts) {
			$proxyname = $proxyaccount.name
			if ($proxyaccounts.length -gt 0 -and $proxyaccounts -notcontains $proxyname) { continue }
			
			# Proxy accounts rely on Credential accounts 
			$credentialName = $proxyaccount.CredentialName
			if ($destserver.Credentials[$CredentialName] -eq $null) {
				Write-Warning "Associated credential account, $CredentialName, does not exist on $destination. Skipping migration of $proxyname."
				continue
			}
			
			if ($destproxyaccounts.name -contains $proxyname) {
				if ($force -eq $false) {
					Write-Warning "Server proxy account $proxyname exists at destination. Use -Force to drop and migrate."
					continue
				}
				else {
					If ($Pscmdlet.ShouldProcess($destination, "Dropping server proxy account $proxyname and recreating")) {
						try {
							Write-Verbose "Dropping server proxy account $proxyname"
							$destserver.jobserver.proxyaccounts[$proxyname].Drop()
						}
						catch { 
							Write-Exception $_
							continue
							
						}
					}
				}
			}
	
			If ($Pscmdlet.ShouldProcess($destination, "Creating server proxy account $proxyname")) {
				try {
					Write-Output "Copying server proxy account $proxyname"
					$sql = $proxyaccount.Script() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
					Write-Verbose $sql
					$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
				}
				catch {
					$exceptionstring = $_.Exception.InnerException.ToString()
					if ($exceptionstring -match 'subsystem') {
						Write-Warning "One or more subsystems do not exist on the destination server. Skipping that part."
					} 
					else {
						Write-Exception $_
					}
				}
			}
		}
	}
	
	end {
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Server proxy account migration finished" }
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlProxyAccount
	}
}
