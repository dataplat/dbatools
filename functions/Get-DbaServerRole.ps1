function Get-DbaServerRole {
    <#
    .SYNOPSIS
        Gets the list of server-level roles.

    .DESCRIPTION
        Gets the list of server-level roles for SQL Server instance.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2005 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER ServerRole
        Server-Level role to filter results to that role only.

    .PARAMETER ExcludeServerRole
        Server-Level role to exclude from results.

    .PARAMETER ExcludeFixedRole
        Filter the fixed server-level roles. Only applies to SQL Server 2017 that supports creation of server-level roles.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message. This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting. Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ServerRole, Security
        Author: Shawn Melton (@wsmelton)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.ServerType -eq 'SqlAzureDatabase') {
                Stop-Function -Message "The SqlAzureDatabase - $server is not supported." -Continue
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