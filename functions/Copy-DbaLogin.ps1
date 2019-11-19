function Copy-DbaLogin {
    <#
    .SYNOPSIS
        Migrates logins from source to destination SQL Servers. Supports SQL Server versions 2000 and newer.

    .DESCRIPTION
        SQL Server 2000: Migrates logins with SIDs, passwords, server roles and database roles.

        SQL Server 2005 & newer: Migrates logins with SIDs, passwords, defaultdb, server roles & securables, database permissions & securables, login attributes (enforce password policy, expiration, etc.)

        The login hash algorithm changed in SQL Server 2012, and is not backwards compatible with previous SQL Server versions. This means that while SQL Server 2000 logins can be migrated to SQL Server 2012, logins created in SQL Server 2012 can only be migrated to SQL Server 2012 and above.

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
        The login(s) to process. Options for this list are auto-populated from the server. If unspecified, all logins will be processed.

    .PARAMETER ExcludeLogin
        The login(s) to exclude. Options for this list are auto-populated from the server.

    .PARAMETER ExcludeSystemLogins
        If this switch is enabled, NT SERVICE accounts will be skipped.

    .PARAMETER ExcludePermissionSync
        Skips permission syncs

    .PARAMETER SyncSaName
        If this switch is enabled, the name of the sa account will be synced between Source and Destination

    .PARAMETER OutFile
        Calls Export-DbaLogin and exports all logins to a T-SQL formatted file. This does not perform a copy, so no destination is required.

    .PARAMETER InputObject
        Takes the parameters required from a Login object that has been piped into the command

    .PARAMETER LoginRenameHashtable
        Pass a hash table into this parameter to be passed into Rename-DbaLogin to update the Login and mappings after the Login is completed.

    .PARAMETER KillActiveConnection
        If this switch and -Force are enabled, all active connections and sessions on Destination will be killed.

        A login cannot be dropped when it has active connections on the instance.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        If this switch is enabled, the Login(s) will be dropped and recreated on Destination. Logins that own Agent jobs cannot be dropped at this time.

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

        Copies PreviousUser and then renames it to newlogin.

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
        [object]$InputObject,
        [hashtable]$LoginRenameHashtable,
        [switch]$KillActiveConnection,
        [switch]$Force,
        [switch]$ExcludePermissionSync,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }
        function Copy-Login {
            foreach ($sourceLogin in $sourceServer.Logins) {
                $userName = $sourceLogin.name

                $copyLoginStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Type              = "Login - $($sourceLogin.LoginType)"
                    Name              = $userName
                    DestinationLogin  = $userName
                    SourceLogin       = $userName
                    Status            = $null
                    Notes             = $null
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($Login -and $Login -notcontains $userName -or $ExcludeLogin -contains $userName) { continue }

                if ($sourceLogin.id -eq 1) { continue }

                if ($userName.StartsWith("##") -or $userName -eq 'sa') {
                    Write-Message -Level Verbose -Message "Skipping $userName."
                    continue
                }

                if ($sourceLogin.LoginType -like 'Window*' -and $destServer.DatabaseEngineEdition -eq 'SqlManagedInstance' ) {
                    Write-Message -Level Verbose -Message "$sourceLogin is a Windows login, not supported on a SQL Managed Instance"
                    $copyLoginStatus.Status = "Skipped"
                    $copyLoginStatus.Notes = "$sourceLogin is a Windows login, not supported on a SQL Managed Instance"
                    $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    continue
                }

                $serverName = Resolve-NetBiosName $sourceServer

                $currentLogin = $sourceServer.ConnectionContext.truelogin

                if ($currentLogin -eq $userName -and $force) {
                    if ($Pscmdlet.ShouldProcess("console", "Stating $userName is skipped because it is performing the migration.")) {
                        Write-Message -Level Verbose -Message "Cannot drop login performing the migration. Skipping."
                        $copyLoginStatus.Status = "Skipped"
                        $copyLoginStatus.Notes = "Current login"
                        $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                    continue
                }

                if (($destServer.LoginMode -ne [Microsoft.SqlServer.Management.Smo.ServerLoginMode]::Mixed) -and ($sourceLogin.LoginType -eq [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin)) {
                    Write-Message -Level Verbose -Message "$Destination does not have Mixed Mode enabled. [$userName] is an SQL Login. Enable mixed mode authentication after the migration completes to use this type of login."
                }

                $userBase = ($userName.Split("\")[0]).ToLowerInvariant()

                if ($serverName -eq $userBase -or $userName.StartsWith("NT ")) {
                    if ($sourceServer.ComputerName -ne $destServer.ComputerName) {
                        if ($Pscmdlet.ShouldProcess("console", "Stating $userName was skipped because it is a local machine name.")) {
                            Write-Message -Level Verbose -Message "$userName was skipped because it is a local machine name."
                            $copyLoginStatus.Status = "Skipped"
                            $copyLoginStatus.Notes = "Local machine name"
                            $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }
                        continue
                    } else {
                        if ($ExcludeSystemLogins) {
                            if ($Pscmdlet.ShouldProcess("console", "$userName was skipped because ExcludeSystemLogins was specified.")) {
                                Write-Message -Level Verbose -Message "$userName was skipped because ExcludeSystemLogins was specified."

                                $copyLoginStatus.Status = "Skipped"
                                $copyLoginStatus.Notes = "System login"
                                $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            }
                            continue
                        }

                        if ($Pscmdlet.ShouldProcess("console", "Stating local login $userName since the source and destination server reside on the same machine.")) {
                            Write-Message -Level Verbose -Message "Copying local login $userName since the source and destination server reside on the same machine."
                        }
                    }
                }

                if ($null -ne $destServer.Logins.Item($userName) -and !$force) {
                    if ($Pscmdlet.ShouldProcess("console", "Stating $userName is skipped because it exists at destination.")) {
                        Write-Message -Level Verbose -Message "$userName already exists in destination. Use -Force to drop and recreate."
                        $copyLoginStatus.Status = "Skipped"
                        $copyLoginStatus.Notes = "Already exists on destination"
                        $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                    continue
                }

                if ($null -ne $destServer.Logins.Item($userName) -and $force) {
                    if ($userName -eq $destServer.ServiceAccount) {
                        if ($Pscmdlet.ShouldProcess("console", "$userName is the destination service account. Skipping drop.")) {
                            Write-Message -Level Verbose -Message "$userName is the destination service account. Skipping drop."

                            $copyLoginStatus.Status = "Skipped"
                            $copyLoginStatus.Notes = "Destination service account"
                            $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }
                        continue
                    }

                    if ($Pscmdlet.ShouldProcess($destinstance, "Dropping $userName")) {

                        # Kill connections, delete user
                        Write-Message -Level Verbose -Message "Attempting to migrate $userName"
                        Write-Message -Level Verbose -Message "Force was specified. Attempting to drop $userName on $destinstance."

                        try {
                            $ownedDbs = $destServer.Databases | Where-Object Owner -eq $userName

                            foreach ($ownedDb in $ownedDbs) {
                                Write-Message -Level Verbose -Message "Changing database owner for $($ownedDb.name) from $userName to sa."
                                $ownedDb.SetOwner('sa')
                                $ownedDb.Alter()
                            }

                            $ownedJobs = $destServer.JobServer.Jobs | Where-Object OwnerLoginName -eq $userName

                            foreach ($ownedJob in $ownedJobs) {
                                Write-Message -Level Verbose -Message "Changing job owner for $($ownedJob.name) from $userName to sa."
                                $ownedJob.Set_OwnerLoginName('sa')
                                $ownedJob.Alter()
                            }

                            $activeConnections = $destServer.EnumProcesses() | Where-Object Login -eq $userName

                            if ($activeConnections -and $KillActiveConnection) {
                                if (!$destServer.Logins.Item($userName).IsDisabled) {
                                    $disabled = $true
                                    $destServer.Logins.Item($userName).Disable()
                                }

                                $activeConnections | ForEach-Object { $destServer.KillProcess($_.Spid) }
                                Write-Message -Level Verbose -Message "-KillActiveConnection was provided. There are $($activeConnections.Count) active connections killed."
                                # just in case the kill didn't work, it'll leave behind a disabled account
                                if ($disabled) { $destServer.Logins.Item($userName).Enable() }
                            } elseif ($activeConnections) {
                                Write-Message -Level Verbose -Message "There are $($activeConnections.Count) active connections found for the login $userName. Utilize -KillActiveConnection with -Force to kill the connections."
                            }
                            $destServer.Logins.Item($userName).Drop()

                            Write-Message -Level Verbose -Message "Successfully dropped $userName on $destinstance."
                        } catch {
                            $copyLoginStatus.Status = "Failed"
                            $copyLoginStatus.Notes = (Get-ErrorMessage -Record $_).Message
                            $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Stop-Function -Message "Could not drop $userName." -Category InvalidOperation -ErrorRecord $_ -Target $destServer -Continue 3>$null
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Adding SQL login $userName")) {

                    Write-Message -Level Verbose -Message "Attempting to add $userName to $destinstance."
                    $destLogin = New-Object Microsoft.SqlServer.Management.Smo.Login($destServer, $userName)

                    Write-Message -Level Verbose -Message "Setting $userName SID to source username SID."
                    $destLogin.Set_Sid($sourceLogin.Get_Sid())

                    $defaultDb = $sourceLogin.DefaultDatabase

                    Write-Message -Level Verbose -Message "Setting login language to $($sourceLogin.Language)."
                    $destLogin.Language = $sourceLogin.Language

                    if ($null -eq $destServer.databases[$defaultDb]) {
                        # we end up here when the default database on source doesn't exist on dest
                        # if source login is a sysadmin, then set the default database to master
                        # if not, set it to tempdb (see #303)
                        $OrigdefaultDb = $defaultDb
                        try { $sourcesysadmins = $sourceServer.roles['sysadmin'].EnumMemberNames() }
                        catch { $sourcesysadmins = $sourceServer.roles['sysadmin'].EnumServerRoleMembers() }
                        if ($sourcesysadmins -contains $userName) {
                            $defaultDb = "master"
                        } else {
                            $defaultDb = "tempdb"
                        }
                        Write-Message -Level Verbose -Message "$OrigdefaultDb does not exist on destination. Setting defaultdb to $defaultDb."
                    }

                    Write-Message -Level Verbose -Message "Set $userName defaultdb to $defaultDb."
                    $destLogin.DefaultDatabase = $defaultDb

                    $checkexpiration = "ON"; $checkpolicy = "ON"

                    if ($sourceLogin.PasswordPolicyEnforced -eq $false) { $checkpolicy = "OFF" }

                    if (!$sourceLogin.PasswordExpirationEnabled) { $checkexpiration = "OFF" }

                    $destLogin.PasswordPolicyEnforced = $sourceLogin.PasswordPolicyEnforced
                    $destLogin.PasswordExpirationEnabled = $sourceLogin.PasswordExpirationEnabled

                    # Attempt to add SQL Login User
                    if ($sourceLogin.LoginType -eq "SqlLogin") {
                        $destLogin.LoginType = "SqlLogin"
                        $sourceLoginname = $sourceLogin.name

                        switch ($sourceServer.versionMajor) {
                            0 { $sql = "SELECT CONVERT(VARBINARY(256),password) as hashedpass FROM master.dbo.syslogins WHERE loginname='$sourceLoginname'" }
                            8 { $sql = "SELECT CONVERT(VARBINARY(256),password) as hashedpass FROM dbo.syslogins WHERE name='$sourceLoginname'" }
                            9 { $sql = "SELECT CONVERT(VARBINARY(256),password_hash) as hashedpass FROM sys.sql_logins where name='$sourceLoginname'" }
                            default {
                                $sql = "SELECT CAST(CONVERT(VARCHAR(256), CAST(LOGINPROPERTY(name,'PasswordHash')
                        AS VARBINARY(256)), 1) AS NVARCHAR(max)) AS hashedpass FROM sys.server_principals
                        WHERE principal_id = $($sourceLogin.id)"
                            }
                        }

                        try {
                            $hashedPass = $sourceServer.ConnectionContext.ExecuteScalar($sql)
                        } catch {
                            $hashedPassDt = $sourceServer.Databases['master'].ExecuteWithResults($sql)
                            $hashedPass = $hashedPassDt.Tables[0].Rows[0].Item(0)
                        }

                        if ($hashedPass.GetType().Name -ne "String") {
                            $passString = "0x"; $hashedPass | ForEach-Object { $passString += ("{0:X}" -f $_).PadLeft(2, "0") }
                            $hashedPass = $passString
                        }

                        try {
                            $destLogin.Create($hashedPass, [Microsoft.SqlServer.Management.Smo.LoginCreateOptions]::IsHashed)
                            $destLogin.Refresh()
                            Write-Message -Level Verbose -Message "Successfully added $userName to $destinstance."

                            $copyLoginStatus.Status = "Successful"
                            $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        } catch {
                            try {
                                $sid = "0x"; $sourceLogin.sid | ForEach-Object { $sid += ("{0:X}" -f $_).PadLeft(2, "0") }
                                $sql = "CREATE LOGIN [$userName] WITH PASSWORD = $hashedPass HASHED, SID = $sid,
                                                DEFAULT_DATABASE = [$defaultDb], CHECK_POLICY = $checkpolicy,
                                                CHECK_EXPIRATION = $checkexpiration, DEFAULT_LANGUAGE = [$($sourceLogin.Language)]"

                                $null = $destServer.Query($sql)

                                $destLogin = $destServer.logins[$userName]
                                Write-Message -Level Verbose -Message "Successfully added $userName to $destinstance."

                                $copyLoginStatus.Status = "Successful"
                                $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            } catch {
                                $copyLoginStatus.Status = "Failed"
                                $copyLoginStatus.Notes = (Get-ErrorMessage -Record $_).Message
                                $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                                Stop-Function -Message "Failed to add $userName to $destinstance." -Category InvalidOperation -ErrorRecord $_ -Target $destServer -Continue 3>$null
                            }
                        }
                    }
                    # Attempt to add Windows User
                    elseif ($sourceLogin.LoginType -eq "WindowsUser" -or $sourceLogin.LoginType -eq "WindowsGroup") {
                        Write-Message -Level Verbose -Message "Adding as login type $($sourceLogin.LoginType)"
                        $destLogin.LoginType = $sourceLogin.LoginType

                        Write-Message -Level Verbose -Message "Setting language as $($sourceLogin.Language)"
                        $destLogin.Language = $sourceLogin.Language

                        try {
                            $destLogin.Create()
                            $destLogin.Refresh()
                            Write-Message -Level Verbose -Message "Successfully added $userName to $destinstance."

                            $copyLoginStatus.Status = "Successful"
                            $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        } catch {
                            $copyLoginStatus.Status = "Failed"
                            $copyLoginStatus.Notes = (Get-ErrorMessage -Record $_).Message
                            $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Stop-Function -Message "Failed to add $userName to $destinstance" -Category InvalidOperation -ErrorRecord $_ -Target $destServer -Continue 3>$null
                        }
                    }
                    # This script does not currently support certificate mapped or asymmetric key users.
                    else {
                        Write-Message -Level Verbose -Message "$($sourceLogin.LoginType) logins not supported. $($sourceLogin.name) skipped."

                        $copyLoginStatus.Status = "Skipped"
                        $copyLoginStatus.Notes = "$($sourceLogin.LoginType) not supported"
                        $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        continue
                    }

                    if ($sourceLogin.IsDisabled) {
                        try {
                            $destLogin.Disable()
                        } catch {
                            $copyLoginStatus.Status = "Successful - but could not disable on destination"
                            $copyLoginStatus.Notes = (Get-ErrorMessage -Record $_).Message
                            $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Stop-Function -Message "$userName disabled on source, could not be disabled on $destinstance." -Category InvalidOperation -ErrorRecord $_ -Target $destServer  3>$null
                        }
                    }
                    if ($sourceLogin.DenyWindowsLogin) {
                        try {
                            $destLogin.DenyWindowsLogin = $true
                        } catch {
                            $copyLoginStatus.Status = "Successful - but could not deny login on destination"
                            $copyLoginStatus.Notes = (Get-ErrorMessage -Record $_).Message
                            $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Stop-Function -Message "$userName denied login on source, could not be denied login on $destinstance." -Category InvalidOperation -ErrorRecord $_ -Target $destServer 3>$null
                        }
                    }
                }

                if (-not $ExcludePermissionSync) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Updating SQL login $userName permissions")) {
                        Update-SqlPermission -sourceserver $sourceServer -sourcelogin $sourceLogin -destserver $destServer -destlogin $destLogin
                    }
                }

                if ($LoginRenameHashtable.Keys -contains $userName) {
                    $NewLogin = $LoginRenameHashtable[$userName]

                    if ($Pscmdlet.ShouldProcess($destinstance, "Renaming SQL Login $userName to $NewLogin")) {
                        try {
                            Rename-DbaLogin -SqlInstance $destServer -Login $userName -NewLogin $NewLogin

                            $copyLoginStatus.DestinationLogin = $NewLogin
                            $copyLoginStatus.Status = "Successful"
                            $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                        } catch {
                            $copyLoginStatus.DestinationLogin = $NewLogin
                            $copyLoginStatus.Status = "Failed to rename"
                            $copyLoginStatus.Notes = (Get-ErrorMessage -Record $_).Message
                            $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Stop-Function -Message "Issue renaming $userName to $NewLogin" -Category InvalidOperation -ErrorRecord $_ -Target $destServer 3>$null
                        }
                    }
                }
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        if ($InputObject) {
            $Source = $InputObject[0].Parent.Name
            $Sourceserver = $InputObject[0].Parent
            $Login = $InputObject.Name
        } else {
            try {
                $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
                return
            }
        }
        $sourceVersionMajor = $sourceServer.VersionMajor

        if ($OutFile) {
            Export-DbaLogin -SqlInstance $sourceServer -FilePath $OutFile -Login $Login -ExcludeLogin $ExcludeLogin
            continue
        }

        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-SqlInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $destinstance" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }

            $destVersionMajor = $destServer.VersionMajor
            if ($sourceVersionMajor -gt 10 -and $destVersionMajor -lt 11) {
                Stop-Function -Message "Login migration from version $sourceVersionMajor to $destVersionMajor is not supported." -Target $sourceServer
            }

            if ($sourceVersionMajor -lt 8 -or $destVersionMajor -lt 8) {
                Stop-Function -Message "SQL Server 7 and below are not supported." -Target $sourceServer
            }

            if ($destserver.ConnectionContext.TrueLogin -notin $destserver.Logins.Name -and $Force) {
                if ($Login -or $ExcludeLogin) {
                    Write-Message -Level Verbose -Message "Force was used and $($destserver.ConnectionContext.TrueLogin) not found in logins list but an explicit Login or ExcludeLogin was specified, so we trust you won't drop the group that allows $($destserver.ConnectionContext.TrueLogin) access. Proceeding."
                } else {
                    Stop-Function -Message "Force was used, no explicit -Login or -ExcludeLogin was specified and $($destserver.ConnectionContext.TrueLogin) cannot be found in the logins list. It may be part of a group. This will likely result in you being locked out of the server. To use Force, $($destserver.ConnectionContext.TrueLogin) must be added directly to logins before proceeding." -Target $destserver
                    continue
                }
            }

            Write-Message -Level Verbose -Message "Attempting Login Migration."
            Copy-Login -sourceserver $sourceServer -destserver $destServer -Login $Login -Exclude $ExcludeLogin

            if ($SyncSaName) {
                $sa = $sourceServer.Logins | Where-Object id -eq 1
                $destSa = $destServer.Logins | Where-Object id -eq 1
                $saName = $sa.Name
                if ($saName -ne $destSa.name) {
                    Write-Message -Level Verbose -Message "Changing sa username to match source ($saName)."
                    if ($Pscmdlet.ShouldProcess($destinstance, "Changing sa username to match source ($saName)")) {
                        $destSa.Rename($saName)
                        $destSa.Alter()
                    }
                }
            }
        }
    }
}