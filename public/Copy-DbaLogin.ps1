function Copy-DbaLogin {
    <#
    .SYNOPSIS
        Copies SQL Server logins between instances with passwords, permissions, and role memberships intact

    .DESCRIPTION
        Transfers SQL Server logins from one instance to another while preserving authentication details and security context. Essential for server migrations, disaster recovery setups, and environment synchronization where you need users to maintain the same access without recreating accounts manually.

        Handles both SQL Server and Windows Authentication logins, copying passwords (with original SIDs to prevent orphaned users), server roles, database permissions, and login properties like password policy enforcement. Includes smart conflict resolution - can drop and recreate existing logins, rename logins during copy, or generate new SIDs when copying to the same server.

        Version compatibility: SQL Server 2000-2008 R2 logins copy to any version, but SQL Server 2012+ logins (due to hash algorithm changes) only copy to SQL Server 2012 and newer. Automatically handles version-specific features and validates compatibility before attempting migration.

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Login
        Specifies which SQL Server logins to copy from the source instance. Accepts wildcards and arrays of login names.
        Use this when you need to copy specific logins rather than all logins, such as during application migrations or when setting up users for specific databases.

    .PARAMETER ExcludeLogin
        Specifies which logins to skip during the copy operation. Accepts wildcards and arrays of login names.
        Useful for excluding test accounts, service accounts that should remain environment-specific, or logins that already exist on the destination with different configurations.

    .PARAMETER ExcludeSystemLogins
        Excludes NT SERVICE accounts and other system-generated logins from the copy operation.
        Use this during server migrations when you don't want to copy OS-level service accounts that may differ between environments.

    .PARAMETER ExcludePermissionSync
        Skips copying server roles, database permissions, and security mappings for the login accounts.
        Use this when you only need the login accounts created but plan to configure permissions separately, or when copying logins for testing purposes.

    .PARAMETER SyncSaName
        Renames the destination sa account to match the source sa account name if they differ.
        Use this during migrations when your organization has renamed the sa account for security purposes and you need consistent naming across instances.

    .PARAMETER OutFile
        Exports login creation scripts to a T-SQL file instead of copying directly to a destination instance.
        Use this to generate scripts for manual review, version control, or deployment through automated processes rather than performing immediate migration.

    .PARAMETER InputObject
        Accepts login objects from Get-DbaLogin or other dbatools commands through the pipeline.
        Use this when you want to filter or manipulate login objects before copying, such as selecting logins through Out-GridView or combining multiple sources.

    .PARAMETER NewSid
        Forces generation of new Security Identifiers (SIDs) for copied logins instead of preserving original SIDs.
        Use this when copying logins to the same instance (login cloning) or when SID conflicts exist on the destination server.

    .PARAMETER LoginRenameHashtable
        Renames logins during copy using a hashtable with old names as keys and new names as values.
        Use this for login consolidation, environment-specific naming conventions, or when resolving naming conflicts during migrations.

    .PARAMETER ObjectLevel
        Copies granular object-level permissions (table, view, procedure permissions) in addition to database and server roles.
        Use this for complete security replication when applications rely on specific object permissions rather than just role memberships.

    .PARAMETER KillActiveConnection
        Terminates active sessions for logins being replaced when using -Force, allowing the drop and recreate operation to proceed.
        Use this during maintenance windows when you need to force login replacement despite active connections, but ensure users are notified of potential disruption.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        Drops and recreates existing logins on the destination server, transferring ownership of databases and SQL Agent jobs to 'sa' first.
        Use this when you need to update login passwords or properties that can't be modified in place, but ensure job ownership changes are acceptable.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Login
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaLogin

    .EXAMPLE
        PS C:\> Copy-DbaLogin -Source sqlserver2014a -Destination sqlcluster -Force

        Copies all logins from Source Destination. If a SQL Login on Source exists on the Destination, the Login on Destination will be dropped and recreated.

        If active connections are found for a login, the copy of that Login will fail as it cannot be dropped.

    .EXAMPLE
        PS C:\> Copy-DbaLogin -Source sqlserver2014a -Destination sqlcluster -Force -KillActiveConnection

        Copies all logins from Source Destination. If a SQL Login on Source exists on the Destination, the Login on Destination will be dropped and recreated.

        If any active connections are found they will be killed.

    .EXAMPLE
        PS C:\> Copy-DbaLogin -Source sqlserver2014a -Destination sqlcluster -ExcludeLogin realcajun -SourceSqlCredential $scred -DestinationSqlCredential $dcred

        Copies all Logins from Source to Destination except for realcajun using SQL Authentication to connect to both instances.

        If a Login already exists on the destination, it will not be migrated.

    .EXAMPLE
        PS C:\> Copy-DbaLogin -Source sqlserver2014a -Destination sqlcluster -Login realcajun, netnerds -force

        Copies ONLY Logins netnerds and realcajun. If Login realcajun or netnerds exists on Destination, the existing Login(s) will be dropped and recreated.

    .EXAMPLE
        PS C:\> Copy-DbaLogin -LoginRenameHashtable @{ "PreviousUser" = "newlogin" } -Source $Sql01 -Destination Localhost -SourceSqlCredential $sqlcred -Login PreviousUser

        Copies PreviousUser as newlogin.

    .EXAMPLE
        PS C:\> Copy-DbaLogin -LoginRenameHashtable @{ OldLogin = "NewLogin" } -Source Sql01 -Destination Sql01 -Login ORG\OldLogin -ObjectLevel -NewSid

        Clones OldLogin as NewLogin onto the same server, generating a new SID for the login. Also clones object-level permissions.

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 | Out-GridView -Passthru | Copy-DbaLogin -Destination sql2017

        Displays all available logins on sql2016 in a grid view, then copies all selected logins to sql2017.

    .EXAMPLE
        PS C:\> $loginSplat = @{
        >> Source = $Sql01
        >> Destination = "Localhost"
        >> SourceSqlCredential = $sqlcred
        >> Login = 'ReadUserP', 'ReadWriteUserP', 'AdminP'
        >> LoginRenameHashtable = @{
        >> "ReadUserP" = "ReadUserT"
        >> "ReadWriteUserP" = "ReadWriteUserT"
        >> "AdminP"         = "AdminT"
        >> }
        >> }
        PS C:\> Copy-DbaLogin @loginSplat

        Copies the three specified logins to 'localhost' and renames them according to the LoginRenameHashTable.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(ParameterSetName = "File", Mandatory)]
        [parameter(ParameterSetName = "SqlInstance", Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(ParameterSetName = "SqlInstance", Mandatory)]
        [parameter(ParameterSetName = "InputObject", Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$Login,
        [object[]]$ExcludeLogin,
        [switch]$ExcludeSystemLogins,
        [parameter(ParameterSetName = "Live")]
        [parameter(ParameterSetName = "SqlInstance")]
        [switch]$SyncSaName,
        [parameter(ParameterSetName = "File", Mandatory)]
        [string]$OutFile,
        [parameter(ParameterSetName = "InputObject", ValueFromPipeline)]
        [object[]]$InputObject,
        [hashtable]$LoginRenameHashtable,
        [switch]$KillActiveConnection,
        [switch]$NewSid,
        [switch]$Force,
        [switch]$ObjectLevel,
        [switch]$ExcludePermissionSync,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }
        function Copy-Login {
            [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
            Param (
                $SourceServer,
                $DestServer,
                $Login,
                $Exclude
            )
            $destinstance = $DestServer.Name
            if ($LoginRenameHashtable.Keys -contains $Login.name) {
                $newUserName = $LoginRenameHashtable[$Login.name]
            } else {
                $newUserName = $Login.name
            }

            $copyLoginStatus = [PSCustomObject]@{
                SourceServer      = $sourceServer.Name
                DestinationServer = $destServer.Name
                Type              = "Login - $($Login.LoginType)"
                Name              = $newUserName
                DestinationLogin  = $newUserName
                SourceLogin       = $Login.name
                Status            = $null
                Notes             = $null
                DateTime          = [DbaDateTime](Get-Date)
            }

            if ($ExcludeLogin -contains $Login.name) { continue }

            if ($Login.id -eq 1) { continue }

            if ($newUserName.StartsWith("##") -or $newUserName -eq 'sa') {
                Write-Message -Level Verbose -Message "Skipping $newUserName."
                continue
            }

            if ($newUserName -like "BUILTIN\Administrators" -and $sourceServer.HostPlatform -eq "Linux") {
                if ($Pscmdlet.ShouldProcess($destinstance, "Skipping BUILTIN\Administrators on Linux SQL Server")) {
                    Write-Message -Level Warning -Message "BUILTIN\Administrators cannot be dropped on SQL Server on Linux as it breaks system stored procedures. Skipping."
                    $copyLoginStatus.Status = "Skipped"
                    $copyLoginStatus.Notes = "BUILTIN\Administrators is required on Linux SQL Server"
                    $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
                continue
            }

            if ($Login.LoginType -like 'Window*' -and $destServer.DatabaseEngineEdition -eq 'SqlManagedInstance' ) {
                if ($Pscmdlet.ShouldProcess($destinstance, "$Login is a Windows login and not supported on a SQL Managed Instance, skipping on $destInstance")) {
                    Write-Message -Level Verbose -Message "$Login is a Windows login and not supported on a SQL Managed Instance, skipping on $destInstance"
                    $copyLoginStatus.Status = "Skipped"
                    $copyLoginStatus.Notes = "$($Login.name) is a Windows login, not supported on a SQL Managed Instance"
                    $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
                continue
            }

            # Here we don't need the FullComputerName, but only the machine name to compare to the host part of the login name. So ComputerName should be fine.
            $serverName = $sourceServer.ComputerName

            $currentLogin = $DestServer.ConnectionContext.truelogin

            if ($currentLogin -eq $newUserName -and $force) {
                if ($Pscmdlet.ShouldProcess($destinstance, "Login $newUserName is skipped because it is performing the migration")) {
                    Write-Message -Level Verbose -Message "Cannot drop login performing the migration. Skipping."
                    $copyLoginStatus.Status = "Skipped"
                    $copyLoginStatus.Notes = "Current login"
                    $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
                continue
            }

            if (($destServer.LoginMode -ne [Microsoft.SqlServer.Management.Smo.ServerLoginMode]::Mixed) -and ($Login.LoginType -eq [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin)) {
                Write-Message -Level Verbose -Message "$Destination does not have Mixed Mode enabled. [$($Login.Name)] is an SQL Login. Enable mixed mode authentication after the migration completes to use this type of login."
            }

            $userBase = ($Login.Name.Split("\")[0]).ToLowerInvariant()

            if ($serverName -eq $userBase -or $Login.Name.StartsWith("NT ")) {
                if ($sourceServer.ComputerName -ne $destServer.ComputerName) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Skipping $($Login.Name) because it is a local machine name")) {
                        Write-Message -Level Verbose -Message "$($Login.Name) was skipped because it is a local machine name."
                        $copyLoginStatus.Status = "Skipped"
                        $copyLoginStatus.Notes = "Local machine name"
                        $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                    continue
                } else {
                    if ($ExcludeSystemLogins) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "$($Login.Name) was skipped because ExcludeSystemLogins was specified")) {
                            Write-Message -Level Verbose -Message "$($Login.Name) was skipped because ExcludeSystemLogins was specified."
                            $copyLoginStatus.Status = "Skipped"
                            $copyLoginStatus.Notes = "System login"
                            $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }
                        continue
                    }
                    Write-Message -Level Verbose -Message "Skipping local login $($Login.Name) since the source and destination server reside on the same machine."
                }
            }

            if ($null -ne $destServer.Logins.Item($newUserName) -and !$force) {
                if ($Pscmdlet.ShouldProcess($destinstance, "Skipping $newUserName because it exists at destination")) {
                    Write-Message -Level Verbose -Message "$newUserName already exists in destination. Use -Force to drop and recreate."
                    $copyLoginStatus.Status = "Skipped"
                    $copyLoginStatus.Notes = "Already exists on destination"
                    $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
                continue
            }

            if ($null -ne $destServer.Logins.Item($newUserName) -and $force) {
                if ($newUserName -eq $destServer.ServiceAccount) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "$newUserName is the destination service account, skipping drop")) {
                        Write-Message -Level Verbose -Message "$newUserName is the destination service account. Skipping drop."
                        $copyLoginStatus.Status = "Skipped"
                        $copyLoginStatus.Notes = "Destination service account"
                        $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                    continue
                }

                if ($newUserName -like "BUILTIN\Administrators" -and $destServer.HostPlatform -eq "Linux") {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Skipping BUILTIN\Administrators on Linux SQL Server")) {
                        Write-Message -Level Warning -Message "BUILTIN\Administrators cannot be dropped on SQL Server on Linux as it breaks system stored procedures. Skipping."
                        $copyLoginStatus.Status = "Skipped"
                        $copyLoginStatus.Notes = "BUILTIN\Administrators is required on Linux SQL Server"
                        $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                    continue
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Dropping $newUserName")) {

                    # Kill connections, delete user
                    Write-Message -Level Verbose -Message "Attempting to migrate $newUserName"
                    Write-Message -Level Verbose -Message "Force was specified. Attempting to drop $newUserName on $destinstance."

                    try {
                        $ownedDbs = $destServer.Databases | Where-Object Owner -eq $newUserName

                        foreach ($ownedDb in $ownedDbs) {
                            Write-Message -Level Verbose -Message "Changing database owner for $($ownedDb.name) from $newUserName to sa."
                            $ownedDb.SetOwner('sa')
                            $ownedDb.Alter()
                        }

                        $ownedJobs = $destServer.JobServer.Jobs | Where-Object OwnerLoginName -eq $newUserName

                        foreach ($ownedJob in $ownedJobs) {
                            Write-Message -Level Verbose -Message "Changing job owner for $($ownedJob.name) from $newUserName to sa."
                            $ownedJob.Set_OwnerLoginName('sa')
                            $ownedJob.Alter()
                        }

                        $activeConnections = $destServer.EnumProcesses() | Where-Object Login -eq $newUserName

                        if ($activeConnections -and $KillActiveConnection) {
                            if (!$destServer.Logins.Item($newUserName).IsDisabled) {
                                $disabled = $true
                                $destServer.Logins.Item($newUserName).Disable()
                            }

                            $activeConnections | ForEach-Object { $destServer.KillProcess($_.Spid) }
                            Write-Message -Level Verbose -Message "-KillActiveConnection was provided. There are $($activeConnections.Count) active connections killed."
                        } elseif ($activeConnections) {
                            Write-Message -Level Verbose -Message "There are $($activeConnections.Count) active connections found for the login $newUserName. Utilize -KillActiveConnection to kill the connections."
                        }
                        try {
                            $destServer.Logins.Item($newUserName).Drop()
                        } catch {
                            # just in case the kill didn't work, it'll leave behind a disabled account
                            if ($disabled) { $destServer.Logins.Item($newUserName).Enable() }
                            throw $_
                        }
                        Write-Message -Level Verbose -Message "Successfully dropped $newUserName on $destinstance."
                    } catch {
                        $copyLoginStatus.Status = "Failed"
                        $copyLoginStatus.Notes = (Get-ErrorMessage -Record $_)
                        $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Could not drop $newuserName on $destinstance | $PSItem"
                        continue
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($destinstance, "Adding SQL login $newUserName")) {

                Write-Message -Level Verbose -Message "Attempting to add $newUserName to $destinstance."
                try {
                    $splatNewLogin = @{
                        SqlInstance          = $destServer
                        InputObject          = $Login
                        NewSid               = $NewSid
                        LoginRenameHashtable = $LoginRenameHashtable
                    }
                    if ($Login.DefaultDatabase -notin $destServer.Databases.Name) {
                        $copyLoginStatus.Notes = "Database $($Login.DefaultDatabase) does not exist on $destServer, switching DefaultDatabase to 'master' for $($Login.Name)"
                        Write-Message -Level Warning -Message $copyLoginStatus.Notes
                        $splatNewLogin.DefaultDatabase = 'master'
                    }
                    $destLogin = New-DbaLogin @splatNewLogin -EnableException:$true
                    $copyLoginStatus.Status = "Successful"
                } catch {
                    $copyLoginStatus.Status = "Failed"
                    $copyLoginStatus.Notes = (Get-ErrorMessage -Record $_)
                    $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Write-Message -Level Verbose -Message "Could not create $newuserName on $destinstance | $PSItem"
                    continue
                }

                $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                if (-not $ExcludePermissionSync) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Updating SQL login $newUserName permissions")) {
                        # In rare cases, when the instance has a case sensitive collation and there are two logins that differ only in case, New-DbaLogin will return them both into $destLogin
                        # So we loop, just in case...
                        foreach ($dl in $destLogin) {
                            Update-SqlPermission -SourceServer $sourceServer -SourceLogin $Login -DestServer $destServer -DestLogin $dl -ObjectLevel:$ObjectLevel
                        }
                    }
                }
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        $loginsCollection = @()
        if ($InputObject) {
            $loginsCollection += $InputObject
        } else {
            $loginsCollection += Get-DbaLogin -SqlInstance $Source -SqlCredential $SourceSqlCredential -Login $Login -EnableException:$EnableException
        }

        if ($OutFile) {
            return (Export-DbaLogin -SqlInstance $Source -SqlCredential $SourceSqlCredential -FilePath $OutFile -Login $loginsCollection -ObjectLevel:$ObjectLevel -ExcludeLogin $ExcludeLogin -EnableException:$EnableException)
        }
        foreach ($loginObject in $loginsCollection) {
            $sourceServer = $loginObject.Parent
            $sourceVersionMajor = $sourceServer.VersionMajor

            foreach ($destinstance in $Destination) {
                try {
                    $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -AzureUnsupported
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
                }

                $destVersionMajor = $destServer.VersionMajor
                if ($sourceVersionMajor -gt 10 -and $destVersionMajor -lt 11) {
                    Stop-Function -Message "Login migration from version $sourceVersionMajor to $destVersionMajor is not supported." -Target $sourceServer
                }

                if ($sourceVersionMajor -lt 8 -or $destVersionMajor -lt 8) {
                    Stop-Function -Message "SQL Server 7 and below are not supported." -Target $sourceServer
                }

                if ($destserver.ConnectionContext.TrueLogin -notin $destserver.Logins.Name -and $Force) {
                    if ($Login -or $ExcludeLogin -or $InputObject) {
                        Write-Message -Level Verbose -Message "Force was used and $($destserver.ConnectionContext.TrueLogin) not found in logins list but an explicit Login or ExcludeLogin was specified, so we trust you won't drop the group that allows $($destserver.ConnectionContext.TrueLogin) access. Proceeding."
                    } else {
                        Stop-Function -Message "Force was used, no explicit -Login or -ExcludeLogin was specified and $($destserver.ConnectionContext.TrueLogin) cannot be found in the logins list. It may be part of a group. This will likely result in you being locked out of the server. To use Force, $($destserver.ConnectionContext.TrueLogin) must be added directly to logins before proceeding." -Target $destserver
                        continue
                    }
                }

                Write-Message -Level Verbose -Message "Attempting Login Migration."
                Copy-Login -sourceserver $sourceServer -destserver $destServer -Login $loginObject -Exclude $ExcludeLogin

                if ($SyncSaName) {
                    $sa = $sourceServer.Logins | Where-Object id -eq 1
                    $destSa = $destServer.Logins | Where-Object id -eq 1
                    $saName = $sa.Name
                    if ($saName -ne $destSa.name) {
                        Write-Message -Level Verbose -Message "Changing sa username to match source ($saName)."
                        if ($Pscmdlet.ShouldProcess($destinstance, "Changing sa username to match source ($saName)")) {
                            try {
                                $destSa.Rename($saName)
                                $destSa.Alter()
                            } catch {
                                Write-Message -Level Verbose -Message "Could not change sa username to match source ($saName) on $destinstance | $PSItem"
                            }
                        }
                    }
                }
            }
        }
    }
}