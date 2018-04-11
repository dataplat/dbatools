function Remove-DbaDbUser {
    <#
    .SYNOPSIS
    Drop database user

    .DESCRIPTION
    If user is the owner of a schema with the same name and if if the schema does not have any underlying objects the schema will be
    dropped.  If user owns more than one schema, the owner of the schemas that does not have the same name as the user, will be
    changed to 'dbo'. If schemas have underlying objects, you must specify the -Force parameter so the user can be dropped.

    .PARAMETER SqlInstance
    The SQL Instances that you're connecting to.

    .PARAMETER SqlCredential
    Credential object used to connect to the SQL Server as a different user.

    .PARAMETER Database
    Specifies the database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
    Specifies the database(s) to exclude from processing. Options for this list are auto-populated from the server.

    .PARAMETER User
    Specifies the list of users to remove.

    .PARAMETER InputObject
    Support piping from Get-DbaDatabaseUser.

    .PARAMETER Force
    If enabled this will force the change of the owner to 'dbo' for any schema which owner is the User.

    .PARAMETER WhatIf
    Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
    If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Tags: Databases, User
    Author: Doug Meyers (@dgmyrs)

    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: MIT https://opensource.org/licenses/MIT

    .LINK
    https://dbatools.io/Remove-DbaDbUser

    .EXAMPLE
    Remove-DbaDbUser -SqlInstance sqlserver2014 -User user1

    Drops user1 from all databases it exists in on server 'sqlserver2014'.

    .EXAMPLE
    Remove-DbaDbUser -SqlInstance sqlserver2014 -Database database1 -User user1

    Drops user1 from the database1 database on server 'sqlserver2014'.

    .EXAMPLE
    Remove-DbaDbUser -SqlInstance sqlserver2014 -ExcludeDatabase model -User user1

    Drops user1 from all databases it exists in on server 'sqlserver2014' except for the model database.

    .EXAMPLE
    Get-DbaDatabaseUser sqlserver2014 | Where-Object Name -In "user1" | Remove-DbaDbUser

    Drops user1 from all databases it exists in on server 'sqlserver2014'.

#>

    [CmdletBinding(DefaultParameterSetName = 'User', SupportsShouldProcess = $true)]
    Param (
        [parameter(Position = 1, Mandatory, ValueFromPipeline, ParameterSetName = 'User')]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,

        [parameter(ParameterSetName = 'User')]
        [Alias("Credential")]
        [PSCredential]
        $SqlCredential,

        [parameter(ParameterSetName = 'User')]
        [Alias("Databases")]
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

        [Alias('Silent')]
        [switch]$EnableException
    )

    begin {
        function Remove-DbUser {
            [CmdletBinding()]
            param ([Microsoft.SqlServer.Management.Smo.User[]]$users)

            foreach ($user in $users) {
                $db = $user.Parent
                $server = $db.Parent
                $ownedObjects = $false
                Write-Message -Level Verbose -Message "Removing User $user from Database $db on target $server"

                # Drop Schemas owned by the user before droping the user
                $schemaUrns = $user.EnumOwnedObjects() | Where-Object Type -EQ Schema
                if ($schemaUrns) {
                    Write-Message -Level Verbose -Message "User $user owns $($schemaUrns.Count) schema(s)."

                    # Need to gather up the schema changes so they can be done in a non-desctructive order
                    $alterSchemas = @()
                    $dropSchemas = @()

                    foreach ($schemaUrn in $schemaUrns) {
                        $schema = $server.GetSmoObject($schemaUrn)

                        # Drop any schema that is the same name as the user
                        if ($schema.Name -EQ $user.Name) {
                            # Check for owned objects early so we can exit before any changes are made
                            $ownedUrns = $schema.EnumOwnedObjects()
                            if (-Not $ownedUrns) {
                                $dropSchemas += $schema
                            }
                            else {
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
                            }
                            else {
                                Write-Message -Level Warning -Message "User $user owns the Schema $schema, which owns $($ownedUrns.Count) Object(s).  If you want to change the schemas' owner to [dbo] and drop the user anyway, use -Force parameter.  User $user will not be removed."
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

                    }
                    catch {
                        Write-Error -Message "Could not drop $user from Database $db on target $server"
                        $status = "Not Dropped"
                    }

                    [pscustomobject]@{
                        ComputerName = $server.NetName
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

    process {
        if ($InputObject) {
            Remove-DbUser $InputObject
        }
        else {
            foreach ($instance in $SqlInstance) {
                try {
                    Write-Message -Level Verbose -Message "Connecting to $instance"
                    $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
                }
                catch {
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
                    $users = Get-DbaDatabaseUser -SqlInstance $server -Database $db.Name
                    $users = $users | Where-Object Name -In $User
                    Remove-DbUser $users
                }
            }
        }
    }

}