function Add-DbaServerRoleMember {
    <#
    .SYNOPSIS
        Adds a Database User to a database role for each instance(s) of SQL Server.

    .DESCRIPTION
        The Add-DbaServerRoleMember adds users in a database to a database role or roles for each instance(s) of SQL Server.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. This list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ServerRole
        The server-level role(s) to process.

    .PARAMETER Login
        The login(s) to add to server-level role(s) specified.

    .PARAMETER Role
        The role(s) to add to server-level role(s) specified.

    .PARAMETER InputObject
        Enables piped input from Get-DbaServerRole or New-DbaServerRole

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Role, Security, Login
        Author: Shawn Melton (@wsmelton)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Add-DbaServerRoleMember

    .EXAMPLE
        PS C:\> Add-DbaServerRoleMember -SqlInstance server1 -Role dbcreator -Login login1

        Adds login1 to the server-level role dbcreator on the instance server1

    .EXAMPLE
        PS C:\> Add-DbaServerRoleMember -SqlInstance server1, sql2016 -ServerRole customrole -Login login1

        Adds login1 in custom, server-level role customrole on the instance server1 and sql2016

    .EXAMPLE
        PS C:\> Add-DbaServerRoleMember -SqlInstance server1 -ServerRole customrole -Role dbcreator

        Adds custom, server-level role customrole to dbcreator server-level fixed role.

    .EXAMPLE
        PS C:\> $servers = Get-Content C:\servers.txt
        PS C:\> $servers | Add-DbaServerRoleMember -ServerRole sysadmin -Login login1

        Adds login1 to the sysadmin server-level role in every server in C:\servers.txt

    .EXAMPLE
        PS C:\> Add-DbaServerRoleMember -SqlInstance localhost -ServerRole "bulkadmin","dbcreator" -Login login1

        Adds login1 on the server localhost to the server-level roles bulkadmin and dbcreator

    .EXAMPLE
        PS C:\> $roles = Get-DbaServerRole -SqlInstance localhost -ServerRole "bulkadmin","dbcreator"
        PS C:\> $roles | Add-DbaServerRoleMember -Login login1

        Adds login1 on the server localhost to the server-level roles bulkadmin and dbcreator

    .EXAMPLE
        PS C:\ $logins = Get-Content C:\logins.txt
        PS C:\ $srvLogins = Get-DbaLogin -SqlInstance server1 -Login $logins
        PS C:\ New-DbaServerRole -SqlInstance server1 -ServerRole mycustomrole -Owner sa | Add-DbaServerRoleMember -Login $logins

        Adds all the logins found in C:\logins.txt to the newly created server-level role mycustomrole on server1.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(ValueFromPipeline)]
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
                'Sqlcollaborative.Dbatools.Parameter.DbaInstanceParameter' {
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
                    if ( $sr.EnumMemberNames().Contains($l.Name) ) {
                        Write-Message -Level Warning -Message "Login $l is already a member in server-level role: $sr"
                        continue
                    } else {
                        if ($PSCmdlet.ShouldProcess($instance, "Adding login $l to server-level role: $sr")) {
                            Write-Message -Level Verbose -Message "Adding login $l to server-level role: $sr on $instance"
                            try {
                                $sr.AddMember($l)
                            } catch {
                                Stop-Function -Message "Failure adding $l on $instance" -ErrorRecord $_ -Target $sr
                            }
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
                    if ($PSCmdlet.ShouldProcess($instance, "Adding role $r to server-level role: $sr")) {
                        Write-Message -Level Verbose -Message "Adding role $r to server-level role: $sr on $instance"
                        try {
                            $sr.AddMembershipToRole($r)
                        } catch {
                            Stop-Function -Message "Failure adding $r on $instance" -ErrorRecord $_ -Target $sr
                        }
                    }
                }
            }
        }
    }
}