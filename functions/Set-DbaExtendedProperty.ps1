function Set-DbaExtendedProperty {
    <#
    .SYNOPSIS
        Set extended property values

    .DESCRIPTION
        Set extended property values

        You can set extended properties on all these different types of objects:

        Aggregate
        Assembly
        Column
        Constraint
        Contract
        Database
        Event Notification
        Filegroup
        Function
        Index
        Logical File Name
        Message Type
        Parameter
        Partition Function
        Partition Scheme
        Procedure
        Queue
        Remote Service Binding
        Route
        Rule
        Schema
        Service
        Synonym
        Table
        Trigger
        Type
        View
        Xml Schema Collection

    .PARAMETER InputObject
        Enables piping from Get-DbaExtendedProperty

    .PARAMETER Value
        The new value for the extended property

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