function Sync-DbaLoginPassword {
    <#
    .SYNOPSIS
        Synchronizes SQL Server login passwords between instances using hashed password values.

    .DESCRIPTION
        Syncs SQL Server authentication login passwords from a source to destination instance(s) without requiring knowledge of the actual passwords. Uses the same technique as Microsoft's sp_help_revlogin by extracting and applying hashed password values.

        This is particularly useful for:
        - Maintaining consistent passwords across Availability Group replicas
        - Migrating logins between instances when users cannot provide their passwords
        - Disaster recovery scenarios where password synchronization is critical
        - Keeping development/test environments synchronized with production passwords

        The function only works with SQL Server authentication logins. Windows authentication logins are automatically skipped since their authentication is handled by Active Directory. The login must already exist on the destination instance(s) - this function only updates passwords, it does not create new logins.

    .PARAMETER Source
        Specifies the source SQL Server instance to read login passwords from. The login password hashes will be extracted from this instance.
        You must have sysadmin access and the server version must be SQL Server 2000 or higher.

    .PARAMETER SourceSqlCredential
        Specifies alternative credentials to connect to the source SQL Server instance. Use this when your current Windows credentials don't have sysadmin access to the source server.
        Accepts PowerShell credentials created with Get-Credential. Supports Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated.
        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Specifies the destination SQL Server instance(s) where login passwords will be updated. Accepts multiple instances to sync passwords to several servers simultaneously.
        The logins must already exist on the destination - this function only syncs passwords, not the logins themselves. You must have sysadmin access and the server must be SQL Server 2005 or higher.

    .PARAMETER DestinationSqlCredential
        Specifies alternative credentials to connect to the destination SQL Server instance(s). Use this when your current Windows credentials don't have sysadmin access to the destination server(s).
        Accepts PowerShell credentials created with Get-Credential. Supports Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated.
        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Specifies login objects from the pipeline to sync passwords for. Accepts login objects from Get-DbaLogin.
        When using InputObject, only SQL Server authentication logins will be processed - Windows authentication logins are automatically filtered out.
        This parameter enables pipeline scenarios where you can filter logins first and then sync their passwords.

    .PARAMETER Login
        Specifies which specific logins to sync passwords for. Use this when you only want to sync passwords for certain accounts rather than all SQL logins.
        Accepts multiple login names as an array. Only SQL Server authentication logins will be processed - Windows logins are automatically skipped.

    .PARAMETER ExcludeLogin
        Specifies login names to exclude from the password sync process. Use this to skip specific accounts that shouldn't have their passwords synced.
        Commonly used to exclude service accounts, application accounts, or logins with environment-specific passwords that should remain different between servers.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Login, Password
        Author: Shawn Melton (@wsmelton), http://www.wsmelton.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires sysadmin access on both source and destination instances.

    .LINK
        https://dbatools.io/Sync-DbaLoginPassword

    .EXAMPLE
        PS C:\> Sync-DbaLoginPassword -Source sql2016 -Destination sql2016ag1, sql2016ag2

        Syncs all SQL Server authentication login passwords from sql2016 to sql2016ag1 and sql2016ag2. Windows authentication logins are automatically skipped.

    .EXAMPLE
        PS C:\> Sync-DbaLoginPassword -Source sql2016 -Destination sql2016ag1 -Login app_user, reports_user

        Syncs passwords only for the app_user and reports_user logins from sql2016 to sql2016ag1.

    .EXAMPLE
        PS C:\> Sync-DbaLoginPassword -Source sql2016 -Destination sql2016ag1 -ExcludeLogin sa, admin

        Syncs all SQL Server login passwords except for sa and admin accounts from sql2016 to sql2016ag1.

    .EXAMPLE
        PS C:\> $splatSync = @{
        >>     Source                     = "sql2016"
        >>     Destination                = "sql2016ag1", "sql2016ag2"
        >>     SourceSqlCredential        = $sourceCred
        >>     DestinationSqlCredential   = $destCred
        >>     EnableException            = $true
        >> }
        PS C:\> Sync-DbaLoginPassword @splatSync

        Syncs all SQL Server login passwords using SQL Authentication credentials for both source and destination connections. Throws exceptions on errors for easier scripting and automation.

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 | Where-Object LoginType -eq "SqlLogin" | Sync-DbaLoginPassword -Destination sql2016ag1

        Gets all SQL Server authentication logins from sql2016 and syncs their passwords to sql2016ag1 using pipeline input.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
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
            # Use logins from pipeline
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
                    MinimumVersion = 9
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

                if ($PSCmdlet.ShouldProcess($dest, "Syncing password for login $loginName")) {
                    try {
                        # Get the password hash from source
                        $passwordHash = Get-LoginPasswordHash -Login $sourceLogin

                        if (-not $passwordHash) {
                            Write-Message -Level Warning -Message "Failed to retrieve password hash for login $loginName from source. Skipping."
                            continue
                        }

                        # Apply the password hash to destination
                        $splatSetLogin = @{
                            SqlInstance     = $destServer
                            Login           = $loginName
                            PasswordHash    = $passwordHash
                            EnableException = $true
                        }
                        $result = Set-DbaLogin @splatSetLogin

                        [PSCustomObject]@{
                            SourceServer      = $sourceServer.Name
                            DestinationServer = $destServer.Name
                            Login             = $loginName
                            Status            = "Success"
                            Notes             = $null
                        }
                    } catch {
                        $errorMessage = $_.Exception.Message
                        Stop-Function -Message "Failed to sync password for login $loginName on $dest : $errorMessage" -ErrorRecord $_ -Target $loginName -Continue

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
