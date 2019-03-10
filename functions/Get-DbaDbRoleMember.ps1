#ValidationTags#CodeStyle, Messaging, FlowControl, Pipeline#
function Get-DbaDbRoleMember {
    <#
    .SYNOPSIS
        Get members of database roles for each instance(s) of SQL Server.

    .DESCRIPTION
        The Get-DbaDbRoleMember returns connected SMO object for database roles for each instance(s) of SQL Server.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternate Windows or SQL Login Authentication. Accepts credential objects (Get-Credential).

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

    #>
    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstance[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$Role,
        [string[]]$ExcludeRole,
        [switch]$ExcludeFixedRole,
        [switch]$IncludeSystemUser,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message 'Failure' -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($item in $Database) {
                Write-Message -Level Verbose -Message "Check if database: $item on $instance is accessible or not"
                if ($server.Databases[$item].IsAccessible -eq $false) {
                    Stop-Function -Message "Database: $item is not accessible. Check your permissions or database state." -Category ResourceUnavailable -ErrorRecord $_ -Target $instance -Continue
                }
            }

            $databases = $server.Databases | Where-Object { $_.IsAccessible -eq $true }

            if (Test-Bound -Parameter 'Database') {
                $databases = $databases | Where-Object { $_.Name -in $Database }
            }

            if (Test-Bound -Parameter 'ExcludeDatabase') {
                $databases = $databases | Where-Object { $_.Name -notin $ExcludeDatabase}
            }

            foreach ($db in $databases) {
                Write-Message -Level 'Verbose' -Message "Getting Database Roles for $db on $instance"

                $dbRoles = $db.roles

                if (Test-Bound -Parameter 'Role') {
                    $dbRoles = $dbRoles | Where-Object { $_.Name -in $Role }
                }

                if (Test-Bound -Parameter 'ExcludeRole') {
                    $dbRoles = $dbRoles | Where-Object { $_.Name -notin $ExcludeRole }
                }

                if (Test-Bound -Parameter 'ExcludeFixedRole') {
                    $dbRoles = $dbRoles | Where-Object { $_.IsFixedRole -eq $false }
                }

                foreach ($dbRole in $dbRoles) {
                    Write-Message -Level 'Verbose' -Message "Getting Database Role Members for $dbRole in $db on $instance"

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
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Alias Get-DbaRoleMember
    }
}
