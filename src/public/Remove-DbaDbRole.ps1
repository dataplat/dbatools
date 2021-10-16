function Remove-DbaDbRole {
    <#
    .SYNOPSIS
        Removes a database role from database(s) for each instance(s) of SQL Server.

    .DESCRIPTION
        The Remove-DbaDbRole removes role(s) from database(s) for each instance(s) of SQL Server.

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

    .PARAMETER IncludeSystemDbs
        If this switch is enabled, roles can be removed from system databases.

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
        https://dbatools.io/Remove-DbaDbRole

    .EXAMPLE
        PS C:\> Remove-DbaDbRole -SqlInstance localhost -Database dbname -Role "customrole1", "customrole2"

        Removes roles customrole1 and customrole2 from the database dbname on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Remove-DbaDbRole -SqlInstance localhost, sql2016 -Database db1, db2 -Role role1, role2, role3

        Removes role1,role2,role3 from db1 and db2 on the local and sql2016 SQL Server instances

    .EXAMPLE
        PS C:\> $servers = Get-Content C:\servers.txt
        PS C:\> $servers | Remove-DbaDbRole -Database db1, db2 -Role role1

        Removes role1 from db1 and db2 on the servers in C:\servers.txt

    .EXAMPLE
        PS C:\> $roles = Get-DbaDbRole -SqlInstance localhost, sql2016 -Database db1, db2 -Role role1, role2, role3
        PS C:\> $roles | Remove-DbaDbRole

        Removes role1,role2,role3 from db1 and db2 on the local and sql2016 SQL Server instances
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$Role,
        [string[]]$ExcludeRole,
        [switch]$IncludeSystemDbs,
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
                    $dbRoles = Get-DbaDBRole -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -Role $Role -ExcludeRole $ExcludeRole -ExcludeFixedRole:$True
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject"
                    $dbRoles = Get-DbaDBRole -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -Role $Role -ExcludeRole $ExcludeRole -ExcludeFixedRole:$True
                }
                'Microsoft.SqlServer.Management.Smo.Database' {
                    Write-Message -Level Verbose -Message "Processing Database through InputObject"
                    $dbRoles = $input | Get-DbaDBRole -ExcludeDatabase $ExcludeDatabase -Role $Role -ExcludeRole $ExcludeRole -ExcludeFixedRole:$True
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

            foreach ($dbRole in $dbRoles) {
                $db = $dbRole.Parent
                $instance = $db.Parent
                if ((!$db.IsSystemObject) -or ($db.IsSystemObject -and $IncludeSystemDbs )) {
                    if ((!$dbRole.IsFixedRole) -and ($dbRole.Name -ne 'public')) {
                        if ($PSCmdlet.ShouldProcess($instance, "Remove role $dbRole from database $db")) {
                            $schemas = $dbRole.Parent.Schemas | Where-Object { $_.Owner -eq $dbRole.Name }
                            if (!$schemas) {
                                $dbRole.Drop()
                            } else {
                                Write-Message -Level warning -Message "Cannot remove role $dbRole from database $db on instance $instance as it owns one or more Schemas"
                            }
                        }
                    } else {
                        Write-Message -Level Verbose -Message "Cannot remove fixed role $dbRole from database $db on instance $instance"
                    }
                } else {
                    Write-Message -Level Verbose -Message "Can only remove roles from System database when IncludeSystemDbs switch used."
                }
            }
        }
    }
}