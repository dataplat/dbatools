function Set-DbaAgListener {
    <#
    .SYNOPSIS
        Modifies the port number for Availability Group listeners on SQL Server instances.

    .DESCRIPTION
        Modifies the port number for Availability Group listeners, allowing you to change the network port that clients use to connect to the availability group. This is commonly needed when standardizing ports across environments, resolving port conflicts with other services, or implementing security policies that require non-default ports. The command works with existing listeners and requires the availability group to be online to complete the port change.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        Specifies the name of the availability group containing the listener to modify. Required when using SqlInstance parameter.
        Use this to target specific availability groups when multiple groups exist on the same instance.

    .PARAMETER Port
        Sets the new port number for the availability group listener. This is the TCP port clients will use to connect to the availability group.
        Commonly changed to standardize ports across environments, resolve conflicts with other services, or meet security requirements.

    .PARAMETER Listener
        Specifies the name of specific listeners to modify within the availability group. Optional parameter to target only certain listeners.
        Use this when an availability group has multiple listeners and you only want to change the port for specific ones.

    .PARAMETER InputObject
        Accepts availability group listener objects from the pipeline, typically from Get-DbaAgListener. Allows you to chain commands together.
        Use this approach when you want to filter or select specific listeners before modifying their ports.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AG, HA
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.AvailabilityGroupListener

        Returns the modified availability group listener object for each listener that was successfully updated. This is the same object type as returned by Get-DbaAgListener, but with the modified port number applied.

        Properties available on the returned object include:
        - Name: The name of the availability group listener
        - AvailabilityGroup: The name of the parent availability group
        - PortNumber: The port number for client connections (modified by this command)
        - IPAddress: The IP address for the listener
        - SubnetMask: The subnet mask for the listener
        - Parent: Reference to the parent AvailabilityGroup object

        All properties from the base SMO AvailabilityGroupListener object are accessible using Select-Object *.

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
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroupListener[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object"
            return
        }
        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName AvailabilityGroup)) {
            Stop-Function -Message "You must specify one or more Availability Groups when using the SqlInstance parameter."
            return
        }

        if ($SqlInstance) {
            if (Test-Bound -ParameterName Listener) {
                $InputObject += Get-DbaAgListener -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup -Listener $Listener
            } else {
                $InputObject += Get-DbaAgListener -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
            }
        }

        foreach ($aglistener in $InputObject) {
            if ($Pscmdlet.ShouldProcess($aglistener.Parent.Name, "Setting port to $Port for $($aglistener.Name)")) {
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