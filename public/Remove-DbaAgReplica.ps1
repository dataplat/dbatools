function Remove-DbaAgReplica {
    <#
    .SYNOPSIS
        Removes secondary replicas from SQL Server Availability Groups

    .DESCRIPTION
        Removes secondary replicas from Availability Groups by calling the Drop() method on the replica object. This is commonly used when decommissioning servers, scaling down your availability group topology, or removing failed replicas that cannot be recovered. The function accepts either direct SQL instance parameters or piped input from Get-DbaAgReplica for batch operations. All removal operations require explicit confirmation due to the high-impact nature of this change.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        The specific availability group to query.

    .PARAMETER Replica
        The replica to remove.

    .PARAMETER InputObject
        Enables piped input from Get-DbaAgReplica.

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

    .LINK
        https://dbatools.io/Remove-DbaAgReplica

    .EXAMPLE
        PS C:\> Remove-DbaAgReplica -SqlInstance sql2017a -AvailabilityGroup SharePoint -Replica sp1

        Removes the sp1 replica from the SharePoint ag on sql2017a. Prompts for confirmation.

    .EXAMPLE
        PS C:\> Remove-DbaAgReplica -SqlInstance sql2017a | Select-Object *

        Returns full object properties on all availability group replicas found on sql2017a
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [string[]]$Replica,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityReplica[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object"
            return
        }

        if ($SqlInstance -and -not $Replica) {
            Stop-Function -Message "You must specify a replica when using the SqlInstance parameter."
            return
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaAgReplica -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Replica $Replica -AvailabilityGroup $AvailabilityGroup
        }

        foreach ($agreplica in $InputObject) {
            if ($Pscmdlet.ShouldProcess($agreplica.Parent.Parent.Name, "Removing availability group replica $agreplica")) {
                try {
                    $agreplica.Drop()
                    [PSCustomObject]@{
                        ComputerName      = $agreplica.ComputerName
                        InstanceName      = $agreplica.InstanceName
                        SqlInstance       = $agreplica.SqlInstance
                        AvailabilityGroup = $agreplica.Parent.AvailabilityGroup
                        Replica           = $agreplica.Name
                        Status            = "Removed"
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}