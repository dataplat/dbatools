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
        The target database(s).

    .PARAMETER Schema
        The name(s) of the schema(s)

    .PARAMETER SchemaOwner
        The name of the database user that will own the schema(s).

    .PARAMETER InputObject
        Allows piping from Get-DbaDatabase.

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