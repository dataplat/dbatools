function Update-SqlPermission {
    <#
        .SYNOPSIS
            Internal function. Updates permission sets, roles, database mappings on server and databases
        .PARAMETER SourceServer
            Source Server
        .PARAMETER SourceLogin
            Source login
        .PARAMETER DestServer
            Destination Server
        .PARAMETER DestLogin
            Destination Login
        .PARAMETER ObjectLevel
            Use Export-DbaUser to update object-level permissions as well
        .PARAMETER EnableException
            Use this switch to disable any kind of verbose messages
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$SourceServer,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$SourceLogin,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$DestServer,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]$DestLogin,
        [switch]$ObjectLevel,
        [switch]$ExcludeDatabaseMapping,
        [switch]$EnableException
    )

    $destination = $DestServer.DomainInstanceName
    $source = $SourceServer.DomainInstanceName
    $loginName = $SourceLogin.Name
    $newLoginName = $DestLogin.Name

    $saname = Get-SaLoginName -SqlInstance $DestServer

    # Sync login enabled/disabled state
    if ($SourceLogin.IsDisabled -ne $DestLogin.IsDisabled) {
        if ($Pscmdlet.ShouldProcess($destination, "Setting login $newLoginName IsDisabled to $($SourceLogin.IsDisabled).")) {
            try {
                if ($SourceLogin.IsDisabled) {
                    $DestLogin.Disable()
                } else {
                    $DestLogin.Enable()
                }
                $DestLogin.Alter()
                Write-Message -Level Verbose -Message "Setting login $newLoginName IsDisabled to $($SourceLogin.IsDisabled) on $destination successfully performed."
            } catch {
                Stop-Function -Message "Failed to set login $newLoginName IsDisabled to $($SourceLogin.IsDisabled) on $destination." -Target $DestLogin -ErrorRecord $_
            }
        }
    }

    # Server Roles: sysadmin, bulklogin, etc
    # The memberships come from the logins themselves, so the server answers them by the login and not by a comparison of
    # names in PowerShell, which ignored case: on a case sensitive instance a member whose name differed only in case
    # counted as the login. Every role of the source login is resolved on the destination by its name, with the collation
    # of the destination, and the memberships of the destination login are then compared by the role they resolve to.
    # Comparing role names in PowerShell instead, or in the collection of the source, matched a destination role
    # [adminrole] to a source role [AdminRole] and kept the login in both.
    # The role collection of the destination is loaded fresh: the server object can come from the caller with roles
    # loaded before a role was created, and a role missing there was never visited, so its membership stayed.
    $DestServer.Roles.Refresh()
    $sourceMemberOf = @($SourceLogin.ListMembers())
    $destMemberOf = @($DestLogin.ListMembers())
    $destMemberOfIds = @()
    foreach ($destRoleName in $destMemberOf) {
        $destRole = $DestServer.Roles[$destRoleName]
        if ($null -ne $destRole) {
            $destMemberOfIds += $destRole.ID
        }
    }

    $keepRoleIds = @()
    foreach ($roleName in $sourceMemberOf) {
        $destRole = $DestServer.Roles[$roleName]
        if ($null -eq $destRole) {
            continue
        }
        $keepRoleIds += $destRole.ID
        if ($destMemberOfIds -contains $destRole.ID) {
            continue
        }
        if ($Pscmdlet.ShouldProcess($destination, "Adding $newLoginName to $($destRole.Name) server role.")) {
            if ($loginName -ne $saname) {
                try {
                    $destRole.AddMember($newLoginName)
                    Write-Message -Level Verbose -Message "Adding $newLoginName to $($destRole.Name) server role on $destination successfully performed."
                } catch {
                    Stop-Function -Message "Failed to add $newLoginName to $($destRole.Name) server role on $destination." -Target $destRole -ErrorRecord $_
                }
            }
        }
    }

    # Remove for Syncs
    # Every role of the destination login that no role of the source login resolves to, also a role that exists on the
    # destination only, because a login updated in place kept such a membership, and with it permissions like CONTROL
    # SERVER of a user-defined role, while a login that -Force drops and recreates loses it.
    # The member to drop is the login on the destination: with a rename, the name of the source login can belong to a
    # different login there.
    foreach ($destRoleName in $destMemberOf) {
        $destRole = $DestServer.Roles[$destRoleName]
        if ($null -eq $destRole -or $keepRoleIds -contains $destRole.ID) {
            continue
        }
        if ($Pscmdlet.ShouldProcess($destination, "Removing $newLoginName from $($destRole.Name) server role.")) {
            try {
                $destRole.DropMember($newLoginName)
                Write-Message -Level Verbose -Message "Removing $newLoginName from $($destRole.Name) server role on $destination successfully performed."
            } catch {
                Stop-Function -Message "Failed to remove $newLoginName from $($destRole.Name) server role on $destination." -Target $destRole -ErrorRecord $_
            }
        }
    }

    $ownedJobs = $SourceServer.JobServer.Jobs | Where-Object OwnerLoginName -eq $loginName
    foreach ($ownedJob in $ownedJobs) {
        if ($null -ne $DestServer.JobServer.Jobs[$ownedJob.Name]) {
            if ($Pscmdlet.ShouldProcess($destination, "Changing of job owner to $newLoginName for $($ownedJob.Name).")) {
                try {
                    $destOwnedJob = $DestServer.JobServer.Jobs | Where-Object { $_.Name -eq $ownedJob.Name }
                    $destOwnedJob.Set_OwnerLoginName($newLoginName)
                    $destOwnedJob.Alter()
                    Write-Message -Level Verbose -Message "Changing job owner to $newLoginName for $($ownedJob.Name) on $destination successfully performed."
                } catch {
                    Stop-Function -Message "Failed to change job owner for $($ownedJob.Name) to $newLoginName on $destination." -Target $ownedJob -ErrorRecord $_
                }
            }
        }
    }

    if ($SourceServer.VersionMajor -ge 9 -and $DestServer.VersionMajor -ge 9) {
        <#
            These operations are only supported by SQL Server 2005 and above.
            Securables: Connect SQL, View any database, Administer Bulk Operations, etc.
        #>

        $perms = $SourceServer.EnumServerPermissions($loginName)
        foreach ($perm in $perms) {
            $permState = $perm.PermissionState
            if ($permState -eq "GrantWithGrant") {
                $grantWithGrant = $true;
                $permState = "grant"
            } elseif ($permState -eq "Deny") {
                # Deny takes cascade where Grant takes the grant option. SQL Server refuses a DENY without CASCADE when the
                # login has the permission WITH GRANT OPTION, as a login that already exists on the destination can have it.
                $grantWithGrant = $true
            } else {
                $grantWithGrant = $false
            }

            $permSet = New-Object Microsoft.SqlServer.Management.Smo.ServerPermissionSet($perm.PermissionType)
            if ($Pscmdlet.ShouldProcess($destination, "$permState on $($perm.PermissionType) for $newLoginName.")) {
                try {
                    $DestServer.PSObject.Methods[$permState].Invoke($permSet, $newLoginName, $grantWithGrant)
                    Write-Message -Level Verbose -Message "$permState $($perm.PermissionType) to $newLoginName on $destination successfully performed."
                } catch {
                    Stop-Function -Message "Failed to $permState $($perm.PermissionType) to $newLoginName on $destination." -Target $perm -ErrorRecord $_
                }
            }
        }

        # for Syncs
        # After the loop over the permissions of the source, not inside it: for a source login without any direct server
        # permission, one that gets CONNECT SQL through a server role for example, that loop never ran, so the login on
        # the destination kept every direct permission it had, CONTROL SERVER included.
        $destPerms = $DestServer.EnumServerPermissions($newLoginName)
        foreach ($perm in $destPerms) {
            $permState = $perm.PermissionState
            $sourcePerm = $perms | Where-Object { $_.PermissionType -eq $perm.PermissionType -and $_.PermissionState -eq $permState }

            if ($null -eq $sourcePerm) {
                # The source login has the permission without the grant option, so only the grant option is revoked. The
                # GRANT of the loop above leaves an existing grant option in place, and a REVOKE of the permission itself
                # took it from the login completely, CONNECT SQL included.
                $revokeGrantOnly = $permState -eq "GrantWithGrant" -and [bool]($perms | Where-Object { $_.PermissionType -eq $perm.PermissionType -and $_.PermissionState -eq "Grant" })
                if ($revokeGrantOnly) {
                    $revokeAction = "Revoking the grant option of $($perm.PermissionType)"
                } else {
                    $revokeAction = "Revoking $($perm.PermissionType)"
                }
                if ($Pscmdlet.ShouldProcess($destination, "$revokeAction for $newLoginName.")) {
                    try {
                        $permSet = New-Object Microsoft.SqlServer.Management.Smo.ServerPermissionSet($perm.PermissionType)

                        if ($permState -eq "GrantWithGrant") {
                            $grantWithGrant = $true;
                            $permState = "grant"
                        } else {
                            $grantWithGrant = $false
                        }

                        $DestServer.PSObject.Methods["Revoke"].Invoke($permSet, $newLoginName, $revokeGrantOnly, $grantWithGrant)
                        Write-Message -Level Verbose -Message "$revokeAction for $newLoginName on $destination successfully performed."
                    } catch {
                        Stop-Function -Message "Failed to revoke $($perm.PermissionType) from $newLoginName on $destination." -Target $perm -ErrorRecord $_
                    }
                }
            }
        }

        # Permissions on logins and server roles, like IMPERSONATE ON LOGIN::sa or CONTROL ON SERVER ROLE. The
        # enumeration above returns the permissions on the server only, so a login that already exists on the destination
        # kept them, while a login that -Force drops and recreates loses them. A created login gets none of them from the
        # source, so here only the ones the source login does not have are revoked, matched by securable and permission.
        # Permissions on endpoints and availability groups stay: they belong to the replica. A secondary grants CONNECT on
        # its endpoint to the service account of the primary, and that login has no such permission on the primary.
        # The securable of a source permission is resolved on the destination by its name, with the collation of the
        # destination, and compared by its principal_id there. Comparing names in PowerShell ignored case, so on a case
        # sensitive destination IMPERSONATE on [scopedlogin] was kept because the source login has it on [ScopedLogin],
        # and it took accents into account, so on an accent insensitive destination the permission on the login that the
        # source writes with accents and the destination without was revoked. Numbers are never compared across instances.
        $securableClasses = "Login", "ServerRole"
        $sourceObjectPerms = $SourceServer.EnumObjectPermissions($loginName) | Where-Object { "$($_.ObjectClass)" -in $securableClasses }
        $destObjectPerms = $DestServer.EnumObjectPermissions($newLoginName) | Where-Object { "$($_.ObjectClass)" -in $securableClasses }
        $sourceStatesBySecurable = @{ }
        foreach ($perm in $sourceObjectPerms) {
            if ("$($perm.ObjectClass)" -eq "Login") {
                $securables = $DestServer.Logins
            } else {
                $securables = $DestServer.Roles
            }
            # The server object can come from the caller with a collection loaded before the securable was created.
            if ($null -eq $securables[$perm.ObjectName]) {
                $securables.Refresh()
            }
            $destSecurable = $securables[$perm.ObjectName]
            if ($null -eq $destSecurable) {
                continue
            }
            $securableKey = "$($perm.ObjectClass) $($destSecurable.ID) $($perm.PermissionType)"
            if ($sourceStatesBySecurable.ContainsKey($securableKey)) {
                $sourceStatesBySecurable[$securableKey] += "$($perm.PermissionState)"
            } else {
                $sourceStatesBySecurable[$securableKey] = @("$($perm.PermissionState)")
            }
        }
        foreach ($perm in $destObjectPerms) {
            $objectClass = "$($perm.ObjectClass)"
            $objectPermState = "$($perm.PermissionState)"
            $sourceStates = @()
            $securableKey = "$objectClass $($perm.ObjectID) $($perm.PermissionType)"
            if ($sourceStatesBySecurable.ContainsKey($securableKey)) {
                $sourceStates = $sourceStatesBySecurable[$securableKey]
            }
            # A grant stays when the source login has the permission with or without the grant option.
            if ($sourceStates -contains $objectPermState -or ($objectPermState -eq "Grant" -and $sourceStates -contains "GrantWithGrant")) {
                continue
            }
            # As for the server permissions above: only the grant option goes when the source login has the permission without it.
            $revokeGrantOnly = $objectPermState -eq "GrantWithGrant" -and $sourceStates -contains "Grant"
            if ($revokeGrantOnly) {
                $revokeAction = "Revoking the grant option of $($perm.PermissionType) on $objectClass $($perm.ObjectName)"
            } else {
                $revokeAction = "Revoking $($perm.PermissionType) on $objectClass $($perm.ObjectName)"
            }
            if ($Pscmdlet.ShouldProcess($destination, "$revokeAction for $newLoginName.")) {
                try {
                    if ($objectClass -eq "Login") {
                        $securables = $DestServer.Logins
                    } else {
                        $securables = $DestServer.Roles
                    }
                    # The server object can come from the caller with a collection loaded before the securable was created.
                    if ($null -eq $securables[$perm.ObjectName]) {
                        $securables.Refresh()
                    }
                    $securables[$perm.ObjectName].Revoke($perm.PermissionType, $newLoginName, $revokeGrantOnly, $objectPermState -eq "GrantWithGrant")
                    Write-Message -Level Verbose -Message "$revokeAction for $newLoginName on $destination successfully performed."
                } catch {
                    Stop-Function -Message "Failed to revoke $($perm.PermissionType) on $objectClass $($perm.ObjectName) from $newLoginName on $destination." -Target $perm -ErrorRecord $_
                }
            }
        }

        # Credential mapping. Credential removal not currently supported for Syncs.
        $loginCredentials = $SourceServer.Credentials | Where-Object { $_.Identity -eq $SourceLogin.Name }
        foreach ($credential in $loginCredentials) {
            if ($null -eq $DestServer.Credentials[$credential.Name]) {
                if ($Pscmdlet.ShouldProcess($destination, "Creating credential $($credential.Name) for $newLoginName.")) {
                    try {
                        $newCred = New-Object Microsoft.SqlServer.Management.Smo.Credential($DestServer, $credential.Name)
                        $newCred.Identity = $newLoginName
                        $newCred.Create()
                        Write-Message -Level Verbose -Message "Creating credential $($credential.Name) for $newLoginName on $destination successfully performed."
                    } catch {
                        Stop-Function -Message "Failed to create credential $($credential.Name) for $newLoginName on $destination." -Target $credential -ErrorRecord $_
                    }
                }
            }
        }
    }

    if ($ExcludeDatabaseMapping) {
        return
    }

    if ($DestServer.VersionMajor -lt 9) {
        Write-Message -Level Warning -Message "SQL Server 2005 or greater required for database mappings.";
        # Return, not continue: this function has no loop here, so a continue went on with the next iteration of the
        # loop of the caller and skipped the rest of it, the result row of Sync-DbaLoginPermission for example.
        return
    }

    # For Sync, if info doesn't exist in EnumDatabaseMappings, then no big deal.
    foreach ($db in $DestLogin.EnumDatabaseMappings()) {
        $dbName = $db.DbName
        $destDb = $DestServer.Databases[$dbName]
        $sourceDb = $SourceServer.Databases[$dbName]
        $newDbUsername = $db.Username;
        # Adjust renamed database usernames for old server
        if ($newDbUsername -eq $newLoginName) { $dbUsername = $loginName } else { $dbUsername = $newDbUsername }
        $dbLogin = $db.LoginName

        if ($null -ne $sourceDb) {
            if (-not $sourceDb.IsAccessible) {
                Write-Message -Level Verbose -Message "Database [$($sourceDb.Name)] is not accessible on $source. Skipping."
                continue
            }
            if (-not $destDb.IsUpdateable) {
                Write-Message -Level Verbose -Message "Database [$($sourceDb.Name)] is not updateable on destination. Skipping."
                continue
            }
            if ($null -eq $sourceDb.Users[$dbUsername] -and $null -eq $destDb.Users[$newDbUsername]) {
                if ($Pscmdlet.ShouldProcess($destination, "Dropping user $dbUsername from $dbName.")) {
                    try {
                        $destDb.Users[$newDbUsername].Drop()
                        Write-Message -Level Verbose -Message "Dropping user $newDbUsername (login: $dbLogin) from $dbName on destination successfully performed."
                        Write-Message -Level Verbose -Message "Any schema in $dbaName owned by $newDbUsername may still exist."
                    } catch {
                        Stop-Function -Message "Failed to drop $newDbUsername (login: $dbLogin) from $dbName on destination." -Target $db -ErrorRecord $_
                    }
                }
            }

            # Remove user from role. Role removal not currently supported for Syncs.
            # TODO: reassign if dbo, application roles
            foreach ($destRole in $destDb.Roles) {
                $destRoleName = $destRole.Name
                $sourceRole = $sourceDb.Roles[$destRoleName]
                if ($null -eq $sourceRole) {
                    if ($destRole.EnumMembers() -contains $newDbUsername) {
                        if ($newDbUsername -ne "dbo") {
                            if ($Pscmdlet.ShouldProcess($destination, "Dropping user $newDbUsername from $destRoleName database role in $dbName.")) {
                                try {
                                    $destRole.DropMember($newDbUsername)
                                    $destDb.Alter()
                                    Write-Message -Level Verbose -Message "Dropping user $newDbUsername (login: $dbLogin) from $destRoleName database role in $dbName on $destination successfully performed."
                                } catch {
                                    Stop-Function -Message "Failed to remove $newDbUsername (login: $dbLogin) from $destRoleName database role in $dbName on $destination." -Target $destRole -ErrorRecord $_
                                }
                            }
                        }
                    }
                }
            }

            # Remove Connect, Alter Any Assembly, etc
            $destPerms = $destDb.EnumDatabasePermissions($newLoginName)
            $perms = $sourceDb.EnumDatabasePermissions($loginName)
            # for Syncs
            foreach ($perm in $destPerms) {
                $permState = $perm.PermissionState
                $sourcePerm = $perms | Where-Object { $_.PermissionType -eq $perm.PermissionType -and $_.PermissionState -eq $permState }
                if ($null -eq $sourcePerm) {
                    if ($Pscmdlet.ShouldProcess($destination, "Revoking $($perm.PermissionType) from $newLoginName in $dbName.")) {
                        try {
                            $permSet = New-Object Microsoft.SqlServer.Management.Smo.DatabasePermissionSet($perm.PermissionType)

                            if ($permState -eq "GrantWithGrant") {
                                $grantWithGrant = $true;
                                $permState = "grant"
                            } else {
                                $grantWithGrant = $false
                            }

                            $destDb.PSObject.Methods["Revoke"].Invoke($permSet, $newLoginName, $false, $grantWithGrant)
                            Write-Message -Level Verbose -Message "Revoking $($perm.PermissionType) from $newLoginName in $dbName on $destination successfully performed."
                        } catch {
                            Stop-Function -Message "Failed to revoke $($perm.PermissionType) from $newLoginName in $dbName on $destination." -Target $perm -ErrorRecord $_
                        }
                    }
                }
            }
        }
    }

    # Adding database mappings and securables
    foreach ($db in $SourceLogin.EnumDatabaseMappings()) {
        $dbName = $db.DbName
        $destDb = $DestServer.Databases[$dbName]
        $sourceDb = $SourceServer.Databases[$dbName]
        $dbUsername = $db.Username;
        # Adjust renamed database usernames for new server
        if ($newLoginName -eq $loginName) { $newDbUsername = $dbUsername } else { $newDbUsername = $newLoginName }

        if ($null -ne $destDb) {
            if (-not $destDb.IsUpdateable) {
                Write-Message -Level Verbose -Message "Database [$dbName] is not updateable on destination. Skipping."
                continue
            }
            if ($null -eq $destDb.Users[$newDbUsername]) {
                if ($Pscmdlet.ShouldProcess($destination, "Adding $newDbUsername to $dbName.")) {
                    $sql = $SourceServer.Databases[$dbName].Users[$dbUsername].Script() | Out-String
                    try {
                        # Through the Invoke script method and not through ExecuteNonQuery of SMO: both run
                        # the statement in that database by issuing a USE on the connection context of the
                        # parent server, but only ours puts the previous database back. See #10555.
                        $destDb.Invoke($sql.Replace("[$dbUsername]", "[$newDbUsername]").Replace("[$loginName]", "[$newLoginName]"))
                        Write-Message -Level Verbose -Message "Adding user $newDbUsername (login: $newLoginName) to $dbName successfully performed."
                    } catch {
                        Stop-Function -Message "Failed to add $newDbUsername (login: $newLoginName) to $dbName on $destination." -Target $db -ErrorRecord $_
                    }
                }
            }

            # Db owner
            if ($sourceDb.Owner -eq $loginName) {
                if ($Pscmdlet.ShouldProcess($destination, "Changing $dbName dbowner to $newLoginName.")) {
                    try {
                        if ($dbName -notin 'master', 'msdb', 'tempdb', 'model') {
                            $result = Set-DbaDbOwner -SqlInstance $DestServer -Database $dbName -TargetLogin $newLoginName -EnableException:$EnableException
                            if ($result.Owner -eq $newLoginName) {
                                Write-Message -Level Verbose -Message "Changed $($destDb.Name) owner to $newLoginName."
                            } else {
                                Write-Message -Level Warning -Message "Failed to update $($destDb.Name) owner to $newLoginName."
                            }
                        }
                    } catch {
                        Stop-Function -Message "Failed to update $($destDb.Name) owner to $newLoginName." -ErrorRecord $_
                    }
                }
            }

            if ($ObjectLevel) {
                if ($dbUsername -ne "dbo") {
                    $scriptOptions = New-DbaScriptingOption
                    $scriptVersion = $destDb.CompatibilityLevel
                    $scriptOptions.TargetServerVersion = [Microsoft.SqlServer.Management.Smo.SqlServerVersion]::$scriptVersion
                    $scriptOptions.AllowSystemObjects = $false
                    $scriptOptions.IncludeDatabaseRoleMemberships = $true
                    $scriptOptions.ContinueScriptingOnError = $false
                    $scriptOptions.IncludeDatabaseContext = $false
                    $scriptOptions.IncludeIfNotExists = $true
                    $userScript = Export-DbaUser -SqlInstance $SourceServer -Database $dbName -User $dbUsername -Passthru -Template -ScriptingOptionsObject $scriptOptions -EnableException:$EnableException
                    $userScript = $userScript.Replace('{templateUser}', $newDbUsername)
                    # See the comment above: the Invoke script method puts the database back afterwards.
                    $destDb.Invoke($userScript)
                }
            } else {
                # Database Roles: db_owner, db_datareader, etc
                foreach ($role in $sourceDb.Roles) {
                    if ($role.EnumMembers() -contains $loginName) {
                        $roleName = $role.Name
                        $destDbRole = $destDb.Roles[$roleName]

                        if ($null -ne $destDbRole -and $dbUsername -ne "dbo" -and $destDbRole.EnumMembers() -notcontains $newDbUsername) {
                            if ($Pscmdlet.ShouldProcess($destination, "Adding $newDbUsername to $roleName database role in $dbName.")) {
                                try {
                                    $destDbRole.AddMember($newDbUsername)
                                    $destDb.Alter()
                                    Write-Message -Level Verbose -Message "Adding $newDbUsername to $roleName database role in $dbName on $destination successfully performed."
                                } catch {
                                    Stop-Function -Message "Failed to add $newDbUsername to $roleName database role in $dbName on $destination." -Target $role -ErrorRecord $_
                                }
                            }
                        }
                    }
                }
                # Connect, Alter Any Assembly, etc
                $perms = $sourceDb.EnumDatabasePermissions($loginName)
                foreach ($perm in $perms) {
                    $permState = $perm.PermissionState
                    if ($permState -eq "GrantWithGrant") {
                        $grantWithGrant = $true;
                        $permState = "grant"
                    } else {
                        $grantWithGrant = $false
                    }
                    $permSet = New-Object Microsoft.SqlServer.Management.Smo.DatabasePermissionSet($perm.PermissionType)

                    if ($Pscmdlet.ShouldProcess($destination, "$permState on $($perm.PermissionType) for $newDbUsername on $dbName")) {
                        try {
                            $destDb.PSObject.Methods[$permState].Invoke($permSet, $newDbUsername, $grantWithGrant)
                            Write-Message -Level Verbose -Message "$permState on $($perm.PermissionType) to $newDbUsername on $dbName on $destination successfully performed."
                        } catch {
                            Stop-Function -Message "Failed to perform $permState on $($perm.PermissionType) to $newDbUsername on $dbName on $destination." -Target $perm -ErrorRecord $_
                        }
                    }
                }
            }
        }
    }
}