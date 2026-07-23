function Get-DbaServerRoleMember {
    <#
    .SYNOPSIS
        Retrieves server-level role memberships for security auditing and compliance reporting.

    .DESCRIPTION
        Returns detailed information about which logins are members of server-level roles like sysadmin, dbcreator, and securityadmin. Essential for security audits, compliance reviews, and troubleshooting permission issues. Shows both the role assignments and provides access to the underlying SMO objects for further analysis. Supports filtering by specific roles or logins to focus on particular security concerns.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER ServerRole
        Specifies which server roles to check for membership. Accepts role names like 'sysadmin', 'dbcreator', 'securityadmin', or custom server roles.
        Use this when you need to focus your audit on specific high-privilege roles or investigate particular security concerns.

    .PARAMETER ExcludeServerRole
        Excludes specified server roles from the membership report. Useful when you want to see all role memberships except certain roles.
        Commonly used to exclude low-privilege roles like 'public' when focusing on elevated permissions during security reviews.

    .PARAMETER Login
        Filters results to show only server role memberships for specific logins. Accepts login names including Windows accounts, SQL logins, and service accounts.
        Use this when investigating permissions for particular users or troubleshooting access issues for specific accounts.

    .PARAMETER ExcludeFixedRole
        Excludes built-in server roles like sysadmin, securityadmin, and dbcreator, showing only custom server roles created by your organization.
        Only available on SQL Server 2017 and later which supports user-defined server roles. Use this to audit custom role assignments in environments with specialized security models.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Role, Login
        Author: Klaas Vandenberghe (@PowerDBAKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        PSCustomObject

        Returns one object per login that is a member of server-level roles on the specified SQL Server instance(s). For example, if the sysadmin role has three member logins and the dbcreator role has two member logins, four objects are returned total (one for each unique role-login combination when filtering by -Login parameter, or multiple objects per member if they belong to multiple roles).

        Properties:
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - Role: The name of the server role (sysadmin, dbcreator, securityadmin, or custom role name)
        - Name: The login name that is a member of the role
        - SmoRole: The SMO ServerRole object representing the role - allows access to all ServerRole properties and methods for further analysis
        - SmoLogin: The SMO Login object representing the login - allows access to all Login properties and methods for further analysis

        Output quantity note:
        When a login is a member of multiple roles, one object is returned per role-login combination. For example, if 'sa' is a member of both sysadmin and securityadmin roles, two objects are returned - one for each role membership.

    .LINK
        https://dbatools.io/Get-DbaServerRoleMember

    .EXAMPLE
        PS C:\> Get-DbaServerRoleMember -SqlInstance localhost

        Returns all members of all server roles on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaServerRoleMember -SqlInstance localhost, sql2016

        Returns all members of all server roles on the local and sql2016 SQL Server instances

    .EXAMPLE
        PS C:\> $servers = Get-Content C:\servers.txt
        PS C:\> $servers | Get-DbaServerRoleMember

        Returns all members of all server roles for every server in C:\servers.txt

    .EXAMPLE
        PS C:\> Get-DbaServerRoleMember -SqlInstance localhost -ServerRole 'sysadmin', 'dbcreator'

        Returns all members of the sysadmin or dbcreator roles on localhost.

    .EXAMPLE
        PS C:\> Get-DbaServerRoleMember -SqlInstance localhost -ExcludeServerRole 'sysadmin'

        Returns all members of server-level roles other than sysadmin.

    .EXAMPLE
        PS C:\> Get-DbaServerRoleMember -SqlInstance sql2017a -ExcludeFixedRole

        Returns all members of server-level role(s) that are not fixed roles on sql2017a instance.

    .EXAMPLE
        PS C:\> Get-DbaServerRoleMember -SqlInstance localhost -Login 'MyFriendlyDeveloper'

        Returns all server-level role(s) for the MyFriendlyDeveloper login on localhost.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias('Credential')]
        [PSCredential]$SqlCredential,
        [string[]]$ServerRole,
        [string[]]$ExcludeServerRole,
        [object[]]$Login,
        [switch]$ExcludeFixedRole,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $roles = $server.Roles

            if (Test-Bound -ParameterName 'Login') {
                try {
                    $logins = Get-DbaLogin -SqlInstance $server -Login $Login -EnableException
                } catch {
                    Stop-Function -Message "Issue gathering login details" -ErrorRecord $_ -Target $instance
                }
                Write-Message -Level 'Verbose' -Message "Filtering by logins: $($logins -join ', ')"
                $loginRoles = @()
                foreach ($l in $logins) {
                    $loginRoles += $l.ListMembers()
                }

                $loginRoles = $loginRoles | Select-Object -Unique
                Write-Message -Level 'Verbose' -Message "Filtering by roles: $($loginRoles -join ', ')"

                $roles = $roles | Where-Object { $_.Name -in $loginRoles }
            }

            if (Test-Bound -ParameterName 'ServerRole') {
                $roles = $roles | Where-Object { $_.Name -in $ServerRole }
            }

            if (Test-Bound -ParameterName 'ExcludeServerRole') {
                $roles = $roles | Where-Object { $_.Name -notin $ExcludeServerRole }
            }

            if (Test-Bound -ParameterName 'ExcludeFixedRole') {
                $roles = $roles | Where-Object { $_.IsFixedRole -eq $false }
            }

            foreach ($role in $roles) {
                Write-Message -Level 'Verbose' -Message "Getting Server Role Members for $role on $instance"

                $members = $role.EnumMemberNames()
                Write-Message -Level 'Verbose' -Message "$role members: $($members -join ', ')"

                if (Test-Bound -ParameterName 'Login') {
                    Write-Message -Level 'Verbose' -Message "Only returning results for $($logins.Name -join ', ')"
                    $members = $members | Where-Object { $_ -in $logins.Name }
                }

                foreach ($member in $members) {
                    $loginList = $server.Logins | Where-Object { $_.Name -eq $member }

                    if ($loginList) {
                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Role         = $role.Name
                            Name         = $loginList.Name
                            SmoRole      = $role
                            SmoLogin     = $loginList
                        }
                    }
                }
            }
        }
    }
}