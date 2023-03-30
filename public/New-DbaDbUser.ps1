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

    .PARAMETER Password
        When specified, the user will be created as a contained user. Standalone databases partial containment should be turned on to succeed. By default, in Azure SQL databases this is turned on.

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

    .EXAMPLE
        PS C:\> New-DbaDbUser -SqlInstance sqlserver2014 -Database DB1 -Username user1 -Password (ConvertTo-SecureString -String "DBATools" -AsPlainText)

        Creates a new cointained sql user named user1 in the database given database with the password specified.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param(
        [parameter(Mandatory = $True, Position = 1)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [switch]$IncludeSystem = $False,
        [Parameter(ParameterSetName = "Login", Mandatory = $True)]
        [string]$Login,
        [Parameter(ParameterSetName = "Login", Mandatory = $False)]
        [Parameter(ParameterSetName = "NoLogin", Mandatory = $True)]
        [Parameter(ParameterSetName = "ContainedSQLUser", Mandatory = $True)]
        [Parameter(ParameterSetName = "ContainedAADUser", Mandatory = $True)]
        [string]$Username,
        [string]$DefaultSchema = 'dbo',
        [Parameter(ParameterSetName = "ContainedSQLUser", Mandatory = $True)]
        [securestring]$Password,
        [Parameter(ParameterSetName = "ContainedAADUser", Mandatory = $True)]
        [switch]$ExternalProvider,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        $connParam = @{ }
        if ($SqlCredential) { $connParam.SqlCredential = $SqlCredential }

        # is this required?
        if ($Force) { $ConfirmPreference = 'none' }

        # When user is created from login and no user name is provided then login name will be used as the user name
        if ($Login -and -not($Username)) {
            $Username = $Login
        }

        #Set appropriate user type
        #Removed SQLLogin  user type. This is deprecated and the alternate is to map to SqlUser. Reference https://learn.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.usertype?view=sql-smo-160
        if ($ExternalProvider) {
            Write-Message -Level Verbose -Message "Using UserType: External"
            $userType = [Microsoft.SqlServer.Management.Smo.UserType]::External
        } elseif ($Password -or $Login) {
            Write-Message -Level Verbose -Message "Using UserType: SqlUser"
            $userType = [Microsoft.SqlServer.Management.Smo.UserType]::SqlUser
        } else {
            Write-Message -Level Verbose -Message "Using UserType: NoLogin"
            $userType = [Microsoft.SqlServer.Management.Smo.UserType]::NoLogin
        }
    }

    process {

        foreach ($instance in $SqlInstance) {
            #prepare parameter values
            $connParam.SqlInstance = $instance
            $getDbParam = $connParam.Clone()
            $getDbParam.OnlyAccessible = $True
            if ($Database) { $getDbParam.Database = $Database }
            if ($ExcludeDatabase) { $getDbParam.ExcludeDatabase = $ExcludeDatabase }
            if (-not ($IncludeSystem)) { $getDbParam.ExcludeSystem = $True }

            # Is the login exist?
            if ($Login -and (-not(Get-DbaLogin @connParam -Login $Login))) {
                Stop-Function -Message "Invalid Login: [$Login] is not found on [$instance], skipping." -Target $instance -Continue -EnableException $False
            }

            $databases = Get-DbaDatabase @getDbParam
            $getValidSchema = Get-DbaDbSchema -InputObject $databases -Schema $DefaultSchema -IncludeSystemSchemas

            foreach ($db in $Database) {
                $dbSmo = $databases | Where-Object Name -eq $db

                #Check if the database exists and online
                if (-not($dbSmo)) {
                    Stop-Function -Message "Invalid Database: [$db] is not found in the instance [$instance], skipping." -Continue -EnableException $False
                }
                #prepare user query param
                $userParam = $connParam.Clone()
                $userParam.Database = $dbSmo.name
                $userParam.User = $Username

                #check if the schema exists
                if ($dbSmo.Name -in ($getValidSchema).Parent.Name) {
                    if ($Pscmdlet.ShouldProcess($dbSmo, "Creating user $Username")) {
                        Write-Message -Level Verbose -Message "Add user [$Username] to database [$dbSmo] on [$instance]"

                        #smo param builder
                        $smoUser = New-Object Microsoft.SqlServer.Management.Smo.User
                        $smoUser.Parent = $dbSmo
                        $smoUser.Name = $Username
                        if ($Login) { $smoUser.Login = $Login }
                        $smoUser.UserType = $userType
                        $smoUser.DefaultSchema = $DefaultSchema

                        #Check if the user exists already
                        $userExists = Get-DbaDbUser @userParam
                        if ($userExists -and -not($Force)) {
                            Stop-Function -Message "User [$Username] already exists in the database $dbSmo on [$instance] and -Force was not specified, skipping." -Target $Username -Continue -EnableException $False
                        } elseif ($userExists -and $Force) {
                            try {
                                Write-Message -Level Verbose -Message "FORCE is used, user [$Username] will be dropped in the database $dbSmo on [$instance]"
                                Remove-DbaDbUser @userParam -Force
                            } catch {
                                Stop-Function -Message "Could not remove existing user [$Username] in the database $dbSmo on [$instance], skipping." -Target $User -ErrorRecord $_ -Continue
                            }
                        }

                        #Create the user
                        try {
                            if ($Password) {
                                $smoUser.Create($Password)
                            } else { $smoUser.Create() }
                            #Verfiy the user creation
                            Get-DbaDbUser @userParam
                        } catch {
                            Stop-Function -Message "Failed to add user [$Username] in $dbSmo to [$instance]" -Category InvalidOperation -ErrorRecord $_ -Target $instance -Continue
                        }

                    }
                } else {
                    Stop-Function -Message "Invalid DefaultSchema: [$DefaultSchema] is not found in the database $dbSmo on [$instance], skipping." -Continue -EnableException $False
                }
            }
        }
    }
}