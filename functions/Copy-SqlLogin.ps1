Function Copy-SqlLogin
{
<#
.SYNOPSIS
Migrates logins from source to destination SQL Servers. Supports SQL Server versions 2000 and above.

.DESCRIPTION
SQL Server 2000: Migrates logins with SIDs, passwords, server roles and database roles.

SQL Server 2005 & above: Migrates logins with SIDs, passwords, defaultdb, server roles & securables, database permissions & securables, login attributes (enforce password policy, expiration, etc.)

The login hash algorithm changed in SQL Server 2012, and is not backwards compatible with previous SQL versions. This means that while SQL Server 2000 logins can be migrated to SQL Server 2012, logins created in SQL Server 2012 can only be migrated to SQL Server 2012 and above.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER Source
Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER Destination
Destination SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

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

.PARAMETER SyncOnly
Syncs only SQL Server login permissions, roles, etc. Does not add or drop logins or users. If a matching login does not exist on the destination, the login will be skipped. 
Credential removal not currently supported for Syncs. TODO: Application role sync

.PARAMETER OutFile
Calls Export-SqlLogin and exports all logins to a T-SQL formatted file. This does not perform a copy, so no destination is required.

.PARAMETER SyncSaName
Want to sync up the name of the sa account on the source and destination? Use this switch.
	
.PARAMETER Force
Force drops and recreates logins. Logins that own jobs cannot be dropped at this time.

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Copy-SqlLogin

.EXAMPLE
Copy-SqlLogin -Source sqlserver2014a -Destination sqlcluster -Force

Copies all logins from source server to destination server. If a SQL login on source exists on the destination, the destination login will be dropped and recreated.

.EXAMPLE
Copy-SqlLogin -Source sqlserver2014a -Destination sqlcluster -Exclude realcajun -SourceSqlCredential $scred -DestinationSqlCredential $dcred

Authenticates to SQL Servers using SQL Authentication.

Copies all logins except for realcajun. If a login already exists on the destination, the login will not be migrated.

.EXAMPLE
Copy-SqlLogin -Source sqlserver2014a -Destination sqlcluster -Login realcajun, netnerds -force

Copies ONLY logins netnerds and realcajun. If login realcajun or netnerds exists on the destination, they will be dropped and recreated.

.EXAMPLE
Copy-SqlLogin -Source sqlserver2014a -Destination sqlcluster -SyncOnly

Syncs only SQL Server login permissions, roles, etc. Does not add or drop logins or users. If a matching login does not exist on the destination, the login will be skipped.

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers
Limitations: Does not support Application Roles yet

#>
	
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[object]$Source,
		[parameter(ParameterSetName = "Live", Mandatory = $true)]
		[object]$Destination,
		[object]$SourceSqlCredential,
		[object]$DestinationSqlCredential,
		[switch]$SyncOnly,
		[parameter(ParameterSetName = "File", Mandatory = $true)]
		[string]$OutFile,
		[parameter(ParameterSetName = "Live")]
		[switch]$Force,
		[switch]$SyncSaName,
		[object]$pipelogin
	)
	
	DynamicParam { if ($source) { return Get-ParamSqlLogins -SqlServer $source -SqlCredential $SourceSqlCredential } }
	
	BEGIN
	{
		
		Function Copy-Login
		{
			foreach ($sourcelogin in $sourceserver.logins)
			{
				
				$username = $sourcelogin.name
				if ($Logins -ne $null -and $Logins -notcontains $username) { continue }
				if ($sourcelogin.id -eq 1) { continue }
				if ($Exclude -contains $username -or $username.StartsWith("##") -or $username -eq 'sa') { Write-Output "Skipping $username"; continue }
				$servername = Resolve-NetBiosName $sourceserver
				
				$currentlogin = $sourceserver.ConnectionContext.truelogin
				
				if ($currentlogin -eq $username -and $force)
				{
					If ($Pscmdlet.ShouldProcess("console", "Stating $username is skipped because it is performing the migration."))
					{
						Write-Warning "Cannot drop login performing the migration. Skipping"
					}
					continue
				}
				
				$userbase = ($username.Split("\")[0]).ToLower()
				if ($servername -eq $userbase -or $username.StartsWith("NT "))
				{
					If ($Pscmdlet.ShouldProcess("console", "Stating $username is skipped because it is a local machine name."))
					{
						Write-Output "$username is skipped because it is a local machine name."
					}
					continue
				}
				
				if (($login = $destserver.Logins.Item($username)) -ne $null -and !$force)
				{
					If ($Pscmdlet.ShouldProcess("console", "Stating $username is skipped because it exists at destination."))
					{
						Write-Output "$username already exists in destination. Use -force to drop and recreate."
					}
					continue
				}
				
				if ($login -ne $null -and $force)
				{
					if ($username -eq $destserver.ServiceAccount)
					{
						Write-Warning "$username is the destination service account. Skipping drop."
						continue
					}
					
					If ($Pscmdlet.ShouldProcess($destination, "Dropping $username"))
					{
						# Kill connections, delete user
						Write-Output "Attempting to migrate $username"
						Write-Output "Force was specified. Attempting to drop $username on $destination"
						try
						{
							$destserver.EnumProcesses() | Where { $_.Login -eq $username } | ForEach-Object { $destserver.KillProcess($_.spid) }
							
							$owneddbs = $destserver.Databases | Where { $_.Owner -eq $username }
							
							foreach ($owneddb in $owneddbs)
							{
								Write-Output "Changing database owner for $($owneddb.name) from $username to sa"
								$owneddb.SetOwner('sa')
								$owneddb.Alter()
							}
							
							$ownedjobs = $destserver.JobServer.Jobs | Where { $_.OwnerLoginName -eq $username }
							
							foreach ($ownedjob in $ownedjobs)
							{
								Write-Output "Changing job owner for $($ownedjob.name) from $username to sa"
								$ownedjob.set_OwnerLoginName('sa')
								$ownedjob.Alter()
							}
							
							$login.drop()
							Write-Output "Successfully dropped $username on $destination"
						}
						catch
						{
							$ex = $_.Exception.Message
							if ($ex -ne $null) { $ex.trim() }
							Write-Error "Could not drop $username`: $ex"
							Write-Exception $_
							continue
						}
					}
				}
				
				If ($Pscmdlet.ShouldProcess($destination, "Adding SQL login $username"))
				{
					Write-Output "Attempting to add $username to $destination"
					$destlogin = New-Object Microsoft.SqlServer.Management.Smo.Login($destserver, $username)
					Write-Output "Setting $username SID to source username SID"
					$destlogin.set_Sid($sourcelogin.get_Sid())
					
					$defaultdb = $sourcelogin.DefaultDatabase
					Write-Output "Setting login language to $($sourcelogin.Language)"
					$destlogin.Language = $sourcelogin.Language
					
					if ($destserver.databases[$defaultdb] -eq $null)
					{
						Write-Warning "$defaultdb does not exist on destination. Setting defaultdb to master."
						$defaultdb = "master"
					}
					Write-Output "Set $username defaultdb to $defaultdb"
					$destlogin.DefaultDatabase = $defaultdb
					
					$checkexpiration = "ON"; $checkpolicy = "ON"
					if ($sourcelogin.PasswordPolicyEnforced -eq $false) { $checkpolicy = "OFF" }
					if (!$sourcelogin.PasswordExpirationEnabled) { $checkexpiration = "OFF" }
					
					$destlogin.PasswordPolicyEnforced = $sourcelogin.PasswordPolicyEnforced
					$destlogin.PasswordExpirationEnabled = $sourcelogin.PasswordExpirationEnabled
					
					# Attempt to add SQL Login User
					if ($sourcelogin.LoginType -eq "SqlLogin")
					{
						$destlogin.LoginType = "SqlLogin"
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
						
						try { $hashedpass = $sourceserver.ConnectionContext.ExecuteScalar($sql) }
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
						
						try
						{
							$destlogin.Create($hashedpass, [Microsoft.SqlServer.Management.Smo.LoginCreateOptions]::IsHashed)
							$destlogin.refresh()
							Write-Output "Successfully added $username to $destination"
						}
						catch
						{
							try
							{
								$sid = "0x"; $sourcelogin.sid | % { $sid += ("{0:X}" -f $_).PadLeft(2, "0") }
								$sqlfailsafe = "CREATE LOGIN [$username] WITH PASSWORD = $hashedpass HASHED, SID = $sid, 
												DEFAULT_DATABASE = [$defaultdb], CHECK_POLICY = $checkpolicy, 
												CHECK_EXPIRATION = $checkexpiration, DEFAULT_LANGUAGE = [$language]"
								
								$null = $destserver.ConnectionContext.ExecuteNonQuery($sqlfailsafe)
								$destlogin = $destserver.logins[$username]
								Write-Output "Successfully added $username to $destination"
							}
							catch
							{
								Write-Warning "Failed to add $username to $destination`: $_"
								Write-Exception $_
								continue
							}
						}
					}
					# Attempt to add Windows User
					elseif ($sourcelogin.LoginType -eq "WindowsUser" -or $sourcelogin.LoginType -eq "WindowsGroup")
					{
						Write-Output "Adding as login type $($sourcelogin.LoginType)"
						$destlogin.LoginType = $sourcelogin.LoginType
						Write-Output "Setting language as $($sourcelogin.Language)"
						$destlogin.Language = $sourcelogin.Language
						
						try
						{
							$destlogin.Create()
							$destlogin.Refresh()
							Write-Output "Successfully added $username to $destination"
						}
						catch
						{
							Write-Warning "Failed to add $username to $destination"
							Write-Exception $_
							continue
						}
					}
					
					# This script does not currently support certificate mapped or asymmetric key users.
					else
					{
						Write-Warning "$($sourcelogin.LoginType) logins not supported. $($sourcelogin.name) skipped."
						continue
					}
					
					if ($sourcelogin.IsDisabled)
					{
						try { $destlogin.Disable() }
						catch { Write-Warning "$username disabled on source, but could not be disabled on destination."; Write-Exception $_ }
					}
					if ($sourcelogin.DenyWindowsLogin)
					{
						try { $destlogin.DenyWindowsLogin = $true }
						catch { Write-Warning "$username denied login on source, but could not be denied login on destination."; Write-Exception $_ }
					}
				}
				If ($Pscmdlet.ShouldProcess($destination, "Updating SQL login $username permissions"))
				{
					Update-SqlPermissions -sourceserver $sourceserver -sourcelogin $sourcelogin -destserver $destserver -destlogin $destlogin
				}
			}
		}
		
		Write-Output "Attempting to connect to SQL Servers.."
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$source = $sourceserver.DomainInstanceName
		
		if ($Destination.length -gt 0)
		{
			$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
			$destination = $destserver.DomainInstanceName
			
			if ($sourceserver.versionMajor -gt 10 -and $destserver.versionMajor -lt 11)
			{
				throw "SQL login migration from SQL Server version $($sourceserver.versionMajor) to $($destserver.versionMajor) not supported. Halting."
			}
			
			if ($sourceserver.versionMajor -lt 8 -or $destserver.versionMajor -lt 8) { throw "SQL Server 7 and below not supported. Quitting." }
		}
		
		$elapsed = [System.Diagnostics.Stopwatch]::StartNew()
		$started = Get-Date
		
		If ($Pscmdlet.ShouldProcess("console", "Showing time started message"))
		{
			Write-Output "Migration started: $started"
		}
		
		# Convert from RuntimeDefinedParameter object to regular array
		$Logins = $psboundparameters.Logins
		$Exclude = $psboundparameters.Exclude
		
		if ($Logins.length -eq 0)
		{
			$Logins = $sourceserver.logins.name
		}
		
		if ($psboundparameters.Logins -gt 0)
		{
			$loginparms += @{ 'Logins' = $logins }
		}
		
		if ($psboundparameters.Exclude -gt 0)
		{
			$loginparms += @{ 'Exclude' = $exclude }
		}
		
		return $serverparms
	}
	
	PROCESS
	{
		if ($pipelogin.Length -gt 0)
		{
			$Source = $pipelogin[0].parent.name
			$logins = $pipelogin.name
		}
		
		if ($SyncOnly)
		{
			Sync-SqlLoginPermissions -Source $Source -Destination $Destination $loginparms
			return
		}
		
		if ($OutFile)
		{
			Export-SqlLogin -SqlServer $source -FilePath $OutFile $loginparms
			return
		}
		
		If ($Pscmdlet.ShouldProcess("console", "Showing migration attempt message"))
		{
			Write-Output "Attempting Login Migration"
		}
		
		Copy-Login -sourceserver $sourceserver -destserver $destserver -Logins $Logins -Exclude $Exclude -Force $force
		
		$sa = $sourceserver.Logins | Where-Object { $_.id -eq 1 }
		$destsa = $destserver.Logins | Where-Object { $_.id -eq 1 }
		$saname = $sa.name
		
		if ($saname -ne $destsa.name -and $SyncSaName -eq $true)
		{
			Write-Output "Changing sa username to match source ($saname)"
			If ($Pscmdlet.ShouldProcess($destination, "Changing sa username to match source ($saname)"))
			{
				$destsa.Rename($saname)
				$destsa.alter()
			}
		}
	}
	
	END
	{
		
		If ($Pscmdlet.ShouldProcess("console", "Showing time elapsed message"))
		{
			Write-Output "Login migration completed: $(Get-Date)"
			$totaltime = ($elapsed.Elapsed.toString().Split(".")[0])
			$sourceserver.ConnectionContext.Disconnect()
			
			if ($Destination.length -gt 0)
			{
				$destserver.ConnectionContext.Disconnect()
			}
			
			Write-Output "Total elapsed time: $totaltime"
		}
	}
}