function New-DbaDbSchema {
    <#
    .SYNOPSIS
        Creates new database schemas with specified ownership for organizing objects and implementing security boundaries.

    .DESCRIPTION
        Creates new database schemas within SQL Server databases, allowing you to organize database objects into logical groups and implement security boundaries. Schemas provide a way to separate tables, views, procedures, and other objects by ownership or function, which is essential for multi-tenant applications, security models, and organized database development. You can create multiple schemas across multiple databases in a single operation and specify the database user who will own each schema.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the target database(s) where the new schemas will be created. Accepts multiple database names.
        Required when using SqlInstance parameter, and supports wildcards for pattern matching across database names.

    .PARAMETER Schema
        Specifies the name(s) of the schema(s) to create within the target databases. Accepts multiple schema names for batch creation.
        Schema names must be valid SQL Server identifiers and will fail if they already exist in the target database.

    .PARAMETER SchemaOwner
        Specifies the database user who will own the created schema(s). Must be an existing user in the target database.
        When omitted, the schema owner defaults to 'dbo'. Use this to implement security boundaries or assign schemas to application users.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase via pipeline input, eliminating the need to specify SqlInstance and Database parameters.
        Use this approach when you need to work with a pre-filtered set of databases or want to chain multiple dbatools commands together.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Schema, Database
        Author: Adam Lancaster, github.com/lancasteradam

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaDbSchema

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Schema

        Returns one Schema object for each schema created. One schema is created per Schema parameter value in each target database.

        This command returns the raw SMO Schema object with all standard SMO properties accessible.

        Key properties include:
        - Name: The name of the newly created schema
        - Owner: The database user that owns the schema (dbo by default, or custom owner if SchemaOwner is specified)
        - Parent: Reference to the parent Database object
        - CreateDate: DateTime when the schema was created
        - State: The current state of the schema object (Existing, Creating, Pending, etc.)
        - Urn: The Uniform Resource Name of the schema object

        All standard SMO Schema properties are accessible.

    .EXAMPLE
        PS C:\> New-DbaDbSchema -SqlInstance localhost -Database example1 -Schema TestSchema1

        Creates the TestSchema1 schema in the example1 database in the localhost instance. The dbo user will be the owner of the schema.

    .EXAMPLE
        PS C:\> New-DbaDbSchema -SqlInstance localhost -Database example1 -Schema TestSchema1, TestSchema2 -SchemaOwner dbatools

        Creates the TestSchema1 and TestSchema2 schemas in the example1 database in the localhost instance and assigns the dbatools user as the owner of the schemas.

    .EXAMPLE
        PS C:\> New-DbaDbSchema -SqlInstance localhost, localhost\sql2017 -Database example1 -Schema TestSchema1, TestSchema2 -SchemaOwner dbatools

        Creates the TestSchema1 and TestSchema2 schemas in the example1 database in the localhost and localhost\sql2017 instances and assigns the dbatools user as the owner of the schemas.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance localhost, localhost\sql2017 -Database example1 | New-DbaDbSchema -Schema TestSchema1, TestSchema2 -SchemaOwner dbatools

        Passes in the example1 db via pipeline and creates the TestSchema1 and TestSchema2 schemas and assigns the dbatools user as the owner of the schemas.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Schema,
        [string]$SchemaOwner,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {

        if (Test-Bound -Not -ParameterName Schema) {
            Stop-Function -Message "Schema is required"
            return
        }

        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when SqlInstance is specified"
            return
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {

            foreach ($sName in $Schema) {

                if ($db.Schemas.Name -contains $sName) {
                    Stop-Function -Message "Schema $sName already exists in the database $($db.Name) on $($db.Parent.Name)" -Continue
                }

                if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Creating the schema $sName on the database $($db.Name)")) {
                    try {
                        $newSchema = New-Object Microsoft.SqlServer.Management.Smo.Schema -ArgumentList $db, $sName

                        if (Test-Bound SchemaOwner) {
                            $newSchema.Owner = $SchemaOwner
                        }

                        $newSchema.Create()
                        $newSchema
                    } catch {
                        Stop-Function -Message "Failure on $($db.Parent.Name) to create the schema $sName in the database $($db.Name)" -ErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}