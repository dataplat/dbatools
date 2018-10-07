#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Remove-DbaAvailabilityGroup {
<#
    .SYNOPSIS
        Removes availability groups on a SQL Server instance.

    .DESCRIPTION
        Removes availability groups on a SQL Server instance.

        If possible, remove the availability group only while connected to the server instance that hosts the primary replica.
        When the availability group is dropped from the primary replica, changes are allowed in the former primary databases (without high availability protection).
        Deleting an availability group from a secondary replica leaves the primary replica in the RESTORING state, and changes are not allowed on the databases.

        Avoid dropping an availability group when the Windows Server Failover Clustering (WSFC) cluster has no quorum.
        If you must drop an availability group while the cluster lacks quorum, the metadata availability group that is stored in the cluster is not removed.
        After the cluster regains quorum, you will need to drop the availability group again to remove it from the WSFC cluster.

        For more information: https://docs.microsoft.com/en-us/sql/t-sql/statements/drop-availability-group-transact-sql

    .PARAMETER SqlInstance
        SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER AvailabilityGroup
        Only remove specific availability groups.

    .PARAMETER AllAvailabilityGroups
        Remove all availability groups on an instance, ignoring the packaged availability groups: AlwaysOn_health, system_health, telemetry_xevents.

    .PARAMETER InputObject
        Internal parameter to support piping from Get-DbaAvailabilityGroup

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
        https://dbatools.io/Remove-DbaAvailabilityGroup

    .EXAMPLE
        PS C:\> Remove-DbaAvailabilityGroup -SqlInstance sqlserver2012 -AllAvailabilityGroups

        Removes all availability groups on the sqlserver2014 instance. Prompts for confirmation.

    .EXAMPLE
        PS C:\> Remove-DbaAvailabilityGroup -SqlInstance sqlserver2012 -AvailabilityGroups ag1, ag2 -Confirm:$false

        Removes the ag1 and ag2 availability groups on sqlserver2012.  Does not prompt for confirmation.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sqlserver2012 -AvailabilityGroups availability group1 | Remove-DbaAvailabilityGroup

        Removes the availability groups returned from the Get-DbaAvailabilityGroup function. Prompts for confirmation.
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [switch]$AllAvailabilityGroups,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName AvailabilityGroups, AllAvailabilityGroups)) {
            Stop-Function -Message "You must specify AllAvailabilityGroups groups or AvailabilityGroups when using the SqlInstance parameter."
            return
        }
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $instance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        }

        foreach ($ag in $InputObject) {
            if ($Pscmdlet.ShouldProcess("$instance", "Removing availability group $ag from $($ag.Parent)")) {
                # avoid enumeration issues
                $ag.Parent.Query("DROP AVAILABILITY GROUP [$($ag.Name)]")
                try {
                    [pscustomobject]@{
                        ComputerName = $ag.ComputerName
                        InstanceName = $ag.InstanceName
                        SqlInstance  = $ag.SqlInstance
                        AvailabilityGroups = $ag.Name
                        Status       = "Removed"
                    }
                }
                catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}