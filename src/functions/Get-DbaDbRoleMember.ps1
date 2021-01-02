function Get-DbaDbRoleMember {
    <#
    .SYNOPSIS
        Get members of database roles for each instance(s) of SQL Server.

    .DESCRIPTION
        The Get-DbaDbRoleMember returns connected SMO object for database roles for each instance(s) of SQL Server.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. This list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude. This list is auto-populated from the server.

    .PARAMETER Role
        The role(s) to process. If unspecified, all roles will be processed.

    .PARAMETER ExcludeRole
        The role(s) to exclude.

    .PARAMETER ExcludeFixedRole
        Excludes all members of fixed roles.

    .PARAMETER IncludeSystemUser
        Includes system users. By default system users are not included.

    .PARAMETER InputObject
        Enables piped input from Get-DbaDbRole or Get-DbaDatabase

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Role, Database, Security, Login
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
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$Role,
        [string[]]$ExcludeRole,
        [switch]$ExcludeFixedRole,
        [switch]$IncludeSystemUser,
        [parameter(ValueFromPipeline)]
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
            switch ($inputType) {
                'Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject"
                    $dbRoles = Get-DbaDBRole -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -Role $Role -ExcludeRole $ExcludeRole -ExcludeFixedRole:$ExcludeFixedRole
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject"
                    $dbRoles = Get-DbaDBRole -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -Role $Role -ExcludeRole $ExcludeRole -ExcludeFixedRole:$ExcludeFixedRole
                }
                'Microsoft.SqlServer.Management.Smo.Database' {
                    Write-Message -Level Verbose -Message "Processing Database through InputObject"
                    $dbRoles = $input | Get-DbaDBRole -Role $Role -ExcludeRole $ExcludeRole -ExcludeFixedRole:$ExcludeFixedRole
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
                    $user = $db.Users | Where-Object { $_.Name -eq $member }

                    if (Test-Bound -Not -ParameterName 'IncludeSystemUser') {
                        $user = $user | Where-Object { $_.IsSystemObject -eq $false }
                    }

                    if ($user) {
                        Add-Member -Force -InputObject $user -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                        Add-Member -Force -InputObject $user -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                        Add-Member -Force -InputObject $user -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                        Add-Member -Force -InputObject $user -MemberType NoteProperty -Name Database -Value $db.Name
                        Add-Member -Force -InputObject $user -MemberType NoteProperty -Name Role -Value $dbRole.Name
                        Add-Member -Force -InputObject $user -MemberType NoteProperty -Name UserName -Value $user.Name

                        # Select object because Select-DefaultView causes strange behaviors when assigned to a variable (??)
                        Select-Object -InputObject $user -Property 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Role', 'UserName', 'Login', 'IsSystemObject', 'LoginType'
                    }
                }
            }
        }
    }
}