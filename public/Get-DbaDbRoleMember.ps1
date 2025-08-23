function Get-DbaDbRoleMember {
    <#
    .SYNOPSIS
        Retrieves all users and nested roles that are members of database roles across SQL Server instances

    .DESCRIPTION
        This function enumerates the membership of database roles, showing which users and nested roles belong to each role. Essential for security audits, permission troubleshooting, and compliance reporting, it reveals the complete role hierarchy within your databases. By default, system users are excluded to focus on business-relevant accounts, but you can include them for comprehensive security reviews. The function works across multiple instances and databases simultaneously, making it perfect for enterprise-wide role membership documentation and access reviews.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to analyze for role membership. Accepts wildcards for pattern matching.
        Use this to focus on specific databases rather than scanning all databases on the instance. Helpful when you only need role membership data for particular applications or business units.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from role membership analysis. Supports wildcards for pattern matching.
        Use this to skip system databases like tempdb or databases under maintenance when performing enterprise-wide role audits.

    .PARAMETER Role
        Limits the analysis to specific database roles by name. Accepts wildcards for pattern matching.
        Use this when investigating membership of particular roles like 'db_owner', 'db_datareader', or custom application roles during security reviews or troubleshooting.

    .PARAMETER ExcludeRole
        Excludes specific database roles from the membership analysis. Supports wildcards for pattern matching.
        Use this to filter out roles you're not interested in, such as excluding 'public' role or application-specific roles during focused security audits.

    .PARAMETER ExcludeFixedRole
        Excludes members of SQL Server's built-in database roles like db_owner, db_datareader, db_datawriter, etc.
        Use this when you want to focus only on custom application roles and their memberships, filtering out the standard SQL Server role assignments.

    .PARAMETER IncludeSystemUser
        Includes SQL Server system users like 'dbo', 'guest', 'sys', and 'INFORMATION_SCHEMA' in the results.
        Use this for comprehensive security audits or when troubleshooting system-level permission issues. Normally these accounts are excluded to focus on business user accounts.

    .PARAMETER InputObject
        Accepts piped objects from Get-DbaDbRole, Get-DbaDatabase, or SQL Server instances for processing.
        Use this to chain commands together, such as first filtering roles with Get-DbaDbRole then analyzing their membership, or to process multiple database objects efficiently.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Role, User
        Author: Klaas Vandenberghe (@PowerDBAKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbRoleMember

    .EXAMPLE
        PS C:\> Get-DbaDbRoleMember -SqlInstance localhost

        Returns all members of all database roles on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaDbRoleMember -SqlInstance localhost, sql2016

        Returns all members of all database roles on the local and sql2016 SQL Server instances

    .EXAMPLE
        PS C:\> $servers = Get-Content C:\servers.txt
        PS C:\> $servers | Get-DbaDbRoleMember

        Returns all members of all database roles for every server in C:\servers.txt

    .EXAMPLE
        PS C:\> Get-DbaDbRoleMember -SqlInstance localhost -Database msdb

        Returns non-system members of all roles in the msdb database on localhost.

    .EXAMPLE
        PS C:\> Get-DbaDbRoleMember -SqlInstance localhost -Database msdb -IncludeSystemUser -ExcludeFixedRole

        Returns all members of non-fixed roles in the msdb database on localhost.

    .EXAMPLE
        PS C:\> Get-DbaDbRoleMember -SqlInstance localhost -Database msdb -Role 'db_owner'

        Returns all members of the db_owner role in the msdb database on localhost.

    .EXAMPLE
        PS C:\> $roles = Get-DbaDbRole -SqlInstance localhost -Database msdb -Role 'db_owner'
        PS C:\> $roles | Get-DbaDbRoleMember

        Returns all members of the db_owner role in the msdb database on localhost.
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$Role,
        [string[]]$ExcludeRole,
        [switch]$ExcludeFixedRole,
        [switch]$IncludeSystemUser,
        [Parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )

    process {
        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a role, database, or server or specify a SqlInstance"
            return
        }

        if ($SqlInstance) {
            $InputObject = $SqlInstance
        }

        foreach ($input in $InputObject) {
            $inputType = $input.GetType().FullName
            $dbRoleParams = @{
                SqlInstance      = $input
                SqlCredential    = $SqlCredential
                Database         = $Database
                ExcludeDatabase  = $ExcludeDatabase
                Role             = $Role
                ExcludeRole      = $ExcludeRole
                ExcludeFixedRole = $ExcludeFixedRole
                EnableException  = $EnableException
            }
            switch ($inputType) {
                'Dataplat.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject"
                    $dbRoles = Get-DbaDbRole @dbRoleParams
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject"
                    $dbRoles = Get-DbaDbRole @dbRoleParams
                }
                'Microsoft.SqlServer.Management.Smo.Database' {
                    $dbRoleParams.Remove('SqlInstance')
                    $dbRoleParams.Remove('SqlCredential')
                    $dbRoleParams.Remove('Database')
                    Write-Message -Level Verbose -Message "Processing Database through InputObject"
                    $dbRoles = $input | Get-DbaDbRole @dbRoleParams
                }
                'Microsoft.SqlServer.Management.Smo.DatabaseRole' {
                    Write-Message -Level Verbose -Message "Processing DatabaseRole through InputObject"
                    $dbRoles = $input
                }
                default {
                    Stop-Function -Message "InputObject is not a server, database, or database role."
                    return
                }
            }
            foreach ($dbRole in $dbRoles) {
                $db = $dbRole.Parent
                $server = $db.Parent
                Write-Message -Level 'Verbose' -Message "Getting Database Role Members for $dbRole in $db on $server"

                $members = $dbRole.EnumMembers()
                foreach ($member in $members) {
                    $memberUser = $db.Users | Where-Object { $_.Name -eq $member }
                    $memberRole = $db.Roles | Where-Object { $_.Name -eq $member }

                    if (Test-Bound -Not -ParameterName 'IncludeSystemUser') {
                        $memberUser = $memberUser | Where-Object { $_.IsSystemObject -eq $false }
                    }

                    if ($memberUser) {
                        [PSCustomObject]@{
                            ComputerName  = $server.ComputerName
                            InstanceName  = $server.ServiceName
                            SqlInstance   = $server.DomainInstanceName
                            Database      = $db.Name
                            Role          = $dbRole.Name
                            UserName      = $memberUser.Name
                            Login         = $memberUser.Login
                            MemberRole    = $null
                            SmoRole       = $dbRole
                            SmoUser       = $memberUser
                            SmoMemberRole = $null
                        }
                    } elseif ($memberRole) {
                        [PSCustomObject]@{
                            ComputerName  = $server.ComputerName
                            InstanceName  = $server.ServiceName
                            SqlInstance   = $server.DomainInstanceName
                            Database      = $db.Name
                            Role          = $dbRole.Name
                            UserName      = $null
                            Login         = $memberUser.Login
                            MemberRole    = $memberRole.Name
                            SmoRole       = $dbRole
                            SmoUser       = $null
                            SmoMemberRole = $memberRole
                        }
                    }
                }
            }
        }
    }
}