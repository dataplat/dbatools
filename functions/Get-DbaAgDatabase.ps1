function Get-DbaAgDatabase {
    <#
        .SYNOPSIS
            Outputs the databases involved in the Availability Group(s) found on the server.

        .DESCRIPTION
            Default view provides most common set of properties for information on the database in an Availability Group(s).

            Information returned on the database will be specific to that replica, whether it is primary or a secondary.

            This command will return an SMO object, but it is the AvailabilityDatabases object and not the Server.Databases object.

        .PARAMETER SqlInstance
            The SQL Server instance. Server version must be SQL Server version 2012 or higher.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted).

        .PARAMETER AvailabilityGroup
            Specify the Availability Group name that you want to get information on.

        .PARAMETER Database
            Specify the database(s) to pull information for. This list is auto-populated from the server for tab completion. Multiple databases can be specified. If none are specified all databases will be processed.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: DisasterRecovery, AG, AvailabilityGroup, Replica
            Author: Shawn Melton (@wsmelton)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaAgDatabase

        .EXAMPLE
            Get-DbaAgDatabase -SqlInstance sqlserver2014a

            Returns basic information on all the databases in each Availability Group found on sqlserver2014a

        .EXAMPLE
            Get-DbaAgDatabase -SqlInstance sqlserver2014a -AvailabilityGroup AG-a

            Returns basic information on all the databases in the Availability Group AG-a on sqlserver2014a

        .EXAMPLE
            Get-DbaAgDatabase -SqlInstance sqlserver2014a -AvailabilityGroup AG-a -Database AG-Database

            Returns basic information on the database AG-Database found in the Availability Group AG-a on server sqlserver2014a
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential][System.Management.Automation.CredentialAttribute()]
        $SqlCredential,
        [parameter(ValueFromPipeline = $true)]
        [object[]]$AvailabilityGroup,
        [object[]]$Database,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($serverName in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $serverName -SqlCredential $SqlCredential -MinimumVersion 11
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.IsHadrEnabled -eq $false) {
                Stop-Function -Message "Availability Group (HADR) is not configured for the instance: $serverName." -Target $serverName -Continue
            }

            $ags = $server.AvailabilityGroups
            if ($AvailabilityGroup) {
                $ags = $ags | Where-Object Name -in $AvailabilityGroup
            }

            foreach ($ag in $ags) {
                $agDatabases = $ag.AvailabilityDatabases
                foreach ($agDb in $agDatabases) {
                    if ($Database -and $agDb.Name -notmatch $Database) {
                        continue
                    }

                    Add-Member -Force -InputObject $agDb -MemberType NoteProperty -Name ComputerName -value $server.NetName
                    Add-Member -Force -InputObject $agDb -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $agDb -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    Add-Member -Force -InputObject $agDb -MemberType NoteProperty -Name Replica -value $server.NetName

                    $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Parent as AvailabilityGroup', 'Replica', 'Name as DatabaseName', 'SynchronizationState', 'IsFailoverReady', 'IsJoined', 'IsSuspended'
                    Select-DefaultView -InputObject $agDb -Property $defaults
                }
            }
        }
    }
}
