function Get-DbaWsfcSqlResource
{
<#
.SYNOPSIS
Returns the registered SQL Server Instances on a windows Server cluster
	
.DESCRIPTION
By default, this command returns for each Cluster passed in:
Pulls Cluster details via WMI/CIM so doesn't require Failover Cluster PowerShell module to be installed.
Multiple clusters can be piped in.
Returns ALL instance registered on cluster. Does not check that they are viable, correctly installed or currenly running. 
	
.PARAMETER Cluster
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER WindowsCredential
Credential object used to connect to the SQL Server as a different user


.NOTES 
Original Author: Stuart Moore (@napalmgram), stuart-moore.com
	
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>

.LINK
https://dbatools.io/Get-DbaWsfcSqlResource

.EXAMPLE
Get-DbaWsfcSqlResource -ClusterName MyProdCluster.contoso.com

Returns a list of all SQL Server instances that have been setup on the cluster MyProdCluster.contoso.com
.EXAMPLE
$Credential = Get-Credential
"MyProdCluster.contoso.com","MyTestCluster.contoso.com" | Get-DbaWsfcSqlResource -ClusterCredentual $Credential | Get-DbaUptime

Connects to the clusters MyProdCluster.contoso.com and MyProdCluster.contoso.com using the specified cluster administrator credentials, 
and then pushes the instance names through to Get-DbaUptime 	
	
#>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[string[]]$ClusterName,
		[PsCredential]$Credential
	)
	BEGIN
	{
		$FunctionName = "Get-DbaWsfcSqlResource"
		$StatusMessage = @{0= 'Inherited';
							1 = 'Initialising';
							2 = 'Online';
							3 = 'Offline';
							4 = 'Failed';
							128 = 'Pending';
							129 = 'Online Pending';
							130 = 'Offline Pending';}
	}
    PROCESS
    {
        ForEach ($Cluster in $ClusterName)
        {
				try
				{
					Write-Verbose "$FunctionName - Getting Clustered Instances via CimInstance for $Cluster"
					$Results = Get-CimInstance -class "MSCluster_Resource" -namespace "root\mscluster" -computername $Cluster | where {$_.type -eq "SQL Server"}  					
				}
				catch
				{
					try
					{
						Write-Verbose "$functionname - Clustered Instances via CimInstance DCOM for $Cluster"
						$CimOption = New-CimSessionOption -Protocol DCOM
						$CimSession = New-CimSession -Credential:$Credential -ComputerName $Cluster -SessionOption $CimOption
						$Results = $CimSession | Get-CimInstance -class "MSCluster_Resource" -namespace "root\mscluster"| where {$_.type -eq "SQL Server"}  					
					}
					catch
					{
						Write-Exception $_
					}
				}
				Foreach ($Result in $results) 
				{
					[PSCustomObject]@{SqlInstance= $Result.PrivateProperties.VirtualServerName+"\"+$Result.PrivateProperties.InstanceName
											ClusterName = $cluster
											State = $Result.State
											Status = $StatusMessage[[int]$($Result.State)]}
				}

        }
    }

}