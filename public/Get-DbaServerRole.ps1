function Get-DbaServerRole {
    <#
    .SYNOPSIS
        Retrieves server-level security roles and their members from SQL Server instances.

    .DESCRIPTION
        Retrieves all server-level security roles from SQL Server instances, including role members, creation dates, and ownership details. This function helps DBAs audit server-level permissions, identify role membership for compliance reporting, and distinguish between built-in fixed roles (like sysadmin, serveradmin) and custom user-defined roles. Supports filtering to specific roles or excluding fixed roles to focus on custom security configurations.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2005 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER ServerRole
        Specifies one or more server-level roles to include in the results. Accepts role names like 'sysadmin', 'dbcreator', or custom role names.
        Use this when you need to audit specific roles rather than retrieving all server roles from the instance.

    .PARAMETER ExcludeServerRole
        Specifies one or more server-level roles to exclude from the results. Useful for filtering out roles you don't need to audit.
        Commonly used to exclude built-in roles like 'public' when focusing on administrative roles with elevated permissions.

    .PARAMETER ExcludeFixedRole
        Excludes built-in fixed server roles from the results, showing only custom user-defined server roles.
        Use this when auditing custom security configurations or identifying roles created by your organization rather than SQL Server's default roles.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Role
        Author: Shawn Melton (@wsmelton)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.ServerRole

        Returns one ServerRole object per server-level role on the specified SQL Server instance. For example, querying a standard SQL Server instance returns multiple objects - one for each fixed role (sysadmin, serveradmin, dbcreator, etc.) plus any custom user-defined server roles.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Role: The name of the server role (same as Name property)
        - Login: Array of login names that are members of this role
        - Owner: The principal that owns the server role
        - IsFixedRole: Boolean indicating if this is a built-in fixed role (sysadmin, serveradmin, etc.) or a custom user-defined role
        - DateCreated: DateTime when the role was created
        - DateModified: DateTime when the role was last modified

        Additional properties available (from SMO ServerRole object):
        - Name: The name of the server role
        - Urn: The Uniform Resource Name of the server role object
        - Properties: Collection of property objects for the role
        - State: Current state of the SMO object (Existing, Creating, Pending, etc.)

        All properties from the base SMO ServerRole object are accessible using Select-Object * even though only default properties are displayed without using Select-Object *.

    .LINK
        https://dbatools.io/Get-DbaServerRole

    .EXAMPLE
        PS C:\> Get-DbaServerRole -SqlInstance sql2016a

        Outputs list of server-level roles for sql2016a instance.

    .EXAMPLE
        PS C:\> Get-DbaServerRole -SqlInstance sql2017a -ExcludeFixedRole

        Outputs the server-level role(s) that are not fixed roles on sql2017a instance.

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$ServerRole,
        [string[]]$ExcludeServerRole,
        [switch]$ExcludeFixedRole,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -AzureUnsupported
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $serverroles = $server.Roles

            if ($ServerRole) {
                $serverRoles = $serverRoles | Where-Object Name -In $ServerRole
            }
            if ($ExcludeServerRole) {
                $serverRoles = $serverRoles | Where-Object Name -NotIn $ExcludeServerRole
            }
            if ($ExcludeFixedRole) {
                $serverRoles = $serverRoles | Where-Object IsFixedRole -eq $false
            }

            foreach ($role in $serverRoles) {
                $members = $role.EnumMemberNames()

                Add-Member -Force -InputObject $role -MemberType NoteProperty -Name Login -Value $members
                Add-Member -Force -InputObject $role -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                Add-Member -Force -InputObject $role -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $role -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                Add-Member -Force -InputObject $role -MemberType NoteProperty -Name Role -Value $role.Name
                Add-Member -Force -InputObject $role -MemberType NoteProperty -Name ServerRole -Value $role.Name

                $default = 'ComputerName', 'InstanceName', 'SqlInstance', 'Role', 'Login', 'Owner', 'IsFixedRole', 'DateCreated', 'DateModified'
                Select-DefaultView -InputObject $role -Property $default
            }
        }
    }
}