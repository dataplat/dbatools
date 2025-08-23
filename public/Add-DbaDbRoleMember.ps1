function Add-DbaDbRoleMember {
    <#
    .SYNOPSIS
        Adds database users or roles as members to database roles across SQL Server instances

    .DESCRIPTION
        Manages database security by adding users or roles as members to database roles, automating what would otherwise require manual T-SQL commands or SQL Server Management Studio clicks. This function handles membership validation to ensure the user or role exists in the database before attempting to add them, and checks existing membership to prevent duplicate assignments. You can add multiple users to multiple roles across multiple databases and instances in a single operation, making it ideal for bulk security configuration or automated permission management workflows.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to process for role membership changes. Accepts multiple database names and supports wildcards.
        When omitted, the function processes all databases on the target instances, making it useful for organization-wide security standardization.

    .PARAMETER Role
        Specifies the database role(s) to add members to. Accepts multiple role names including built-in roles like db_datareader, db_datawriter, db_owner, or custom database roles.
        Use this when you need to grant specific database permissions by adding users or roles to appropriate database roles.

    .PARAMETER Member
        Specifies the database user(s) or role(s) to add as members to the target roles. Can be individual users, Windows groups, or other database roles.
        The function validates that each member exists in the database before attempting to add them, preventing errors from typos or missing objects.

    .PARAMETER InputObject
        Accepts piped input from Get-DbaDbRole, Get-DbaDatabase, or SQL Server instances for streamlined workflows.
        Use this when chaining commands together, such as filtering specific roles first then adding members to those filtered results.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Role, User
        Author: Ben Miller (@DBAduck)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Add-DbaDbRoleMember

    .EXAMPLE
        PS C:\> Add-DbaDbRoleMember -SqlInstance localhost -Database mydb -Role db_owner -Member user1

        Adds user1 to the role db_owner in the database mydb on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Add-DbaDbRoleMember -SqlInstance localhost, sql2016 -Role SqlAgentOperatorRole -Member user1 -Database msdb

        Adds user1 in servers localhost and sql2016 in the msdb database to the SqlAgentOperatorRole

    .EXAMPLE
        PS C:\> $servers = Get-Content C:\servers.txt
        PS C:\> $servers | Add-DbaDbRoleMember -Role SqlAgentOperatorRole -Member user1 -Database msdb

        Adds user1 to the SqlAgentOperatorROle in the msdb database in every server in C:\servers.txt

    .EXAMPLE
        PS C:\> Add-DbaDbRoleMember -SqlInstance localhost -Role "db_datareader","db_datawriter" -Member user1 -Database DEMODB

        Adds user1 in the database DEMODB on the server localhost to the roles db_datareader and db_datawriter

   .EXAMPLE
        PS C:\> $roles = Get-DbaDbRole -SqlInstance localhost -Role "db_datareader","db_datawriter" -Database DEMODB
        PS C:\> $roles | Add-DbaDbRoleMember -Member user1

        Adds user1 in the database DEMODB on the server localhost to the roles db_datareader and db_datawriter

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Role,
        [parameter(Mandatory)]
        [Alias("User")]
        [string[]]$Member,
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

                foreach ($newMember in $Member) {
                    if ($db.Users.Name -contains $newMember) {
                        if ($members -notcontains $newMember) {
                            if ($PSCmdlet.ShouldProcess($instance, "Adding user $newMember to role: $dbRole in database $db")) {
                                Write-Message -Level 'Verbose' -Message "Adding user $newMember to role: $dbRole in database $db on $instance"
                                $dbRole.AddMember($newMember)
                            }
                        }
                    } elseif ($db.Roles.Name -contains $newMember) {
                        if ($members -notcontains $newMember) {
                            if ($PSCmdlet.ShouldProcess($instance, "Adding role $newMember to role: $dbRole in database $db")) {
                                Write-Message -Level 'Verbose' -Message "Adding role $newMember to role: $dbRole in database $db on $instance"
                                $dbRole.AddMember($newMember)
                            }
                        }
                    } else {
                        Write-Message -Level 'Warning' -Message "User or role $newMember does not exist in $db on $instance"
                    }
                }
            }
        }
    }
}