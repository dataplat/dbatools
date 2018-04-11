function Update-SqlPermissions {
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
        .PARAMETER EnableException
            Use this switch to disable any kind of verbose messages
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object]$SourceServer,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object]$SourceLogin,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object]$DestServer,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object]$DestLogin,
        [Alias('Silent')]
        [switch]$EnableException
    )

    $destination = $DestServer.DomainInstanceName
    $source = $SourceServer.DomainInstanceName
    $userName = $SourceLogin.Name

    # Server Roles: sysadmin, bulklogin, etc
    foreach ($role in $SourceServer.Roles) {
        $roleName = $role.Name
        $destRole = $DestServer.Roles[$roleName]

        if ($null -ne $destRole) {
            try {
                $destRoleMembers = $destRole.EnumMemberNames()
            }
            catch {
                $destRoleMembers = $destRole.EnumServerRoleMembers()
            }
        }

        try {
            $roleMembers = $role.EnumMemberNames()
        }
        catch {
            $roleMembers = $role.EnumServerRoleMembers()
        }

        if ($roleMembers -contains $userName) {
            if ($null -ne $destRole) {
                if ($Pscmdlet.ShouldProcess($destination, "Adding $userName to $roleName server role.")) {
                    try {
                        $destRole.AddMember($userName)
                        Write-Message -Level Verbose -Message "Adding $userName to $roleName server role on $destination successfully performed."
                    }
                    catch {
                        Stop-Function -Message "Failed to add $userName to $roleName server role on $destination." -Target $role -ErrorRecord $_
                    }
                }
            }
        }

        # Remove for Syncs
        if ($roleMembers -notcontains $userName -and $destRoleMembers -contains $userName -and $null -ne $destRole) {
            if ($Pscmdlet.ShouldProcess($destination, "Adding $userName to $roleName server role.")) {
                try {
                    $destRole.DropMember($userName)
                    Write-Message -Level Verbose -Message "Removing $userName from $destRoleName server role on $destination successfully performed."
                }
                catch {
                    Stop-Function -Message "Failed to remove $userName from $destRoleName server role on $destination." -Target $role -ErrorRecord $_
                }
            }
        }
    }

    $ownedJobs = $SourceServer.JobServer.Jobs | Where-Object OwnerLoginName -eq $userName
    foreach ($ownedJob in $ownedJobs) {
        if ($null -ne $DestServer.JobServer.Jobs[$ownedJob.Name]) {
            if ($Pscmdlet.ShouldProcess($destination, "Changing of job owner to $userName for $($ownedJob.Name).")) {
                try {
                    $destOwnedJob = $DestServer.JobServer.Jobs | Where-Object { $_.Name -eq $ownedJobs.Name }
                    $destOwnedJob.Set_OwnerLoginName($userName)
                    $destOwnedJob.Alter()
                    Write-Message -Level Verbose -Message "Changing job owner to $userName for $($ownedJob.Name) on $destination successfully performed."
                }
                catch {
                    Stop-Function -Message "Failed to change job owner for $($ownedJob.Name) on $destination." -Target $ownedJob -ErrorRecord $_
                }
            }
        }
    }

    if ($SourceServer.VersionMajor -ge 9 -and $DestServer.VersionMajor -ge 9) {
        <#
            These operations are only supported by SQL Server 2005 and above.
            Securables: Connect SQL, View any database, Administer Bulk Operations, etc.
        #>

        $perms = $SourceServer.EnumServerPermissions($userName)
        foreach ($perm in $perms) {
            $permState = $perm.PermissionState
            if ($permState -eq "GrantWithGrant") {
                $grantWithGrant = $true;
                $permState = "grant"
            }
            else {
                $grantWithGrant = $false
            }

            $permSet = New-Object Microsoft.SqlServer.Management.Smo.ServerPermissionSet($perm.PermissionType)
            if ($Pscmdlet.ShouldProcess($destination, "$permState on $($perm.PermissionType) for $userName.")) {
                try {
                    $DestServer.PSObject.Methods[$permState].Invoke($permSet, $userName, $grantWithGrant)
                    Write-Message -Level Verbose -Message "$permState $($perm.PermissionType) to $userName on $destination successfully performed."
                }
                catch {
                    Stop-Function -Message "Failed to $permState $($perm.PermissionType) to $userName on $destination." -Target $perm -ErrorRecord $_
                }
            }

            # for Syncs
            $destPerms = $DestServer.EnumServerPermissions($userName)
            foreach ($perm in $destPerms) {
                $permState = $perm.PermissionState
                $sourcePerm = $perms | Where-Object { $_.PermissionType -eq $perm.PermissionType -and $_.PermissionState -eq $permState }

                if ($null -eq $sourcePerm) {
                    if ($Pscmdlet.ShouldProcess($destination, "Revoking $($perm.PermissionType) for $userName.")) {
                        try {
                            $permSet = New-Object Microsoft.SqlServer.Management.Smo.ServerPermissionSet($perm.PermissionType)

                            if ($permState -eq "GrantWithGrant") {
                                $grantWithGrant = $true;
                                $permState = "grant"
                            }
                            else {
                                $grantWithGrant = $false
                            }

                            $DestServer.PSObject.Methods["Revoke"].Invoke($permSet, $userName, $false, $grantWithGrant)
                            Write-Message -Level Verbose -Message "Revoking $($perm.PermissionType) for $userName on $destination successfully performed."
                        }
                        catch {
                            Stop-Function -Message "Failed to revoke $($perm.PermissionType) from $userName on $destination." -Target $perm -ErrorRecord $_
                        }
                    }
                }
            }
        }

        # Credential mapping. Credential removal not currently supported for Syncs.
        $loginCredentials = $SourceServer.Credentials | Where-Object { $_.Identity -eq $SourceLogin.Name }
        foreach ($credential in $loginCredentials) {
            if ($null -eq $DestServer.Credentials[$credential.Name]) {
                if ($Pscmdlet.ShouldProcess($destination, "Creating credential $($credential.Name) for $userName.")) {
                    try {
                        $newCred = New-Object Microsoft.SqlServer.Management.Smo.Credential($DestServer, $credential.Name)
                        $newCred.Identity = $SourceLogin.Name
                        $newCred.Create()
                        Write-Message -Level Verbose -Message "Creating credential $($credential.Name) for $userName on $destination successfully performed."
                    }
                    catch {
                        Stop-Function -Message "Failed to create credential $($credential.Name) for $userName on $destination." -Target $credential -ErrorRecord $_
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
        $dbUsername = $db.Username;
        $dbLogin = $db.LoginName

        if ($null -ne $sourceDb) {
            if (!$sourceDb.IsAccessible) {
                Write-Message -Level Verbose -Message "Database [$($sourceDb.Name)] is not accessible on $source. Skipping."
                continue
            }
            if ($null -eq $sourceDb.Users[$dbUsername] -and $null -eq $destDb.Users[$dbUsername]) {
                if ($Pscmdlet.ShouldProcess($destination, "Dropping user $dbUsername from $dbName.")) {
                    try {
                        $destDb.Users[$dbUsername].Drop()
                        Write-Message -Level Verbose -Message "Dropping user $dbUsername (login: $dbLogin) from $dbName on destination successfully performed."
                        Write-Message -Level Verbose -Message "Any schema in $dbaName owned by $dbUsername may still exist."
                    }
                    catch {
                        Stop-Function -Message "Failed to drop $dbUsername (login: $dbLogin) from $dbName on destination." -Target $db -ErrorRecord $_
                    }
                }
            }

            # Remove user from role. Role removal not currently supported for Syncs.
            # TODO: reassign if dbo, application roles
            foreach ($destRole in $destDb.Roles) {
                $destRoleName = $destRole.Name
                $sourceRole = $sourceDb.Roles[$destRoleName]
                if ($null -eq $sourceRole) {
                    if ($sourceRole.EnumMembers() -notcontains $dbUsername -and $destRole.EnumMembers() -contains $dbUsername) {
                        if ($dbUsername -ne "dbo") {
                            if ($Pscmdlet.ShouldProcess($destination, "Dropping user $userName from $destRoleName database role in $dbName.")) {
                                try {
                                    $destRole.DropMember($dbUsername)
                                    $destDb.Alter()
                                    Write-Message -Level Verbose -Message "Dropping user $dbUsername (login: $dbLogin) from $destRoleName database role in $dbName on $destination successfully performed."
                                }
                                catch {
                                    Stop-Function -Message "Failed to remove $dbUsername (login: $dbLogin) from $destRoleName database role in $dbName on $destination." -Target $destRole -ErrorRecord $_
                                }
                            }
                        }
                    }
                }
            }

            # Remove Connect, Alter Any Assembly, etc
            $destPerms = $destDb.EnumDatabasePermissions($userName)
            $perms = $sourceDb.EnumDatabasePermissions($userName)
            # for Syncs
            foreach ($perm in $destPerms) {
                $permState = $perm.PermissionState
                $sourcePerm = $perms | Where-Object { $_.PermissionType -eq $perm.PermissionType -and $_.PermissionState -eq $permState }
                if ($null -eq $sourcePerm) {
                    if ($Pscmdlet.ShouldProcess($destination, "Revoking $($perm.PermissionType) from $userName in $dbName.")) {
                        try {
                            $permSet = New-Object Microsoft.SqlServer.Management.Smo.DatabasePermissionSet($perm.PermissionType)

                            if ($permState -eq "GrantWithGrant") {
                                $grantWithGrant = $true;
                                $permState = "grant"
                            }
                            else {
                                $grantWithGrant = $false
                            }

                            $destDb.PSObject.Methods["Revoke"].Invoke($permSet, $userName, $false, $grantWithGrant)
                            Write-Message -Level Verbose -Message "Revoking $($perm.PermissionType) from $userName in $dbName on $destination successfully performed."
                        }
                        catch {
                            Stop-Function -Message "Failed to revoke $($perm.PermissionType) from $userName in $dbName on $destination." -Target $perm -ErrorRecord $_
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
        $dbLogin = $db.LoginName

        if ($null -ne $destDb) {
            if (!$destDb.IsAccessible) {
                Write-Message -Level Verbose -Message "Database [$dbName] is not accessible. Skipping."
                continue
            }
            if ($null -eq $destDb.Users[$dbUsername]) {
                if ($Pscmdlet.ShouldProcess($destination, "Adding $dbUsername to $dbName.")) {
                    $sql = $SourceServer.Databases[$dbName].Users[$dbUsername].Script() | Out-String
                    try {
                        $destDb.ExecuteNonQuery($sql)
                        Write-Message -Level Verbose -Message "Adding user $dbUsername (login: $dbLogin) to $dbName successfully performed."
                    }
                    catch {
                        Stop-Function -Message "Failed to add $dbUsername (login: $dbLogin) to $dbName on $destination." -Target $db -ErrorRecord $_
                    }
                }
            }

            # Db owner
            if ($sourceDb.Owner -eq $userName) {
                if ($Pscmdlet.ShouldProcess($destination, "Changing $dbName dbowner to $userName.")) {
                    try {
                        $result = Update-SqlDbOwner $SourceServer $DestServer -DbName $dbName
                        if ($result -eq $true) {
                            Write-Message -Level Verbose -Message "Changed $($destDb.Name) owner to $($sourceDb.owner)."
                        }
                        else {
                            Write-Message -Level Warning -Message "Failed to update $($destDb.Name) owner to $($sourceDb.owner)."
                        }
                    }
                    catch {
                        Write-Message -Level Warning -Message "Failed to update $($destDb.Name) owner to $($sourceDb.owner)."
                    }
                }
            }

            # Database Roles: db_owner, db_datareader, etc
            foreach ($role in $sourceDb.Roles) {
                if ($role.EnumMembers() -contains $userName) {
                    $roleName = $role.Name
                    $destDbRole = $destDb.Roles[$roleName]

                    if ($null -ne $destDbRole -and $dbUsername -ne "dbo" -and $destDbRole.EnumMembers() -notcontains $userName) {
                        if ($Pscmdlet.ShouldProcess($destination, "Adding $userName to $roleName database role in $dbName.")) {
                            try {
                                $destDbRole.AddMember($userName)
                                $destDb.Alter()
                                Write-Message -Level Verbose -Message "Adding $userName to $roleName database role in $dbName on $destination successfully performed."
                            }
                            catch {
                                Stop-Function -Message "Failed to add $userName to $roleName database role in $dbName on $destination." -Target $role -ErrorRecord $_
                            }
                        }
                    }
                }
            }

            # Connect, Alter Any Assembly, etc
            $perms = $sourceDb.EnumDatabasePermissions($userName)
            foreach ($perm in $perms) {
                $permState = $perm.PermissionState
                if ($permState -eq "GrantWithGrant") {
                    $grantWithGrant = $true;
                    $permState = "grant"
                }
                else {
                    $grantWithGrant = $false
                }
                $permSet = New-Object Microsoft.SqlServer.Management.Smo.DatabasePermissionSet($perm.PermissionType)

                if ($Pscmdlet.ShouldProcess($destination, "$permState on $($perm.PermissionType) for $userName on $dbName")) {
                    try {
                        $destDb.PSObject.Methods[$permState].Invoke($permSet, $userName, $grantWithGrant)
                        Write-Message -Level Verbose -Message "$permState on $($perm.PermissionType) to $userName on $dbName on $destination successfully performed."
                    }
                    catch {
                        Stop-Function -Message "Failed to perform $permState on $($perm.PermissionType) to $userName on $dbName on $destination." -Target $perm -ErrorRecord $_
                    }
                }
            }
        }
    }
}