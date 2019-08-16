function Get-DbaDbRole {
    <#
    .SYNOPSIS
        Get the database roles for each instance(s) of SQL Server.

    .DESCRIPTION
        The Get-DbaDbRole returns connected SMO object for database roles for each instance(s) of SQL Server.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. This list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude. This list is auto-populated from the server.

    .PARAMETER Role
        The role(s) to process. If unspecified, all roles will be processed.

    .PARAMETER ExcludeRole
        The role(s) to exclude.

    .PARAMETER ExcludeFixedRole
        Excludes all fixed roles.

    .PARAMETER InputObject
        Enables piped input from Get-DbaDatabase

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
        https://dbatools.io/Get-DbaDbRole

    .EXAMPLE
        PS C:\> Get-DbaDbRole -SqlInstance localhost

        Returns all database roles in all databases on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaDbRole -SqlInstance localhost, sql2016

        Returns all roles of all database(s) on the local and sql2016 SQL Server instances

    .EXAMPLE
        PS C:\> $servers = Get-Content C:\servers.txt
        PS C:\> $servers | Get-DbaDbRole

        Returns roles of all database(s) for every server in C:\servers.txt

    .EXAMPLE
        PS C:\> Get-DbaDbRole -SqlInstance localhost -Database msdb

        Returns roles of the database msdb on localhost.

    .EXAMPLE
        PS C:\> Get-DbaDbRole -SqlInstance localhost -Database msdb -ExcludeFixedRole

        Returns all non-fixed roles in the msdb database on localhost.

    .EXAMPLE
        PS C:\> Get-DbaDbRole -SqlInstance localhost -Database msdb -Role 'db_owner'

        Returns the db_owner role in the msdb database on localhost.

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$Role,
        [string[]]$ExcludeRole,
        [switch]$ExcludeFixedRole,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )

    process {
        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a database or specify a SqlInstance"
            return
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            if ($db.IsAccessible -eq $false) {
                continue
            }
            $server = $db.Parent
            Write-Message -Level 'Verbose' -Message "Getting Database Roles for $db on $server"

            $dbRoles = $db.Roles

            if ($Role) {
                $dbRoles = $dbRoles | Where-Object { $_.Name -in $Role }
            }

            if ($ExcludeRole) {
                $dbRoles = $dbRoles | Where-Object { $_.Name -notin $ExcludeRole }
            }

            if ($ExcludeFixedRole) {
                $dbRoles = $dbRoles | Where-Object { $_.IsFixedRole -eq $false -and $_.Name -ne 'public' }
            }

            foreach ($dbRole in $dbRoles) {
                Add-Member -Force -InputObject $dbRole -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                Add-Member -Force -InputObject $dbRole -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $dbRole -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Add-Member -Force -InputObject $dbRole -MemberType NoteProperty -Name Database -Value $db.Name

                Select-DefaultView -InputObject $dbRole -Property "ComputerName", "InstanceName", "Database", "Name", "IsFixedRole"
            }
        }
    }
}