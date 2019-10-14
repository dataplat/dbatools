function Remove-DbaDbRoleMember {
    <#
    .SYNOPSIS
        Removes a Database User from a database role for each instance(s) of SQL Server.

    .DESCRIPTION
        The Remove-DbaDbRoleMember removes users in a database from a database role or roles for each instance(s) of SQL Server.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. This list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER Role
        The role(s) to process.

    .PARAMETER User
        The user(s) to remove from the role(s) specified.

    .PARAMETER InputObject
        Enables piped input from Get-DbaDbRole or Get-DbaDatabase

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Role, Database, Security, Login
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
                'Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject"
                    $dbRoles = Get-DbaDBRole -SqlInstance $input -SqlCredential $sqlcredential -Database $Database -Role $Role
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject"
                    $dbRoles = Get-DbaDBRole -SqlInstance $input -SqlCredential $sqlcredential -Database $Database -Role $Role
                }
                'Microsoft.SqlServer.Management.Smo.Database' {
                    Write-Message -Level Verbose -Message "Processing Database through InputObject"
                    $dbRoles = $input | Get-DbaDBRole -Role $Role
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