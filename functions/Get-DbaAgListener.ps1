function Get-DbaAgListener {
    <#
        .SYNOPSIS
            Outputs the name of the Listener for the Availability Group(s) found on the server.

        .DESCRIPTION
            Default view provides most common set of properties for information on the database in an Availability Group(s).

            Information returned on the database will be specific to that replica, whether it is primary or a secondary.

            This command will return an SMO object, but it is the AvailabilityDatabases object  and not the Server.Databases object.

        .PARAMETER SqlInstance
            The SQL Server instance. Server version must be SQL Server version 2012 or higher.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted).

        .PARAMETER AvailabilityGroup
            Specify the Availability Group name that you want to get information on.

        .PARAMETER Listener
            Specify the Listener name that you want to get information on.

        .PARAMETER InputObject
            Piped in Availability Group objects
   
        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: DisasterRecovery, AG, AvailabilityGroup, Replica
            Author: Viorel Ciucu (@viorelciucu)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaAgListener

        .EXAMPLE
            Get-DbaAgListener -SqlInstance sqlserver2014a

            Returns basic information on the listener found on sqlserver2014a

        .EXAMPLE
            Get-DbaAgListener -SqlInstance sqlserver2014a -AvailabilityGroup AG-a

            Returns basic information on the listener found on sqlserver2014a in the Availability Group AG-a

    #>
    [CmdletBinding()]
    param (
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(ValueFromPipeline = $true)]
        [string[]]$AvailabilityGroup,
        [string[]]$Listener,
        [object[]]$InputObject,
        [Alias('Silent')]
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $instance -SqlCredential $SqlCredential -AvailabilityGroup $AvailabilityGroup
        }
        if (Test-Bound -ParameterName Listener) {
            $InputObject = $InputObject | Where-Object { $_.AvailabilityGroupListeners.Name -contains $Listener }
        }
        
        $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'AvailabilityGroup', 'Name', 'PortNumber', 'ClusterIPConfiguration'
        foreach ($aglistener in $InputObject.AvailabilityGroupListeners) {
            $server = $aglistener.Parent.Parent
            Add-Member -Force -InputObject $aglistener -MemberType NoteProperty -Name ComputerName -value $server.NetName
            Add-Member -Force -InputObject $aglistener -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
            Add-Member -Force -InputObject $aglistener -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
            Add-Member -Force -InputObject $aglistener -MemberType NoteProperty -Name AvailabilityGroup -value $aglistener.Parent.Name
            Select-DefaultView -InputObject $aglistener -Property $defaults
        }
    }
}