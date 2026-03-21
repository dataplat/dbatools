function Set-DbaExtendedProperty {
    <#
    .SYNOPSIS
        Updates the value of existing extended properties on SQL Server database objects

    .DESCRIPTION
        Updates the value of existing extended properties on SQL Server database objects. Extended properties store custom metadata like application versions, documentation, or business rules directly with database objects. This function modifies the values of properties that already exist, making it useful for maintaining application version numbers, updating documentation, or batch-modifying metadata across multiple objects.

        Works with extended properties on all SQL Server object types including databases, tables, views, stored procedures, functions, columns, indexes, schemas, and many others. The function accepts extended property objects from Get-DbaExtendedProperty through the pipeline, so you can easily filter and update specific properties across your environment.

    .PARAMETER InputObject
        Accepts extended property objects from Get-DbaExtendedProperty to update their values. Use this to pipeline specific extended properties that you want to modify.
        Typically used after filtering extended properties by name, object type, or other criteria to batch update property values across multiple database objects.

    .PARAMETER Value
        Specifies the new value to assign to the extended property. Accepts any string value including version numbers, descriptions, or configuration data.
        Common uses include updating application version numbers, modifying documentation text, or changing configuration values stored as extended properties.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: General, ExtendedProperties
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaExtendedProperty

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.ExtendedProperty

        Returns the updated ExtendedProperty object for each extended property modified. The returned object reflects all changes made by the Alter() method.

        Default properties returned:
        - Name: The name of the extended property
        - Value: The updated value that was set

        Additional properties available (from SMO ExtendedProperty object):
        - ID: The identifier of the extended property
        - Parent: The parent object that this extended property is attached to
        - State: The current state of the SMO object (Existing, Creating, Pending, etc.)
        - Urn: The Uniform Resource Name (URN) of the extended property
        - Properties: Collection of SQL Server object properties

        All properties from the base SMO ExtendedProperty object are accessible using Select-Object *.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance localhost -Database mydb | Get-DbaExtendedProperty -Name appversion | Set-DbaExtendedProperty -Value "1.1.0"

        Sets the value of appversion to 1.1.0 on the mydb database

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance localhost -Database mydb -Table mytable | Get-DbaExtendedProperty -Name appversion | Set-DbaExtendedProperty -Value "1.1.0"

        Sets the value of appversion to 1.1.0 on the mytable table of the mydb database
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [parameter(ValueFromPipeline, Mandatory)]
        [Microsoft.SqlServer.Management.Smo.ExtendedProperty[]]$InputObject,
        [parameter(Mandatory)]
        [string]$Value,
        [switch]$EnableException
    )
    process {
        foreach ($object in $InputObject) {
            if ($Pscmdlet.ShouldProcess($object.Name, "Updating value from '$($object.Value)' to '$Value'")) {
                try {
                    Write-Message -Level System -Message "Updating value from '$($object.Value)' to '$Value'"
                    $object.Value = $Value
                    $object.Alter()
                    $object.Refresh()
                    $object
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}