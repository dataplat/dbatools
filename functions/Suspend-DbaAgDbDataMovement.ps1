function Suspend-DbaAgDbDataMovement {
    <#
    .SYNOPSIS
        Suspends data movement for an availability group database on a SQL Server instance.

    .DESCRIPTION
        Suspends data movement for an availability group database on a SQL Server instance.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database or databases to suspend movement upon.

    .PARAMETER AvailabilityGroup
        The availability group where the database movement will be suspended.

    .PARAMETER InputObject
        Enables piping from Get-DbaAgDatabase

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
        https://dbatools.io/Suspend-DbaAgDbDataMovement

    .EXAMPLE
        PS C:\> Suspend-DbaAgDbDataMovement -SqlInstance sql2017a -AvailabilityGroup ag1 -Database db1, db2

        Suspends data movement on db1 and db2 to ag1 on sql2017a. Prompts for confirmation.

    .EXAMPLE
        PS C:\> Get-DbaAgDatabase -SqlInstance sql2017a, sql2019 | Out-GridView -Passthru | Suspend-DbaAgDbDataMovement -Confirm:$false

        Suspends data movement on the selected availability group databases. Does not prompt for confirmation.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$AvailabilityGroup,
        [string[]]$Database,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityDatabase[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object"
            return
        }

        if ((Test-Bound -ParameterName SqlInstance)) {
            if ((Test-Bound -Not -ParameterName Database) -and (Test-Bound -Not -ParameterName AvailabilityGroup)) {
                Stop-Function -Message "You must specify one or more databases and one Availability Groups when using the SqlInstance parameter."
                return
            }
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaAgDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($agdb in $InputObject) {
            if ($Pscmdlet.ShouldProcess($ag.Parent.Name, "Seting availability group $db to $($db.Parent.Name)")) {
                try {
                    $null = $agdb.SuspendDataMovement()
                    $agdb
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}