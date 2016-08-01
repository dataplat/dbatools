Function Copy-SqlProxyAccount
{
<#
.SYNOPSIS 
Copy-SqlProxyAccount migrates proxy accounts from one SQL Server to another. 

.DESCRIPTION
By default, all proxy accounts are copied. The -ProxyAccounts parameter is autopopulated for command-line completion and can be used to copy only specific proxy accounts.

If the associated credential for the account does not exist on the destination, it will be skipped. If the proxy account already exists on the destination, it will be skipped unless -Force is used.  

.PARAMETER Source
Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER Destination
Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SourceSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter. 

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER DestinationSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter. 

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Copy-SqlProxyAccount

.EXAMPLE   
Copy-SqlProxyAccount -Source sqlserver2014a -Destination sqlcluster

Copies all proxy accounts from sqlserver2014a to sqlcluster, using Windows credentials. If proxy accounts with the same name exist on sqlcluster, they will be skipped.

.EXAMPLE   
Copy-SqlProxyAccount -Source sqlserver2014a -Destination sqlcluster -ProxyAccount PSProxy -SourceSqlCredential $cred -Force

Copies a single proxy account, the PSProxy proxy account from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a proxy account with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

.EXAMPLE   
Copy-SqlProxyAccount -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

Shows what would happen if the command were executed using force.
#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[object]$Source,
		[parameter(Mandatory = $true)]
		[object]$Destination,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[switch]$Force
	)
	DynamicParam { if ($source) { return (Get-ParamSqlProxyAccounts -SqlServer $Source -SqlCredential $SourceSqlCredential) } }
	
	BEGIN
	{
		$proxyaccounts = $psboundparameters.ProxyAccounts
		
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
		if ($sourceserver.versionMajor -lt 9 -or $destserver.versionMajor -lt 9)
		{
			throw "Server ProxyAccounts are only supported in SQL Server 2005 and above. Quitting."
		}
		
		$serverproxyaccounts = $sourceserver.JobServer.ProxyAccounts
		$destproxyaccounts = $destserver.JobServer.ProxyAccounts
		
	}
	PROCESS
	{
		
		foreach ($proxyaccount in $serverproxyaccounts)
		{
			$proxyname = $proxyaccount.name
			if ($proxyaccounts.length -gt 0 -and $proxyaccounts -notcontains $proxyname) { continue }
			
			# Proxy accounts rely on Credential accounts 
			$credentialName = $proxyaccount.CredentialName
			if ($destserver.Credentials[$CredentialName] -eq $null)
			{
				Write-Warning "Associated credential account, $CredentialName, does not exist on $destination. Skipping migration of $proxyname."
				continue
			}
			
			if ($destproxyaccounts.name -contains $proxyname)
			{
				if ($force -eq $false)
				{
					Write-Warning "Server proxy account $proxyname exists at destination. Use -Force to drop and migrate."
					continue
				}
				else
				{
					If ($Pscmdlet.ShouldProcess($destination, "Dropping server proxy account $proxyname and recreating"))
					{
						try
						{
							Write-Verbose "Dropping server proxy account $proxyname"
							$destserver.jobserver.proxyaccounts[$proxyname].Drop()
						}
						catch 
						{ 
							Write-Exception $_
							continue
							
						}
					}
				}
			}
	
			If ($Pscmdlet.ShouldProcess($destination, "Creating server proxy account $proxyname"))
			{
				try
				{
					Write-Output "Copying server proxy account $proxyname"
					$sql = $proxyaccount.Script() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
					Write-Verbose $sql
					$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
				}
				catch
				{
					$exceptionstring = $_.Exception.InnerException.ToString()
					if ($exceptionstring -match 'subsystem') 
					{
						Write-Warning "One or more subsystems do not exist on the destination server. Skipping that part."
					} 
					else 
					{
						Write-Exception $_
					}
				}
			}
		}
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Server proxy account migration finished" }
	}
}