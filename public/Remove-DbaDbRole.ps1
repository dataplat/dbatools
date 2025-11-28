function Remove-DbaDbRole {
    <#
    .SYNOPSIS
        Removes custom database roles from SQL Server databases

    .DESCRIPTION
        Removes user-defined database roles from SQL Server databases while protecting against accidental deletion of system roles. This function automatically excludes fixed database roles (like db_owner, db_datareader) and the public role, ensuring only custom roles created for specific security requirements can be removed.

        The function performs safety checks before removal, preventing deletion of roles that own database schemas to avoid orphaning database objects. This is particularly useful when cleaning up deprecated security configurations or removing roles from development databases that were copied from production.

        You can target specific roles across multiple databases and instances, making it ideal for standardizing security configurations or bulk cleanup operations. By default, system databases are excluded unless explicitly included with the IncludeSystemDbs parameter.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to remove roles from. Accepts multiple database names and supports wildcards for pattern matching.
        When omitted, the function processes all user databases on the instance. Use this when you need to clean up roles from specific databases only.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from role removal operations. Accepts multiple database names and supports wildcards.
        Use this when processing all databases except certain ones, such as excluding production databases during cleanup operations.

    .PARAMETER Role
        Specifies which custom database roles to remove. Accepts multiple role names and supports wildcards for pattern matching.
        When omitted, all custom roles in the target databases will be removed. Fixed database roles (db_owner, db_datareader, etc.) and the public role are automatically protected from deletion.

    .PARAMETER ExcludeRole
        Excludes specific roles from removal operations. Accepts multiple role names and supports wildcards.
        Use this when you want to remove most custom roles but preserve certain ones, such as keeping application-specific roles while cleaning up deprecated security configurations.

    .PARAMETER IncludeSystemDbs
        Allows role removal operations to target system databases (master, model, msdb, tempdb).
        By default, system databases are excluded to prevent accidental removal of roles that may be required for SQL Server operations. Only use this when you specifically need to clean up custom roles from system databases.

    .PARAMETER InputObject
        Accepts piped objects from Get-DbaDbRole, Get-DbaDatabase, or SQL Server instances for processing.
        Use this for pipeline operations where you first retrieve specific roles or databases, then remove roles from them. This allows for more complex filtering and processing scenarios.

    .PARAMETER Force
        Forces schema ownership transfer to 'dbo' when the role owns schemas containing database objects. Without this, role removal fails if owned schemas contain objects.
        Use this during security configuration cleanup when you need to ensure complete role removal regardless of schema dependencies.

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
        [switch]$Force,
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
                    $dbRoles = Get-DbaDbRole -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -Role $Role -ExcludeRole $ExcludeRole -ExcludeFixedRole:$True
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject"
                    $dbRoles = Get-DbaDbRole -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -Role $Role -ExcludeRole $ExcludeRole -ExcludeFixedRole:$True
                }
                'Microsoft.SqlServer.Management.Smo.Database' {
                    Write-Message -Level Verbose -Message "Processing Database through InputObject"
                    $dbRoles = $input | Get-DbaDbRole -ExcludeDatabase $ExcludeDatabase -Role $Role -ExcludeRole $ExcludeRole -ExcludeFixedRole:$True
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
                $ownedObjects = $false

                if ($db.IsSystemObject -and (!$IncludeSystemDbs)) {
                    Write-Message -Level Verbose -Message "Can only remove roles from System database when IncludeSystemDbs switch used."
                    continue
                }

                if ($dbRole.IsFixedRole -or $dbRole.Name -eq 'public') {
                    Write-Message -Level Verbose -Message "Cannot remove fixed role $dbRole from database $db on instance $instance"
                    continue
                }

                if ($PSCmdlet.ShouldProcess($instance, "Remove role $dbRole from database $db")) {
                    $ownedSchemas = $db.Schemas | Where-Object Owner -eq $dbRole.Name

                    foreach ($schema in $ownedSchemas) {
                        $ownedUrns = $schema.EnumOwnedObjects()

                        if ($schema.Name -eq $dbRole.Name) {
                            if ($ownedUrns) {
                                Write-Message -Level Warning -Message "Role $($dbRole.Name) owns the Schema $($schema.Name), which owns $($ownedUrns.Count) object(s). If you want to change the schema's owner to [dbo] and drop the role anyway, use -Force parameter. Role $($dbRole.Name) will not be removed."
                                $ownedObjects = $true
                            } else {
                                if ($PSCmdlet.ShouldProcess($instance, "Drop Schema $schema from Database $db.")) {
                                    $schema.Drop()
                                }
                            }
                        } else {
                            if ($ownedUrns -and (!$Force)) {
                                Write-Message -Level Warning -Message "Role $($dbRole.Name) owns the Schema $($schema.Name), which owns $($ownedUrns.Count) object(s). If you want to change the schema's owner to [dbo] and drop the role anyway, use -Force parameter. Role $($dbRole.Name) will not be removed."
                                $ownedObjects = $true
                            } else {
                                Write-Message -Level Verbose -Message "Owner of Schema $schema will be changed to [dbo]."
                                if ($PSCmdlet.ShouldProcess($instance, "Change the owner of Schema $schema to [dbo].")) {
                                    $schema.Owner = "dbo"
                                    $schema.Alter()
                                }
                            }
                        }
                    }

                    if (!$ownedObjects) {
                        if ($PSCmdlet.ShouldProcess($instance, "Drop role $dbRole from database $db")) {
                            $dbRole.Drop()
                        }
                    } else {
                        Write-Message -Level Warning -Message "Could not remove role $dbRole because it still owns one or more schemas."
                    }
                }
            }
        }
    }
}