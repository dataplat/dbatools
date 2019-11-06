function Invoke-DbaAgFailover {
    <#
    .SYNOPSIS
        Failover an availability group.

    .DESCRIPTION
        Failover an availability group.

    .PARAMETER SqlInstance
        The SQL Server instance. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance..

    .PARAMETER AvailabilityGroup
        Only failover specific availability groups.

    .PARAMETER InputObject
        Enables piping from Get-DbaAvailabilityGroup

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Force
        Force Failover and allow data loss

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
        https://dbatools.io/Invoke-DbaAgFailover

    .EXAMPLE
        PS C:\> Invoke-DbaAgFailover -SqlInstance sql2017 -AvailabilityGroup SharePoint

        Safely (no potential data loss) fails over the SharePoint AG to sql2017. Prompts for confirmation.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql2017 | Out-GridView -Passthru | Invoke-DbaAgFailover -Confirm:$false

        Safely (no potential data loss) fails over the selected availability groups to sql2017. Does not prompt for confirmation.

    .EXAMPLE
        PS C:\> Invoke-DbaAgFailover -SqlInstance sql2017 -AvailabilityGroup SharePoint -Force

        Forcefully (with potential data loss) fails over the SharePoint AG to sql2017. Prompts for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (-not $SqlInstance -and -not $InputObject) {
            Stop-Function -Message "You must either specify the SqlInstance parameter or pass in at least one AvailabilityGroup object."
            return
        }

        if ($SqlInstance -and -not $AvailabilityGroup) {
            Stop-Function -Message "You must specify at least one availability group when using SqlInstance."
            return
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        }

        foreach ($ag in $InputObject) {
            try {
                $server = $ag.Parent
                if ($Force) {
                    if ($Pscmdlet.ShouldProcess($server.Name, "Forcefully failing over $($ag.Name), allowing potential data loss")) {
                        $ag.FailoverWithPotentialDataLoss()
                        $ag.Refresh()
                        $ag
                    }
                } else {
                    if ($Pscmdlet.ShouldProcess($server.Name, "Gracefully failing over $($ag.Name)")) {
                        $ag.Failover()
                        $ag.Refresh()
                        $ag
                    }
                }
            } catch {
                Stop-Function -Continue -Message "Failure" -ErrorRecord $_
            }
        }
    }
}