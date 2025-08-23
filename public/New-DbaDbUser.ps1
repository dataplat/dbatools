function New-DbaDbUser {
    <#
    .SYNOPSIS
        Creates database users with support for SQL logins, contained users, and Azure AD authentication.

    .DESCRIPTION
        Creates database users across one or more databases, supporting multiple authentication types including traditional SQL login mapping, contained users with passwords, and Azure Active Directory external provider authentication. This command handles the common DBA task of provisioning database access without requiring manual T-SQL scripts for each database. You can create users mapped to existing SQL logins, standalone contained users for partially contained databases, or Azure AD users for cloud environments. The function automatically validates that specified logins and schemas exist before attempting user creation.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to create the user in. Accepts multiple database names separated by commas.
        If not specified, the user will be created in all user databases on the instance.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from user creation when processing all databases on an instance.
        Use this to skip databases where you don't want the user created, such as read-only or archived databases.

    .PARAMETER IncludeSystem
        Creates the user in system databases (master, model, msdb, tempdb) in addition to user databases.
        Typically used when creating maintenance or administrative users that need access to system databases.

    .PARAMETER User
        Sets the name of the database user to be created. Required for contained users, external provider users, and users without logins.
        If not specified when using -Login, the user name will match the login name.

    .PARAMETER Login
        Maps the database user to an existing SQL Server login for authentication.
        The login must already exist on the instance before creating the user.

    .PARAMETER Password
        Creates a contained database user with the specified password, allowing authentication without a server-level login.
        The database must have containment enabled (partial containment) for this to work. Azure SQL databases have this enabled by default.

    .PARAMETER ExternalProvider
        Creates a user for Azure Active Directory authentication in Azure SQL databases or SQL Server with AAD integration.
        The User parameter should contain the full AAD principal name (user@domain.com or groupname).

    .PARAMETER DefaultSchema
        Sets the default schema that will be used when the user creates objects without specifying a schema.
        Defaults to 'dbo' if not specified. The schema must already exist in the target database.

    .PARAMETER Force
        Drops and recreates the user if it already exists in the database.
        Use this when you need to reset a user's properties or when automation scripts need to ensure a clean user state.

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

        Creates a new sql user named user1 for the login user1 in the database DB1.

    .EXAMPLE
        PS C:\> New-DbaDbUser -SqlInstance sqlserver2014 -Database DB1 -User user1

        Creates a new sql user named user1 without login in the database DB1.

    .EXAMPLE
        PS C:\> New-DbaDbUser -SqlInstance sqlserver2014 -Database DB1 -User user1 -Login login1

        Creates a new sql user named user1 for the login login1 in the database DB1.

    .EXAMPLE
        PS C:\> New-DbaDbUser -SqlInstance sqlserver2014 -Database DB1 -User user1 -Login Login1 -DefaultSchema schema1

        Creates a new sql user named user1 for the login login1 in the database DB1 and specifies the default schema to be schema1.

    .EXAMPLE
        PS C:\> New-DbaDbUser -SqlInstance sqlserver2014 -Database DB1 -User "claudio@********.onmicrosoft.com" -ExternalProvider

        Creates a new sql user named 'claudio@********.onmicrosoft.com' mapped to Azure Active Directory (AAD) in the database DB1.

    .EXAMPLE
        PS C:\> New-DbaDbUser -SqlInstance sqlserver2014 -Database DB1 -Username user1 -Password (ConvertTo-SecureString -String "DBATools" -AsPlainText -Force)

        Creates a new contained sql user named user1 in the database DB1 with the password specified.
    #>

    ### This command has more comments than other commands, because it should act as an example for other commands.
    ### These extra lines start with "###" and should help new contributors to understand why we code the way we do.

    ### All commands that change objects must use SupportsShouldProcess to support -WhatIf.
    ### All commands that add or change objects (New-... or Set-...) must use ConfirmImpact = "Medium".
    ### All commands that drop existing objects (Remove-...) must use ConfirmImpact = "High".
    ### For most of the commands, we try to not use parameter sets and try to check valid parameter combinations inside of the command to be able to give the user a "nice" feedback.
    ### But this is an example of a command that uses parameter sets, which gives better help output.
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param(
        ### All commands that need a connection to an instance use the following two parameters in the way we define here.
        ### This supports parameter by position for the parameter SqlInstance and makes this a mandatory parameter.
        ### Exception: Some commands allow pipeline input, in this case the parameter is not mandatory.
        [Parameter(Mandatory, Position = 1)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        ### All commands that need to work with databases or database objects use the following three parameters.
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [switch]$IncludeSystem,
        ### The following parameters are specific to the objects that the command works with, in this case a database user.
        ### We start with the name of the object, in this case the name of the user that will be created.
        ### For the default parameter set Login, the name of the user can be set to the mandatory parameter Login, in all other cases, we need the name of the user.
        [Parameter(ParameterSetName = "Login")]
        [Parameter(Mandatory, ParameterSetName = "NoLogin")]
        [Parameter(Mandatory, ParameterSetName = "ContainedSQLUser")]
        [Parameter(Mandatory, ParameterSetName = "ContainedAADUser")]
        [Alias("Username")]
        [string]$User,
        ### Now we add parameters to specify the individual attributes for the object. We start with parameters that are mandatory for parameter sets.
        [Parameter(Mandatory, ParameterSetName = "Login")]
        [string]$Login,
        ### If we need to pass a password to the command, we always use the type securestring and name the parameter SecurePassword. Here we only use the alias for backwords compatibility.
        [Parameter(Mandatory, ParameterSetName = "ContainedSQLUser")]
        [Alias("Password")]
        [securestring]$SecurePassword,
        [Parameter(Mandatory, ParameterSetName = "ContainedAADUser")]
        [switch]$ExternalProvider,
        ### Now we add parameters to specify the individual attributes for the object that are not specific for a parameter set.
        ### As we want to use the schema dbo in most cases, we use default values in those cases.
        [string]$DefaultSchema = 'dbo',
        ### All commands that create new objects have a switch parameter Force to drop and re-create the object in case it already exists.
        ### Sometimes, this parameter also changes the ConfirmPreference to "none". This way, -WhatIf and -Force cannot be used together. So this has to be removed everywhere.
        ### This parameter is always the second last parameter.
        [switch]$Force,
        ### All public commands have a switch parameter called EnableException as the last parameter. This changes the behavior of Stop-Function inside of the command.
        [switch]$EnableException
    )

    begin {
        ### To help analyzing bugs in commands using parameter sets, we write the used parameter set to verbose output.
        Write-Message -Level Verbose -Message "Using parameter set $($PSCmdlet.ParameterSetName)."

        ### To help analyzing bugs, we write at least one line to verbose output per code path. This can also be used as a kind of comment.
        ### Changing parameter values is only allowed in the begin block, so that every execution of the process block or the instance loop in the process block has the same set of parameter values.
        if ($Login -and -not $User) {
            Write-Message -Level Verbose -Message "No user name provided, so login name [$Login] will be used as user name."
            $User = $Login
        }

        # Set appropriate user type based on provided parameters.
        # See https://learn.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.usertype for details.
        if ($ExternalProvider) {
            Write-Message -Level Verbose -Message "Using UserType [External]."
            $userType = [Microsoft.SqlServer.Management.Smo.UserType]::External
        } elseif ($SecurePassword -or $Login) {
            Write-Message -Level Verbose -Message "Using UserType [SqlUser]."
            $userType = [Microsoft.SqlServer.Management.Smo.UserType]::SqlUser
        } else {
            Write-Message -Level Verbose -Message "Using UserType [NoLogin]."
            $userType = [Microsoft.SqlServer.Management.Smo.UserType]::NoLogin
        }
    }

    process {
        ### Every process block starts with a loop through the parameter SqlInstance.
        ### Inside of the loop the current instance is named "instance".
        ### The first thing we do is to connect to the instance and save the returned server SMO in a variable called server.
        ### If this fails, we notify the user and continue with the next instance.
        ### The next six lines are (nearly) always the same for every command that connects to one or more instances.
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            ### Run checks as early as possible.
            ### After connecting to the instance, run checks that need a connected instance.
            ### As the check might be successful on the next instance in the loop, use -Continue.
            ### In the messages, all strings should be surrounded by "[]", but all SMO variables will get "[]" automaticaly by their .ToString() method.
            if ($Login -and -not $server.Logins[$Login]) {
                Stop-Function -Message "Login [$Login] not found on instance $server" -Continue
            }

            ### As we need the database object(s) to be able to add a new users to it, we have to filter the databases of the instance based on the provided parameters.
            ### We use Get-DbaDatabase here, because that command does all we need.
            ### We generally avoid to use other commands as they add more load and prefer to use the SMO directly. But in this case there is not much extra work.
            ### The following lines are always the same for all commands that work on a set of databases.
            $databases = Get-DbaDatabase -SqlInstance $server -Database $Database -ExcludeDatabase $ExcludeDatabase -ExcludeSystem:$(-not $IncludeSystem)
            ### Commands that need to change the database test for IsUpdateable, other commands test for IsAccessible.
            $databases = $databases | Where-Object IsUpdateable
            foreach ($db in $databases) {
                ### Where should be a verbose message at the start of each loop to help analyzing issues.
                Write-Message -Level Verbose -Message "Processing database $db on instance $server."

                ### Run checks that need a database object. The same rules as for the instance checks apply.
                if (-not $db.Schemas[$DefaultSchema]) {
                    Stop-Function -Message "Schema [$DefaultSchema] does not exist in database $db on instance $server" -Continue
                }

                ### As a last check, check for existance of the object that should be created.
                ### Depending on the usage of -Force, drop the object or continue with the next database.
                if ($db.Users[$User]) {
                    if ($Force) {
                        if ($Pscmdlet.ShouldProcess("User [$User] in database $db on instance $server", "Dropping user")) {
                            try {
                                $db.Users[$User].Drop()
                            } catch {
                                Stop-Function -Message "Dropping user [$User] in database $db on instance $server failed" -ErrorRecord $_ -Continue
                            }
                        }
                    } else {
                        Stop-Function -Message "User [$User] already exists in database $db on instance $server and -Force was not specified" -Continue
                    }
                }

                if ($Pscmdlet.ShouldProcess("User [$User] in database $db on instance $server", "Creating user")) {
                    try {
                        $newUser = New-Object Microsoft.SqlServer.Management.Smo.User
                        $newUser.Parent = $db
                        $newUser.Name = $User
                        if ($Login) {
                            $newUser.Login = $Login
                        }
                        $newUser.UserType = $userType
                        $newUser.DefaultSchema = $DefaultSchema
                        if ($SecurePassword) {
                            $newUser.Create($SecurePassword)
                        } else {
                            $newUser.Create()
                        }

                        ### Add the common dbatools properties to the new object
                        Add-Member -Force -InputObject $newUser -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                        Add-Member -Force -InputObject $newUser -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                        Add-Member -Force -InputObject $newUser -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                        Add-Member -Force -InputObject $newUser -MemberType NoteProperty -Name Database -value $db.Name

                        ### Output the new object
                        Select-DefaultView -InputObject $newUser -Property ComputerName, InstanceName, SqlInstance, Database, Name, LoginType, Login, AuthenticationType, DefaultSchema
                    } catch {
                        Stop-Function -Message "Creating user [$User] in database $db on instance $server failed" -ErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}