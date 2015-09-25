Function Copy-SqlCentralManagementServer {
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
If -CMSGroups is not specified, theCopy-SqlCentralManagementServer script will migrate all groups in your Central Management Server. Note this 
variable is only populated by top level groups.

.PARAMETER SwitchServerName
Central Management Server does not allow you to add a shared registered server with the same name as the Configuration Server. If you wish to 
change all migrating instance names of $Destination to $Source, use this switch.

.PARAMETER SourceSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, this pass $scred object to the param. 

.PARAMETER DestinationSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$dcred = Get-Credential, this pass this $dcred to the param. 

.NOTES 
Author  : Chrissy LeMaire
Requires: 	PowerShell Version 3.0, SQL Server SMO
Version: 2.0
DateUpdated: 2015-Sept-22


.LINK 
https://gallery.technet.microsoft.com/scriptcenter/Migrate-Central-Management-e062943f

.EXAMPLE   
Copy-SqlCentralManagementServer -Source sqlserver -Destination sqlcluster

In the above example, all groups, subgroups, and server instances are copied from sqlserver's Central Management Server to sqlcluster's Central Management Server.

.EXAMPLE   
Copy-SqlCentralManagementServer -Source sqlserver -Destination sqlcluster -CMSGroups Group1,Group3

In the above example, top level Group1 and Group3, along with its subgroups and server instances are copied from sqlserver to sqlcluster.

.EXAMPLE   
Copy-SqlCentralManagementServer -Source sqlserver -Destination sqlcluster -CMSGroups Group1,Group3 -SwitchServerName -SourceSqlCredential $SourceSqlCredential -DestinationSqlCredential $DestinationSqlCredential

In the above example, top level Group1 and Group3, along with its subgroups and server instances are copied from sqlserver to sqlcluster. When adding sql instances to sqlcluster, if
the server name of the migrating instance is "sqlcluster", it will be switched to "sqlserver". If SwitchServerName is not specified, "sqlcluster" will be skipped.

#> 
#Requires -Version 3.0
[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess = $true)] 

Param(
	[parameter(Mandatory = $true)]
	[object]$Source,
	[parameter(Mandatory = $true)]
	[object]$Destination,
	[System.Management.Automation.PSCredential]$SourceSqlCredential,
	[System.Management.Automation.PSCredential]$DestinationSqlCredential,
	[switch]$SwitchServerName
	)

DynamicParam  { if ($Source) { return (Get-ParamSqlCmsGroups -SqlServer $Source -SqlCredential $SourceSqlCredential) } }

BEGIN {

	Function Parse-ServerGroup($sourceGroup, $destinationgroup, $SwitchServerName) {

	if ($destinationgroup.name -eq "DatabaseEngineServerGroup" -and $sourceGroup.name -ne "DatabaseEngineServerGroup") {
		$currentservergroup = $destinationgroup
		$destinationgroup = $destinationgroup.ServerGroups[$sourceGroup.name]
		if ($destinationgroup -eq $null) {
			Write-Output "Creating group $($sourceGroup.name)"
			$destinationgroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($currentservergroup,$sourcegroup.name)
			$destinationgroup.create()
		}
	}
			
	# Add Servers
		foreach ($instance in $sourceGroup.RegisteredServers) {
			$instancename = $instance.name
			$servername = $instance.ServerName
			
			if ($servername.ToLower() -eq $tocmstore.DomainInstanceName.ToLower()) {
				if ($SwitchServerName) {				
					$servername = $fromcmstore.DomainInstanceName
					$instancename = $fromcmstore.DomainInstanceName
					Write-Output "SwitchServerName was used and new CMS equals current server name. $($tocmstore.DomainInstanceName.ToLower()) changed to $servername."
				}
				else {
					Write-Warning "$servername is Central Management Server. Add prohibited. Skipping."
					continue
				}
			}		
			 
			if($destinationgroup.RegisteredServers.name -notcontains $instancename) {
				$newserver = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer($destinationgroup, $instancename)
				$newserver.ServerName = $servername
				$newserver.Description = $instance.Description
				
				if ($servername -ne $fromcmstore.DomainInstanceName) {
					$newserver.SecureConnectionString = $instance.SecureConnectionString.tostring()
					$newserver.ConnectionString = $instance.ConnectionString.tostring()
				}
				
				try { $newserver.Create() } catch { 
					if ($_.Exception -match "same name") { Write-Error "Could not add Switched Server instance name."; continue }
					else { Write-Error "Failed to add $servername" }
				}
				Write-Output "Added Server $servername as $instancename to $($destinationgroup.name)"
			  }
			else { Write-Warning "Server $instancename already exists. Skipped" }
		}
	 
		# Add Groups
		foreach($fromsubgroup in $sourceGroup.ServerGroups)
		{
			$tosubgroup = $destinationgroup.ServerGroups[$fromsubgroup.name]
			if ($tosubgroup -eq $null) {
				Write-Output "Creating group $($fromsubgroup.name)"
				$tosubgroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($destinationgroup,$fromsubgroup.name)
				$tosubgroup.create()
			}
		
		 Parse-ServerGroup -sourceGroup $fromsubgroup -destinationgroup $tosubgroup -SwitchServerName $SwitchServerName
		}
	}
}

PROCESS { 
	
	$SqlCmsGroups = $psboundparameters.SqlCmsGroups
			 
	Write-Output "Connecting to SQL Servers"
	$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
	$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential

	$source = $sourceserver.name
	$destination = $destserver.name

	if (!(Test-SqlSa -SqlServer $sourceserver -SqlCredential $SourceSqlCredential)) { throw "Not a sysadmin on $($sourceserver.name). Quitting." }  
	if (!(Test-SqlSa -SqlServer $destserver -SqlCredential $DestinationSqlCredential)) { throw "Not a sysadmin on  $($destserver.name). Quitting." }  

	Write-Output "Connecting to Central Management Servers"
	try { 
		$fromcmstore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($sourceserver.ConnectionContext.SqlConnectionObject)
		$tocmstore = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($destserver.ConnectionContext.SqlConnectionObject)
		}
	catch { throw "Cannot access Central Management Servers" }
	
	If ($Pscmdlet.ShouldProcess($destination,"Copying CMS Servers")) {
		if ($CMSGroups -eq $null) { $stores = $fromcmstore.DatabaseEngineServerGroup } 
		else { $stores = @(); foreach ($groupname in $CMSGroups) { $stores += $fromcmstore.DatabaseEngineServerGroup.ServerGroups[$groupname] } }

		foreach ($store in $stores) {
			Parse-ServerGroup -sourceGroup $store -destinationgroup $tocmstore.DatabaseEngineServerGroup -SwitchServerName $SwitchServerName
		}
	}
}

END {
	$sourceserver.ConnectionContext.Disconnect()
	$destserver.ConnectionContext.Disconnect()
	Write-Output "Central Management Server migration finished"
}
}