function Remove-DbaAvailabilityGroup {
    <#
    .SYNOPSIS
        Removes availability groups from SQL Server instances using DROP AVAILABILITY GROUP.

    .DESCRIPTION
        Removes availability groups from SQL Server instances by executing the DROP AVAILABILITY GROUP T-SQL command. This is typically used when decommissioning high availability setups, migrating to different solutions, or cleaning up test environments.

        The function handles the complex considerations around properly removing availability groups to avoid leaving databases in problematic states. If possible, remove the availability group only while connected to the server instance that hosts the primary replica.
        When the availability group is dropped from the primary replica, changes are allowed in the former primary databases (without high availability protection).
        Deleting an availability group from a secondary replica leaves the primary replica in the RESTORING state, and changes are not allowed on the databases.

        Avoid dropping an availability group when the Windows Server Failover Clustering (WSFC) cluster has no quorum.
        If you must drop an availability group while the cluster lacks quorum, the metadata availability group that is stored in the cluster is not removed.
        After the cluster regains quorum, you will need to drop the availability group again to remove it from the WSFC cluster.

        For more information: https://docs.microsoft.com/en-us/sql/t-sql/statements/drop-availability-group-transact-sql

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        Specifies the name(s) of specific availability groups to remove. Accepts multiple values and wildcards for pattern matching.
        Use this when you need to remove only certain availability groups rather than all groups on the instance.

    .PARAMETER AllAvailabilityGroups
        Removes all availability groups found on the specified SQL Server instance.
        Use this switch when decommissioning a server or performing bulk cleanup operations.

    .PARAMETER InputObject
        Accepts availability group objects from Get-DbaAvailabilityGroup for pipeline operations.
        Use this when you need to filter or pre-process availability groups before removal.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Returns one object per availability group that is successfully removed.

        Properties:
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The name of the SQL Server instance (e.g., "MSSQLSERVER" for default instance)
        - SqlInstance: The full SQL Server instance name in format ComputerName\InstanceName
        - AvailabilityGroup: The name of the availability group that was removed
        - Status: Always "Removed" when the availability group is successfully dropped

    .NOTES
        Tags: AG, HA
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
        PS C:\> Remove-DbaAvailabilityGroup -SqlInstance sqlserver2012 -AvailabilityGroup ag1, ag2 -Confirm:$false

        Removes the ag1 and ag2 availability groups on sqlserver2012.  Does not prompt for confirmation.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sqlserver2012 -AvailabilityGroup availabilitygroup1 | Remove-DbaAvailabilityGroup

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
        if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object"
            return
        }

        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName AvailabilityGroup, AllAvailabilityGroups)) {
            Stop-Function -Message "You must specify AllAvailabilityGroups groups or AvailabilityGroups when using the SqlInstance parameter."
            return
        }
        if ($SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        }
        foreach ($ag in $InputObject) {
            if ($Pscmdlet.ShouldProcess($ag.Parent.Name, "Removing availability group $ag")) {
                # avoid enumeration issues
                try {
                    $null = $ag.Parent.Query("DROP AVAILABILITY GROUP $ag")
                    [PSCustomObject]@{
                        ComputerName      = $ag.ComputerName
                        InstanceName      = $ag.InstanceName
                        SqlInstance       = $ag.SqlInstance
                        AvailabilityGroup = $ag.Name
                        Status            = "Removed"
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}