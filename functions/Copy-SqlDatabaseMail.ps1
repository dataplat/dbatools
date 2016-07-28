Function Copy-SqlDatabaseMail
{
<#
.SYNOPSIS
Migrates Mail Profiles, Accounts, Mail Servers and Mail Server Configs from one SQL Server to another.


.DESCRIPTION
By default, all mail configurations for Profiles, Accounts, Mail Servers and Configs are copied. 
 
The -Profiles parameter is autopopulated for command-line completion and can be used to copy only specific mail profiles.
The -Accounts parameter is autopopulated for command-line completion and can be used to copy only specific mail accounts.
The -MailServers parameter is autopopulated for command-line completion and can be used to copy only specific mail servers.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

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

.PARAMETER Type
Specifies the object type to migrate. Valid options are Job, Alert and Operator. When CategoryType is specified, all categories from the selected type will be migrated. For granular migrations, use the three parameters below.

.PARAMETER Profiles 
This parameter is autopopulated for command-line completion and can be used to copy only specific mail profiles.

.PARAMETER Accounts
This parameter is autopopulated for command-line completion and can be used to copy only specific mail accounts.

.PARAMETER MailServers
The parameter is autopopulated for command-line completion and can be used to copy only specific mail servers.

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Copy-SqlDatabaseMail 

.EXAMPLE   
Copy-SqlDatabaseMail -Source sqlserver2014a -Destination sqlcluster

Copies all database mail objects from sqlserver2014a to sqlcluster, using Windows credentials. If database mail objects with the same name exist on sqlcluster, they will be skipped.

.EXAMPLE   
Copy-SqlDatabaseMail -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

Copies all database mail objects from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

.EXAMPLE   
Copy-SqlDatabaseMail -Source sqlserver2014a -Destination sqlcluster -WhatIf

Shows what would happen if the command were executed.
#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[object]$Source,
		[parameter(Mandatory = $true)]
		[object]$Destination,
		[Parameter(ParameterSetName = 'SpecifcTypes')]
		[ValidateSet('ConfigurationValues', 'Profiles', 'Accounts', 'MailServers')]
		[string[]]$Type,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[switch]$Force
		
	)
	
	DynamicParam { if ($source) { return (Get-ParamSqlDatabaseMail -SqlServer $Source -SqlCredential $SourceSqlCredential) } }
	
	BEGIN
	{
		
		Function Copy-SqlDatabaseMailConfig
		{
			Write-Output "Migrating mail server configuration values"
			if ($Pscmdlet.ShouldProcess($destination, "Migrating all mail server configuration values"))
			{
				try
				{
					$sql = $mail.ConfigurationValues.Script() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
					Write-Verbose $sql
					$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
					$mail.ConfigurationValues.Refresh()
				}
				catch
				{
					Write-Exception $_
				}
			}
		}
		
		Function Copy-SqlDatabaseAccount
		{
			$sourceaccounts = $sourceserver.Mail.Accounts
			$destaccounts = $destserver.Mail.Accounts
			
			Write-Output "Migrating accounts"
			foreach ($account in $sourceaccounts)
			{
				$accountname = $account.name
				if ($accounts.count -gt 0 -and $accounts -notcontains $accountname)
				{
					continue
				}
				
				if ($destaccounts.name -contains $accountname)
				{
					if ($force -eq $false)
					{
						Write-Warning "Account $accountname exists at destination. Use -Force to drop and migrate."
						continue
					}
					
					If ($Pscmdlet.ShouldProcess($destination, "Dropping account $accountname and recreating"))
					{
						try
						{
							Write-Verbose "Dropping account $accountname"
							$destserver.Mail.Accounts[$accountname].Drop()
							$destserver.Mail.Accounts.Refresh()
						}
						catch
						{
							Write-Exception $_
							continue
						}
					}
				}
				
				if ($Pscmdlet.ShouldProcess($destination, "Migrating account $accountname"))
				{
					try
					{
						Write-Output "Copying mail account $accountname"
						$sql = $account.Script() | Out-String
						$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
						Write-Verbose $sql
						$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
					}
					catch
					{
						Write-Exception $_
					}
				}
			}
		}
		
		Function Copy-SqlDatabaseMailProfile
		{
			
			$sourceprofiles = $sourceserver.Mail.Profiles
			$destprofiles = $destserver.Mail.Profiles
			
			Write-Output "Migrating mail profiles"
			foreach ($profile in $sourceprofiles)
			{
			
				$profilename = $profile.name
				if ($profiles.count -gt 0 -and $profiles -notcontains $profilename) { continue }
				
				if ($destprofiles.name -contains $profilename)
				{
					if ($force -eq $false)
					{
						Write-Warning "Profile $profilename exists at destination. Use -Force to drop and migrate."
						continue
					}
					
					If ($Pscmdlet.ShouldProcess($destination, "Dropping profile $profilename and recreating"))
					{
						try
						{
							Write-Verbose "Dropping profile $profilename"
							$destserver.Mail.Profiles[$profilename].Drop()
							$destserver.Mail.Profiles.Refresh()
						}
						catch
						{
							Write-Exception $_
							continue
						}
					}
				}
				
				if ($Pscmdlet.ShouldProcess($destination, "Migrating mail profile $profilename"))
				{
					try
					{
						Write-Output "Copying mail profile $profilename"
						$sql = $profile.Script() | Out-String
						$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
						Write-Verbose $sql
						$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
						$destserver.Mail.Profiles.Refresh()
					}
					catch
					{
	
						Write-Exception $_ 
					}
				}
			}
		}
		
		Function Copy-SqlDatabaseMailServer
		{
			$sourcemailservers = $sourceserver.Mail.Accounts.MailServers
			$destmailservers = $destserver.Mail.Accounts.MailServers
			
			Write-Output "Migrating mail servers"
			foreach ($mailserver in $sourcemailservers)
			{
				$mailservername = $mailserver.name
				if ($mailservers.count -gt 0 -and $mailservers -notcontains $mailservername) { continue }
				
				if ($destmailservers.name -contains $mailservername)
				{
					if ($force -eq $false)
					{
						Write-Warning "Mail server $mailservername exists at destination. Use -Force to drop and migrate."
						continue
					}
					
					If ($Pscmdlet.ShouldProcess($destination, "Dropping mail server $mailservername and recreating"))
					{
						try
						{
							Write-Verbose "Dropping mail server $mailservername"
							$destserver.Mail.Accounts.MailServers[$mailservername].Drop()
						}
						catch
						{
							Write-Exception $_
							continue
						}
					}
				}
				
				if ($Pscmdlet.ShouldProcess($destination, "Migrating account mail server $mailservername"))
				{
					try
					{
						Write-Output "Copying mail server $mailservername"
						$sql = $mailserver.Script() | Out-String
						$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
						Write-Verbose $sql
						$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
					}
					catch
					{
						Write-Exception $_
					}
				}
			}
		}
		
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
		
		if ($sourceserver.versionMajor -lt 9 -or $destserver.versionMajor -lt 9)
		{
			throw "Database Mail is only supported in SQL Server 2005 and above. Quitting."
		}
		
		$mail = $sourceserver.mail
	}
	PROCESS
	{
	
	if ($type.count -gt 0)
		{
			
			switch ($type)
			{
				"ConfigurationValues" {
					Copy-SqlDatabaseMailConfig
					$destserver.Mail.ConfigurationValues.Refresh()
				}
				
				"Profiles" {
					Copy-SqlDatabaseMailProfile
					$destserver.Mail.Profiles.Refresh()
				}
				
				"Accounts" {
					Copy-SqlDatabaseAccount
					$destserver.Mail.Accounts.Refresh()
				}
				
				"MailServers" {
					Copy-SqlDatabaseMailServer
				}
			}
			
			return
		}
		
		
		$profiles = $psboundparameters.Profiles
		$accounts = $psboundparameters.Accounts
		$mailServers = $psboundparameters.MailServers
		
		if (($profiles.count + $accounts.count + $mailServers.count) -gt 0)
		{
			
			if ($profiles.count -gt 0)
			{
				Copy-SqlDatabaseMailProfile -Profiles $profiles
				$destserver.Mail.Profiles.Refresh()
			}
			
			if ($accounts.count -gt 0)
			{
				Copy-SqlDatabaseAccount -Accounts $accounts
				$destserver.Mail.Accounts.Refresh()
			}
			
			if ($mailServers.count -gt 0)
			{
				Copy-SqlDatabaseMailServer -MailServers $mailServers
			}
			
			return
		}
		
		Copy-SqlDatabaseMailConfig
		$destserver.Mail.ConfigurationValues.Refresh()
		Copy-SqlDatabaseAccount
		$destserver.Mail.Accounts.Refresh()
		Copy-SqlDatabaseMailProfile
		$destserver.Mail.Profiles.Refresh()
		Copy-SqlDatabaseMailServer
	}
	
	end
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Mail migration finished" }
	}
}

