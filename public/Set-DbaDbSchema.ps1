function Set-DbaDbSchema {
    <#
    .SYNOPSIS
        Changes the owner of database schemas to reassign security and object ownership responsibilities

    .DESCRIPTION
        Modifies the ownership of database schemas by updating the schema owner property in SQL Server. This is commonly needed when reorganizing database security, transferring ownership from developers to service accounts, or standardizing schema ownership after database migrations. The function works by retrieving the schema object and updating its Owner property through SQL Server Management Objects, then applying the change to the database.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases contain the schemas to be updated. Required when using SqlInstance parameter.
        Use this to target specific databases where you need to change schema ownership.

    .PARAMETER Schema
        Specifies the name(s) of the database schemas whose ownership will be changed. Accepts multiple schema names.
        Common scenarios include transferring ownership from developers to service accounts or standardizing ownership after migrations.

    .PARAMETER SchemaOwner
        Specifies the database user or role that will become the new owner of the specified schemas. Must be a valid database principal.
        Typically used to assign ownership to service accounts, application users, or standardized roles like db_owner.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase via pipeline input. Use this to work with database objects already retrieved.
        Useful when you want to filter databases first or work with databases from multiple instances in a single operation.

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
        https://dbatools.io/Set-DbaDbSchema

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Schema

        Returns one Schema object for each schema updated. The returned schema objects are the updated SMO objects after the owner has been changed and the Alter() method has been applied.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: The name of the schema that was updated
        - IsSystemObject: Boolean indicating if this is a built-in system schema or custom user-defined schema

        Additional properties available (from SMO Schema object):
        - Owner: The new owner of the schema (updated to the value specified by -SchemaOwner)
        - DatabaseName: The name of the database containing the schema
        - DatabaseId: The unique identifier (ID) of the database
        - CreateDate: DateTime when the schema was created
        - DateLastModified: DateTime when the schema was last modified
        - ID: The schema's unique object ID within the database
        - Urn: The Urn identifier for the schema

        All properties from the base SMO Schema object are accessible via Select-Object * even though only default properties are displayed. When -WhatIf is used, no output objects are returned.

    .EXAMPLE
        PS C:\> Set-DbaDbSchema -SqlInstance sqldev01 -Database example1 -Schema TestSchema1 -SchemaOwner dbatools

        Updates the TestSchema1 schema in the example1 database in the sqldev01 instance. The dbatools user will be the new owner of the schema.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqldev01, sqldev02 -Database example1 | Set-DbaDbSchema -Schema TestSchema1, TestSchema2 -SchemaOwner dbatools

        Passes in the example1 db via pipeline and updates the TestSchema1 and TestSchema2 schemas and assigns the dbatools user as the owner of the schemas.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [Parameter(Mandatory)]
        [string[]]$Schema,
        [Parameter(Mandatory)]
        [string]$SchemaOwner,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {

        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when SqlInstance is specified"
            return
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {

            foreach ($sName in $Schema) {

                if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Updating the schema $sName on the database $($db.Name) to be owned by $SchemaOwner")) {
                    try {
                        $schemaObject = $db | Get-DbaDbSchema -Schema $sName
                        $schemaObject.Owner = $SchemaOwner
                        $schemaObject.Alter()
                        $schemaObject
                    } catch {
                        Stop-Function -Message "Failure on $($db.Parent.Name) to update the schema owner for $sName in the database $($db.Name)" -ErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}