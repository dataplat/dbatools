function New-DbaDbUser {
    <#
    .SYNOPSIS
        Creates a new user for the specified database.

    .DESCRIPTION
        Creates a new user for a specified database with provided specifications.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to the default instance on localhost.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database(s) to process. Options for this list are auto-populated from the server. If unspecified, all user databases will be processed.

    .PARAMETER ExcludeDatabase
        Specifies the database(s) to exclude from processing. Options for this list are auto-populated from the server. By default, system databases are excluded.

    .PARAMETER IncludeSystem
        If this switch is enabled, the user will be added to system databases. This switch will be ignored if -Database is used.

    .PARAMETER Login
        When specified, the user will be associated to this SQL login and have the same name as the Login.

    .PARAMETER Username
        When specified, the user will have this name.

    .PARAMETER DefaultSchema
        The default database schema for the user. If not specified this value will default to dbo.

    .PARAMETER ExternalProvider
        Specifies that the user is for Azure AD Authentication.
        Equivalent to T-SQL: 'CREATE USER [claudio@********.onmicrosoft.com] FROM EXTERNAL PROVIDER`

    .PARAMETER Force
        If user exists, drop and recreate.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, User
        Author: Frank Henninger (@osiris687) | Andreas Jordan (@JordanOrdix), ordix.de

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaDbUser

    .EXAMPLE
        PS C:\> New-DbaDbUser -SqlInstance sqlserver2014 -Database DB1 -Login user1

        Creates a new sql user with login named user1 in the specified database.

    .EXAMPLE
        PS C:\> New-DbaDbUser -SqlInstance sqlserver2014 -Database DB1 -Username user1

        Creates a new sql user without login named user1 in the specified database.

    .EXAMPLE
        PS C:\> New-DbaDbUser -SqlInstance sqlserver2014 -Database DB1 -Login Login1 -Username user1

        Creates a new sql user named user1 mapped to Login1 in the specified database.

    .EXAMPLE
        PS C:\> New-DbaDbUser -SqlInstance sqlserver2014 -Database DB1 -Login Login1 -Username user1 -DefaultSchema schema1

        Creates a new sql user named user1 mapped to Login1 in the specified database and specifies the default schema to be schema1.

    .EXAMPLE
        PS C:\> New-DbaDbUser -SqlInstance sqlserver2014 -Database DB1 -Username "claudio@********.onmicrosoft.com" -ExternalProvider

        Creates a new sql user named 'claudio@********.onmicrosoft.com' mapped to Azure Active Directory (AAD) in the specified database.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param(
        [parameter(Mandatory, Position = 1)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [switch]$IncludeSystem,
        [string]$Login,
        [string]$Username = $Login,
        [string]$DefaultSchema = 'dbo',
        [switch]$ExternalProvider,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        function Remove-User {
            param (
                [Microsoft.SqlServer.Management.Smo.User]$User
            )
            if ($Force) {
                if ($Pscmdlet.ShouldProcess($User, "Dropping existing user $($User.Name) in the database $($User.Parent.Name) on $instance because -Force was used")) {
                    try {
                        $User.Drop()
                    } catch {
                        Stop-Function -Message "Could not remove existing user $($User.Name) in the database $($User.Parent.Name) on $instance, skipping." -Target $User -ErrorRecord $_ -Continue
                    }
                }
            } else {
                Stop-Function -Message "User $($User.Name) already exists in the database $($User.Parent.Name) on $instance and -Force was not specified, skipping." -Target $User -Continue
            }
        }
    }

    process {
        if (-not $Login -and -not $Username) {
            Stop-Function -Message "One of -Login or -Username is needed."
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Does the given login exist?
            if ($Login) {
                $existingLogin = $server.Logins | Where-Object Name -eq $Login
                if (-not $existingLogin) {
                    Stop-Function -Message "Invalid Login: $Login is not found on $instance, skipping." -Target $instance -Continue
                }
            }

            $databases = $server.Databases | Where-Object IsAccessible -eq $true

            if ($Database) {
                $databases = $databases | Where-Object Name -In $Database
            } else {
                if (-not $IncludeSystem) {
                    $databases = $databases | Where-Object IsSystemObject -ne $true
                }
            }
            if ($ExcludeDatabase) {
                $databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $databases) {
                Write-Message -Level Verbose -Message "Add user $Username to database $db on $instance"

                # Does a schema exist with the given name?
                $existingSchema = $db.Schemas | Where-Object Name -eq $DefaultSchema
                if (-not $existingSchema) {
                    Stop-Function -Message "Invalid DefaultSchema: $DefaultSchema is not found in the database $db on $instance, skipping." -Continue
                }

                # Does a user exist with the given name?
                $existingUser = $db.Users | Where-Object Name -eq $Username
                if ($existingUser) {
                    Remove-User -User $existingUser
                }

                if ($ExternalProvider) {
                    Write-Message -Level Verbose -Message "Using UserType: External"
                    $userType = [Microsoft.SqlServer.Management.Smo.UserType]::External
                } elseif ($Login) {
                    # Does a user exist with same login?
                    $existingUser = $db.Users | Where-Object Login -eq $Login
                    if ($existingUser) {
                        Remove-User -User $existingUser
                    }

                    Write-Message -Level Verbose -Message "Using UserType: SqlLogin"
                    $userType = [Microsoft.SqlServer.Management.Smo.UserType]::SqlLogin
                } else {
                    Write-Message -Level Verbose -Message "Using UserType: NoLogin"
                    $userType = [Microsoft.SqlServer.Management.Smo.UserType]::NoLogin
                }

                if ($Pscmdlet.ShouldProcess($db, "Creating user $Username")) {
                    try {
                        if ($ExternalProvider) {
                            # Due to a bug at the time of writing, the user is created using T-SQL
                            # More info at: https://github.com/microsoft/sqlmanagementobjects/issues/112
                            $sql = "CREATE USER [$Username] FROM EXTERNAL PROVIDER WITH DEFAULT_SCHEMA = [$DefaultSchema]"
                            $db.Query($sql)
                            # Refresh the user list otherwise won't appear in the list
                            $db.Users.Refresh()
                        } else {
                            $smoUser = New-Object Microsoft.SqlServer.Management.Smo.User
                            $smoUser.Parent = $db
                            $smoUser.Name = $Username
                            $smoUser.Login = $Login
                            $smoUser.UserType = $userType
                            $smoUser.DefaultSchema = $DefaultSchema

                            $smoUser.Create()
                        }
                        Write-Message -Level Verbose -Message "Successfully added $Username in $db to $instance."

                        # Display Results
                        Get-DbaDbUser -SqlInstance $server -Database $db.Name -User $Username
                    } catch {
                        Stop-Function -Message "Failed to add user $Username in $db to $instance" -Category InvalidOperation -ErrorRecord $_ -Target $instance -Continue
                    }
                }
            }
        }
    }
}