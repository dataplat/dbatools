function Get-DbaAvailabilityGroup {
	<#
		.SYNOPSIS 
			Outputs information of the Availability Group(s) found on the server.

		.DESCRIPTION
			By default outputs a small set of information around the Availability Group found on the server.

		.PARAMETER SqlInstance
			The SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2012 or higher.

		.PARAMETER SqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

		.PARAMETER Detailed
			Output is expanded with more information around each Availability Group replica found on the server.

		.PARAMETER AvailabilityGroup
			Specify the Availability Group name that you want to get information on.

		.PARAMETER Simple
			Show only server name, availability groups and role.

		.PARAMETER Detailed
			Shows detailed information about the AGs including EndpointUrl and BackupPriority.

		.PARAMETER IsPrimary
			Returns true or false for the server passed in.

		.PARAMETER Silent 
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: DisasterRecovery, AG, AvailabilityGroup
			Original Author: Shawn Melton (@wsmelton) | Chrissy LeMaire (@ctrlb)

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaAvailabilityGroup

		.EXAMPLE
			Get-DbaAvailabilityGroup -SqlInstance sqlserver2014a

			Returns basic information on all the Availability Group(s) found on sqlserver2014a

		.EXAMPLE   
			Get-DbaAvailabilityGroup -SqlInstance sqlserver2014a -Simple

			Show only server name, availability groups and role

		.EXAMPLE   
			Get-DbaAvailabilityGroup -SqlInstance sqlserver2014a -Detailed

			Returns basic information plus additional info on each replica for all Availability Group(s) on sqlserver2014a

		.EXAMPLE   
			Get-DbaAvailabilityGroup -SqlInstance sqlserver2014a -AvailabilityGroup AG-a

			Shows basic information on the Availability Group AG-a on sqlserver2014a
			
		.EXAMPLE   
			Get-DbaAvailabilityGroup -SqlInstance sqlserver2014a -AvailabilityGroup AG-a -IsPrimary

			Returns true/false if the server, sqlserver2014a, is the primary replica for AG-a Availability Group
	#>
	[CmdletBinding()]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[object[]]$AvailabilityGroup,
		[switch]$Simple,
		[switch]$Detailed,
		[switch]$IsPrimary,
		[switch]$Silent
	)

	begin {
		$agCollection = @()
	}
	process {

		foreach ($servername in $SqlInstance) {
			$agReplicas = @()
			$server = Connect-SqlInstance -SqlInstance $servername -SqlCredential $SqlCredential
			
			$version = $server.VersionMajor
			if ($version -lt 11) {
				Write-Verbose "$server Major Version detected: $version"
				Write-Warning "$server is version $version. Availability Groups are only supported in SQL Server 2012 and above."
				continue
			}

			if (!$server.IsHadrEnabled) {
				Write-Warning "$server Availability Group is not configured."
				continue
			}

			if ($AvailabilityGroup) {
				foreach ($ag in $AvailabilityGroup) {
					$agReplicas += $server.AvailabilityGroups[$ag].AvailabilityReplicas
				}
			}
			else {
				$agReplicas += $server.AvailabilityGroups.AvailabilityReplicas
			}
			
			if (!$agReplicas) {
				Write-Warning "[$servername] Availability Groups not found"
				continue
			}
			
			
			foreach ($r in $agReplicas) {
				$agCollection += [pscustomobject]@{
					AvailabilityGroup           = $r.Parent.Name
					ReplicaName                 = $r.name
					Role                        = $r.Role
					SyncState                   = $r.RollupSynchronizationState
					AvailabilityMode            = $r.AvailabilityMode
					FailoverMode                = $r.FailoverMode
					ConnectionModeInPrimaryRole = $r.ConnectionModeInPrimaryRole
					ReadableSecondary           = $r.ConnectionModeInSecondaryRole
					SessionTimeout              = $r.SessionTimeout
					EndpointUrl                 = $r.EndpointUrl
					BackupPriority              = $r.BackupPriority
					ExcludeReplica              = if ($r.BackupPriority -eq 0) { $true } else { $false }
					QuorumVoteCount             = $r.QuorumVoteCount
					ReadonlyRoutingUrl          = $r.ReadonlyRoutingConnectionUrl
					ReadonlyRoutingList         = $r.ReadonlyRoutingList -join ","
				}
			}
			
			$server.ConnectionContext.Disconnect()
		}
	}
	end {
		if ($AvailabilityGroup) {
			$agCollection = ($agCollection | Where-Object AvailabilityGroup -in $AvailabilityGroup)
		}

		if ($IsPrimary) {
			return ($agCollection | Where-Object { $_.ReplicaName -in $SqlInstance -and $_.Role -ne 'Unknown' } | Select-Object ReplicaName, AvailabilityGroup, @{ Name="IsPrimary"; Expression= { $_.Role -eq "Primary" } } )
		}
		
		if ($Simple) {
			return $agCollection | Select-Object ReplicaName, AvailabilityGroup, Role
		}
		
		if ($Detailed) {
			return $agCollection
		}
		else {
			return ($agCollection | Select-Object AvailabilityGroup, ReplicaName, Role, SyncState, AvailabilityMode, FailoverMode)
		}
	}
}
