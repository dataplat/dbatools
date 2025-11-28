function Remove-DbaDbRole {
    <#
    .SYNOPSIS
        Removes custom database roles from SQL Server databases

    .DESCRIPTION
        Removes user-defined database roles from SQL Server databases while protecting against accidental deletion of system roles and intelligently handling schema ownership. This function automatically excludes fixed database roles (like db_owner, db_datareader) and the public role, ensuring only custom roles created for specific security requirements can be removed.

        When a role owns schemas, the function intelligently manages the cleanup: schemas with the same name as the role are dropped (if empty), while other owned schemas have their ownership transferred to 'dbo'. If schemas contain objects, use -Force to allow ownership transfer and proceed with role removal.

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
        Use this during role cleanup when you need to ensure complete removal regardless of schema dependencies.

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
        Author: Ben Miller (@DBAduck), the dbatools team + Claude

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
                $alterSchemas = @()
                $dropSchemas = @()

                if ((!$db.IsSystemObject) -or ($db.IsSystemObject -and $IncludeSystemDbs )) {
                    if ((!$dbRole.IsFixedRole) -and ($dbRole.Name -ne 'public')) {
                        if ($PSCmdlet.ShouldProcess($instance, "Remove role $dbRole from database $db")) {
                            # Handle schemas owned by the role
                            $ownedSchemas = $db.Schemas | Where-Object { $_.Owner -eq $dbRole.Name }

                            if ($ownedSchemas) {
                                Write-Message -Level Verbose -Message "Role $dbRole owns $($ownedSchemas.Count) schema(s)."

                                # Need to gather up the schema changes so they can be done in a non-destructive order
                                foreach ($schema in $ownedSchemas) {
                                    # Drop any schema that is the same name as the role
                                    if ($schema.Name -eq $dbRole.Name) {
                                        # Check for owned objects early so we can exit before any changes are made
                                        $ownedUrns = $schema.EnumOwnedObjects()
                                        if (-not $ownedUrns) {
                                            $dropSchemas += $schema
                                        } else {
                                            Write-Message -Level Warning -Message "Role $dbRole owns the Schema $schema, which owns $($ownedUrns.Count) object(s). Role $dbRole will not be removed."
                                            $ownedObjects = $true
                                        }
                                    }

                                    # Change the owner of any schema not the same name as the role
                                    if ($schema.Name -ne $dbRole.Name) {
                                        # Check for owned objects early so we can exit before any changes are made
                                        $ownedUrns = $schema.EnumOwnedObjects()
                                        if (($ownedUrns -and $Force) -or (-not $ownedUrns)) {
                                            $alterSchemas += $schema
                                        } else {
                                            Write-Message -Level Warning -Message "Role $dbRole owns the Schema $schema, which owns $($ownedUrns.Count) object(s). If you want to change the schema's owner to [dbo] and drop the role anyway, use -Force parameter. Role $dbRole will not be removed."
                                            $ownedObjects = $true
                                        }
                                    }
                                }
                            }

                            if (-not $ownedObjects) {
                                try {
                                    # Alter Schemas
                                    foreach ($schema in $alterSchemas) {
                                        Write-Message -Level Verbose -Message "Owner of Schema $schema will be changed to [dbo]."
                                        if ($PSCmdlet.ShouldProcess($instance, "Change the owner of Schema $schema to [dbo].")) {
                                            $schema.Owner = "dbo"
                                            $schema.Alter()
                                        }
                                    }

                                    # Drop Schemas
                                    foreach ($schema in $dropSchemas) {
                                        if ($PSCmdlet.ShouldProcess($instance, "Drop Schema $schema from Database $db.")) {
                                            $schema.Drop()
                                        }
                                    }

                                    # Drop the role
                                    $dbRole.Drop()
                                    Write-Message -Level Verbose -Message "Role $dbRole removed from database $db on instance $instance"
                                } catch {
                                    Stop-Function -Message "Failed to remove role $dbRole from database $db on instance $instance" -ErrorRecord $_ -Continue
                                }
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