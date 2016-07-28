Function Copy-SqlCentralManagementServer
{
<# 
.SYNOPSIS 
Migrates SQL Server Central Management groups and server instances from one SQL Server to another.

.DESCRIPTION 
Copy-SqlCentralManagementServer copies all groups, subgroups, and server instances from one SQL Server to another. 

.PARAMETER Source
The SQL Server Central Management Server you are migrating from.

.PARAMETER Destination
The SQL Server Central Management Server you are migrating to.

.PARAMETER CMSGroups
This is an auto-populated array that contains your Central Management Server top-level groups on $Source. You can specify one, many or none.
If -CMSGroups is not specified, the Copy-SqlCentralManagementServer script will migrate all groups in your Central Management Server. Note this variable is only populated by top level groups.

.PARAMETER SwitchServerName
Central Management Server does not allow you to add a shared registered server with the same name as the Configuration Server. If you wish to change all migrating instance names of $Destination to $Source, use this switch.

.PARAMETER SourceSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter. 

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER DestinationSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter. 

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Copy-SqlCentralManagementServer

.EXAMPLE   
Copy-SqlCentralManagementServer -Source sqlserver2014a -Destination sqlcluster

In the above example, all groups, subgroups, and server instances are copied from sqlserver's Central Management Server to sqlcluster's Central Management Server.

.EXAMPLE   
Copy-SqlCentralManagementServer -Source sqlserver2014a -Destination sqlcluster -CMSGroups Group1,Group3

In the above example, top level Group1 and Group3, along with its subgroups and server instances are copied from sqlserver to sqlcluster.

.EXAMPLE   
Copy-SqlCentralManagementServer -Source sqlserver2014a -Destination sqlcluster -CMSGroups Group1,Group3 -SwitchServerName -SourceSqlCredential $SourceSqlCredential -DestinationSqlCredential $DestinationSqlCredential

In the above example, top level Group1 and Group3, along with its subgroups and server instances are copied from sqlserver to sqlcluster. When adding sql instances to sqlcluster, if the server name of the migrating instance is "sqlcluster", it will be switched to "sqlserver". If SwitchServerName is not specified, "sqlcluster" will be skipped.

#>	
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true)]
		[object]$Source,
		[parameter(Mandatory = $true)]
		[object]$Destination,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[switch]$SwitchServerName,
		[switch]$Force
	)
	
	DynamicParam { if ($Source) { return (Get-ParamSqlCmsGroups -SqlServer $Source -SqlCredential $SourceSqlCredential) } }
	
	BEGIN
	{
		Function Parse-ServerGroup($sourceGroup, $destinationgroup, $SwitchServerName)
		{
			if ($destinationgroup.name -eq "DatabaseEngineServerGroup" -and $sourceGroup.name -ne "DatabaseEngineServerGroup")
			{
				$currentservergroup = $destinationgroup
				$groupname = $sourceGroup.name
				$destinationgroup = $destinationgroup.ServerGroups[$groupname]
				
				if ($destinationgroup -ne $null)
				{
					if ($force -eq $false)
					{
						Write-Warning "Destination group $groupname exists at destination. Use -Force to drop and migrate."
						continue
					}
					
					If ($Pscmdlet.ShouldProcess($destination, "Dropping group $groupname and recreating"))
					{
						try
						{
							Write-Verbose "Dropping Alert $alertname"
							$destinationgroup.Drop()
						}
						catch 
						{
							Write-Exception $_
							continue
						}
					}
				}
				
				Write-Output "Creating group $($sourceGroup.name)"
				$destinationgroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($currentservergroup, $sourcegroup.name)
				$destinationgroup.Create()
			}
			
			# Add Servers
			foreach ($instance in $sourceGroup.RegisteredServers)
			{
				$instancename = $instance.name
				$servername = $instance.ServerName
				
				if ($servername.ToLower() -eq $tocmstore.DomainInstanceName.ToLower())
				{
					if ($SwitchServerName)
					{
						$servername = $fromcmstore.DomainInstanceName
						$instancename = $fromcmstore.DomainInstanceName
						Write-Output "SwitchServerName was used and new CMS equals current server name. $($tocmstore.DomainInstanceName.ToLower()) changed to $servername."
					}
					else
					{
						Write-Warning "$servername is Central Management Server. Add prohibited. Skipping."
						continue
					}
				}
				
				if ($destinationgroup.RegisteredServers.name -contains $instancename)
				{
					if ($force -eq $false)
					{
						Write-Warning "Instance $instancename exists in group $groupname at destination. Use -Force to drop and migrate."
						continue
					}
					
					If ($Pscmdlet.ShouldProcess($destination, "Dropping instance $instancename from $groupname and recreating"))
					{
						try
						{
							Write-Verbose "Dropping Alert $alertname"
							$destinationgroup.RegisteredServers[$instancename].Drop()
						}
						catch 
						{
							Write-Exception $_
							continue
						}
					}
				}
				
				if ($Pscmdlet.ShouldProcess($destination, "Copying $instancename"))
				{
					$newserver = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($destinationgroup, $instancename)
					$newserver.ServerName = $servername
					$newserver.Description = $instance.Description
					
					if ($servername -ne $fromcmstore.DomainInstanceName)
					{
						$newserver.SecureConnectionString = $instance.SecureConnectionString.tostring()
						$newserver.ConnectionString = $instance.ConnectionString.tostring()
					}
					
					try 
					{ 
						$newserver.Create() 
					}
					catch
					{
						if ($_.Exception -match "same name") 
						{ 
							Write-Error "Could not add Switched Server instance name."
							continue 
						}
						else 
						{ 
							Write-Error "Failed to add $servername" 
						}
					}
					Write-Output "Added Server $servername as $instancename to $($destinationgroup.name)"
				}
			}
			
			# Add Groups
			foreach ($fromsubgroup in $sourceGroup.ServerGroups)
			{
				$fromsubgroupname = $fromsubgroup.name
				$tosubgroup = $destinationgroup.ServerGroups[$fromsubgroupname]
				
				if ($tosubgroup -ne $null) {
				
					if ($force -eq $false)
					{
						Write-Warning "Subgroup $fromsubgroupname exists at destination. Use -Force to drop and migrate."
						continue
					}
					
					If ($Pscmdlet.ShouldProcess($destination, "Dropping subgroup $fromsubgroupname recreating"))
					{
						try
						{
							Write-Verbose "Dropping subgroup $fromsubgroupname"
							$tosubgroup.Drop()
						}
						catch 
						{
							Write-Exception $_
							continue
						}
					}
				}
				
				
				Write-Output "Creating group $($fromsubgroup.name)"
				$tosubgroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($destinationgroup, $fromsubgroup.name)
				$tosubgroup.create()
				
				
				Parse-ServerGroup -sourceGroup $fromsubgroup -destinationgroup $tosubgroup -SwitchServerName $SwitchServerName
			}
		}
		
		$SqlCmsGroups = $psboundparameters.SqlCmsGroups
		
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
		if ($sourceserver.versionMajor -lt 10 -or $destserver.versionMajor -lt 10)
		{
			throw "Central Management Server is only supported in SQL Server 2008 and above. Quitting."
		}
	}
	
	PROCESS
	{
		Write-Output "Connecting to Central Management Servers"
		
		try
		{
			$fromcmstore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($sourceserver.ConnectionContext.SqlConnectionObject)
			$tocmstore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($destserver.ConnectionContext.SqlConnectionObject)
		}
		catch 
		{ 
			throw "Cannot access Central Management Servers" 
		}
		
		if ($CMSGroups -eq $null) { 
			$stores = $fromcmstore.DatabaseEngineServerGroup 
		}
		else 
		{ 
			$stores = @(); foreach ($groupname in $CMSGroups) { $stores += $fromcmstore.DatabaseEngineServerGroup.ServerGroups[$groupname] } 
		}
		
		foreach ($store in $stores)
		{
			Parse-ServerGroup -sourceGroup $store -destinationgroup $tocmstore.DatabaseEngineServerGroup -SwitchServerName $SwitchServerName
		}
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) 
		{ 
			Write-Output "Central Management Server migration finished" 
		}
	}
}
