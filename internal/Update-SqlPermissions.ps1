Function Update-SqlPermissions
{
 <#
 
.SYNOPSIS
 Internal function. Updates permission sets, roles, database mappings on server and databases

 #>
	[CmdletBinding()]
	param (
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
	
	$destination = $destserver.DomainInstanceName
	$source = $sourceserver.DomainInstanceName
	$username = $sourcelogin.name
	
	# Server Roles: sysadmin, bulklogin, etc
	foreach ($role in $sourceserver.roles)
	{
		$rolename = $role.name
		$destrole = $destserver.roles[$rolename]
		if ($destrole -ne $null)
		{
			try { $destrolemembers = $destrole.EnumMemberNames() }
			catch { $destrolemembers = $destrole.EnumServerRoleMembers() }
		}
		try { $rolemembers = $role.EnumMemberNames() }
		catch { $rolemembers = $role.EnumServerRoleMembers() }
		if ($rolemembers -contains $username)
		{
			if ($destrole -ne $null)
			{
				If ($Pscmdlet.ShouldProcess($destination, "Adding $username to $rolename server role"))
				{
					try
					{
						$destrole.AddMember($username)
						Write-Output "Added $username to $rolename server role."
					}
					catch
					{
						Write-Warning "Failed to add $username to $rolename server role."
						Write-Exception $_
					}
				}
			}
		}
		
		# Remove for Syncs
		if ($rolemembers -notcontains $username -and $destrolemembers -contains $username -and $destrole -ne $null)
		{
			If ($Pscmdlet.ShouldProcess($destination, "Adding $username to $rolename server role"))
			{
				try
				{
					$destrole.DropMember($username)
					Write-Output "Removed $username from $destrolename server role on $($destserver.name)."
				}
				catch
				{
					Write-Warning "Failed to remove $username from $destrolename server role on $($destserver.name)."
					Write-Exception $_
				}
			}
		}
	}
	
	$ownedjobs = $sourceserver.JobServer.Jobs | Where-Object { $_.OwnerLoginName -eq $username }
	foreach ($ownedjob in $ownedjobs)
	{
		if ($destserver.JobServer.Jobs[$ownedjob.name] -ne $null)
		{
			If ($Pscmdlet.ShouldProcess($destination, "Changing job owner to $username for $($ownedjob.name)"))
			{
				try
				{
					Write-Output "Changing job owner to $username for $($ownedjob.name)"
					$destownedjob = $destserver.JobServer.Jobs | Where-Object { $_.name -eq $ownedjobs.name }
					$destownedjob.set_OwnerLoginName($username)
					$destownedjob.Alter()
				}
				catch
				{
					Write-Warning "Could not change job owner for $($ownedjob.name)"
					Write-Exception $_
				}
			}
		}
	}
	
	if ($sourceserver.versionMajor -ge 9 -and $destserver.versionMajor -ge 9)
	{
		# These operations are only supported by SQL Server 2005 and above.
		# Securables: Connect SQL, View any database, Administer Bulk Operations, etc.
		
		$perms = $sourceserver.EnumServerPermissions($username)
		foreach ($perm in $perms)
		{
			$permstate = $perm.permissionstate
			if ($permstate -eq "GrantWithGrant") { $grantwithgrant = $true; $permstate = "grant" }
			else { $grantwithgrant = $false }
			$permset = New-Object Microsoft.SqlServer.Management.Smo.ServerPermissionSet($perm.permissiontype)
			If ($Pscmdlet.ShouldProcess($destination, "Performing $permstate on $($perm.permissiontype) for $username"))
			{
				try
				{
					$destserver.PSObject.Methods[$permstate].Invoke($permset, $username, $grantwithgrant)
					Write-Output "Successfully performed $permstate $($perm.permissiontype) to $username"
				}
				catch
				{
					Write-Warning "Failed to $permstate $($perm.permissiontype) to $username"
					Write-Exception $_
				}
			}
			
			# for Syncs
			$destperms = $destserver.EnumServerPermissions($username)
			foreach ($perm in $destperms)
			{
				$permstate = $perm.permissionstate
				$sourceperm = $perms | Where-Object { $_.PermissionType -eq $perm.Permissiontype -and $_.PermissionState -eq $permstate }
				if ($sourceperm -eq $null)
				{
					If ($Pscmdlet.ShouldProcess($destination, "Performing Revoke on $($perm.permissiontype) for $username"))
					{
						try
						{
							$permset = New-Object Microsoft.SqlServer.Management.Smo.ServerPermissionSet($perm.permissiontype)
							if ($permstate -eq "GrantWithGrant") { $grantwithgrant = $true; $permstate = "grant" }
							else { $grantwithgrant = $false }
							$destserver.PSObject.Methods["Revoke"].Invoke($permset, $username, $false, $grantwithgrant)
							Write-Output "Successfully revoked $($perm.permissiontype) from $username"
						}
						catch
						{
							Write-Warning "Failed to revoke $($perm.permissiontype) from $username"
							Write-Exception $_
						}
					}
				}
			}
		}
		
		# Credential mapping. Credential removal not currently supported for Syncs.
		$logincredentials = $sourceserver.credentials | Where-Object { $_.Identity -eq $sourcelogin.name }
		foreach ($credential in $logincredentials)
		{
			if ($destserver.Credentials[$credential.name] -eq $null)
			{
				If ($Pscmdlet.ShouldProcess($destination, "Adding $($credential.name) to $username"))
				{
					try
					{
						$newcred = New-Object Microsoft.SqlServer.Management.Smo.Credential($destserver, $credential.name)
						$newcred.identity = $sourcelogin.name
						$newcred.Create()
						Write-Output "Successfully created credential for $username"
					}
					catch
					{
						Write-Warning "Failed to create credential for $username"
						Write-Exception $_
					}
				}
			}
		}
	}
	
	if ($destserver.versionMajor -lt 9) { Write-Warning "Database mappings skipped when destination is SQL Server 2000"; continue }
	
	# For Sync, if info doesn't exist in EnumDatabaseMappings, then no big deal.
	foreach ($db in $destlogin.EnumDatabaseMappings())
	{
		$dbname = $db.dbname
		$destdb = $destserver.databases[$dbname]
		$sourcedb = $sourceserver.databases[$dbname]
		$dbusername = $db.username; $dblogin = $db.loginName
		
		if ($sourcedb -ne $null)
		{
			if ($sourcedb.users[$dbusername] -eq $null -and $destdb.users[$dbusername] -ne $null)
			{
				If ($Pscmdlet.ShouldProcess($destination, "Dropping $dbusername from $dbname on destination."))
				{
					try
					{
						$destdb.users[$dbusername].Drop()
						Write-Output "Dropped user $dbusername (login: $dblogin) from $dbname on destination. User may own a schema."
					}
					catch
					{
						Write-Warning "Failed to drop $dbusername ($dblogin) from $dbname on destination."
						Write-Exception $_
					}
				}
			}
			
			# Remove user from role. Role removal not currently supported for Syncs.
			# TODO: reassign if dbo, application roles
			foreach ($destrole in $destdb.roles)
			{
				$destrolename = $destrole.name
				$sourcerole = $sourcedb.roles[$destrolename]
				if ($sourcerole -ne $null)
				{
					if ($sourcerole.EnumMembers() -notcontains $dbusername -and $destrole.EnumMembers() -contains $dbusername)
					{
						if ($dbusername -ne "dbo")
						{
							If ($Pscmdlet.ShouldProcess($destination, "Dropping $username from $destrolename database role on $dbname"))
							{
								try
								{
									$destrole.DropMember($dbusername)
									$destdb.Alter()
									Write-Output "Dropped username $dbusername (login: $dblogin) from $destrolename on $destination"
								}
								catch
								{
									Write-Warning "Failed to remove $dbusername from $destrolename database role on $dbname."
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
			foreach ($perm in $destperms)
			{
				$permstate = $perm.permissionstate
				$sourceperm = $perms | Where-Object { $_.PermissionType -eq $perm.Permissiontype -and $_.PermissionState -eq $permstate }
				if ($sourceperm -eq $null)
				{
					If ($Pscmdlet.ShouldProcess($destination, "Performing Revoke on $($perm.permissiontype) for $username on $dbname on $destination"))
					{
						try
						{
							$permset = New-Object Microsoft.SqlServer.Management.Smo.DatabasePermissionSet($perm.permissiontype)
							if ($permstate -eq "GrantWithGrant") { $grantwithgrant = $true; $permstate = "grant" }
							else { $grantwithgrant = $false }
							$destdb.PSObject.Methods["Revoke"].Invoke($permset, $username, $false, $grantwithgrant)
							Write-Output "Successfully revoked $($perm.permissiontype) from $username on $dbname on $destination"
						}
						catch
						{
							Write-Warning "Failed to revoke $($perm.permissiontype) from $username on $dbname on $destination"
							Write-Exception $_
						}
					}
				}
			}
		}
	}
	
	# Adding database mappings and securables
	foreach ($db in $sourcelogin.EnumDatabaseMappings())
	{
		$dbname = $db.dbname
		$destdb = $destserver.databases[$dbname]
		$sourcedb = $sourceserver.databases[$dbname]
		$dbusername = $db.username; $dblogin = $db.loginName
		
		if ($destdb -ne $null)
		{
			if (!$destdb.IsAccessible)
			{
				Write-Output "Database [$($destdb.Name)] is not accessible. Skipping"
				Continue
			}
			if ($destdb.users[$dbusername] -eq $null)
			{
				If ($Pscmdlet.ShouldProcess($destination, "Adding $dbusername to $dbname"))
				{
					$sql = $sourceserver.databases[$dbname].users[$dbusername].script() | Out-String
					$sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
					try
					{
						$destdb.ExecuteNonQuery($sql)
						Write-Output "Added user $dbusername (login: $dblogin) to $dbname"
					}
					catch
					{
						Write-Warning "Failed to add $dbusername ($dblogin) to $dbname on $destination."
						Write-Exception $_
					}
				}
			}
			
			# Db owner
			If ($sourcedb.owner -eq $username)
			{
				If ($Pscmdlet.ShouldProcess($destination, "Changing $dbname dbowner to $username"))
				{
					try
					{
						$result = Update-SqlDbOwner $sourceserver $destserver -dbname $dbname
						if ($result -eq $true)
						{
							Write-Output "Changed $($destdb.name) owner to $($sourcedb.owner)."
						}
						else { Write-Warning "Failed to update $($destdb.name) owner to $($sourcedb.owner)." }
					}
					catch { Write-Warning "Failed to update $($destdb.name) owner to $($sourcedb.owner)." }
				}
			}
			
			# Database Roles: db_owner, db_datareader, etc
			foreach ($role in $sourcedb.roles)
			{
				if ($role.EnumMembers() -contains $username)
				{
					$rolename = $role.name
					$destdbrole = $destdb.roles[$rolename]
					
					if ($destdbrole -ne $null -and $dbusername -ne "dbo" -and $destdbrole.EnumMembers() -notcontains $username)
					{
						If ($Pscmdlet.ShouldProcess($destination, "Adding $username to $rolename database role on $dbname"))
						{
							try
							{
								$destdbrole.AddMember($username)
								$destdb.Alter()
								Write-Output "Added $username to $rolename database role on $dbname."
								
							}
							catch
							{
								Write-Warning "Failed to add $username to $rolename database role on $dbname."
								Write-Exception $_
							}
						}
					}
				}
			}
			
			# Connect, Alter Any Assembly, etc
			$perms = $sourcedb.EnumDatabasePermissions($username)
			foreach ($perm in $perms)
			{
				$permstate = $perm.permissionstate
				if ($permstate -eq "GrantWithGrant") { $grantwithgrant = $true; $permstate = "grant" }
				else { $grantwithgrant = $false }
				$permset = New-Object Microsoft.SqlServer.Management.Smo.DatabasePermissionSet($perm.permissiontype)
				If ($Pscmdlet.ShouldProcess($destination, "Performing $permstate on $($perm.permissiontype) for $username on $dbname"))
				{
					try
					{
						$destdb.PSObject.Methods[$permstate].Invoke($permset, $username, $grantwithgrant)
						Write-Output "Successfully performed $permstate $($perm.permissiontype) to $username on $dbname"
					}
					catch
					{
						Write-Warning "Failed to perform $permstate on $($perm.permissiontype) for $username on $dbname."
						Write-Exception $_
					}
				}
			}
		}
	}
}
