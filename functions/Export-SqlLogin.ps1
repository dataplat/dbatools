Function Export-SqlLogin
{
<#
.SYNOPSIS
Exports Windows and SQL Logins to a T-SQL file. Export includes login, SID, password, default database, default language, server permissions, server roles, db permissions, db roles.

.DESCRIPTION
Exports Windows and SQL Logins to a T-SQL file. Export includes login, SID, password, default database, default language, server permissions, server roles, db permissions, db roles.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER SqlServer
The SQL Server to export the logins from. SQL Server 2000 and above supported.

.PARAMETER FileName
The file to write to.

.PARAMETER NoClobber
Do not overwrite file
	
.PARAMETER Append
Append to file
	
.PARAMETER Exclude
Excludes specified logins. This list is auto-populated for tab completion.

.PARAMETER Login
Migrates ONLY specified logins. This list is auto-populated for tab completion. Multiple logins allowed.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.
	
.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net

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
https://dbatools.io/Export-SqlLogin

.EXAMPLE
Export-SqlLogin -SqlServer sql2005 -FileName C:\temp\sql2005-logins.sql

Exports SQL for the logins in server "sql2005" and writes them to the file "C:\temp\sql2005-logins.sql"

.EXAMPLE
Export-SqlLogin -SqlServer sqlserver2014a -Exclude realcajun -SqlCredential $scred -FileName C:\temp\logins.sql -Append

Authenticates to sqlserver2014a using SQL Authentication. Exports all logins except for realcajun to C:\temp\logins.sql, and appends to the file if it exists. If not, the file will be created.

.EXAMPLE
Export-SqlLogin -SqlServer sqlserver2014a -Login realcajun, netnerds -FileName C:\temp\logins.sql

Exports ONLY logins netnerds and realcajun fron sqlsever2014a to the file  C:\temp\logins.sql

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net

.LINK 
https://dbatools.io/Export-SqlLogin

#>
	
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string]$SqlServer,
		[Alias("OutFile", "Path")]
		[string]$FilePath,
		[object]$SqlCredential,
		[Alias("NoOverwrite")]
		[switch]$NoClobber,
		[switch]$Append,
		[switch]$NoDatabases,
		[switch]$NoJobs
	)
	
	DynamicParam
	{
		if ($sqlserver)
		{
			$dbparams = Get-ParamSqlDatabases -SqlServer $sqlserver -SqlCredential $SqlCredential
			$allparams = Get-ParamSqlLogins -SqlServer $sqlserver -SqlCredential $SqlCredential
			$null = $allparams.Add("Databases", $dbparams.Databases)
			return $allparams
		}
	}
	
	BEGIN
	{
		if ($FilePath.Length -gt 0)
		{
			if ($FilePath -notlike "*\*") { $FilePath = ".\$filepath" }
			$directory = Split-Path $FilePath
			$exists = Test-Path $directory
			
			if ($exists -eq $false)
			{
				throw "Parent directory $directory does not exist"
			}
			
			Write-Output "--Attempting to connect to SQL Servers.."
		}
		
		
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
				Write-Output "--Skipping $username"
				continue
			}
			
			$servername = $sourceserver
			
			$userbase = ($username.Split("\")[0]).ToLower()
			if ($servername -eq $userbase -or $username.StartsWith("NT "))
			{
				If ($Pscmdlet.ShouldProcess("console", "Stating $username is skipped because it is a local machine name."))
				{
					Write-Output "--$username is skipped because it is a local machine name."
				}
				continue
			}
			
			If ($Pscmdlet.ShouldProcess("Outfile", "Adding T-SQL for login $username"))
			{
				if ($FilePath.Length -gt 0)
				{
					Write-Output "--Exporting $username"
				}
				
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
					$outsql += "IF NOT EXISTS (SELECT loginname from master.dbo.syslogins where name = '$username')
CREATE LOGIN [$username] WITH PASSWORD = $hashedpass HASHED, SID = $sid, DEFAULT_DATABASE = [$defaultdb], CHECK_POLICY = $checkpolicy, CHECK_EXPIRATION = $checkexpiration, DEFAULT_LANGUAGE = [$language]"
				}
				
				# Attempt to script out Windows User
				elseif ($sourcelogin.LoginType -eq "WindowsUser" -or $sourcelogin.LoginType -eq "WindowsGroup")
				{
					$outsql += "IF NOT EXISTS (SELECT loginname from master.dbo.syslogins where name = '$username')
CREATE LOGIN [$username] FROM WINDOWS WITH DEFAULT_DATABASE = [$defaultdb], DEFAULT_LANGUAGE = [$language]"
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
			
			if ($NoJobs -eq $false)
			{
				$ownedjobs = $sourceserver.JobServer.Jobs | Where { $_.OwnerLoginName -eq $username }
				
				foreach ($ownedjob in $ownedjobs)
				{
					$outsql += "use msdb"
					$jobname = $ownedjob.name
					$outsql += "EXEC msdb.dbo.sp_update_job @job_name=N'$ownedjob', @owner_login_name=N'$username'"
				}
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
			
			if ($NoDatabases -eq $false)
			{
				if ($databases.length -eq 0) { $databases = $sourcelogin.EnumDatabaseMappings() }
				# Adding database mappings and securables
				foreach ($db in $databases)
				{
					$dbname = $db.dbname
					$sourcedb = $sourceserver.databases[$dbname]
					$dbusername = $db.username
					$dblogin = $db.loginName
					
					$outsql += "use [$dbname]"
					try
					{
						$sql = $sourceserver.databases[$dbname].users[$dbusername].script()
						$outsql += $sql
					}
					catch
					{
						Write-Warning "User cannot be found in selected database"	
					}
					
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
	}
	
	END
	{
		$sql = $sql | Where-Object { $_ -notlike "CREATE USER [dbo] FOR LOGIN * WITH DEFAULT_SCHEMA=[dbo]" }
		
		$sql = $outsql -join "`r`nGO`r`n"
		
		if ($FilePath.Length -gt 0)
		{
			$sql | Out-File -FilePath $FilePath -Append:$Append -NoClobber:$NoClobber
		}
		else
		{
			return $sql
		}
		
		If ($Pscmdlet.ShouldProcess("console", "Showing final message"))
		{
			Write-Output "--SQL Login export to $FilePath complete"
			$sourceserver.ConnectionContext.Disconnect()
		}
	}
}