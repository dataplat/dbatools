function Remove-DbaServerRoleMember {
    <#
    .SYNOPSIS
        Revokes server-level role membership from SQL Server logins and roles.

    .DESCRIPTION
        Revokes membership from server-level roles by removing logins or nested roles from target roles like sysadmin, dbcreator, or custom server roles. This is essential for security management when you need to reduce user privileges or clean up role assignments after organizational changes. The function works with both fixed server roles (sysadmin, securityadmin, etc.) and user-defined server roles, supporting bulk operations across multiple instances.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER ServerRole
        Specifies the server-level role(s) from which to remove members. Accepts both fixed server roles like sysadmin, securityadmin, dbcreator, and custom user-defined server roles.
        Use this when you need to revoke specific permissions by removing logins or nested roles from elevated privilege roles.

    .PARAMETER Login
        Specifies the login name(s) to remove from the target server role(s). Accepts SQL Server logins, Windows logins, and Active Directory accounts.
        Use this when removing user access after role changes, departures, or security reviews where individual logins need privilege reduction.

    .PARAMETER Role
        Specifies the server role name(s) to remove from the target server role(s), enabling nested role management.
        Use this when restructuring role hierarchies or removing inherited permissions where one server role should no longer be a member of another.

    .PARAMETER InputObject
        Accepts piped server role objects from Get-DbaServerRole, allowing you to chain role discovery with member removal operations.
        Use this pattern when you need to filter roles first then remove specific members from the filtered results.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Role, Login
        Author: Mikey Bronowski (@MikeyBronowski), bronowski.it

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaServerRoleMember

    .EXAMPLE
        PS C:\> Remove-DbaServerRoleMember -SqlInstance server1 -ServerRole dbcreator -Login login1

        Removes login1 from the dbcreator fixed server-level role on the instance server1.

    .EXAMPLE
        PS C:\> Remove-DbaServerRoleMember -SqlInstance server1, sql2016 -ServerRole customrole -Login login1

        Removes login1 from customrole custom server-level role on the instance server1 and sql2016.

    .EXAMPLE
        PS C:\> Remove-DbaServerRoleMember -SqlInstance server1 -ServerRole customrole -Role dbcreator

        Removes customrole custom server-level role from the dbcreator fixed server-level role.

    .EXAMPLE
        PS C:\> $servers = Get-Content C:\servers.txt
        PS C:\> $servers | Remove-DbaServerRoleMember -ServerRole sysadmin -Login login1

        Removes login1 from the sysadmin fixed server-level role in every server in C:\servers.txt.

    .EXAMPLE
        PS C:\> Remove-DbaServerRoleMember -SqlInstance localhost -ServerRole bulkadmin, dbcreator -Login login1

        Removes login1 from the bulkadmin and dbcreator fixed server-level roles on the server localhost.

    .EXAMPLE
        PS C:\> $roles = Get-DbaServerRole -SqlInstance localhost -ServerRole bulkadmin, dbcreator
        PS C:\> $roles | Remove-DbaServerRoleMember -Login login1

        Removes login1 from the bulkadmin and dbcreator fixed server-level roles on the server localhost.

    .EXAMPLE
        PS C:\ $logins = Get-Content C:\logins.txt
        PS C:\ $srvLogins = Get-DbaLogin -SqlInstance server1 -Login $logins
        PS C:\ Remove-DbaServerRoleMember -Login $logins -ServerRole mycustomrole

        Removes all the logins found in C:\logins.txt from mycustomrole custom server-level role on server1.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$ServerRole,
        [string[]]$Login,
        [string[]]$Role,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        if ( (Test-Bound SqlInstance -Not) -and (Test-Bound ServerRole -Not) -and (Test-Bound Login -Not) ) {
            Stop-Function -Message "You must pipe in a ServerRole, Login, or specify a SqlInstance"
            return
        }

        if (Test-Bound SqlInstance) {
            $InputObject = $SqlInstance
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($input in $InputObject) {
            $inputType = $input.GetType().FullName

            if ((Test-Bound ServerRole -Not ) -and ($inputType -ne 'Microsoft.SqlServer.Management.Smo.ServerRole')) {
                Stop-Function -Message "You must pipe in a ServerRole or specify a ServerRole."
                return
            }

            switch ($inputType) {
                'Dataplat.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject"
                    try {
                        $serverRoles = Get-DbaServerRole -SqlInstance $input -SqlCredential $SqlCredential -ServerRole $ServerRole -EnableException
                    } catch {
                        Stop-Function -Message "Failure access $input" -ErrorRecord $_ -Target $input -Continue
                    }
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject"
                    try {
                        $serverRoles = Get-DbaServerRole -SqlInstance $input -SqlCredential $SqlCredential -ServerRole $ServerRole -EnableException
                    } catch {
                        Stop-Function -Message "Failure access $input" -ErrorRecord $_ -Target $input -Continue
                    }
                }
                'Microsoft.SqlServer.Management.Smo.ServerRole' {
                    Write-Message -Level Verbose -Message "Processing ServerRole through InputObject"
                    try {
                        $serverRoles = $inputObject
                    } catch {
                        Stop-Function -Message "Failure access $input" -ErrorRecord $_ -Target $input -Continue
                    }
                }
                default {
                    Stop-Function -Message "InputObject is not a server or role."
                    continue
                }
            }

            foreach ($sr in $serverRoles) {
                $instance = $sr.Parent
                foreach ($l in $Login) {
                    if ($PSCmdlet.ShouldProcess($instance, "Removing login $l from server-level role: $sr")) {
                        Write-Message -Level Verbose -Message "Removing login $l from server-level role: $sr on $instance"
                        try {
                            $sr.DropMember($l)
                        } catch {
                            Stop-Function -Message "Failure removing $l on $instance" -ErrorRecord $_ -Target $sr
                        }
                    }

                }
                foreach ($r in $Role) {
                    try {
                        $isServerRole = Get-DbaServerRole -SqlInstance $input -SqlCredential $SqlCredential -ServerRole $r -EnableException
                    } catch {
                        Stop-Function -Message "Failure access $input" -ErrorRecord $_ -Target $input
                        continue
                    }
                    if (-not $isServerRole) {
                        Write-Message -Level Warning -Message "$r server-level role was not found on $instance"
                        continue
                    }
                    if ($PSCmdlet.ShouldProcess($instance, "Removing role $r from server-level role: $sr")) {
                        Write-Message -Level Verbose -Message "Removing role $r from server-level role: $sr on $instance"
                        try {
                            $sr.DropMembershipFromRole($r)
                        } catch {
                            Stop-Function -Message "Failure removing $r on $instance" -ErrorRecord $_ -Target $sr
                        }
                    }
                }
            }
        }
    }
}