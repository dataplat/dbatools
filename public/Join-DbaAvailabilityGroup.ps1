function Join-DbaAvailabilityGroup {
    <#
    .SYNOPSIS
        Adds a SQL Server instance as a secondary replica to an existing availability group.

    .DESCRIPTION
        Adds a SQL Server instance as a secondary replica to an existing availability group that has already been created on the primary replica. This command is typically used after creating the availability group on the primary server and before adding databases to the group. The target instance must have the availability group feature enabled and be properly configured for high availability. For SQL Server 2017 and later, you can specify the cluster type (External, Wsfc, or None) to match your environment's configuration.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        Specifies the name of the availability group that the target instance will join as a secondary replica.
        Use this when you need to add a secondary replica to an existing availability group that was created on the primary server.

    .PARAMETER ClusterType
        Specifies the cluster type for the availability group when joining SQL Server 2017 or later instances.
        Use 'Wsfc' for Windows Server Failover Clustering, 'External' for Linux cluster managers like Pacemaker, or 'None' for read-scale availability groups without clustering.
        If not specified, the cluster type is automatically detected from the existing availability group.

    .PARAMETER InputObject
        Accepts availability group objects from Get-DbaAvailabilityGroup for pipeline operations.
        Use this when you want to retrieve availability group details from the primary replica and pipe them directly to join secondary replicas.
        The availability group name and cluster type are automatically extracted from the input object.

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
        https://dbatools.io/Join-DbaAvailabilityGroup

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql01 -AvailabilityGroup SharePoint | Join-DbaAvailabilityGroup -SqlInstance sql02

        Joins sql02 to the SharePoint availability group on sql01

    .EXAMPLE
        PS C:\> $ag = Get-DbaAvailabilityGroup -SqlInstance sql01 -AvailabilityGroup SharePoint
        PS C:\> Join-DbaAvailabilityGroup -SqlInstance sql02 -InputObject $ag

        Joins sql02 to the SharePoint availability group on sql01

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql01 -AvailabilityGroup SharePoint | Join-DbaAvailabilityGroup -SqlInstance sql02 -WhatIf

        Shows what would happen if the command were to run. No actions are actually performed.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql01 -AvailabilityGroup SharePoint | Join-DbaAvailabilityGroup -SqlInstance sql02 -Confirm

        Prompts for confirmation then joins sql02 to the SharePoint availability group on sql01.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [ValidateSet('External', 'Wsfc', 'None')]
        [string]$ClusterType,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object"
            return
        }

        if ($InputObject) {
            $AvailabilityGroup += $InputObject.Name
            if (-not $ClusterType) {
                $tempclustertype = ($InputObject | Select-Object -First 1).ClusterType
                if ($tempclustertype) {
                    $ClusterType = $tempclustertype
                }
            }
        }

        if (-not $AvailabilityGroup) {
            Stop-Function -Message "No availability group to add"
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($ag in $AvailabilityGroup) {
                if ($Pscmdlet.ShouldProcess($server.Name, "Joining $ag")) {
                    try {
                        if ($ClusterType -and $server.VersionMajor -ge 14) {
                            $server.Query("ALTER AVAILABILITY GROUP [$ag] JOIN WITH (CLUSTER_TYPE = $ClusterType)")
                        } else {
                            $server.JoinAvailabilityGroup($ag)
                        }
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                    }
                }
            }
        }
    }
}