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

.PARAMETER UseSqlLoginSource
Uses SQL Login credentials to connect to Source server. Note this is a switch. You will be prompted to enter your SQL login credentials. 

Windows Authentication will be used if UseSqlLoginSource is not specified.

NOTE: Auto-populating parameters (ExcludeLogins, IncludeLogins) are populated by the account running the PowerShell script.

.PARAMETER UseSqlLoginDestination
Uses SQL Login credentials to connect to Destination server. Note this is a switch. You will be prompted to enter your SQL login credentials. 

Windows Authentication will be used if UseSqlLoginDestination is not specified. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER ExcludeLogins
Excludes specified logins. This list is auto-populated for tab completion.

.PARAMETER IncludeLogins
Migrates ONLY specified logins. This list is auto-populated for tab completion.

.PARAMETER SyncOnly
Syncs only SQL Server login permissions, roles, etc. Does not add or drop logins or users. If a matching login does not exist on the destination, the login will be skipped. 
Credential removal not currently supported for Syncs. TODO: Application role sync

.PARAMETER Force
Force drops and recreates logins. Logins that own jobs cannot be dropped at this time.

.EXAMPLE
.\Copy-SQLServerLogins.ps1 -Source sqlserver -Destination sqlcluster -Force

Copies all logins from source server to destination server. If a SQL login on source exists on the destination,
the destination login will be dropped and recreated.

.EXAMPLE
.\Copy-SQLServerLogins.ps1 -Source sqlserver -Destination sqlcluster -ExcludeLogins realcajun -UseSqlLoginSource -UseSqlLoginDestination

Prompts for SQL login usernames and passwords on both the Source and Destination then connects to each using the SQL Login credentials. 
Copies all logins except for realcajun. If a login already exists on the destination, the login will not be migrated.

.EXAMPLE
.\Copy-SQLServerLogins.ps1 -Source sqlserver -Destination sqlcluster -IncludeLogins realcajun -force

Copies ONLY login realcajun. If login realcajun exists on the destination, it will be dropped and recreated.

.EXAMPLE
.\Copy-SQLServerLogins.ps1 -Source sqlserver -Destination sqlcluster -SyncOnly

Syncs only SQL Server login permissions, roles, etc. Does not add or drop logins or users. If a matching login does not exist on the destination, the login will be skipped.


.NOTES 
Author: 		Chrissy LeMaire
Requires: 		PowerShell Version 3.0, SQL Server SMO
DateUpdated: 	2015-Apr-27
Version: 		1.5.1
Limitations: 	Does not support Application Roles yet. When using -Force, logins that own jobs cannot be dropped at this time.

.LINK 
https://gallery.technet.microsoft.com/scriptcenter/Fully-TransferMigrate-SQL-25a0cf05

.OUTPUTS
A CSV log and visual output of added or skipped logins.

#>
#Requires -Version 3.0
[CmdletBinding(SupportsShouldProcess = $true)] 

Param(
	# Source SQL Server
	[parameter(Mandatory = $true)]
	[string]$Source,
	
	# Destination SQL Server
	[parameter(Mandatory = $true)]
	[string]$Destination,

	[switch]$UseSqlLoginSource,
	[switch]$UseSqlLoginDestination,
	[switch]$SyncOnly,	
	[switch]$Force
	)

DynamicParam  {
	if ($Source) {
		# Check for SMO and SQL Server access
		if ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") -eq $null) {return}
		
		$server = New-Object Microsoft.SqlServer.Management.Smo.Server $source
		$server.ConnectionContext.ConnectTimeout = 2
		try { $server.ConnectionContext.Connect() } catch { return }

		# Populate arrays
		$loginlist = @()
		foreach ($login in $server.logins) { 
			if (!$login.name.StartsWith("##") -and $login.name -ne 'sa') {
				$loginlist += $login.name}
			}
				
		# Reusable parameter setup
		$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
		$attributes = New-Object System.Management.Automation.ParameterAttribute
		$attributes.ParameterSetName = "__AllParameterSets"
		$attributes.Mandatory = $false
		
		# Login list parameter setup
		if ($loginlist) { $loginvalidationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $loginlist }
		$loginattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
		$loginattributes.Add($attributes)
		if ($loginlist) { $loginattributes.Add($loginvalidationset) }
		$IncludeLogins = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("IncludeLogins", [String[]], $loginattributes)
		$ExcludeLogins = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("ExcludeLogins", [String[]], $loginattributes)

		$newparams.Add("IncludeLogins", $IncludeLogins)
		$newparams.Add("ExcludeLogins", $ExcludeLogins)
		
		$server.ConnectionContext.Disconnect()
	
	return $newparams
	}
}

BEGIN {

Function Copy-SQLLogins {
	<#
	.SYNOPSIS
	  Migrates logins from source to destination SQL Servers. Database & Server securables & permissions are preserved.
	
	.EXAMPLE
	 Copy-SQLLogins -Source $sourceserver -Destination $destserver -Force $true
	
	 Copies logins from source server to destination server.
	 
	.OUTPUTS
	   A CSV log and visual output of added or skipped logins.
	#>
		[cmdletbinding(SupportsShouldProcess = $true)] 
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$sourceserver,
			
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[object]$destserver,
			
			[Parameter()]
            [string[]]$IncludeLogins,
			
			[Parameter()]
            [string[]]$ExcludeLogins,
			
			[Parameter()]
            [bool]$Force
		)
		
	if ($sourceserver.versionMajor -gt 10 -and $destserver.versionMajor -lt 11) {
		throw "SQL user migration from SQL Server version $($sourceserver.versionMajor) to $($destserver.versionMajor) not supported. Halting."
	}

	$skippeduser = @{}; $migrateduser = @{}; $source = $sourceserver.name; $destination = $destserver.name
	$ExcludeLogins | Where-Object {!([string]::IsNullOrEmpty($_))} | ForEach-Object { $skippeduser.Add($_,"Explicitly Skipped") }
	$timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
	$csvfilename = "$($sourceserver.name.replace('\','$'))-to-$($destserver.name.replace('\','$'))-$timenow"
	
	foreach ($sourcelogin in $sourceserver.logins) {

		$username = $sourcelogin.name
		if ($IncludeLogins -ne $null -and $IncludeLogins -notcontains $username) { continue }
		if ($skippeduser.ContainsKey($username) -or $username.StartsWith("##") -or $username -eq 'sa') { continue }
		$servername = Get-NetBIOSName $sourceserver

		$currentuser = $sourceserver.ConnectionContext.truelogin

		if ($currentuser -eq $username -and $force) {
			Write-Warning "Cannot drop login performing the migration. Skipping"
			$skippeduser.Add("$username","Skipped. Cannot drop login performing the migration.")
			continue
		}
		
		$userbase = ($username.Split("\")[0]).ToLower()
		if ($servername -eq $userbase -or $username.StartsWith("NT ")) {
			$skippeduser.Add("$username","Skipped. Local machine username.")
			continue }
		if (($login = $destserver.Logins.Item($username)) -ne $null -and !$force) { 
			$skippeduser.Add("$username","Already exists in destination. Use -force to drop and recreate.")
			continue }
	
		if ($login -ne $null -and $force) {
			if ($username -eq $destserver.ServiceAccount) { Write-Warning "$username is the destination service account. Skipping drop."; continue }
			If ($Pscmdlet.ShouldProcess($destination,"Dropping $username")) {
				# Kill connections, delete user
				Write-Host "Attempting to migrate $username" -ForegroundColor Yellow
				Write-Host "Force was specified. Attempting to drop $username on $destination" -ForegroundColor Yellow
				try {
					$destserver.EnumProcesses() | Where { $_.Login -eq $username }  | ForEach-Object {$destserver.KillProcess($_.spid)}		
					$destserver.Databases | Where { $_.Owner -eq $username } | ForEach-Object { $_.SetOwner('sa'); $_.Alter()  }	
					$login.drop()
					Write-Host "Successfully dropped $username on $destination" -ForegroundColor Green
				} catch { 
					$errormessage = (($_.Exception.InnerException).ToString()).Trim()
					$skippeduser.Add("$username","Couldn't drop $username on $($destination): $errormessage")
					Write-Warning "Could not drop $username. Skipping"
					continue 
				}
			}
		}
		
		If ($Pscmdlet.ShouldProcess($destination,"Adding SQL login $username")) {
			Write-Host "Attempting to add $username to $destination" -ForegroundColor Yellow
			$destlogin = new-object Microsoft.SqlServer.Management.Smo.Login($destserver, $username)
			Write-Host "Setting $username SID to source username SID" -ForegroundColor Green
			$destlogin.set_Sid($sourcelogin.get_Sid())
			$defaultdb = $sourcelogin.DefaultDatabase
			if ($destserver.databases[$defaultdb] -eq $null) {
				Write-Warning "$defaultdb does not exist on destination. Setting defaultdb to master."
				$defaultdb = "master" 
			}
			Write-Host "Set $username defaultdb to $defaultdb" -ForegroundColor Green
			$destlogin.DefaultDatabase = $defaultdb

			$checkexpiration = "ON"; $checkpolicy = "ON"
			if (!$sourcelogin.PasswordPolicyEnforced) { 
				$destlogin.PasswordPolicyEnforced = $false 
				$checkpolicy = "OFF"
			}
			if (!$sourcelogin.PasswordExpirationEnabled) { 
				$destlogin.PasswordExpirationEnabled = $false
				$checkexpiration = "OFF"
			}
	
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
					$migrateduser.Add("$username","SQL Login Added successfully") 
					$destlogin.refresh()
					Write-Host "Successfully added $username to $destination" -ForegroundColor Green }
				catch {
					try {
						$sid = "0x"; $sourcelogin.sid | % {$sid += ("{0:X}" -f $_).PadLeft(2, "0")}
						$sqlfailsafe = "CREATE LOGIN [$username] WITH PASSWORD = $hashedpass HASHED, SID = $sid, 
						DEFAULT_DATABASE = [$defaultdb], CHECK_POLICY = $checkpolicy, CHECK_EXPIRATION = $checkexpiration"
						$null = $destserver.ConnectionContext.ExecuteNonQuery($sqlfailsafe) 
						$destlogin = $destserver.logins[$username]
						$migrateduser.Add("$username","SQL Login Added successfully") 
						Write-Host "Successfully added $username to $destination" -ForegroundColor Green
					} catch {
						$ex = ($_.Exception.InnerException).tostring()
						$ex = ($ex -split "at Microsoft.SqlServer.Management.Common.ConnectionManager")[0]
						$skippeduser.Add("$username","Add failed: $ex")
						Write-Warning "Failed to add $username to $destination. See log for details."
						continue 
					}
				}
			} 
			# Attempt to add Windows User
			elseif ($sourcelogin.LoginType -eq "WindowsUser" -or $sourcelogin.LoginType -eq "WindowsGroup") {
				$destlogin.LoginType = $sourcelogin.LoginType
				try {
					$destlogin.Create()
					$migrateduser.Add("$username","Windows user/group added successfully") 
					$destlogin.refresh()
					Write-Host "Successfully added $username to $destination" -ForegroundColor Green }
				catch { 
					$skippeduser.Add("$username","Add failed")
					Write-Warning "Failed to add $username to $destination. See log for details."
					continue }
			}
			# This script does not currently support certificate mapped or asymmetric key users.
			else { 
				$skippeduser.Add("$username","Skipped. $($sourcelogin.LoginType) logins not supported.")
				Write-Warning "$($sourcelogin.LoginType) logins not supported. $($sourcelogin.name) skipped."
				continue }
			
			if ($sourcelogin.IsDisabled) { try { $destlogin.Disable() } catch { Write-Warning "$username disabled on source, but could not be disabled on destination." } }
			if ($sourcelogin.DenyWindowsLogin) { try { $destlogin.DenyWindowsLogin = $true } catch { Write-Warning "$username denied login on source, but could not be denied ogin on destination." } }
		}
		Update-SQLPermissions -sourceserver $sourceserver -sourcelogin $sourcelogin -destserver $destserver -destlogin $destlogin
	}

	$migrateduser.GetEnumerator() | Sort-Object value; $skippeduser.GetEnumerator() | Sort-Object value
	$migrateduser.GetEnumerator() | Sort-Object value | Select Name, Value | Export-Csv -Path "$csvfilename-users.csv" -NoTypeInformation
	$skippeduser.GetEnumerator() | Sort-Object value | Select Name, Value | Export-Csv -Append -Path "$csvfilename-users.csv" -NoTypeInformation
	Write-Host "Completed user migration" -ForegroundColor Green
			
}

Function Update-SQLPermissions      {
	 <#
	.SYNOPSIS
	 Updates permission sets, roles, database mappings on server and databases
	.EXAMPLE 
	Update-SQLPermissions -sourceserver $sourceserver -sourcelogin $sourcelogin -destserver $destserver -destlogin $destlogin

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

# Server Roles: sysadmin, bulkcurrentuser, etc
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
						Write-Host "Added $username to $($role.name) server role."  -ForegroundColor Green
						} catch {
						Write-Warning "Failed to add $username to $($role.name) server role." 
					}
				}
			}
		}

		# Remove for Syncs
		if ($rolemembers -notcontains $username -and $destrolemembers -contains $username -and $destrole -ne $null) {
			If ($Pscmdlet.ShouldProcess($destination,"Adding $username to $($role.name) server role")) {
				try {
					$destrole.DropMember($username)
					Write-Host "Removed $username from $($destrole.name) server role on $($destserver.name)."  -ForegroundColor Yellow
					} catch {
					Write-Warning "Failed to remove $username from $($destrole.name) server role on $($destserver.name)." 
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
			$permset = New-object Microsoft.SqlServer.Management.Smo.ServerPermissionSet($perm.permissiontype)
			If ($Pscmdlet.ShouldProcess($destination,"Performing $permstate on $($perm.permissiontype) for $username")) {
				try { 
					$destserver.PSObject.Methods[$permstate].Invoke($permset, $username, $grantwithgrant)
					Write-Host "Successfully performed $permstate $($perm.permissiontype) to $username"  -ForegroundColor Green
				} catch {
					Write-Warning "Failed to $permstate $($perm.permissiontype) to $username" 
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
							$permset = New-object Microsoft.SqlServer.Management.Smo.ServerPermissionSet($perm.permissiontype)
							if ($permstate -eq "GrantWithGrant") { $grantwithgrant = $true; $permstate = "grant" } else { $grantwithgrant = $false }
							$destserver.PSObject.Methods["Revoke"].Invoke($permset, $username, $false, $grantwithgrant)
							Write-Host "Successfully revoked $($perm.permissiontype) from $username"  -ForegroundColor Yellow
						} catch {
							Write-Warning "Failed to revoke $($perm.permissiontype) from $username" 
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
						$newcred = new-object Microsoft.SqlServer.Management.Smo.Credential($destserver, $credential.name)
						$newcred.identity = $sourcelogin.name
						$newcred.Create() 
						Write-Host "Successfully created credential for $username"  -ForegroundColor Green
					} catch {
						Write-Warning "Failed to create credential for $username" }
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
						Write-Host "Dropped username $dbusername (login: $dblogin) from $dbname on destination. User may own a schema." -ForegroundColor Yellow }
					catch { Write-Warning "Failed to drop $dbusername ($dblogin) from $dbname on destination."
					}
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
								Write-Host "Dropped username $dbusername (login: $dblogin) from ($destrole.name) on $destination" -ForegroundColor Yellow
							}
							catch { Write-Warning "Failed to remove $dbusername from $($destrole.name) database role on $dbname." }
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
						$permset = New-object Microsoft.SqlServer.Management.Smo.DatabasePermissionSet($perm.permissiontype)
						if ($permstate -eq "GrantWithGrant") { $grantwithgrant = $true; $permstate = "grant" } else { $grantwithgrant = $false }
						$destdb.PSObject.Methods["Revoke"].Invoke($permset, $username, $false, $grantwithgrant)
						Write-Host "Successfully revoked $($perm.permissiontype) from $username on $dbname on $destination"  -ForegroundColor Yellow
					} catch {
						Write-Warning "Failed to revoke $($perm.permissiontype) from $username on $dbname on $destination" 
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
						Write-Host "Added username $dbusername (login: $dblogin) to $dbname" -ForegroundColor Green 
					}
					catch { Write-Warning "Failed to add $dbusername ($dblogin) to $dbname on $destination."
					}
				}
			}
			
		 # DB owner
			If ($sourcedb.owner -eq $username) {
				If ($Pscmdlet.ShouldProcess($destination,"Changing $dbname dbowner to $username")) {
					try {
						$result = Update-SQLdbowner $sourceserver $destserver -dbname $dbname
						if ($result -eq $true) {
							Write-Host "Changed $($destdb.name) owner to $($sourcedb.owner)." -ForegroundColor Green
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
								Write-Host "Added $username to $($role.name) database role on $dbname."  -ForegroundColor Green
								
							} catch { Write-Warning "Failed to add $username to $($role.name) database role on $dbname." }
						}
					}
				}
			}
			
			# Connect, Alter Any Assembly, etc
			$perms = $sourcedb.EnumDatabasePermissions($username)
			foreach ($perm in $perms) {
				$permstate = $perm.permissionstate
				if ($permstate -eq "GrantWithGrant") { $grantwithgrant = $true; $permstate = "grant" } else { $grantwithgrant = $false }
				$permset = New-object Microsoft.SqlServer.Management.Smo.DatabasePermissionSet($perm.permissiontype)
				If ($Pscmdlet.ShouldProcess($destination,"Performing $permstate on $($perm.permissiontype) for $username on $dbname")) {
					try { 
						$destdb.PSObject.Methods[$permstate].Invoke($permset, $username, $grantwithgrant)
						Write-Host "Successfully performed $permstate $($perm.permissiontype) to $username on $dbname"  -ForegroundColor Green
					}
					catch { Write-Warning "Failed to perform $permstate on $($perm.permissiontype) for $username on $dbname." }		
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
	 Sync-Only -sourceserver $sourceserver -destserver $destserver -IncludeLogins $IncludeLogins -ExcludeLogins $ExcludeLogins

		#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[object]$sourceserver,
		[object]$destserver,
		[array]$IncludeLogins,
		[array]$ExcludeLogins
	)
	
	$skippeduser = @{}; $source = $sourceserver.name; $destination = $destserver.name
	$ExcludeLogins | Where-Object {!([string]::IsNullOrEmpty($_))} | ForEach-Object { $skippeduser.Add($_,"Explicitly Skipped") }
	$timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
	$csvfilename = "$($sourceserver.name.replace('\','$'))-to-$($destserver.name.replace('\','$'))-$timenow"
	
	foreach ($sourcelogin in $sourceserver.logins) {

		$username = $sourcelogin.name
		$currentuser = $sourceserver.ConnectionContext.truelogin
		if ($IncludeLogins -ne $null -and $IncludeLogins -notcontains $username) { continue }
		if ($skippeduser.ContainsKey($username) -or $username.StartsWith("##") -or $username -eq 'sa') { continue }
		
		if ($currentuser -eq $username) {
			Write-Warning "Sync does not modify the permissions of the current user. Skipping."
			continue
		}
		
		$servername = Get-NetBIOSName $sourceserver
		$userbase = ($username.Split("\")[0]).ToLower()
		if ($servername -eq $userbase -or $username.StartsWith("NT ")) { continue }
		if (($destlogin = $destserver.Logins.Item($username)) -eq $null) { continue }
		
		Update-SQLPermissions -sourceserver $sourceserver -sourcelogin $sourcelogin -destserver $destserver -destlogin $destlogin
	}
	
}
# Supporting Functions

Function Update-SQLdbowner  { 
        <#
            .SYNOPSIS
                Updates specified database dbowner.

            .EXAMPLE
                Update-SQLdbowner $sourceserver $destserver -dbname $dbname

            .OUTPUTS
                $true if success
                $false if failure
        #>
		[CmdletBinding()]
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$sourceserver,
			
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$destserver,
			
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [string]$dbname
        )

		$destdb = $destserver.databases[$dbname]
		$dbowner = $sourceserver.databases[$dbname].owner
		
		if ($dbowner -eq $null -or $destserver.logins[$dbowner] -eq $null) { $dbowner = 'sa' }
				
		try {
			if ($destdb.ReadOnly -eq $true) 
			{
				$changeroback = $true
				Update-SQLdbReadOnly $destserver $dbname $false
			}
			
			$destdb.SetOwner($dbowner)
						
			if ($changeroback) {
				Update-SQLdbReadOnly $destserver $dbname $true
				$changeroback = $null
			}
			
			return $true
		} catch { 
			Write-Warning "Failed to update $dbname owner to $dbowner."
			return $false 
		}
}

Function Update-SQLdbReadOnly  { 
        <#
            .SYNOPSIS
                Updates specified database to read-only or read-write. Necessary because SMO doesn't appear to support NO_WAIT.
				Also, necessary within this script because dbowner can't be updated if db is set to read-only.

            .EXAMPLE
               Update-SQLdbReadOnly $server $dbname $true

            .OUTPUTS
                $true if success
                $false if failure
        #>
		[CmdletBinding()]
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$server,

			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [string]$dbname,
			
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [bool]$readonly
        )
		
		if ($readonly) {
			$sql = "ALTER DATABASE [$dbname] SET READ_ONLY WITH NO_WAIT"
		} else {
			$sql = "ALTER DATABASE [$dbname] SET READ_WRITE WITH NO_WAIT"
		}

		try {
			Write-Warning "Setting $dbname to $readonly to faciliate dbowner change."
			$null = $server.ConnectionContext.ExecuteNonQuery($sql)
			Write-Host "Changed ReadOnly status to $readonly for $dbname on $($server.name)." -ForegroundColor Green
			return $true
		} catch { 
			Write-Host "Could not change readonly status for $dbname on $($server.name)" -ForegroundColor Red
			return $false }

}

Function Test-SQLSA      {
 <#
            .SYNOPSIS
              Ensures sysadmin account access on SQL Server. $server is an SMO server object.

            .EXAMPLE
              if (!(Test-SQLSA $server)) { throw "Not a sysadmin on $source. Quitting." }  

            .OUTPUTS
                $true if sycurrentuser
                $false if not
			
        #>
		[CmdletBinding()]
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$server	
		)
try {
		return ($server.ConnectionContext.FixedServerRoles -match "sysadmin")
	}
	catch { return $false }
}

Function Get-NetBIOSName {
 <#
	.SYNOPSIS
	Takes a best guess at the NetBIOS name of a server. 

	.EXAMPLE
	$sourcenetbios = Get-NetBIOSName $server
	
	.OUTPUTS
	  String with netbios name.
			
 #>
		[CmdletBinding()]
        param(
			[Parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
            [object]$server
		)

	$servernetbios = $server.ComputerNamePhysicalNetBIOS
	
	if ($servernetbios -eq $null) {
		$servernetbios = ($server.name).Split("\")[0]
		$servernetbios = $servernetbios.Split(",")[0]
	}
	
	return $($servernetbios.ToLower())
}

}


PROCESS { 
	<# ----------------------------------------------------------
		Sanity Checks
			- Is SMO available?
			- Are SQL Servers reachable?
			- Is the account running this script an currentuser?
			- Are SQL Versions >= 2005?
	---------------------------------------------------------- #>
	$elapsed = [System.Diagnostics.Stopwatch]::StartNew() 
	$started = Get-Date
	
	if ($source -eq $destination) { throw "Source and Destination SQL Servers are the same. Quitting." }

	if ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") -eq $null )
	{ throw "Quitting: SMO Required. You can download it from http://goo.gl/R4yA6u" }
	
	Write-Host "Attempting to connect to SQL Servers.."  -ForegroundColor Green
	$sourceserver = New-Object Microsoft.SqlServer.Management.Smo.Server $source
	$destserver = New-Object Microsoft.SqlServer.Management.Smo.Server $destination
	
	if ($UseSqlLoginSource -eq $true) {
		$sourcemsg = "Enter the SQL Login credentials for the SOURCE server, $($source.ToUpper())"; 
		$sourceserver.ConnectionContext.LoginSecure = $false
		$sourcelogin = Get-Credential -Message $sourcemsg
		$sourceserver.ConnectionContext.set_Login($sourcelogin.username)
		$sourceserver.ConnectionContext.set_SecurePassword($sourcelogin.Password)
	}
	
	if ($UseSqlLoginDestination -eq $true) {
		$destmsg = "Enter the SQL Login credentials for the DESTINATION server, $($destination.ToUpper())"; 
		$destserver.ConnectionContext.LoginSecure = $false
		$destlogin = Get-Credential -Message $destmsg
		$destserver.ConnectionContext.set_Login($destlogin.username)
		$destserver.ConnectionContext.Set_SecurePassword($destlogin.Password)	
	}
	
	try { $sourceserver.ConnectionContext.Connect() } catch { throw "Can't connect to $source. Quitting." }
	try { $destserver.ConnectionContext.Connect() } catch { throw "Can't connect to $destination. Quitting." }
	
	if ($sourceserver.versionMajor -lt 8 -or $destserver.versionMajor -lt 8) {throw "SQL Server 7 and below not supported. Quitting." }
		
	if (!(Test-SQLSA $sourceserver)) { throw "Not a sysadmin on $source. Quitting." }
	if (!(Test-SQLSA $destserver)) { throw "Not a sysadmin on $destination. Quitting." }
	
	<# ----------------------------------------------------------
		Preps
	---------------------------------------------------------- #>

	# Convert from RuntimeDefinedParameter  object to regular array
	if ($IncludeLogins.Value -ne $null) {$IncludeLogins = @($IncludeLogins.Value)}  else {$IncludeLogins = $null}
	if ($ExcludeLogins.Value -ne $null) {$ExcludeLogins = @($ExcludeLogins.Value)}  else {$ExcludeLogins = $null}
	
	<# ----------------------------------------------------------
		Run
	---------------------------------------------------------- #>
	
	if ($SyncOnly) {
		Write-Host "Syncing User Permissions" -ForegroundColor Green; 
		Sync-Only -sourceserver $sourceserver -destserver $destserver -IncludeLogins $IncludeLogins -ExcludeLogins $ExcludeLogins
		return
	}
	 
	Write-Host "Attempting Login Migration" -ForegroundColor Green; 
	Copy-SQLLogins -sourceserver $sourceserver -destserver $destserver -includelogins $IncludeLogins -excludelogins $ExcludeLogins -Force $force
}

END {
	$totaltime = ($elapsed.Elapsed.toString().Split(".")[0])
	$sourceserver.ConnectionContext.Disconnect()
	$destserver.ConnectionContext.Disconnect()
	Write-Host "Script completed" -ForegroundColor Green
	Write-Host "Migration started: $started"  -ForegroundColor Cyan
	Write-Host "Migration completed: $(Get-Date)"  -ForegroundColor Cyan
	Write-Host "Total Elapsed time: $totaltime"  -ForegroundColor Cyan
}