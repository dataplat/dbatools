Function Export-SqlLogin
{
<#
.SYNOPSIS
Copies SQL login permission from one server to another.

.DESCRIPTION
Syncs only SQL Server login permissions, roles, etc. Does not add or drop logins. If a matching login does not exist on the destination, the login will be skipped. 
Credential removal not currently supported for Syncs. TODO: Application role sync

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER Source
Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

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

.PARAMETER Exclude
Excludes specified logins. This list is auto-populated for tab completion.

.PARAMETER Login
Migrates ONLY specified logins. This list is auto-populated for tab completion. Multiple logins allowed.


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
https://dbatools.io/Sync-SqlLoginPermissions

.EXAMPLE
Sync-SqlLoginPermissions -Source sqlserver2014a -Destination sqlcluster -

Copies all logins from source server to destination server.

.EXAMPLE
Sync-SqlLoginPermissions -Source sqlserver2014a -Destination sqlcluster -Exclude realcajun -SourceSqlCredential $scred -DestinationSqlCredential $dcred

Authenticates to SQL Servers using SQL Authentication.

Copies all logins permissions except for realcajun. If a login already exists on the destination, the login will not be migrated.

.EXAMPLE
Sync-SqlLoginPermissions -Source sqlserver2014a -Destination sqlcluster -Login realcajun, netnerds

Copies permissions ONLY for logins netnerds and realcajun.

.EXAMPLE
Sync-SqlLoginPermissions -Source sqlserver2014a -Destination sqlcluster

Syncs only SQL Server login permissions, roles, etc. Does not add or drop logins or users. If a matching login does not exist on the destination, the login will be skipped.


.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers
Limitations: Does not support Application Roles yet

.LINK 
https://dbatools.io/Sync-SqlLoginPermissions 

#>
	
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string]$SqlServer,
		[parameter(Mandatory = $true)]
		[string]$OutFile,
		[object]$SqlCredential,
		[Alias("NoOverwrite")]
		[switch]$NoClobber,
		[switch]$Append,
		[parameter(ValueFromPipeline = $true, DontShow)]
		[object]$pipelogin
	)
	
	DynamicParam { if ($sqlserver) { return Get-ParamSqlLogins -SqlServer $sqlserver -SqlCredential $SqlCredential } }
	
	BEGIN
	{
		$directory = Split-Path $OutFile
		$exists = Test-Path $directory
		
		if ($exists -eq $false)
		{
			throw "Parent directory $directory does not exist"	
		}
		
		Write-Output "Attempting to connect to SQL Servers.."
		$sourceserver = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential
		
		$source = $sourceserver.DomainInstanceName
		
		# Convert from RuntimeDefinedParameter object to regular array
		$Logins = $psboundparameters.Logins
		$Exclude = $psboundparameters.Exclude
		
		$outsql = @()
		
	}
	
	PROCESS
	{
		if ($pipelogin.Length -gt 0)
		{
			$Source = $pipelogin[0].parent.name
			$logins = $pipelogin.name
		}
		
		foreach ($sourcelogin in $sourceserver.logins)
		{
			$username = $sourcelogin.name

			if ($Logins -ne $null -and $Logins -notcontains $username) { continue }
			if ($Exclude -contains $username -or $username.StartsWith("##") -or $username -eq 'sa')
			{
				Write-Output "Skipping $username"
				continue
			}
			
			$servername =  $sourceserver
			
			$userbase = ($username.Split("\")[0]).ToLower()
			if ($servername -eq $userbase -or $username.StartsWith("NT "))
			{
				If ($Pscmdlet.ShouldProcess("console", "Stating $username is skipped because it is a local machine name."))
				{
					Write-Output "$username is skipped because it is a local machine name."
				}
				continue
			}
			
			If ($Pscmdlet.ShouldProcess("Outfile", "Adding T-SQL for login $username"))
			{
				Write-Output "Exporting $username"
				$outsql += "use master"
				# Getting some attributes
				$defaultdb = $sourcelogin.DefaultDatabase
				$language = $sourcelogin.Language
				
				if ($sourcelogin.PasswordPolicyEnforced -eq $false)
				{
					$checkpolicy = "OFF"
				}
				else
				{
					$checkpolicy = "ON"
				}
				
				if (!$sourcelogin.PasswordExpirationEnabled)
				{
					$checkexpiration = "OFF"
				}
				else
				{
					$checkexpiration = "ON"
				}
				
				# Attempt to script out SQL Login
				if ($sourcelogin.LoginType -eq "SqlLogin")
				{
					$sourceloginname = $sourcelogin.name
					
					switch ($sourceserver.versionMajor)
					{
						0 { $sql = "SELECT convert(varbinary(256),password) as hashedpass FROM master.dbo.syslogins WHERE loginname='$sourceloginname'" }
						8 { $sql = "SELECT convert(varbinary(256),password) as hashedpass FROM dbo.syslogins WHERE name='$sourceloginname'" }
						9 { $sql = "SELECT convert(varbinary(256),password_hash) as hashedpass FROM sys.sql_logins where name='$sourceloginname'" }
						default
						{
							$sql = "SELECT CAST(CONVERT(varchar(256), CAST(LOGINPROPERTY(name,'PasswordHash') 
									AS varbinary (256)), 1) AS nvarchar(max)) as hashedpass FROM sys.server_principals
									WHERE principal_id = $($sourcelogin.id)"
						}
					}
					
					try
					{
						$hashedpass = $sourceserver.ConnectionContext.ExecuteScalar($sql)
					}
					catch
					{
						$hashedpassdt = $sourceserver.databases['master'].ExecuteWithResults($sql)
						$hashedpass = $hashedpassdt.Tables[0].Rows[0].Item(0)
					}
					
					if ($hashedpass.gettype().name -ne "String")
					{
						$passtring = "0x"; $hashedpass | % { $passtring += ("{0:X}" -f $_).PadLeft(2, "0") }
						$hashedpass = $passtring
					}
					
					$sid = "0x"; $sourcelogin.sid | ForEach-Object { $sid += ("{0:X}" -f $_).PadLeft(2, "0") }
					
					$outsql += "CREATE LOGIN [$username] WITH PASSWORD = $hashedpass HASHED, SID = $sid, DEFAULT_DATABASE = [$defaultdb], CHECK_POLICY = $checkpolicy, CHECK_EXPIRATION = $checkexpiration, DEFAULT_LANGUAGE = [$language]"
				}
				
				# Attempt to script out Windows User
				elseif ($sourcelogin.LoginType -eq "WindowsUser" -or $sourcelogin.LoginType -eq "WindowsGroup")
				{
					$outsql += "CREATE LOGIN [$username] FROM WINDOWS WITH DEFAULT_DATABASE = [$defaultdb], DEFAULT_LANGUAGE = [$language]"
				}
				
				# This script does not currently support certificate mapped or asymmetric key users.
				else
				{
					Write-Warning "$($sourcelogin.LoginType) logins not supported. $($sourcelogin.name) skipped."
					continue
				}
				
				if ($sourcelogin.IsDisabled)
				{
					$outsql += "ALTER LOGIN [$username] DISABLE"
				}
				if ($sourcelogin.DenyWindowsLogin)
				{
					$outsql += "DENY CONNECT SQL TO [$username]"
				}
			}
			
			# Server Roles: sysadmin, bulklogin, etc
			foreach ($role in $sourceserver.roles)
			{
				$rolename = $role.name
				
				# SMO changed over time
				try { $rolemembers = $role.EnumMemberNames() }
				catch { $rolemembers = $role.EnumServerRoleMembers() }
				
				if ($rolemembers -contains $username)
				{
					$outsql += "ALTER SERVER ROLE [$rolename] ADD MEMBER [$username]"
				}
			}
			
			$ownedjobs = $sourceserver.JobServer.Jobs | Where { $_.OwnerLoginName -eq $username }
			
			foreach ($ownedjob in $ownedjobs)
			{
				$outsql += "use msdb"
				$jobname = $ownedjob.name
				$outsql += "EXEC msdb.dbo.sp_update_job @job_name=N'$ownedjob', @owner_login_name=N'$username'"
			}
			
			if ($sourceserver.versionMajor -ge 9)
			{
				# These operations are only supported by SQL Server 2005 and above.
				# Securables: Connect SQL, View any database, Administer Bulk Operations, etc.
				
				$perms = $sourceserver.EnumServerPermissions($username)
				$outsql += "use master"
				foreach ($perm in $perms)
				{
					$permstate = $perm.permissionstate
					$permtype = $perm.PermissionType
					$grantor = $perm.grantor
					
					if ($permstate -eq "GrantWithGrant")
					{
						$grantwithgrant = "WITH GRANT OPTION"
						$permstate = "grant"
					}
					else
					{
						$grantwithgrant = $null
					}
					
					$outsql += "$permstate $permtype TO [$username] $grantwithgrant AS [$grantor]"
				}
				
				# Credential mapping. Credential removal not currently supported for Syncs.
				$logincredentials = $sourceserver.credentials | Where-Object { $_.Identity -eq $sourcelogin.name }
				foreach ($credential in $logincredentials)
				{
					$credentialname = $credential.name
					$outsql += "Print '$username is associated with the $credentialname credential'"
				}
			}
			
			# Adding database mappings and securables
			foreach ($db in $sourcelogin.EnumDatabaseMappings())
			{
				$dbname = $db.dbname
				$sourcedb = $sourceserver.databases[$dbname]
				$dbusername = $db.username
				$dblogin = $db.loginName
				
				$outsql += "use [$dbname]"
				$sql = $sourceserver.databases[$dbname].users[$dbusername].script()
				$outsql += $sql
				
				# Skipping updating dbowner
				
				# Database Roles: db_owner, db_datareader, etc
				foreach ($role in $sourcedb.roles)
				{
					if ($role.EnumMembers() -contains $username)
					{
						$rolename = $role.name
						$outsql += "ALTER ROLE [$rolename] ADD MEMBER [$username]"
					}
				}
				
				# Connect, Alter Any Assembly, etc
				$perms = $sourcedb.EnumDatabasePermissions($username)
				foreach ($perm in $perms)
				{
					$permstate = $perm.permissionstate
					$permtype = $perm.PermissionType
					$grantor = $perm.grantor
					
					if ($permstate -eq "GrantWithGrant")
					{
						$grantwithgrant = "WITH GRANT OPTION"
						$permstate = "grant"
					}
					else
					{
						$grantwithgrant = $null
					}
					
					$outsql += "$permstate $permtype TO [$username] $grantwithgrant AS [$grantor]"
				}
			}
		}
	}
	
	END
	{
		$sql = $sql | Where-Object { $_ -notlike "CREATE USER [dbo] FOR LOGIN * WITH DEFAULT_SCHEMA=[dbo]" }
		
		$sql = $outsql -join "`r`nGO`r`n"
		
		$sql | Out-File -FilePath $OutFile -Append:$Append -NoClobber:$NoClobber
		
		If ($Pscmdlet.ShouldProcess("console", "Showing final message"))
		{
			Write-Output "SQL Login export to $outfile complete"
			$sourceserver.ConnectionContext.Disconnect()
		}
	}
}