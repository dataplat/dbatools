function Get-DbaAvailabilityGroup {
    <#
    .SYNOPSIS
        Retrieves Availability Group configuration and status information from SQL Server instances.

    .DESCRIPTION
        Retrieves detailed Availability Group information including replica roles, cluster configuration, database membership, and listener details from SQL Server 2012+ instances.

        This command helps DBAs monitor AG health, identify primary replicas for failover planning, and generate inventory reports for compliance or troubleshooting. The default view shows essential properties like replica roles, primary replica location, and cluster type, while the full object contains comprehensive AG configuration details.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER AvailabilityGroup
        Return only specific availability groups.

    .PARAMETER IsPrimary
        If this switch is enabled, a boolean indicating whether SqlInstance is the Primary replica in the AG is returned.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AG, HA
        Author: Shawn Melton (@wsmelton) | Chrissy LeMaire (@cl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAvailabilityGroup

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sqlserver2014a

        Returns basic information on all the Availability Group(s) found on sqlserver2014a.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sqlserver2014a -AvailabilityGroup AG-a

        Shows basic information on the Availability Group AG-a on sqlserver2014a.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sqlserver2014a | Select-Object *

        Returns full object properties on all Availability Group(s) on sqlserver2014a.

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sqlserver2014a | Select-Object -ExpandProperty PrimaryReplicaServerName

        Returns the SQL Server instancename of the primary replica as a string

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sqlserver2014a -AvailabilityGroup AG-a -IsPrimary

        Returns true/false if the server, sqlserver2014a, is the primary replica for AG-a Availability Group.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$AvailabilityGroup,
        [switch]$IsPrimary,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (-not $server.IsHadrEnabled) {
                Stop-Function -Message "Availability Group (HADR) is not configured for the instance: $instance." -Target $instance -Continue
            }

            $ags = $server.AvailabilityGroups

            if ($AvailabilityGroup) {
                $ags = $ags | Where-Object Name -in $AvailabilityGroup
            }

            foreach ($ag in $ags) {
                # Refresh list of databases to fix #9094
                $ag.AvailabilityDatabases.Refresh()

                Add-Member -Force -InputObject $ag -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                Add-Member -Force -InputObject $ag -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $ag -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName

                if ($IsPrimary) {
                    $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Name as AvailabilityGroup', 'IsPrimary'
                    Add-Member -Force -InputObject $ag -MemberType NoteProperty -Name IsPrimary -Value ($ag.LocalReplicaRole -eq "Primary")
                    Select-DefaultView -InputObject $ag -Property $defaults
                } else {
                    $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'LocalReplicaRole', 'Name as AvailabilityGroup', 'PrimaryReplicaServerName as PrimaryReplica', 'ClusterType', 'DtcSupportEnabled', 'AutomatedBackupPreference', 'AvailabilityReplicas', 'AvailabilityDatabases', 'AvailabilityGroupListeners'
                    Select-DefaultView -InputObject $ag -Property $defaults
                }
            }
        }
    }
}