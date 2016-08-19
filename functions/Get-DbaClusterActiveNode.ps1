Function Get-DbaClusterActiveNode
{
<#
.SYNOPSIS
Returns the active node of a SQL Cluster
	
.DESCRIPTION
Returns a string of the current owner. If -Detailed is specified, a datatable of details will be returned.
	
.PARAMETER SqlServer
The SQL Cluster

.PARAMETER SqlCredential
If you want to use alternative credentials to connect.
	
.PARAMETER Detailed
Returns available details of SQL Cluster nodes. In SQL Server 2008, this will return node names. In SQL Server 2012 and above, this will return:
	
NodeName
Status
StatusDescription
CurrentOwner
	
.NOTES
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Get-DbaClusterActiveNode

.EXAMPLE
Get-DbaClusterActiveNode -SqlServer sqlcluster

Returns a simple string with the ComputerNamePhysicalNetBIOS property

.EXAMPLE
Get-DbaClusterActiveNode -SqlServer sqlcluster -Detailed

Returns a datatable with details
	
#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string]$SqlServer,
		[object]$SqlCredential,
		[switch]$Detailed
	)
	
	BEGIN
	{
		$server = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential -RegularUser
		$computername = $server.ComputerNamePhysicalNetBIOS
	}
	
	PROCESS
	{
		if ($server.IsClustered -eq $false)
		{
			return "Not a clustered instance"
		}
		
		if ($Detailed -eq $true)
		{
			$sql = "Select *  FROM sys.dm_os_cluster_nodes"
			$datatable = $server.ConnectionContext.ExecuteWithResults($sql).Tables
			return $datatable
		}
		else
		{
			# support multiple active nodes on SQL Server 2012 and above.
			if ($server.VersionMajor -ge 11)
			{
				$sql = "Select nodename FROM sys.dm_os_cluster_nodes where is_current_owner = 1"
				$datatable = $server.ConnectionContext.ExecuteWithResults($sql).Tables.NodeName
				return $datatable
			}
			else
			{
				return $computername
			}
		}
	}
	
	END
	{
		$server.ConnectionContext.Disconnect()
	}
}

