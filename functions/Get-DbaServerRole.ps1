function Get-DbaServerRole {
    <#
        .SYNOPSIS
            Gets the list of server-level roles.

        .DESCRIPTION
            Gets the list of server-level roles for SQL Server instance.

        .PARAMETER SqlInstance
            The SQL Server instance. Server version must be SQL Server version 2005 or higher.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

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
            Original Author: Shawn Melton (@wsmelton)

            Website: https: //dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaServerRole

        .EXAMPLE
            Get-DbaServerRole -SqlInstance sql2016a

            Outputs list of server-level roles for sql2016a instance.

        .EXAMPLE
            Get-DbaServerRole -SqlInstance sql2017a -ExcludeFixedRole

            Outputs the server-level role(s) that are not fixed roles on sql2017a instance.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$ServerRole,
        [object[]]$ExcludeServerRole,
        [switch]$ExcludeFixedRole,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $roles = $server.Roles

            if ($ServerRole) {
                $roles = $roles | Where-Object Name -In $ServerRole
            }
            if ($ExcludeServerRole) {
                $roles = $roles | Where-Object Name -NotIn $ExcludeServerRole
            }
            if ($ExcludeFixedRole) {
                $roles = $roles | Where-Object IsFixedRole -eq $false
            }

            foreach ($role in $roles) {
                $members = $role.EnumMemberNames()

                Add-Member -Force -InputObject $role -MemberType NoteProperty -Name Login -Value $members
                Add-Member -Force -InputObject $role -MemberType NoteProperty -Name ComputerName -value $server.NetName
                Add-Member -Force -InputObject $role -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $role -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName

                $default = 'ComputerName', 'InstanceName', 'SqlInstance', 'Name as Role', 'IsFixedRole', 'DateCreated', 'DateModified'
                Select-DefaultView -InputObject $role -Property $default
            }
        }
    }
}
