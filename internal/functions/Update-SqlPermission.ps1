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
        [switch]$EnableException
    )

    $destination = $DestServer.DomainInstanceName
    $source = $SourceServer.DomainInstanceName
    $loginName = $SourceLogin.Name
    $newLoginName = $DestLogin.Name

    $saname = Get-SaLoginName -SqlInstance $DestServer

    # gotta close because enum repeatedly causes problems with the datareader
    $null = $SourceServer.ConnectionContext.SqlConnectionObject.Close()
    $null = $DestServer.ConnectionContext.SqlConnectionObject.Close()

    # Server Roles: sysadmin, bulklogin, etc
    foreach ($role in $SourceServer.Roles) {
        $roleName = $role.Name
        $destRole = $DestServer.Roles[$roleName]

        if ($null -ne $destRole) {
            try {
                $destRoleMembers = $destRole.EnumMemberNames()
            } catch {
                $destRoleMembers = $destRole.EnumServerRoleMembers()
            }
        }

        try {
            $roleMembers = $role.EnumMemberNames()
        } catch {
            $roleMembers = $role.EnumServerRoleMembers()
        }

        if ($roleMembers -contains $loginName) {
            if ($null -ne $destRole) {
                if ($Pscmdlet.ShouldProcess($destination, "Adding $newLoginName to $roleName server role.")) {
                    if ($loginName -ne $saname) {
                        try {
                            $destRole.AddMember($newLoginName)
                            Write-Message -Level Verbose -Message "Adding $newLoginName to $roleName server role on $destination successfully performed."
                        } catch {
                            Stop-Function -Message "Failed to add $newLoginName to $roleName server role on $destination." -Target $role -ErrorRecord $_
                        }
                    }
                }
            }
        }

        # Remove for Syncs
        if ($roleMembers -notcontains $loginName -and $destRoleMembers -contains $newLoginName -and $null -ne $destRole) {
            if ($Pscmdlet.ShouldProcess($destination, "Adding $loginName to $roleName server role.")) {
                try {
                    $destRole.DropMember($loginName)
                    Write-Message -Level Verbose -Message "Removing $newLoginName from $destRoleName server role on $destination successfully performed."
                } catch {
                    Stop-Function -Message "Failed to remove $newLoginName from $destRoleName server role on $destination." -Target $role -ErrorRecord $_
                }
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

        $null = $sourceServer.ConnectionContext.SqlConnectionObject.Close()
        $null = $destServer.ConnectionContext.SqlConnectionObject.Close()

        $perms = $SourceServer.EnumServerPermissions($loginName)
        foreach ($perm in $perms) {
            $permState = $perm.PermissionState
            if ($permState -eq "GrantWithGrant") {
                $grantWithGrant = $true;
                $permState = "grant"
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

            # for Syncs
            $destPerms = $DestServer.EnumServerPermissions($newLoginName)
            foreach ($perm in $destPerms) {
                $permState = $perm.PermissionState
                $sourcePerm = $perms | Where-Object { $_.PermissionType -eq $perm.PermissionType -and $_.PermissionState -eq $permState }

                if ($null -eq $sourcePerm) {
                    if ($Pscmdlet.ShouldProcess($destination, "Revoking $($perm.PermissionType) for $newLoginName.")) {
                        try {
                            $permSet = New-Object Microsoft.SqlServer.Management.Smo.ServerPermissionSet($perm.PermissionType)

                            if ($permState -eq "GrantWithGrant") {
                                $grantWithGrant = $true;
                                $permState = "grant"
                            } else {
                                $grantWithGrant = $false
                            }

                            $DestServer.PSObject.Methods["Revoke"].Invoke($permSet, $newLoginName, $false, $grantWithGrant)
                            Write-Message -Level Verbose -Message "Revoking $($perm.PermissionType) for $newLoginName on $destination successfully performed."
                        } catch {
                            Stop-Function -Message "Failed to revoke $($perm.PermissionType) from $newLoginName on $destination." -Target $perm -ErrorRecord $_
                        }
                    }
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

    if ($DestServer.VersionMajor -lt 9) {
        Write-Message -Level Warning -Message "SQL Server 2005 or greater required for database mappings.";
        continue
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
            if (-not $destDb.IsAccessible) {
                Write-Message -Level Verbose -Message "Database [$($sourceDb.Name)] is not accessible on destination. Skipping."
                continue
            }
            if ((Get-DbaAgDatabase -SqlInstance $DestServer -Database $dbName -ErrorAction Ignore -WarningAction SilentlyContinue)) {
                Write-Message -Level Verbose -Message "Database [$dbName] is part of an availability group. Skipping."
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

            $null = $sourceDb.Parent.ConnectionContext.SqlConnectionObject.Close()
            $null = $destDb.Parent.ConnectionContext.SqlConnectionObject.Close()
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
    $null = $SourceLogin.Parent.ConnectionContext.SqlConnectionObject.Close()
    $null = $DestServer.ConnectionContext.SqlConnectionObject.Close()

    foreach ($db in $SourceLogin.EnumDatabaseMappings()) {
        $dbName = $db.DbName
        $destDb = $DestServer.Databases[$dbName]
        $sourceDb = $SourceServer.Databases[$dbName]
        $dbUsername = $db.Username;
        # Adjust renamed database usernames for new server
        if ($newLoginName -eq $loginName) { $newDbUsername = $dbUsername } else { $newDbUsername = $newLoginName }

        if ($null -ne $destDb) {
            if (-not $destDb.IsAccessible) {
                Write-Message -Level Verbose -Message "Database [$dbName] is not accessible. Skipping."
                continue
            }

            if ((Get-DbaAgDatabase -SqlInstance $DestServer -Database $dbName -ErrorAction Ignore -WarningAction SilentlyContinue)) {
                Write-Message -Level Verbose -Message "Database [$dbName] is part of an availability group. Skipping."
                continue
            }
            if ($null -eq $destDb.Users[$newDbUsername]) {
                if ($Pscmdlet.ShouldProcess($destination, "Adding $newDbUsername to $dbName.")) {
                    $sql = $SourceServer.Databases[$dbName].Users[$dbUsername].Script() | Out-String
                    try {
                        $destDb.ExecuteNonQuery($sql.Replace("[$dbUsername]", "[$newDbUsername]"))
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
                    $destDb.ExecuteNonQuery($userScript)
                }
            } else {
                # Database Roles: db_owner, db_datareader, etc
                foreach ($role in $sourceDb.Roles) {
                    $null = $sourceDb.Parent.ConnectionContext.SqlConnectionObject.Close()
                    $null = $destDb.Parent.ConnectionContext.SqlConnectionObject.Close()
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
                $null = $sourceDb.Parent.ConnectionContext.SqlConnectionObject.Close()
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