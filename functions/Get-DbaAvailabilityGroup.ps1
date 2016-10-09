Function Get-SqlAvailabilityGroup
{
<#
.SYNOPSIS 
Outputs information of the Availabilty Group(s) found on the server.

.DESCRIPTION
By default outputs a small set of information around the Availability Group found on the server.

.PARAMETER SqlServer
The SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2012 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. 

.PARAMETER Detailed
Output is expanded with more information around each Availability Group replica found on the server.

.PARAMETER AvailabilityGroupName
Specify the Availability Group name that you want to get information on.

.PARAMETER IsPrimary
Returns true or false for the server passed in. Requires AvailabilityGroupName parameter.

.NOTES 
Original Author: Shawn Melton (@wsmelton)

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Get-SqlAvailabilityGroup

.EXAMPLE
Get-SqlAvailabilityGroup -SqlServer sqlserver2014a
Returns basic information on all the Availability Group(s) found on sqlserver2014a

.EXAMPLE   
Get-SqlAvailabilityGroup -SqlServer sqlserver2014a -Detailed
Returns basic information plus additional info on each replica for all Availability Group(s) on sqlserver2014a

.EXAMPLE   
Get-SqlAvailabilityGroup -SqlServer sqlserver2014a -AvailabilityGroup AG-a
Shows basic information on the Availability Group AG-a on sqlserver2014a
	
.EXAMPLE   
Get-SqlAvailabilityGroup -SqlServer sqlserver2014a -AvailabilityGroup AG-a -IsPrimary
Returns true/false if the server, sqlserver2014a, is the primary replica for AG-a Availability Group
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[object]$SqlCredential,
        [switch]$Detailed,
        [string]$AvailabilityGroupName,
		[switch]$IsPrimary        
	)
	
#	DynamicParam { if ($sqlserver) { return Get-ParamSqlDatabases -SqlServer $sqlserver -SqlCredential $SqlCredential } }
	
	BEGIN
	{
		
		$server = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential
	}
	
	PROCESS
	{
		if (!$server.IsHadrEnabled)
		{
			Return "Availability Group is not configured."
		}

        if ($AvailabilityGroupName)
        {
            $agReplicas = $server.AvailabilityGroups[$AvailabilityGroupName].AvailabilityReplicas
        }
        else
        {
            $agReplicas = $server.AvailabilityGroups.AvailabilityReplicas
        }

        if (!$agReplicas)
        {
            return "No data found"
        }

        $agCollection = @()
		foreach ($r in $agReplicas)
		{
		    $data = [pscustomobject]@{
			    AvailabilityGroupName = $r.Parent.Name
			    ReplicaName = $r.name
                Role = $r.Role
                SyncState = $r.RollupSynchronizationState
			    AvailabilityMode = $r.AvailabilityMode
			    FailoverMode = $r.FailoverMode
			    ConnectionModeInPrimaryRole = $r.ConnectionModeInPrimaryRole
			    ReadableSecondary = $r.ConnectionModeInSecondaryRole
			    SessionTimeout = $r.SessionTimeout
			    EndpointUrl = $r.EndpointUrl
			    BackupPriority = $r.BackupPriority
			    ExcludeReplica = if ($r.BackupPriority -eq 0) {$true} else {$false}
			    QuorumVoteCount = $r.QuorumVoteCount
			    ReadonlyRoutingUrl = $r.ReadonlyRoutingConnectionUrl
			    ReadonlyRoutingList = $r.ReadonlyRoutingList -join ","
   			}
            $agCollection += $data
		}
        if ($IsPrimary)
        {
            if (!$AvailabilityGroupName)
            {
                Write-Error "AvailabilityGroupName is missing. Please provide value and re-run command."
                Return "Unable to process command due to missing parameter"
            }
            if ($agCollection.ReplicaName -contains $server.Name)
            {
                $srole = ($agCollection | where ReplicaName -eq $server.Name).Role
                switch ($srole) {
                    'Primary' {return $true}
                    default {$false}
                }
            }     
        }
        else
        {
            if ($Detailed)
            {
                $agCollection
            }
            else
            {
                $agCollection | select AvailabilityGroupName, ReplicaName, Role, SyncState, AvailabilityMode, FailoverMode
            }
        }
	}
	
	END
	{
		$server.ConnectionContext.Disconnect()
	}
}