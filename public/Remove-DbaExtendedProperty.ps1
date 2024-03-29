function Remove-DbaExtendedProperty {
    <#
    .SYNOPSIS
        Drops an extended property

    .DESCRIPTION
        Drops an extended property

    .PARAMETER InputObject
        Enables piping from Get-DbaExtendedProperty

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: extendedproperties
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaExtendedProperty


    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance localhost -Database mydb | Get-DbaExtendedProperty -Name appversion | Remove-DbaExtendedProperty

        Removes the appversion extended property from the mydb database

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance localhost -Database mydb -Table mytable | Get-DbaExtendedProperty -Name appversion | Remove-DbaExtendedProperty -Confirm:$false

        Removes the appversion extended property on the mytable table of the mydb database and does not prompt for confirmation
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [parameter(ValueFromPipeline, Mandatory)]
        [Microsoft.SqlServer.Management.Smo.ExtendedProperty[]]$InputObject,
        [switch]$EnableException
    )
    process {
        foreach ($object in $InputObject) {
            if ($Pscmdlet.ShouldProcess($object.Name, "Dropping")) {
                $db = $object | Get-ConnectionParent -Database
                try {
                    $null = $db.Invoke("EXEC sp_dropextendedproperty @name = N'$($object.Name)'; ")
                    [PSCustomObject]@{
                        ComputerName = $object.ComputerName
                        InstanceName = $object.InstanceName
                        SqlInstance  = $object.SqlInstance
                        ParentName   = $object.ParentName
                        PropertyType = $object.Type
                        Name         = $object.Name
                        Status       = "Dropped"
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}