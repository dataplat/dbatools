Function Copy-SqlDatabaseMail
{
<#
.SYNOPSIS
Copies *all* database mail profiles, accounts and settings. More granularity coming later. 

Ignores -force: does not drop and recreate.

.DESCRIPTION
This function could use some refining, as *all* database mail objects are copied. 

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

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Copy-SqlDatabaseMail 

.EXAMPLE   
Copy-SqlDatabaseMail -Source sqlserver2014a -Destination sqlcluster

Copies all database mail objects from sqlserver2014a to sqlcluster, using Windows credentials. If database mail objects with the same name exist on sqlcluster, they will be skipped.

.EXAMPLE   
Copy-SqlDatabaseMail -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

Copies all database mail objects from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a
and Windows credentials for sqlcluster.

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
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential
	)
	
	DynamicParam { if ($source) { return (Get-ParamSqlDatabaseMail -SqlServer $Source -SqlCredential $SourceSqlCredential) } }
	
	process
	{
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
		if (!(Test-SqlSa -SqlServer $sourceserver -SqlCredential $SourceSqlCredential)) { throw "Not a sysadmin on $source. Quitting." }
		if (!(Test-SqlSa -SqlServer $destserver -SqlCredential $DestinationSqlCredential)) { throw "Not a sysadmin on $destination. Quitting." }
		
		if ($sourceserver.versionMajor -lt 9 -or $destserver.versionMajor -lt 9)
		{
			throw "Database Mail is only supported in SQL Server 2005 and above. Quitting."
		}
		
		$mail = $sourceserver.mail
		
		
		Write-Output "Migrating mail server configuration values"
		$sql = $mail.ConfigurationValues.Script() | Out-String
		$sql = $sql -replace "'$source'", "'$destination'"
		Write-Verbose $sql
		
		if ($Pscmdlet.ShouldProcess($destination, "Migrating mail server parameters"))
		{
			try
			{
				$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
			}
			catch
			{
				Write-Exception $_
			}
		}
		
		
		Write-Output "Migrating mail accounts"
		foreach ($acct in $mail.Accounts)
		{
			$sql = $acct.Script() | Out-String
			$sql = $sql -replace "'$source'", "'$destination'"
			Write-Verbose $sql
			
			if ($Pscmdlet.ShouldProcess($destination, "Migrating mail account $acct"))
			{
				try
				{
					$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
				}
				catch
				{
					if ($_.Exception -like '*duplicate*' -or $_.Exception -like '*exist*')
					{
						Write-Warning "Mail account '$acct' was skipped because it already exists on $destination"
					}
					else { Write-Exception $_ }
				}
			}
		}
		
		Write-Output "Migrating mail profiles"
		foreach ($profile in $mail.Profiles)
		{
			$sql = $profile.Script() | Out-String
			$sql = $sql -replace "'$source'", "'$destination'"
			Write-Verbose $sql
			
			if ($Pscmdlet.ShouldProcess($destination, "Migrating mail profile $profile"))
			{
				try
				{
					$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
				}
				catch
				{
					if ($_.Exception -like '*duplicate*' -or $_.Exception -like '*exist*')
					{
						Write-Warning "Mail profile '$profile' was skipped because it already exists on $destination"
					}
					else { Write-Exception $_ }
				}
			}
		}
		
		Write-Output "Updating account mail servers"
		foreach ($mailsrv in $mail.Accounts.MailServers)
		{
			$sql = $mailsrv.Script() | Out-String
			$sql = $sql -replace "'$source'", "'$destination'"
			Write-Verbose $sql
			
			if ($Pscmdlet.ShouldProcess($destination, "Migrating account mail server $mailsrv"))
			{
				try
				{
					$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
				}
				catch
				{
					if ($_.Exception -like '*duplicate*' -or $_.Exception -like '*exist*')
					{
						Write-Warning "Mail account '$mailsrv' was skipped because it already exists on $destination"
					}
					else { Write-Exception $_ }
				}
			}
		}
	}
	
	end
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Mail migration finished" }
	}
}

