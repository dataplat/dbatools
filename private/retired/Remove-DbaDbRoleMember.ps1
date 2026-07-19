function Remove-DbaDbRoleMember {
    <#
    .SYNOPSIS
        Removes database users from database roles across SQL Server instances.

    .DESCRIPTION
        Removes database users from specified database roles, supporting both built-in roles (like db_datareader, db_datawriter, db_owner) and custom database roles. This function streamlines user access management when you need to revoke permissions during employee transitions, security reviews, or role-based access cleanup.

        Handles user removal from multiple roles simultaneously and works across multiple databases and instances. Particularly useful for bulk permission changes, compliance requirements, or when migrating users between different security models. The function validates that users are actually members of the specified roles before attempting removal, preventing unnecessary errors.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to process for role member removal. Accepts wildcards for pattern matching.
        When omitted, the function processes all databases on the instance. Use this to target specific databases during security reviews or when cleaning up permissions in development environments.

    .PARAMETER Role
        Specifies the database roles to remove users from, such as db_datareader, db_datawriter, db_owner, or custom roles.
        Accepts multiple roles to remove users from several roles simultaneously. Required unless you're piping in DatabaseRole objects from Get-DbaDbRole.

    .PARAMETER User
        Specifies the database users to remove from the specified roles. Accepts multiple usernames for bulk operations.
        The function validates that users are actually members of the roles before attempting removal, preventing errors when users aren't currently assigned to the roles.

    .PARAMETER InputObject
        Accepts piped input from Get-DbaDatabase, Get-DbaDbRole, or SQL Server instance objects.
        Use this to chain commands together, such as piping specific databases or roles to process only those objects instead of specifying them via parameters.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        None

        This command does not return any output objects. It removes specified users from database roles and returns no information about the operation.

    .NOTES
        Tags: Role, User
        Author: Ben Miller (@DBAduck)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbRoleMember

    .EXAMPLE
        PS C:\> Remove-DbaDbRoleMember -SqlInstance localhost -Database mydb -Role db_owner -User user1

        Removes user1 from the role db_owner in the database mydb on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Remove-DbaDbRoleMember -SqlInstance localhost, sql2016 -Role SqlAgentOperatorRole -User user1 -Database msdb

        Removes user1 in servers localhost and sql2016 in the msdb database from the SqlAgentOperatorRole

    .EXAMPLE
        PS C:\> $servers = Get-Content C:\servers.txt
        PS C:\> $servers | Remove-DbaDbRoleMember -Role SqlAgentOperatorRole -User user1 -Database msdb

        Removes user1 from the SqlAgentOperatorRole in the msdb database in every server in C:\servers.txt

    .EXAMPLE
        PS C:\> $db = Get-DbaDataabse -SqlInstance localhost -Database DEMODB
        PS C:\> $db | Remove-DbaDbRoleMember -Role "db_datareader","db_datawriter" -User user1

        Removes user1 in the database DEMODB on the server localhost from the roles db_datareader and db_datawriter

    .EXAMPLE
        PS C:\> $roles = Get-DbaDbRole -SqlInstance localhost -Role "db_datareader","db_datawriter"
        PS C:\> $roles | Remove-DbaDbRoleMember -User user1

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Role,
        [parameter(Mandatory)]
        [string[]]$User,
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
                'Dataplat.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject"
                    $dbRoles = Get-DbaDbRole -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -Role $Role
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject"
                    $dbRoles = Get-DbaDbRole -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -Role $Role
                }
                'Microsoft.SqlServer.Management.Smo.Database' {
                    Write-Message -Level Verbose -Message "Processing Database through InputObject"
                    $dbRoles = $input | Get-DbaDbRole -Role $Role
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

            if ((Test-Bound -Not -ParameterName Role) -and ($inputType -ne 'Microsoft.SqlServer.Management.Smo.DatabaseRole')) {
                Stop-Function -Message "You must pipe in a DatabaseRole or specify a Role."
                return
            }

            foreach ($dbRole in $dbRoles) {
                $db = $dbRole.Parent
                $instance = $db.Parent

                Write-Message -Level 'Verbose' -Message "Getting Database Role Members for $dbRole in $db on $instance"

                $members = $dbRole.EnumMembers()

                foreach ($username in $User) {
                    if ($members -contains $username) {
                        if ($PSCmdlet.ShouldProcess($instance, "Removing User $username from role: $dbRole in database $db")) {
                            Write-Message -Level 'Verbose' -Message "Removing User $username from role: $dbRole in database $db on $instance"
                            $dbRole.DropMember($username)
                        }
                    }
                }
            }
        }
    }
}