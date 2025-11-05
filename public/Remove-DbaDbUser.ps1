function Remove-DbaDbUser {
    <#
    .SYNOPSIS
        Removes database users from SQL Server databases with intelligent schema ownership handling

    .DESCRIPTION
        Safely removes database users from SQL Server databases while automatically handling schema ownership conflicts that would normally prevent user deletion. This eliminates the manual process of identifying and resolving schema ownership issues before removing users.

        When a user owns schemas, the function intelligently manages the cleanup: schemas with the same name as the user are dropped (if empty), while other owned schemas have their ownership transferred to 'dbo'. If schemas contain objects, use -Force to allow ownership transfer and proceed with user removal.

        The function works across multiple databases and instances, making it ideal for cleanup operations during user deprovisioning or database migrations where you need to remove users without leaving orphaned objects or broken ownership chains.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance..

    .PARAMETER Database
        Specifies the database(s) from which to remove the specified users. Accepts wildcards for pattern matching.
        When omitted, the function processes all accessible databases on the instance to find and remove the specified users.

    .PARAMETER ExcludeDatabase
        Specifies the database(s) to skip during user removal operations. Use this to protect critical databases like system databases.
        Commonly used to exclude model, tempdb, or production databases during bulk user cleanup operations.

    .PARAMETER User
        Specifies the database user(s) to remove from the target databases. Accepts multiple user names for bulk operations.
        The function will automatically handle schema ownership conflicts that typically prevent user deletion.

    .PARAMETER InputObject
        Accepts user objects from Get-DbaDbUser for pipeline operations. This allows for advanced filtering scenarios.
        Use this when you need to remove users based on complex criteria like creation date, permissions, or other user properties.

    .PARAMETER Force
        Forces schema ownership transfer to 'dbo' when the user owns schemas containing database objects. Without this, user removal fails if owned schemas contain objects.
        Use this during user deprovisioning when you need to ensure complete cleanup regardless of schema dependencies.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: User
        Author: Doug Meyers (@dgmyrs)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbUser

    .EXAMPLE
        PS C:\> Remove-DbaDbUser -SqlInstance sqlserver2014 -User user1

        Drops user1 from all databases it exists in on server 'sqlserver2014'.

    .EXAMPLE
        PS C:\> Remove-DbaDbUser -SqlInstance sqlserver2014 -Database database1 -User user1

        Drops user1 from the database1 database on server 'sqlserver2014'.

    .EXAMPLE
        PS C:\> Remove-DbaDbUser -SqlInstance sqlserver2014 -ExcludeDatabase model -User user1

        Drops user1 from all databases it exists in on server 'sqlserver2014' except for the model database.

    .EXAMPLE
        PS C:\> Get-DbaDbUser sqlserver2014 | Where-Object Name -In "user1" | Remove-DbaDbUser

        Drops user1 from all databases it exists in on server 'sqlserver2014'.
    #>
    [CmdletBinding(DefaultParameterSetName = 'User', SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Position = 1, Mandatory, ValueFromPipeline, ParameterSetName = 'User')]
        [DbaInstanceParameter[]]$SqlInstance,
        [parameter(ParameterSetName = 'User')]
        [PSCredential]$SqlCredential,
        [parameter(ParameterSetName = 'User')]
        [object[]]$Database,
        [parameter(ParameterSetName = 'User')]
        [object[]]$ExcludeDatabase,
        [parameter(Mandatory, ParameterSetName = 'User')]
        [object[]]$User,
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Object')]
        [Microsoft.SqlServer.Management.Smo.User[]]$InputObject,
        [parameter(ParameterSetName = 'User')]
        [parameter(ParameterSetName = 'Object')]
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        $pipedUsers = @( )

        function Remove-DbUser {
            [CmdletBinding(SupportsShouldProcess)]
            param ([Microsoft.SqlServer.Management.Smo.User[]]$users)

            foreach ($user in $users) {
                $db = $user.Parent
                $server = $db.Parent
                $ownedObjects = $false
                $alterSchemas = @()
                $dropSchemas = @()
                Write-Message -Level Verbose -Message "Removing User $user from Database $db on target $server"

                if ($Pscmdlet.ShouldProcess($user, "Removing user from Database $db on target $server")) {
                    # Drop Schemas owned by the user before dropping the user
                    # Azure SQL Database doesn't support EnumOwnedObjects(), so we need to use T-SQL query instead
                    if ($server.DatabaseEngineType -eq "SqlAzureDatabase") {
                        $splatQuery = @{
                            SqlInstance     = $server
                            Database        = $db.Name
                            Query           = "SELECT s.name FROM sys.schemas s WHERE s.principal_id = USER_ID('$($user.Name)')"
                            EnableException = $true
                        }
                        $ownedSchemaNames = Invoke-DbaQuery @splatQuery | Select-Object -ExpandProperty name
                        $schemaUrns = @()
                        foreach ($schemaName in $ownedSchemaNames) {
                            $schema = $db.Schemas[$schemaName]
                            if ($schema) {
                                $schemaUrns += $schema.Urn
                            }
                        }
                    } else {
                        $schemaUrns = $user.EnumOwnedObjects() | Where-Object Type -EQ Schema
                    }

                    if ($schemaUrns) {
                        Write-Message -Level Verbose -Message "User $user owns $($schemaUrns.Count) schema(s)."

                        # Need to gather up the schema changes so they can be done in a non-destructive order
                        foreach ($schemaUrn in $schemaUrns) {
                            $schema = $server.GetSmoObject($schemaUrn)

                            # Drop any schema that is the same name as the user
                            if ($schema.Name -EQ $user.Name) {
                                # Check for owned objects early so we can exit before any changes are made
                                $ownedUrns = $schema.EnumOwnedObjects()
                                if (-Not $ownedUrns) {
                                    $dropSchemas += $schema
                                } else {
                                    Write-Message -Level Warning -Message "User owns objects in the database and will not be removed."
                                    foreach ($ownedUrn in $ownedUrns) {
                                        $obj = $server.GetSmoObject($ownedUrn)
                                        Write-Message -Level Warning -Message "User $user owns $($obj.GetType().Name) $obj"
                                    }
                                    $ownedObjects = $true
                                }
                            }

                            # Change the owner of any schema not the same name as the user
                            if ($schema.Name -NE $user.Name) {
                                # Check for owned objects early so we can exit before any changes are made
                                $ownedUrns = $schema.EnumOwnedObjects()
                                if (($ownedUrns -And $Force) -Or (-Not $ownedUrns)) {
                                    $alterSchemas += $schema
                                } else {
                                    Write-Message -Level Warning -Message "User $user owns the Schema $schema, which owns $($ownedUrns.Count) object(s).  If you want to change the schemas' owner to [dbo] and drop the user anyway, use -Force parameter.  User $user will not be removed."
                                    $ownedObjects = $true
                                }
                            }
                        }
                    }

                    if (-Not $ownedObjects) {
                        try {
                            # Alter Schemas
                            foreach ($schema in $alterSchemas) {
                                Write-Message -Level Verbose -Message "Owner of Schema $schema will be changed to [dbo]."
                                if ($PSCmdlet.ShouldProcess($server, "Change the owner of Schema $schema to [dbo].")) {
                                    $schema.Owner = "dbo"
                                    $schema.Alter()
                                }
                            }

                            # Drop Schemas
                            foreach ($schema in $dropSchemas) {
                                if ($PSCmdlet.ShouldProcess($server, "Drop Schema $schema from Database $db.")) {
                                    $schema.Drop()
                                }
                            }

                            # Finally, Drop user
                            if ($PSCmdlet.ShouldProcess($server, "Drop User $user from Database $db.")) {
                                $user.Drop()
                            }

                            $status = "Dropped"

                        } catch {
                            Write-Error -Message "Could not drop $user from Database $db on target $server"
                            $status = "Not Dropped"
                        }

                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Database     = $db.name
                            User         = $user
                            Status       = $status
                        }
                    }
                }
            }
        }
    }

    process {
        if ($InputObject) {
            $pipedUsers += $InputObject
        } else {
            foreach ($instance in $SqlInstance) {
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }

                $databases = $server.Databases | Where-Object IsAccessible

                if ($Database) {
                    $databases = $databases | Where-Object Name -In $Database
                }
                if ($ExcludeDatabase) {
                    $databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
                }

                foreach ($db in $databases) {
                    Write-Message -Level Verbose -Message "Get users in Database $db on target $server"
                    $users = Get-DbaDbUser -SqlInstance $server -Database $db.Name
                    $users = $users | Where-Object Name -In $User
                    Remove-DbUser $users
                }
            }
        }
    }

    end {
        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaDbUser.
        Remove-DbUser $pipedUsers
    }
}