function Remove-DbaAgDatabase {
    <#
    .SYNOPSIS
        Removes databases from availability groups on SQL Server instances.

    .DESCRIPTION
        Removes databases from availability groups, effectively stopping replication and high availability protection for those databases. This is commonly needed when decommissioning databases, reconfiguring availability group membership during maintenance windows, or troubleshooting replication issues. The function safely removes the database from all replicas in the availability group while preserving the actual database files on each replica. You can target specific databases and availability groups, or use pipeline input from Get-DbaAgDatabase to remove multiple databases efficiently.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to remove from their availability groups. Accepts multiple database names as an array.
        Required when using SqlInstance parameter. Use this to target specific databases rather than removing all databases from an availability group.

    .PARAMETER AvailabilityGroup
        Limits the operation to databases within specific availability groups. When specified, only databases belonging to these availability groups will be removed.
        Useful when you have databases with the same name across multiple availability groups and need to target specific groups.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER InputObject
        Accepts availability group database objects from Get-DbaAgDatabase or database objects from Get-DbaDatabase through the pipeline.
        This enables efficient batch operations and complex filtering scenarios using the pipeline.

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
        https://dbatools.io/Remove-DbaAgDatabase

    .EXAMPLE
        PS C:\> Remove-DbaAgDatabase -SqlInstance sqlserver2012 -AvailabilityGroup ag1, ag2 -Confirm:$false

        Removes all databases from the ag1 and ag2 availability groups on sqlserver2012.  Does not prompt for confirmation.

    .EXAMPLE
        PS C:\> Remove-DbaAgDatabase -SqlInstance sqlserver2012 -AvailabilityGroup ag1 -Database pubs -Confirm:$false

        Removes the pubs database from the ag1 availability group on sqlserver2012.  Does not prompt for confirmation.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sqlserver2012 -AvailabilityGroup availabilitygroup1 | Remove-DbaAgDatabase

        Removes the availability groups returned from the Get-DbaAvailabilityGroup function. Prompts for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$AvailabilityGroup,
        # needs to accept db or agdb so generic object

        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object"
            return
        }

        if ((Test-Bound -ParameterName SqlInstance)) {
            if ((Test-Bound -Not -ParameterName Database)) {
                Stop-Function -Message "You must specify one or more databases and one or more Availability Groups when using the SqlInstance parameter."
                return
            }
        }

        if ($InputObject) {
            if ($InputObject[0].GetType().Name -eq 'Database') {
                $Database += $InputObject.Name
            }
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaAgDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            if ($Pscmdlet.ShouldProcess($db.Parent.Parent.Name, "Removing availability group database $db")) {
                try {
                    $ag = $db.Parent.Name
                    $db.Parent.AvailabilityDatabases[$db.Name].Drop()
                    [PSCustomObject]@{
                        ComputerName      = $db.ComputerName
                        InstanceName      = $db.InstanceName
                        SqlInstance       = $db.SqlInstance
                        AvailabilityGroup = $ag
                        Database          = $db.Name
                        Status            = "Removed"
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}