function Set-DbaAgListener {
    <#
    .SYNOPSIS
        Sets a listener property for an availability group on a SQL Server instance.

    .DESCRIPTION
        Sets a listener property for an availability group on a SQL Server instance.

        Basically, only the port is settable at this time, so this command updates the listener port.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        The Availability Group to which a property will be changed.

    .PARAMETER Port
        Sets the port number used to communicate with the availability group.

    .PARAMETER Listener
        Modify only specific listeners.

    .PARAMETER InputObject
        Enables piping from Get-DbaAvailabilityGroup

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AvailabilityGroup, HA, AG
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaAgListener

    .EXAMPLE
        PS C:\> Set-DbaAgListener -SqlInstance sql2017 -AvailabilityGroup SharePoint -Port 14333

        Changes the port for the SharePoint AG Listener on sql2017. Prompts for confirmation.

    .EXAMPLE
        PS C:\> Get-DbaAgListener -SqlInstance sql2017 | Out-GridView -Passthru | Set-DbaAgListener -Port 1433 -Confirm:$false

        Changes the port for selected AG listeners to 1433. Does not prompt for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [string[]]$Listener,
        [Parameter(Mandatory)]
        [int]$Port,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName AvailabilityGroup)) {
            Stop-Function -Message "You must specify one or more databases and one or more Availability Groups when using the SqlInstance parameter."
            return
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaAgListener -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup -Listener $Listener
        }

        foreach ($aglistener in $InputObject) {
            if ($Pscmdlet.ShouldProcess($ag.Parent.Name, "Setting port to $Port for $($ag.Name)")) {
                try {
                    $aglistener.PortNumber = $Port
                    $aglistener.Alter()
                    $aglistener
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_
                }
            }
        }
    }
}