Function Copy-SqlLogin { 
<#
.SYNOPSIS
Migrates logins from source to destination SQL Servers. Supports SQL Server versions 2000 and above.

SQL Server 2000: Migrates logins with SIDs, passwords, server roles and database roles.

SQL Server 2005 & above: Migrates logins with SIDs, passwords, defaultdb, server roles & securables,
database permissions & securables, login attributes (enforce password policy, expiration, etc)

The login hash algorithm changed in SQL Server 2012, and is not backwards compatible with previous SQL
versions. This means that while SQL Server 2000 logins can be migrated to SQL Server 2012, logins
created in SQL Server 2012 can only be migrated to SQL Server 2012 and above.

.PARAMETER Source
Source SQL Server. You must have sysadmin access and server version must be > SQL Server 7.

.PARAMETER Destination
Destination SQL Server. You must have sysadmin access and server version must be > SQL Server 7.

.PARAMETER SourceSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, this pass $scred object to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER DestinationSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$dcred = Get-Credential, this pass this $dcred to the param. 

Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

.PARAMETER Exclude
Excludes specified logins. This list is auto-populated for tab completion.

.PARAMETER Logins
Migrates ONLY specified logins. This list is auto-populated for tab completion.

.PARAMETER SyncOnly
Syncs only SQL Server login permissions, roles, etc. Does not add or drop logins or users. If a matching login does not exist on the destination, the login will be skipped. 
Credential removal not currently supported for Syncs. TODO: Application role sync

.PARAMETER Force
Force drops and recreates logins. Logins that own jobs cannot be dropped at this time.

.EXAMPLE
Copy-SqlLogin -Source sqlserver -Destination sqlcluster -Force

Copies all logins from source server to destination server. If a SQL login on source exists on the destination,
the destination login will be dropped and recreated.

.EXAMPLE
Copy-SqlLogin -Source sqlserver -Destination sqlcluster -Exclude realcajun -SourceSqlCredential -DestinationSqlCredential

Prompts for SQL login names and passwords on both the Source and Destination then connects to each using the SQL Login credentials. 
Copies all logins except for realcajun. If a login already exists on the destination, the login will not be migrated.

.EXAMPLE
Copy-SqlLogin -Source sqlserver -Destination sqlcluster -Logins realcajun -force

Copies ONLY login realcajun. If login realcajun exists on the destination, it will be dropped and recreated.

.EXAMPLE
Copy-SqlLogin -Source sqlserver -Destination sqlcluster -SyncOnly

Syncs only SQL Server login permissions, roles, etc. Does not add or drop logins or users. If a matching login does not exist on the destination, the login will be skipped.


.NOTES 
Author: 		Chrissy LeMaire
Requires: 		PowerShell Version 3.0, SQL Server SMO
DateUpdated: 	2015-Sept-22
Version: 		2.0
Limitations: 	Does not support Application Roles yet.

.LINK 
https://gallery.technet.microsoft.com/scriptcenter/Fully-TransferMigrate-Sql-25a0cf05

.OUTPUTS
A CSV log and visual output of added or skipped logins.

#>
#Requires -Version 3.0
[CmdletBinding(SupportsShouldProcess = $true)] 

Param(
	[parameter(Mandatory = $true)]
	[object]$Source,
	[parameter(Mandatory = $true)]
	[object]$Destination,
	[object]$SourceSqlCredential,
	[object]$DestinationSqlCredential,
	[switch]$SyncOnly,	
	[switch]$Force,
	[Switch]$CsvLog
	)
	
DynamicParam  { if ($source) { return Get-ParamSqlLogins -SqlServer $source -SqlCredential $SourceSqlCredential } }

BEGIN {

Function Copy-Login {
		[cmdletbinding(SupportsShouldProcess = $true)] 
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$sourceserver,
			
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[object]$destserver,
			
			[Parameter()]
            [string[]]$Logins,
			
			[Parameter()]
            [string[]]$Exclude,
			
			[Parameter()]
            [bool]$Force
		)
		
	if ($sourceserver.versionMajor -gt 10 -and $destserver.versionMajor -lt 11) {
		throw "SQL login migration from SQL Server version $($sourceserver.versionMajor) to $($destserver.versionMajor) not supported. Halting."
	}

	$source = $sourceserver.name
	$destination = $destserver.name
	$Exclude | Where-Object {!([string]::IsNullOrEmpty($_))} | ForEach-Object { $skippedlogin.Add($_,"Explicitly Skipped") }
	
	foreach ($sourcelogin in $sourceserver.logins) {

		$username = $sourcelogin.name
		if ($Logins -ne $null -and $Logins -notcontains $username) { continue }
		if ($skippedlogin.ContainsKey($username) -or $username.StartsWith("##") -or $username -eq 'sa') { Write-Output "Skipping $username"; continue }
		$servername = Get-NetBiosName $sourceserver

		$currentlogin = $sourceserver.ConnectionContext.truelogin

		if ($currentlogin -eq $username -and $force) {
			If ($Pscmdlet.ShouldProcess("console","Stating $username is skipped because it is performing the migration.")) {
				Write-Warning "Cannot drop login performing the migration. Skipping"
				$skippedlogin.Add("$username","Skipped. Cannot drop login performing the migration.")
			}
			continue
		}
		
		$userbase = ($username.Split("\")[0]).ToLower()
		if ($servername -eq $userbase -or $username.StartsWith("NT ")) {
			If ($Pscmdlet.ShouldProcess("console","Stating $username is skipped because it is a local machine name.")) {
				Write-Output "Stating $username is skipped because it is a local machine name."
				$skippedlogin.Add("$username","Skipped. Local machine username.") 
			}
			continue
		}
		
		if (($login = $destserver.Logins.Item($username)) -ne $null -and !$force) { 
			If ($Pscmdlet.ShouldProcess("console","Stating $username is skipped because it exists at destination.")) {
				Write-Output "$username already exists in destination. Use -force to drop and recreate."
				$skippedlogin.Add("$username","Already exists in destination. Use -force to drop and recreate.") 
			}
			continue
		}
	
		if ($login -ne $null -and $force) {
			if ($username -eq $destserver.ServiceAccount) { Write-Warning "$username is the destination service account. Skipping drop."; continue }
			If ($Pscmdlet.ShouldProcess($destination,"Dropping $username")) {
				# Kill connections, delete user
				Write-Output "Attempting to migrate $username"
				Write-Output "Force was specified. Attempting to drop $username on $destination"
				try {
					$destserver.EnumProcesses() | Where { $_.Login -eq $username }  | ForEach-Object {$destserver.KillProcess($_.spid)}
					
					$owneddbs = $destserver.Databases | Where { $_.Owner -eq $username }	
						foreach ($owneddb in $owneddbs) {
							Write-Output "Changing database owner for $($owneddb.name) from $username to sa"
							$owneddb.SetOwner('sa')
							$owneddb.Alter()
						}
					
					$ownedjobs = $destserver.JobServer.Jobs | Where { $_.OwnerLoginName -eq $username } 
					foreach ($ownedjob in $ownedjobs) {
						Write-Output "Changing job owner for $($ownedjob.name) from $username to sa" 
						$ownedjob.set_OwnerLoginName('sa')
						$ownedjob.Alter() 
					}
					
					$login.drop()
					Write-Output "Successfully dropped $username on $destination"
				} catch {
					$ex = $_.Exception.Message
					if ($ex -ne $null) { $ex.trim() }
					$skippedlogin.Add("$username","Couldn't drop $username on $($destination): $ex")
					Write-Error "Could not drop $username`: $ex"
					Write-Exception $_
					continue 
				}
			}
		}
		
		If ($Pscmdlet.ShouldProcess($destination,"Adding SQL login $username")) {
			Write-Output "Attempting to add $username to $destination"
			$destlogin = New-Object Microsoft.SqlServer.Management.Smo.Login($destserver, $username)
			Write-Output "Setting $username SID to source username SID"
			$destlogin.set_Sid($sourcelogin.get_Sid())
			
			$defaultdb = $sourcelogin.DefaultDatabase
			$destlogin.Language = $sourcelogin.Language
						
			if ($destserver.databases[$defaultdb] -eq $null) {
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
			if ($sourcelogin.LoginType -eq "SqlLogin") {
				$destlogin.LoginType = "SqlLogin"
				$sourceloginname = $sourcelogin.name
				
				switch ($sourceserver.versionMajor) 
				{ 	0 {$sql = "SELECT convert(varbinary(256),password) as hashedpass FROM master.dbo.syslogins WHERE loginname='$sourceloginname'"} 
					8 {$sql = "SELECT convert(varbinary(256),password) as hashedpass FROM dbo.syslogins WHERE name='$sourceloginname'"} 
					9 {$sql = "SELECT convert(varbinary(256),password_hash) as hashedpass FROM sys.sql_logins where name='$sourceloginname'"} 
					default {$sql = "SELECT CAST(CONVERT(varchar(256), CAST(LOGINPROPERTY(name,'PasswordHash') 
						AS varbinary (256)), 1) AS nvarchar(max)) as hashedpass FROM sys.server_principals
						WHERE principal_id = $($sourcelogin.id)"
					} 
				}

				try { $hashedpass = $sourceserver.ConnectionContext.ExecuteScalar($sql) }
				catch { 
					$hashedpassdt = $sourceserver.databases['master'].ExecuteWithResults($sql) 
					$hashedpass = $hashedpassdt.Tables[0].Rows[0].Item(0)
				}
				
				if ($hashedpass.gettype().name -ne "String") {
					$passtring = "0x"; $hashedpass | % {$passtring += ("{0:X}" -f $_).PadLeft(2, "0")}
					$hashedpass = $passtring
				}
					
				try {
					$destlogin.Create($hashedpass, [Microsoft.SqlServer.Management.Smo.LoginCreateOptions]::IsHashed)
					$migratedlogin.Add("$username","SQL Login Added successfully") 
					$destlogin.refresh()
					Write-Output "Successfully added $username to $destination" }
				catch {
					try {
						$sid = "0x"; $sourcelogin.sid | % {$sid += ("{0:X}" -f $_).PadLeft(2, "0")}
						$sqlfailsafe = "CREATE LOGIN [$username] WITH PASSWORD = $hashedpass HASHED, SID = $sid, 
						DEFAULT_DATABASE = [$defaultdb], CHECK_POLICY = $checkpolicy, CHECK_EXPIRATION = $checkexpiration"
						$null = $destserver.ConnectionContext.ExecuteNonQuery($sqlfailsafe) 
						$destlogin = $destserver.logins[$username]
						$migratedlogin.Add("$username","SQL Login Added successfully") 
						Write-Output "Successfully added $username to $destination"
					} catch {
							$skippedlogin.Add("$username","Add failed")
							Write-Warning "Failed to add $username to $destination`: $_"
							Write-Exception $_
							continue 
					}
				}
			} 
			# Attempt to add Windows User
			elseif ($sourcelogin.LoginType -eq "WindowsUser" -or $sourcelogin.LoginType -eq "WindowsGroup") {
				$destlogin.LoginType = $sourcelogin.LoginType
				$destlogin.Language = $sourcelogin.Language
								
				try {
					$destlogin.Create()
					$migratedlogin.Add("$username","Windows user/group added successfully") 
					$destlogin.refresh()
					Write-Output "Successfully added $username to $destination" }
				catch  { 
					$skippedlogin.Add("$username","Add failed")
					Write-Warning "Failed to add $username to $destination"
					Write-Exception $_
					continue 
				}
			}
			# This script does not currently support certificate mapped or asymmetric key users.
			else { 
				$skippedlogin.Add("$username","Skipped. $($sourcelogin.LoginType) logins not supported.")
				Write-Warning "$($sourcelogin.LoginType) logins not supported. $($sourcelogin.name) skipped."
				continue 
			}
			
			if ($sourcelogin.IsDisabled) { try { $destlogin.Disable() } catch { Write-Warning "$username disabled on source, but could not be disabled on destination."; Write-Exception $_ } }
			if ($sourcelogin.DenyWindowsLogin) { try { $destlogin.DenyWindowsLogin = $true } catch { Write-Warning "$username denied login on source, but could not be denied login on destination."; Write-Exception $_ } }
		}
		If ($Pscmdlet.ShouldProcess($destination,"Updating SQL login $username permissions")) {
			Update-SqlPermissions -sourceserver $sourceserver -sourcelogin $sourcelogin -destserver $destserver -destlogin $destlogin
		}
	}
			
}

Function Update-SqlPermissions      {
	 <#
	.SYNOPSIS
	 Updates permission sets, roles, database mappings on server and databases
	.EXAMPLE 
	Update-SqlPermissions -sourceserver $sourceserver -sourcelogin $sourcelogin -destserver $destserver -destlogin $destlogin

		#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[object]$sourceserver,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[object]$sourcelogin,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[object]$destserver,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[object]$destlogin
	)

$destination = $destserver.name
$source = $sourceserver.name
$username = $sourcelogin.name

# Server Roles: sysadmin, bulkcurrentlogin, etc
	foreach ($role in $sourceserver.roles) {
		$destrole = $destserver.roles[$role.name]
		if ($destrole -ne $null) { 
			try { $destrolemembers = $destrole.EnumMemberNames() } catch { $destrolemembers = $destrole.EnumServerRoleMembers() }
		}
		try { $rolemembers = $role.EnumMemberNames() } catch { $rolemembers = $role.EnumServerRoleMembers() }		
		if ($rolemembers -contains $username) {
			if ($destrole -ne $null) { 
				If ($Pscmdlet.ShouldProcess($destination,"Adding $username to $($role.name) server role")) {
					try {
						$destrole.AddMember($username)
						Write-Output "Added $username to $($role.name) server role." 
					} catch {
						Write-Warning "Failed to add $username to $($role.name) server role."
						Write-Exception $_
					}
				}
			}
		}

		# Remove for Syncs
		if ($rolemembers -notcontains $username -and $destrolemembers -contains $username -and $destrole -ne $null) {
			If ($Pscmdlet.ShouldProcess($destination,"Adding $username to $($role.name) server role")) {
				try {
					$destrole.DropMember($username)
					Write-Output "Removed $username from $($destrole.name) server role on $($destserver.name)." 
					} catch {
					Write-Warning "Failed to remove $username from $($destrole.name) server role on $($destserver.name)." 
					Write-Exception $_
				}
			}
		}
	}
	
	$ownedjobs = $sourceserver.JobServer.Jobs | Where { $_.OwnerLoginName -eq $username } 
	foreach ($ownedjob in $ownedjobs) {
		if ($destserver.JobServer.Jobs[$ownedjob.name] -ne $null) {
			If ($Pscmdlet.ShouldProcess($destination,"Changing job owner to $username for $($ownedjob.name)")) {
				try {
					Write-Output "Changing job owner to $username for $($ownedjob.name)"
					$destownedjob = $destserver.JobServer.Jobs | Where { $_.name -eq $ownedjobs.name } 
					$destownedjob.set_OwnerLoginName($username)
					$destownedjob.Alter() 
				} catch { 
					Write-Warning "Could not change job owner for $($ownedjob.name)" 
					Write-Exception $_
				}
			}
		}
	}
		
	if ($sourceserver.versionMajor -ge 9 -and $destserver.versionMajor -ge 9) { 
		# These operations are only supported by SQL Server 2005 and above.
		# Securables: Connect SQL, View any database, Administer Bulk Operations, etc.
		
		$perms = $sourceserver.EnumServerPermissions($username)
		foreach ($perm in $perms) {
			$permstate = $perm.permissionstate
			if ($permstate -eq "GrantWithGrant") { $grantwithgrant = $true; $permstate = "grant" } else { $grantwithgrant = $false }
			$permset = New-Object Microsoft.SqlServer.Management.Smo.ServerPermissionSet($perm.permissiontype)
			If ($Pscmdlet.ShouldProcess($destination,"Performing $permstate on $($perm.permissiontype) for $username")) {
				try { 
					$destserver.PSObject.Methods[$permstate].Invoke($permset, $username, $grantwithgrant)
					Write-Output "Successfully performed $permstate $($perm.permissiontype) to $username" 
				} catch {
					Write-Warning "Failed to $permstate $($perm.permissiontype) to $username"
					Write-Exception $_
				}
			}
			
			# for Syncs
			$destperms = $destserver.EnumServerPermissions($username) 
			foreach ($perm in $destperms) {
				$permstate = $perm.permissionstate
				$sourceperm = $perms | Where-Object { $_.PermissionType -eq $perm.Permissiontype -and $_.PermissionState -eq $permstate}
				if ($sourceperm -eq $null) {
					If ($Pscmdlet.ShouldProcess($destination,"Performing Revoke on $($perm.permissiontype) for $username")) {
						try { 
							$permset = New-Object Microsoft.SqlServer.Management.Smo.ServerPermissionSet($perm.permissiontype)
							if ($permstate -eq "GrantWithGrant") { $grantwithgrant = $true; $permstate = "grant" } else { $grantwithgrant = $false }
							$destserver.PSObject.Methods["Revoke"].Invoke($permset, $username, $false, $grantwithgrant)
							Write-Output "Successfully revoked $($perm.permissiontype) from $username" 
						} catch {
							Write-Warning "Failed to revoke $($perm.permissiontype) from $username"
							Write-Exception $_
						}
					}
				}
			}
		}
		
		# Credential mapping. Credential removal not currently supported for Syncs.
		$logincredentials = $sourceserver.credentials | Where-Object {$_.Identity -eq $sourcelogin.name}
		foreach ($credential in $logincredentials) {
			if ($destserver.Credentials[$credential.name] -eq $null) {
				If ($Pscmdlet.ShouldProcess($destination,"Adding $($credential.name) to $username")) {
					try {
						$newcred = New-Object Microsoft.SqlServer.Management.Smo.Credential($destserver, $credential.name)
						$newcred.identity = $sourcelogin.name
						$newcred.Create() 
						Write-Output "Successfully created credential for $username" 
					} catch {
						Write-Warning "Failed to create credential for $username" 
						Write-Exception $_
					}
				}
			}
		}
	}
		
	if ($destserver.versionMajor -lt 9) { Write-Warning "Database mappings skipped when destination is < SQL Server 2005"; continue }
	
	# For Sync, if info doesn't exist in EnumDatabaseMappings, then no big deal.
	foreach ($db in $destlogin.EnumDatabaseMappings()) {
		$dbname = $db.dbname
		$destdb = $destserver.databases[$dbname]
		$sourcedb = $sourceserver.databases[$dbname]
		$dbusername = $db.username; $dblogin = $db.loginName
		
		if ($sourcedb -ne $null) {
			if ($sourcedb.users[$dbusername] -eq $null -and $destdb.users[$dbusername] -ne $null) {
				If ($Pscmdlet.ShouldProcess($destination,"Dropping $dbusername from $dbname on destination.")) {
					try { 
						$destdb.users[$dbusername].Drop()
						Write-Output "Dropped user $dbusername (login: $dblogin) from $dbname on destination. User may own a schema." }
					catch { 
						Write-Warning "Failed to drop $dbusername ($dblogin) from $dbname on destination."
						Write-Exception $_
					}
				}
			}

			# Remove user from role. Role removal not currently supported for Syncs.
			# TODO: reassign if dbo, application roles
			foreach ($destrole in $destdb.roles) {
				$sourcerole = $sourcedb.roles[$destrole.name]
				if ($sourcerole -ne $null) {
					if ($sourcerole.EnumMembers() -notcontains $dbusername -and $destrole.EnumMembers() -contains $dbusername) {
						if ($dbusername -ne "dbo") {
							If ($Pscmdlet.ShouldProcess($destination,"Dropping $username from $($destrole.name) database role on $dbname")) {
								try { 
									$destrole.DropMember($dbusername)
									$destdb.Alter()
									Write-Output "Dropped username $dbusername (login: $dblogin) from ($destrole.name) on $destination"
								}
								catch { 
									Write-Warning "Failed to remove $dbusername from $($destrole.name) database role on $dbname."
									Write-Exception $_
								}
							}
						}
					}
				}
			}
		
			# Remove Connect, Alter Any Assembly, etc
			$destperms = $destdb.EnumDatabasePermissions($username)
			$perms = $sourcedb.EnumDatabasePermissions($username)
			# for Syncs
			foreach ($perm in $destperms) {
				$permstate = $perm.permissionstate
				$sourceperm = $perms | Where-Object { $_.PermissionType -eq $perm.Permissiontype -and $_.PermissionState -eq $permstate}
				if ($sourceperm -eq $null) {
					If ($Pscmdlet.ShouldProcess($destination,"Performing Revoke on $($perm.permissiontype) for $username on $dbname on $destination")) {
						try { 
							$permset = New-Object Microsoft.SqlServer.Management.Smo.DatabasePermissionSet($perm.permissiontype)
							if ($permstate -eq "GrantWithGrant") { $grantwithgrant = $true; $permstate = "grant" } else { $grantwithgrant = $false }
							$destdb.PSObject.Methods["Revoke"].Invoke($permset, $username, $false, $grantwithgrant)
							Write-Output "Successfully revoked $($perm.permissiontype) from $username on $dbname on $destination" 
						} catch {
							Write-Warning "Failed to revoke $($perm.permissiontype) from $username on $dbname on $destination" 
							Write-Exception $_
						}
					}
				}
			}
		}
	}
	
	# Adding database mappings and securables
	foreach ($db in $sourcelogin.EnumDatabaseMappings()) {
		$dbname = $db.dbname
		$destdb = $destserver.databases[$dbname]
		$sourcedb = $sourceserver.databases[$dbname]
		$dbusername = $db.username; $dblogin = $db.loginName
		
		if ($destdb -ne $null) {
			if ($destdb.users[$dbusername] -eq $null) {
				If ($Pscmdlet.ShouldProcess($destination,"Adding $dbusername to $dbname")) {
					$sql = $sourceserver.databases[$dbname].users[$dbusername].script()
					try { 
						$destdb.ExecuteNonQuery($sql)
						Write-Output "Added user $dbusername (login: $dblogin) to $dbname" 
					}
					catch { 
						Write-Warning "Failed to add $dbusername ($dblogin) to $dbname on $destination."
						Write-Exception $_
					}
				}
			}
			
		 # Db owner
			If ($sourcedb.owner -eq $username) {
				If ($Pscmdlet.ShouldProcess($destination,"Changing $dbname dbowner to $username")) {
					try {
						$result = Update-SqlDbOwner $sourceserver $destserver -dbname $dbname
						if ($result -eq $true) {
							Write-Output "Changed $($destdb.name) owner to $($sourcedb.owner)."
						} else { Write-Warning "Failed to update $($destdb.name) owner to $($sourcedb.owner)." }
					} catch { Write-Warning "Failed to update $($destdb.name) owner to $($sourcedb.owner)." }
				}
			}
		
		 # Database Roles: db_owner, db_datareader, etc
			foreach ($role in $sourcedb.roles) {
				if ($role.EnumMembers() -contains $username) {
					$destdbrole = $destdb.roles[$role.name]
					if ($destdbrole -ne $null -and $dbusername -ne "dbo" -and $destdbrole.EnumMembers() -notcontains $username) { 
						If ($Pscmdlet.ShouldProcess($destination,"Adding $username to $($role.name) database role on $dbname")) {
							try { 
								$destdbrole.AddMember($username)
								$destdb.Alter() 
								Write-Output "Added $username to $($role.name) database role on $dbname." 
								
							} catch { 
								Write-Warning "Failed to add $username to $($role.name) database role on $dbname."
								Write-Exception $_ 
							}
						}
					}
				}
			}
			
			# Connect, Alter Any Assembly, etc
			$perms = $sourcedb.EnumDatabasePermissions($username)
			foreach ($perm in $perms) {
				$permstate = $perm.permissionstate
				if ($permstate -eq "GrantWithGrant") { $grantwithgrant = $true; $permstate = "grant" } else { $grantwithgrant = $false }
				$permset = New-Object Microsoft.SqlServer.Management.Smo.DatabasePermissionSet($perm.permissiontype)
				If ($Pscmdlet.ShouldProcess($destination,"Performing $permstate on $($perm.permissiontype) for $username on $dbname")) {
					try { 
						$destdb.PSObject.Methods[$permstate].Invoke($permset, $username, $grantwithgrant)
						Write-Output "Successfully performed $permstate $($perm.permissiontype) to $username on $dbname" 
					}
					catch { 
						Write-Warning "Failed to perform $permstate on $($perm.permissiontype) for $username on $dbname." 
						Write-Exception $_
					}		
				}
			}
		}
	}
}

Function Sync-Only {
	 <#
	.SYNOPSIS
	  Skips migration, and just syncs permission sets, roles, database mappings on server and databases
	.EXAMPLE 
	 Sync-Only -sourceserver $sourceserver -destserver $destserver -Logins $Logins -Exclude $Exclude

		#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[object]$sourceserver,
		[object]$destserver,
		[array]$Logins,
		[array]$Exclude
	)
	
	$source = $sourceserver.name; $destination = $destserver.name
	$exclude | Where-Object {!([string]::IsNullOrEmpty($_))} | ForEach-Object { $skippedlogin.Add($_,"Explicitly Skipped") }
	
	foreach ($sourcelogin in $sourceserver.logins) {

		$username = $sourcelogin.name
		$currentlogin = $sourceserver.ConnectionContext.truelogin
		if ($Logins -ne $null -and $Logins -notcontains $username) { continue }
		if ($skippedlogin.ContainsKey($username) -or $username.StartsWith("##") -or $username -eq 'sa') { continue }
		
		if ($currentlogin -eq $username) {
			Write-Warning "Sync does not modify the permissions of the current user. Skipping."
			continue
		}
		
		$servername = Get-NetBiosName $sourceserver
		$userbase = ($username.Split("\")[0]).ToLower()
		if ($servername -eq $userbase -or $username.StartsWith("NT ")) { continue }
		if (($destlogin = $destserver.Logins.Item($username)) -eq $null) { continue }
		
		Update-SqlPermissions -sourceserver $sourceserver -sourcelogin $sourcelogin -destserver $destserver -destlogin $destlogin
	}
}

}


PROCESS { 
	<# ----------------------------------------------------------
		Sanity Checks
			- Is SMO available?
			- Are SQL Servers reachable?
			- Is the account running this script an currentlogin?
			- Are SQL Versions >= 2005?
	---------------------------------------------------------- #>
	$elapsed = [System.Diagnostics.Stopwatch]::StartNew() 
	$started = Get-Date
	
	if ($source -eq $destination) { throw "Source and Destination SQL Servers are the same. Quitting." }

	$script:skippedlogin = @{}; $script:migratedlogin = @{}; 
	
	Write-Output "Attempting to connect to SQL Servers.." 
	$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
	$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential

	$source = $sourceserver.name
	$destination = $destserver.name
	
	if (!(Test-SqlSa -SqlServer $sourceserver -SqlCredential $SourceSqlCredential)) { throw "Not a sysadmin on $source. Quitting." }
	if (!(Test-SqlSa -SqlServer $destserver -SqlCredential $DestinationSqlCredential)) { throw "Not a sysadmin on $destination. Quitting." }
	
	if ($sourceserver.versionMajor -lt 8 -or $destserver.versionMajor -lt 8) {throw "SQL Server 7 and below not supported. Quitting." }
	
	<# ----------------------------------------------------------
		Preps
	---------------------------------------------------------- #>

	# Convert from RuntimeDefinedParameter  object to regular array
	$Logins = $psboundparameters.Logins
	$Exclude = $psboundparameters.Exclude

	<# ----------------------------------------------------------
		Run
	---------------------------------------------------------- #>
	
	if ($SyncOnly) {
		Write-Output "Syncing Login Permissions"; 
		Sync-Only -sourceserver $sourceserver -destserver $destserver -Logins $Logins -Exclude $Exclude
		return
	}
	 
	Write-Output "Attempting Login Migration"; 
	Copy-Login -sourceserver $sourceserver -destserver $destserver -Logins $Logins -Exclude $Exclude -Force $force
	
	
	$timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
	$csvfilename = "$($sourceserver.name.replace('\','$'))-to-$($destserver.name.replace('\','$'))-$timenow"
	
	if ($CsvLog) {
		If ($Pscmdlet.ShouldProcess("console","Showing summary information.")) {
			$migratedlogin.GetEnumerator() | Sort-Object value; $skippedlogin.GetEnumerator() | Sort-Object value
			$migratedlogin.GetEnumerator() | Sort-Object value | Select Name, Value | Export-Csv -Path "$csvfilename-logins.csv" -NoTypeInformation
			$skippedlogin.GetEnumerator() | Sort-Object value | Select Name, Value | Export-Csv -Append -Path "$csvfilename-logins.csv" -NoTypeInformation
		}
	}
}

END {

	If ($Pscmdlet.ShouldProcess("console","Showing time elapsed message")) {
		$totaltime = ($elapsed.Elapsed.toString().Split(".")[0])
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		Write-Output "Login migration finished"
		Write-Output "Migration started: $started" 
		Write-Output "Migration completed: $(Get-Date)" 
		Write-Output "Total Elapsed time: $totaltime" 
	}
}
}