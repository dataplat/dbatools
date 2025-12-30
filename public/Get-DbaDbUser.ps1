function Get-DbaDbUser {
    <#
    .SYNOPSIS
        Retrieves database user accounts and their associated login mappings from SQL Server databases

    .DESCRIPTION
        Retrieves all database user accounts from one or more databases, showing their associated server logins, authentication types, and access states. This function is essential for security audits, user access reviews, and compliance reporting where you need to see who has database-level access and how their accounts are configured. You can filter results by specific users, logins, databases, or exclude system accounts to focus on custom user accounts that require regular review.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to query for user accounts. Accepts multiple database names and supports wildcards.
        Use this when you need to audit users in specific databases rather than scanning all databases on the instance.

    .PARAMETER ExcludeDatabase
        Specifies databases to skip when retrieving user accounts. Useful for excluding system databases or databases you don't manage.
        Common practice is to exclude tempdb, model, or development databases when focusing on production user access reviews.

    .PARAMETER ExcludeSystemUser
        Excludes built-in system users like 'dbo', 'guest', 'INFORMATION_SCHEMA', and other system-created accounts.
        Use this switch during security audits to focus only on custom user accounts that require regular access review and management.

    .PARAMETER User
        Filters results to specific database user names. Accepts multiple user names for targeted queries.
        Use this when investigating specific user accounts or verifying permissions for particular users during access reviews or troubleshooting.

    .PARAMETER Login
        Filters results to database users associated with specific server logins. Shows which databases a login has user accounts in.
        Essential for understanding a login's database-level access across the instance, especially during user access audits or when removing departing employees.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.User

        Returns one User object per database user found. The output is filtered based on the -User, -Login, and -ExcludeSystemUser parameters.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The name of the database containing the user
        - CreateDate: DateTime when the user was created
        - DateLastModified: DateTime when the user was last modified
        - Name: The name of the database user
        - Login: The associated server login name (empty string if user is an orphan)
        - LoginType: The type of login (SqlLogin, WindowsUser, WindowsGroup, Certificate, AsymmetricKey, or ExternalUser)
        - AuthenticationType: The authentication method (Database or Windows)
        - State: The object state (Existing, Creating, Dropping, etc.)
        - HasDbAccess: Boolean indicating if the user has database access
        - DefaultSchema: The default schema associated with the user

        Additional properties available (from SMO User object):
        - ID: Unique object ID within the database
        - IsSystemObject: Boolean indicating if this is a built-in system user (dbo, guest, INFORMATION_SCHEMA, etc.)
        - IsDisabled: Boolean indicating if the user is disabled
        - Urn: Uniform Resource Name identifier for the user
        - Sid: Security identifier for Windows-authenticated users
        - MustChangePassword: Boolean indicating if user must change password on next login (SQL logins only)
        - PasswordExpirationEnabled: Boolean indicating if password expiration policy is enabled
        - PasswordExpired: Boolean indicating if password has expired

        All properties from the base SMO User object are accessible via Select-Object * even though only default properties are displayed.

    .NOTES
        Tags: User, Database
        Author: Klaas Vandenberghe (@PowerDbaKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbUser

    .EXAMPLE
        PS C:\> Get-DbaDbUser -SqlInstance sql2016

        Gets all database users

    .EXAMPLE
        PS C:\> Get-DbaDbUser -SqlInstance Server1 -Database db1

        Gets the users for the db1 database

    .EXAMPLE
        PS C:\> Get-DbaDbUser -SqlInstance Server1 -ExcludeDatabase db1

        Gets the users for all databases except db1

    .EXAMPLE
        PS C:\> Get-DbaDbUser -SqlInstance Server1 -ExcludeSystemUser

        Gets the users for all databases that are not system objects, like 'dbo', 'guest' or 'INFORMATION_SCHEMA'

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaDbUser

        Gets the users for the databases on Sql1 and Sql2/sqlexpress

    .EXAMPLE
        PS C:\> Get-DbaDbUser -SqlInstance Server1 -Database db1 -User user1, user2

        Gets the users 'user1' and 'user2' from the db1 database

    .EXAMPLE
        PS C:\> Get-DbaDbUser -SqlInstance Server1 -Login login1, login2

        Gets the users associated with the logins 'login1' and 'login2'

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$ExcludeSystemUser,
        [string[]]$User,
        [string[]]$Login,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }


            $databases = Get-DbaDatabase -SqlInstance $server -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -OnlyAccessible

            foreach ($db in $databases) {

                $users = $db.users

                if (!$users) {
                    Write-Message -Message "No users exist in the $db database on $instance" -Target $db -Level Verbose
                    continue
                }
                if ($ExcludeSystemUser) {
                    $users = $users | Where-Object { $_.IsSystemObject -eq $false }
                }
                if (Test-Bound -ParameterName User) {
                    $users = $users | Where-Object { $_.Name -in $User }
                }
                if (Test-Bound -ParameterName Login) {
                    $users = $users | Where-Object { $_.Login -in $Login }
                }

                $users | ForEach-Object {

                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    Add-Member -Force -InputObject $_ -MemberType NoteProperty -Name Database -value $db.Name

                    Select-DefaultView -InputObject $_ -Property ComputerName, InstanceName, SqlInstance, Database, CreateDate, DateLastModified, Name, Login, LoginType, AuthenticationType, State, HasDbAccess, DefaultSchema
                }
            }
        }
    }
}