<# 
 .SYNOPSIS 
    Migrates SQL Server Central Management groups and server instances from one SQL Server to another.
	
 .DESCRIPTION 
   Copy-CentralManagementServer.ps1 copies all groups, subgroups, and server instances from one SQL Server to another. 

 .PARAMETER Source
	The SQL Server Central Management Server you are migrating from.
	
 .PARAMETER Destination
	The SQL Server Central Management Server you are migrating to.
	
 .PARAMETER CMSGroups
	This is an auto-populated array that contains your Central Management Server top-level groups on $Source. You can specify one, many or none.
	If -CMSGroups is not specified, theCopy-CentralManagementServer.ps1 script will migrate all groups in your Central Management Server. Note this 
	variable is only populated by top level groups.
	
 .PARAMETER SwitchServerName
	Central Management Server does not allow you to add a shared registered server with the same name as the Configuration Server. If you wish to 
	change all migrating instance names of $Destination to $Source, use this switch.

 .NOTES 
    Author  : Chrissy LeMaire
    Requires: 	PowerShell Version 3.0, SQL Server SMO
	Version: 0.8.1
	DateUpdated: 2015-Apr-1

 .LINK 
  	https://gallery.technet.microsoft.com/scriptcenter/Migrate-Central-Management-e062943f

 .EXAMPLE   
.\Copy-CentralManagementServer.ps1 -Source sqlserver -Destination sqlcluster

In the above example, all groups, subgroups, and server instances are copied from sqlserver's Central Management Server to sqlcluster's Central Management Server.

 .EXAMPLE   
.\Copy-CentralManagementServer.ps1 -Source sqlserver -Destination sqlcluster -CMSGroups Group1,Group3

In the above example, top level Group1 and Group3, along with its subgroups and server instances are copied from sqlserver to sqlcluster.

 .EXAMPLE   
.\Copy-CentralManagementServer.ps1 -Source sqlserver -Destination sqlcluster -CMSGroups Group1,Group3 -SwitchServerName

In the above example, top level Group1 and Group3, along with its subgroups and server instances are copied from sqlserver to sqlcluster. When adding sql instances to sqlcluster, if
the server name of the migrating instance is "sqlcluster", it will be switched to "sqlserver". If SwitchServerName is not specified, "sqlcluster" will be skipped.

#> 
#Requires -Version 3.0
[CmdletBinding(DefaultParameterSetName="Default")]

Param(
	[parameter(Mandatory = $true)]
	[string]$Source,
	[parameter(Mandatory = $true)]
	[string]$Destination,
	[switch]$SwitchServerName
	)
	
DynamicParam  {
	if ($source) {
		if ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") -eq $null) {return}
		if ([Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.RegisteredServers") -eq $null) {return}

		$server = New-Object Microsoft.SqlServer.Management.Smo.Server $source
		$sqlconnection = $server.ConnectionContext.SqlConnectionObject
		 
		try { $cmstore = new-object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($sqlconnection)}
		catch { throw "Cannot access Central Management Server" }
		
		if ($cmstore -eq $null) { return }
		
		$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
		$paramattributes = New-Object System.Management.Automation.ParameterAttribute
		$paramattributes.ParameterSetName = "__AllParameterSets"
		$paramattributes.Mandatory = $false
		
		$argumentlist = $cmstore.DatabaseEngineServerGroup.ServerGroups.name
		
		if ($argumentlist -ne $null) {
			$validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $argumentlist
			
			$combinedattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
			$combinedattributes.Add($paramattributes)
			$combinedattributes.Add($validationset)

			$CMSGroups = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("CMSGroups", [String[]], $combinedattributes)
			$newparams.Add("CMSGroups", $CMSGroups)
			
			return $newparams
		} else { return $false }
	}
}

BEGIN {
	Function Test-SQLSA      {
	 <#
				.SYNOPSIS
				  Ensures sysadmin account access on SQL Server. $server is an SMO server object.

				.EXAMPLE
				  if (!(Test-SQLSA $server)) { throw "Not a sysadmin on $source. Quitting." }  

				.OUTPUTS
					$true if syadmin
					$false if not
				
			#>
			[CmdletBinding()]
			param(
				[Parameter(Mandatory = $true)]
				[ValidateNotNullOrEmpty()]
				[object]$server	
			)
			
	try {
			return ($server.ConnectionContext.FixedServerRoles -match "SysAdmin")
		}
		catch { return $false }
	}

	Function Parse-ServerGroup($sourceGroup, $destinationgroup, $SwitchServerName) {

	if ($destinationgroup.name -eq "DatabaseEngineServerGroup" -and $sourceGroup.name -ne "DatabaseEngineServerGroup") {
		$currentservergroup = $destinationgroup
		$destinationgroup = $destinationgroup.ServerGroups[$sourceGroup.name]
		if ($destinationgroup -eq $null) {
			Write-Host "Creating group $($sourceGroup.name)" -ForegroundColor Green
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
					Write-Warning "SwitchServerName was used and new CMS equals current server name. $($tocmstore.DomainInstanceName.ToLower()) changed to $servername."
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
					if ($_.Exception -match "same name") { write-warning "Could not add Switched Server instance name."; continue }
					else { Write-Host "Failed to add $servername" -ForegroundColor Red }
				}
				Write-Host "Added Server $servername as $instancename to $($destinationgroup.name)" -ForegroundColor Green
			  }
			else { Write-Warning "Server $instancename already exists. Skipped" }
		}
	 
		# Add Groups
		foreach($fromsubgroup in $sourceGroup.ServerGroups)
		{
			$tosubgroup = $destinationgroup.ServerGroups[$fromsubgroup.name]
			if ($tosubgroup -eq $null) {
				Write-Host "Creating group $($fromsubgroup.name)" -ForegroundColor Green
				$tosubgroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup($destinationgroup,$fromsubgroup.name)
				$tosubgroup.create()
			}
		
		 Parse-ServerGroup -sourceGroup $fromsubgroup -destinationgroup $tosubgroup -SwitchServerName $SwitchServerName
		}
	}
}

PROCESS { 
	if ($CMSGroups.Value -ne $null) {$CMSGroups = @($CMSGroups.Value)}  else {$CMSGroups = $null}
		
	[void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO')
	[void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.Management.RegisteredServers')
	 
	Write-Host "Connecting to SQL Servers" -ForegroundColor Green
	$sourcesmo = New-Object Microsoft.SqlServer.Management.Smo.Server $source
	$destinationsmo = New-Object Microsoft.SqlServer.Management.Smo.Server $destination

	if (!(Test-SQLSA $sourcesmo)) { throw "Not a sysadmin on $($sourcesmo.name). Quitting." }  
	if (!(Test-SQLSA $destinationsmo)) { throw "Not a sysadmin on  $($destinationsmo.name). Quitting." }  

	Write-Host "Connecting to Central Management Servers" -ForegroundColor Green
	try { 
		$fromcmstore = new-object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($sourcesmo.ConnectionContext.SqlConnectionObject)
		$tocmstore = new-object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore($destinationsmo.ConnectionContext.SqlConnectionObject)
		}
	catch { throw "Cannot access Central Management Servers" }
	
	if ($CMSGroups -eq $null) { $stores = $fromcmstore.DatabaseEngineServerGroup } 
	else { $stores = @(); foreach ($groupname in $CMSGroups) { $stores += $fromcmstore.DatabaseEngineServerGroup.ServerGroups[$groupname] } }

	foreach ($store in $stores) {
		Parse-ServerGroup -sourceGroup $store -destinationgroup $tocmstore.DatabaseEngineServerGroup -SwitchServerName $SwitchServerName
	}

}

END {
	$server.ConnectionContext.Disconnect()
	Write-Host "Script completed" -ForegroundColor Green
}