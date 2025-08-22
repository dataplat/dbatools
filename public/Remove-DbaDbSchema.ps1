function Remove-DbaDbSchema {
    <#
    .SYNOPSIS
        Removes database schemas from one or more SQL Server databases.

    .DESCRIPTION
        Removes database schemas from SQL Server databases using the DROP SCHEMA T-SQL command. This function is useful for cleaning up unused schemas during database maintenance, development environment resets, or application decommissioning. The schema must be completely empty before removal - any tables, views, functions, or other objects within the schema will prevent the drop operation from succeeding. You'll need to remove or relocate all schema objects first before running this command.

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
        https://dbatools.io/Remove-DbaDbSchema

    .EXAMPLE
        PS C:\> Remove-DbaDbSchema -SqlInstance sqldev01 -Database example1 -Schema TestSchema1

        Removes the TestSchema1 schema in the example1 database in the sqldev01 instance.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqldev01, sqldev02 -Database example1 | Remove-DbaDbSchema -Schema TestSchema1, TestSchema2

        Passes in the example1 db via pipeline and removes the TestSchema1 and TestSchema2 schemas.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [Parameter(Mandatory)]
        [string[]]$Schema,
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

                if ($Pscmdlet.ShouldProcess($db.Parent.Name, "Dropping the schema $sName on the database $($db.Name)")) {
                    try {
                        $schemaObject = $db | Get-DbaDbSchema -Schema $sName
                        $schemaObject.Drop()
                    } catch {
                        Stop-Function -Message "Failure on $($db.Parent.Name) to drop the schema $sName in the database $($db.Name)" -ErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}