function Get-DbaAvailabilityGroup {
    <#
    .SYNOPSIS
        Returns availability group objects from a SQL Server instance.

    .DESCRIPTION
        Returns availability group objects from a SQL Server instance.

        Default view provides most common set of properties for information on the Availability Group(s).

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
        Tags: AvailabilityGroup, HA, AG
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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            } catch {
                Stop-Function -Message "Failure." -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (-not $server.IsHadrEnabled) {
                Stop-Function -Message "Availability Group (HADR) is not configured for the instance: $instance." -Target $instance -Continue
            }

            $ags = $server.AvailabilityGroups

            if ($AvailabilityGroup) {
                $ags = $ags | Where-Object Name -in $AvailabilityGroup
            }

            foreach ($ag in $ags) {
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