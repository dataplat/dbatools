function New-DbaServerRole {
    <#
    .SYNOPSIS
        Creates custom server-level roles on SQL Server instances for role-based access control.

    .DESCRIPTION
        Creates new server-level roles on one or more SQL Server instances, allowing you to implement custom security frameworks without manually using SSMS or T-SQL. Server roles provide a way to group server-level permissions and assign them to logins, making it easier to manage security across your environment. The function checks for existing roles before creation and optionally allows you to specify a role owner other than the default dbo.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER ServerRole
        Specifies the name of the custom server-level role to create. Accepts multiple role names to create several roles in one operation.
        Use this when implementing role-based security models or when you need custom permission groups beyond the built-in server roles like sysadmin or dbcreator.

    .PARAMETER Owner
        Sets the login that will own the newly created server role. Defaults to 'dbo' if not specified.
        Specify a different owner when you need the role managed by a specific login for security or organizational requirements.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Role
        Author: Claudio Silva (@ClaudioESSilva), claudioessilva.eu
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.ServerRole

        Returns one ServerRole object for each newly created server-level role. The returned object is obtained from Get-DbaServerRole after successful role creation.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Role: The name of the server role
        - Login: Array of logins/users that are members of this role
        - Owner: The login that owns the server role
        - IsFixedRole: Boolean indicating if this is a built-in fixed role (always $false for newly created roles)
        - DateCreated: DateTime when the role was created
        - DateModified: DateTime when the role was last modified

        Additional properties available (from SMO ServerRole object):
        - ServerRole: Duplicate of Role property name
        - Parent: Reference to parent SQL Server object
        - State: SMO object state (Existing, Creating, Pending, etc.)
        - Urn: The unified resource name of the role object
        - Properties: Collection of property objects for the role
        - PermissionSet: Permissions assigned to the role

        All properties from the base SMO ServerRole object are accessible using Select-Object *.

    .LINK
        https://dbatools.io/New-DbaServerRole

    .EXAMPLE
        PS C:\> New-DbaServerRole -SqlInstance sql2017a -ServerRole 'dbExecuter' -Owner sa

        Will create a new server role named dbExecuter and grant ownership to the login sa on sql2017a instance.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [String[]]$ServerRole,
        [String]$Owner,
        [switch]$EnableException
    )
    process {
        if (-not $ServerRole) {
            Stop-Function -Message "You must specify a new server-level role name. Use -ServerRole parameter."
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $serverRoles = $server.Roles

            foreach ($role in $ServerRole) {
                if ($serverRoles | Where-Object Name -eq $role) {
                    Stop-Function -Message "The server-level role $role already exists on instance $server." -Target $instance -Continue
                }

                if ($Pscmdlet.ShouldProcess("Creating new server-level role $role on $server")) {
                    Write-Message -Level Verbose -Message "Creating new server-level role $role on $server"
                    try {
                        $newServerRole = New-Object -TypeName Microsoft.SqlServer.Management.Smo.ServerRole
                        $newServerRole.Name = $role
                        $newServerRole.Parent = $server

                        if ($Owner) {
                            $newServerRole.Owner = $Owner
                        }

                        $newServerRole.Create()

                        Get-DbaServerRole -SqlInstance $server -ServerRole $role -EnableException
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}