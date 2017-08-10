function Get-DbaAgListener {
	<#
		.SYNOPSIS
			Outputs the name of the Listener for the Availability Group(s) found on the server.

		.DESCRIPTION
			Default view provides most common set of properties for information on the database in an Availability Group(s).

			Information returned on the database will be specific to that replica, whether it is primary or a secondary.

			This command will return an SMO object, but it is the AvailabilityDatabases object	and not the Server.Databases object.

		.PARAMETER SqlInstance
			The SQL Server instance. Server version must be SQL Server version 2012 or higher.

		.PARAMETER SqlCredential
			Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted).

		.PARAMETER AvailabilityGroup
			Specify the Availability Group name that you want to get information on.

		.PARAMETER Database
			Specify the database(s) to pull information for. This list is auto-populated from the server for tab completion. Multiple databases can be specified. If none are specified all databases will be processed.

		.PARAMETER Silent
			If this switch is enabled, the internal messaging functions will be silenced.

		.NOTES
			Tags: DisasterRecovery, AG, AvailabilityGroup, Replica
			Original Author: Viorel Ciucu (@viorelciucu)

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaAgListener

		.EXAMPLE
			Get-DbaAgListener -SqlInstance sqlserver2014a

			Returns basic information on all the databases in each Availability Group found on sqlserver2014a

		.EXAMPLE
			Get-DbaAgListener -SqlInstance sqlserver2014a -AvailabilityGroup AG-a

			Returns basic information on all the databases in the Availability Group AG-a on sqlserver2014a

		.EXAMPLE
			Get-DbaAgListener -SqlInstance sqlserver2014a -AvailabilityGroup AG-a -Database AG-Database

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
		[switch]$Silent
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
				Add-Member -Force -InputObject $ag -MemberType NoteProperty -Name ComputerName -value $server.NetName
				Add-Member -Force -InputObject $ag -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
				Add-Member -Force -InputObject $ag -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
				
				$defaults = 'Name as AvailabilityGroup','ComputerName','InstanceName','SqlInstance','ClusterIPConfiguration','PortNumber','AvailabilityGroupListenerIPAddresses','AGListenerName'
				$AvailabilityGroup = Get-DbaAvailabilityGroup $SqlInstance
				$listener = $AvailabilityGroup.AvailabilityGroupListeners
				Add-Member -Force -InputObject $ag -MemberType NoteProperty -Name ClusterIPConfiguration -value $listener.ClusterIPConfiguration
				Add-Member -Force -InputObject $ag -MemberType NoteProperty -Name PortNumber -value $listener.PortNumber
				Add-Member -Force -InputObject $ag -MemberType NoteProperty -Name AvailabilityGroupListenerIPAddresses -value $listener.AvailabilityGroupListenerIPAddresses
				Add-Member -Force -InputObject $ag -MemberType NoteProperty -Name AGListenerName -value $listener.Name
				
				Select-DefaultView -InputObject $ag -Property $defaults
			}

		}
	}
}
