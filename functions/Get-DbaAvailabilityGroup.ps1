function Get-DbaAvailabilityGroup {
    <#
        .SYNOPSIS
            Outputs the Availability Group(s) object found on the server.

        .DESCRIPTION
            Default view provides most common set of properties for information on the Availability Group(s).

        .PARAMETER SqlInstance
            The SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2012 or higher.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $cred = Get-Credential, then pass this $cred to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER AvailabilityGroup
            Specifies the Availability Group name that you want to get information on.

        .PARAMETER IsPrimary
            If this switch is enabled, a boolean indicating whether SqlInstance is the Primary replica in the AG is returned.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: DisasterRecovery, AG, AvailabilityGroup
            Author: Shawn Melton (@wsmelton) | Chrissy LeMaire (@ctrlb)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Get-DbaAvailabilityGroup

        .EXAMPLE
            Get-DbaAvailabilityGroup -SqlInstance sqlserver2014a

            Returns basic information on all the Availability Group(s) found on sqlserver2014a.

        .EXAMPLE
            Get-DbaAvailabilityGroup -SqlInstance sqlserver2014a -AvailabilityGroup AG-a

            Shows basic information on the Availability Group AG-a on sqlserver2014a.

        .EXAMPLE
            Get-DbaAvailabilityGroup -SqlInstance sqlserver2014a | Select *

            Returns full object properties on all Availability Group(s) on sqlserver2014a.

        .EXAMPLE
            Get-DbaAvailabilityGroup -SqlInstance sqlserver2014a -AvailabilityGroup AG-a -IsPrimary

            Returns true/false if the server, sqlserver2014a, is the primary replica for AG-a Availability Group.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$AvailabilityGroup,
        [switch]$IsPrimary,
        [switch][Alias('Silent')]$EnableException
    )

    process {
        foreach ($serverName in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $serverName -SqlCredential $SqlCredential -MinimumVersion 11
            }
            catch {
                Stop-Function -Message "Failure." -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.IsHadrEnabled -eq $false) {
                Stop-Function -Message "Availability Group (HADR) is not configured for the instance: $serverName." -Target $serverName -Continue
            }

            $ags = $server.AvailabilityGroups
            if ($AvailabilityGroup) {
                $ags = $ags | Where-Object Name -in $AvailabilityGroup
            }

            foreach ($ag in $ags) {
                Add-Member -Force -InputObject $ag -MemberType NoteProperty -Name ComputerName -value $server.NetName
                Add-Member -Force -InputObject $ag -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $ag -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName

                if ($IsPrimary) {
                    $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Name as AvailabilityGroup', 'IsPrimary'
                    $value = $false
                    if ($ag.PrimaryReplicaServerName -eq $server.Name) {
                        $value = $true
                    }
                    Add-Member -Force -InputObject $ag -MemberType NoteProperty -Name IsPrimary -Value $value
                    Select-DefaultView -InputObject $ag -Property $defaults
                }
                else {
                    $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'LocalReplicaRole', 'Name as AvailabilityGroup', 'PrimaryReplicaServerName as PrimaryReplica', 'AutomatedBackupPreference', 'AvailabilityReplicas', 'AvailabilityDatabases', 'AvailabilityGroupListeners'
                    Select-DefaultView -InputObject $ag -Property $defaults
                }
            }
        }
    }
}
