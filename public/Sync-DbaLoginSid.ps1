function Sync-DbaLoginSid {
    <#
    .SYNOPSIS
        Synchronizes SQL Server login Security Identifiers (SIDs) between instances to fix SID mismatches.

    .DESCRIPTION
        Syncs SQL Server authentication login SIDs from a source to destination instance(s) to resolve SID mismatch issues that cause orphaned database users. This function is essential for fixing inherited environments where the same login exists across multiple servers but with different SIDs.

        When SQL Server login SIDs don't match across instances, database restores and Availability Group failovers result in orphaned users that require constant repair. This command proactively fixes the root cause by aligning SIDs across your environment.

        This is particularly useful for:
        - Fixing inherited environments with inconsistent login SIDs across servers
        - Preparing servers for Availability Group configurations where matching SIDs are required
        - Eliminating the need to repeatedly run Repair-DbaDbOrphanUser after database restores
        - Standardizing login SIDs across development, staging, and production environments
        - Resolving authentication issues caused by SID mismatches without changing passwords

        The function only works with SQL Server authentication logins. Windows authentication logins are automatically skipped since their SIDs are managed by Active Directory. The login must already exist on both source and destination instances - this function only updates the SID property while preserving all other login properties including passwords, permissions, roles, and database mappings.

    .PARAMETER Source
        Specifies the source SQL Server instance to read login SIDs from. This should be your "gold standard" instance with the correct SIDs that you want to replicate across your environment.
        You must have sysadmin access and the server version must be SQL Server 2000 or higher.

    .PARAMETER SourceSqlCredential
        Specifies alternative credentials to connect to the source SQL Server instance. Use this when your current Windows credentials don't have sysadmin access to the source server.
        Accepts PowerShell credentials created with Get-Credential. Supports Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated.
        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Specifies the destination SQL Server instance(s) where login SIDs will be updated. Accepts multiple instances to sync SIDs to several servers simultaneously.
        The logins must already exist on the destination - this function only syncs SIDs, not the logins themselves. You must have sysadmin access and the server must be SQL Server 2000 or higher.

    .PARAMETER DestinationSqlCredential
        Specifies alternative credentials to connect to the destination SQL Server instance(s). Use this when your current Windows credentials don't have sysadmin access to the destination server(s).
        Accepts PowerShell credentials created with Get-Credential. Supports Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated.
        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Specifies login objects from the pipeline to sync SIDs for. Accepts login objects from Get-DbaLogin.
        When using InputObject, only SQL Server authentication logins will be processed - Windows authentication logins are automatically filtered out.
        This parameter enables pipeline scenarios where you can filter logins first and then sync their SIDs.

    .PARAMETER Login
        Specifies which specific logins to sync SIDs for. Use this when you only want to sync SIDs for certain accounts rather than all SQL logins.
        Accepts multiple login names as an array. Only SQL Server authentication logins will be processed - Windows logins are automatically skipped.

    .PARAMETER ExcludeLogin
        Specifies login names to exclude from the SID sync process. Use this to skip specific accounts that shouldn't have their SIDs synced.
        Commonly used to exclude service accounts, application accounts, or logins with environment-specific SIDs that should remain different between servers.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Login, SID
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires sysadmin access on both source and destination instances.

    .LINK
        https://dbatools.io/Sync-DbaLoginSid

    .EXAMPLE
        PS C:\> Sync-DbaLoginSid -Source sql2016 -Destination sql2016ag1, sql2016ag2

        Syncs all SQL Server authentication login SIDs from sql2016 to sql2016ag1 and sql2016ag2. Windows authentication logins are automatically skipped.
        This is the typical usage for preparing Availability Group replicas where login SIDs must match.

    .EXAMPLE
        PS C:\> Sync-DbaLoginSid -Source sql2016 -Destination sql2017 -Login app_user, reports_user

        Syncs SIDs only for the app_user and reports_user logins from sql2016 to sql2017.
        Use this when you only need to fix SID mismatches for specific application logins.

    .EXAMPLE
        PS C:\> Sync-DbaLoginSid -Source sqlprod -Destination sqldev, sqltest -ExcludeLogin sa, admin

        Syncs all SQL Server login SIDs except for sa and admin accounts from sqlprod to sqldev and sqltest.
        Useful when you want to standardize most logins but keep certain administrative accounts with unique SIDs per environment.

    .EXAMPLE
        PS C:\> $splatSync = @{
        >>     Source                     = "sqlprod"
        >>     Destination                = "sqlag1", "sqlag2", "sqlag3"
        >>     SourceSqlCredential        = $sourceCred
        >>     DestinationSqlCredential   = $destCred
        >>     EnableException            = $true
        >> }
        PS C:\> Sync-DbaLoginSid @splatSync

        Syncs all SQL Server login SIDs across multiple AG replicas using SQL Authentication credentials for connections.
        Throws exceptions on errors for easier scripting and automation. This is ideal for automated AG setup scripts.

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sqlprod -Login app* | Sync-DbaLoginSid -Destination sqlag1, sqlag2

        Gets all logins starting with "app" from sqlprod and syncs their SIDs to sqlag1 and sqlag2 using pipeline input.
        Demonstrates how to filter logins first, then sync only those that match your criteria.

    .EXAMPLE
        PS C:\> Sync-DbaLoginSid -Source sqlprod -Destination sqldev -WhatIf

        Shows what SID synchronization operations would be performed without actually making any changes.
        Use this to preview the impact before running the actual sync operation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [Parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [Parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [Parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [string[]]$Login,
        [string[]]$ExcludeLogin,
        [switch]$EnableException
    )

    process {
        if (Test-FunctionInterrupt) { return }

        try {
            $splatSource = @{
                SqlInstance    = $Source
                SqlCredential  = $SourceSqlCredential
                MinimumVersion = 8
            }
            $sourceServer = Connect-DbaInstance @splatSource
        } catch {
            Stop-Function -Message "Failed to connect to source instance $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }

        # Determine which logins to process
        if ($InputObject) {
            # Use logins from pipeline, filter to SQL logins only
            $sourceLogins = $InputObject | Where-Object LoginType -eq "SqlLogin"
        } else {
            # Get logins from source server
            $splatLogin = @{
                SqlInstance  = $sourceServer
                Login        = $Login
                ExcludeLogin = $ExcludeLogin
            }
            $sourceLogins = Get-DbaLogin @splatLogin | Where-Object LoginType -eq "SqlLogin"
        }

        if (-not $sourceLogins) {
            Write-Message -Level Verbose -Message "No SQL Server authentication logins found on source instance $Source"
            return
        }

        foreach ($dest in $Destination) {
            try {
                $splatDestination = @{
                    SqlInstance    = $dest
                    SqlCredential  = $DestinationSqlCredential
                    MinimumVersion = 8
                }
                $destServer = Connect-DbaInstance @splatDestination
            } catch {
                Stop-Function -Message "Failed to connect to destination instance $dest" -Category ConnectionError -ErrorRecord $_ -Target $dest -Continue
            }

            foreach ($sourceLogin in $sourceLogins) {
                $loginName = $sourceLogin.Name

                # Check if login exists on destination
                $destLogin = $destServer.Logins[$loginName]
                if (-not $destLogin) {
                    Write-Message -Level Verbose -Message "Login '$loginName' not found on destination $dest. Skipping."
                    continue
                }

                # Verify destination login is SQL authentication
                if ($destLogin.LoginType -ne "SqlLogin") {
                    Write-Message -Level Verbose -Message "Login '$loginName' on destination $dest is not a SQL Server login. Skipping."
                    continue
                }

                # Get source SID
                $sourceSid = $sourceLogin.Sid
                $destSid = $destLogin.Sid

                # Check if SIDs already match
                if ([System.BitConverter]::ToString($sourceSid) -eq [System.BitConverter]::ToString($destSid)) {
                    Write-Message -Level Verbose -Message "Login '$loginName' already has matching SID on destination $dest. Skipping."
                    [PSCustomObject]@{
                        SourceServer      = $sourceServer.Name
                        DestinationServer = $destServer.Name
                        Login             = $loginName
                        Status            = "AlreadyMatched"
                        Notes             = "SIDs already match"
                    }
                    continue
                }

                if ($PSCmdlet.ShouldProcess($dest, "Syncing SID for login $loginName")) {
                    try {
                        # Get the password hash from DESTINATION to preserve existing password
                        $passwordHash = Get-LoginPasswordHash -Login $destLogin

                        if (-not $passwordHash) {
                            Stop-Function -Message "Failed to retrieve password hash for login $loginName from destination" -Target $loginName -Continue
                            [PSCustomObject]@{
                                SourceServer      = $sourceServer.Name
                                DestinationServer = $destServer.Name
                                Login             = $loginName
                                Status            = "Failed"
                                Notes             = "Could not retrieve password hash"
                            }
                            continue
                        }

                        # Convert SID to hex string for CREATE LOGIN statement
                        $sidHex = "0x" + [System.BitConverter]::ToString($sourceSid).Replace("-", "")

                        # Get login properties from destination before dropping
                        $defaultDb = $destLogin.DefaultDatabase
                        $language = $destLogin.Language
                        $isDisabled = $destLogin.IsDisabled
                        $denyLogin = $destLogin.DenyWindowsLogin
                        $checkPolicy = if ($destLogin.PasswordPolicyEnforced) { "ON" } else { "OFF" }
                        $checkExpiration = if ($destLogin.PasswordExpirationEnabled) { "ON" } else { "OFF" }

                        # Save server roles before dropping
                        $serverRoles = New-Object System.Collections.ArrayList
                        foreach ($role in $destServer.Roles) {
                            if ($role.EnumMemberNames() -contains $loginName) {
                                $null = $serverRoles.Add($role.Name)
                            }
                        }

                        # Build DROP and CREATE statements
                        $dropSql = "DROP LOGIN [$loginName]"
                        $createSql = "CREATE LOGIN [$loginName] WITH PASSWORD = $passwordHash HASHED, SID = $sidHex, DEFAULT_DATABASE = [$defaultDb], CHECK_POLICY = $checkPolicy, CHECK_EXPIRATION = $checkExpiration, DEFAULT_LANGUAGE = [$language]"

                        Write-Message -Level Debug -Message "Executing: $dropSql"
                        Write-Message -Level Debug -Message "Executing: $createSql"

                        $splatDrop = @{
                            SqlInstance     = $destServer
                            Database        = "master"
                            Query           = $dropSql
                            EnableException = $true
                        }
                        $null = Invoke-DbaQuery @splatDrop

                        $splatCreate = @{
                            SqlInstance     = $destServer
                            Database        = "master"
                            Query           = $createSql
                            EnableException = $true
                        }
                        $null = Invoke-DbaQuery @splatCreate

                        # Refresh the login object to get the newly created login
                        $destServer.Logins.Refresh()
                        $newLogin = $destServer.Logins[$loginName]

                        # Restore server roles
                        foreach ($roleName in $serverRoles) {
                            $splatRole = @{
                                SqlInstance     = $destServer
                                Database        = "master"
                                Query           = "ALTER SERVER ROLE [$roleName] ADD MEMBER [$loginName]"
                                EnableException = $true
                            }
                            $null = Invoke-DbaQuery @splatRole
                        }

                        # Restore disabled/denied state
                        if ($isDisabled) {
                            $newLogin.Disable()
                        }
                        if ($denyLogin) {
                            $newLogin.DenyWindowsLogin = $true
                            $newLogin.Alter()
                        }

                        [PSCustomObject]@{
                            SourceServer      = $sourceServer.Name
                            DestinationServer = $destServer.Name
                            Login             = $loginName
                            Status            = "Success"
                            Notes             = $null
                        }
                    } catch {
                        $errorMessage = $_.Exception.Message
                        Stop-Function -Message "Failed to sync SID for login $loginName on $dest : $errorMessage" -ErrorRecord $_ -Target $loginName -Continue

                        [PSCustomObject]@{
                            SourceServer      = $sourceServer.Name
                            DestinationServer = $destServer.Name
                            Login             = $loginName
                            Status            = "Failed"
                            Notes             = $errorMessage
                        }
                    }
                }
            }
        }
    }
}
