function Remove-DbaAgListener {
    <#
    .SYNOPSIS
        Removes a listener from an availability group on a SQL Server instance.

    .DESCRIPTION
        Removes a listener from an availability group on a SQL Server instance.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Listener
        The listener or listeners to remove.

    .PARAMETER AvailabilityGroup
        Only remove listeners from specific availability groups.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER InputObject
        Enables piping from Get-DbaListener

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
        https://dbatools.io/Remove-DbaAgListener

    .EXAMPLE
        PS C:\> Remove-DbaAgListener -SqlInstance sqlserver2012 -AvailabilityGroup ag1, ag2 -Confirm:$false

        Removes the ag1 and ag2 availability groups on sqlserver2012. Does not prompt for confirmation.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sqlserver2012 -AvailabilityGroup availabilitygroup1 | Remove-DbaAgListener

        Removes the listeners returned from the Get-DbaAvailabilityGroup function. Prompts for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Listener,
        [string[]]$AvailabilityGroup,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroupListener[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound -ParameterName SqlInstance)) {
            if ((Test-Bound -Not -ParameterName Listener)) {
                Stop-Function -Message "You must specify one or more listeners and one or more Availability Groups when using the SqlInstance parameter."
                return
            }
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaAgListener -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Listener $Listener
        }

        foreach ($aglistener in $InputObject) {
            if ($Pscmdlet.ShouldProcess($aglistener.Parent.Parent.Name, "Removing availability group listener $aglistener")) {
                try {
                    $ag = $aglistener.Parent.Name
                    $aglistener.Parent.AvailabilityGroupListeners[$aglistener.Name].Drop()
                    [pscustomobject]@{
                        ComputerName      = $aglistener.ComputerName
                        InstanceName      = $aglistener.InstanceName
                        SqlInstance       = $aglistener.SqlInstance
                        AvailabilityGroup = $ag
                        Listener          = $aglistener.Name
                        Status            = "Removed"
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}