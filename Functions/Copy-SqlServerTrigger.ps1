Function Copy-SqlServerTrigger {
<#
.SYNOPSIS 
Copy-SqlServerTrigger migrates server triggers from one SQL Server to another. 

.DESCRIPTION
By default, all triggers are copied. The -Triggers parameter is autopopulated for command-line completion and can be used to copy only specific triggers.

If the trigger already exists on the destination, it will be skipped unless -Force is used. 

.PARAMETER Source
Source Sql Server. You must have sysadmin access and server version must be > Sql Server 7.

.PARAMETER Destination
Destination Sql Server. You must have sysadmin access and server version must be > Sql Server 7.

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
Author  : Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

.EXAMPLE   
Copy-SqlServerTrigger -Source sqlserver2014a -Destination sqlcluster

Copies all server triggers from sqlserver2014a to sqlcluster, using Windows credentials. If triggers with the same name exist on sqlcluster, they will be skipped.

.EXAMPLE   
Copy-SqlServerTrigger -Source sqlserver2014a -Destination sqlcluster -Trigger tg_noDbDrop -SourceSqlCredential $cred -Force

Copies a single trigger, the tg_noDbDrop trigger from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a
and Windows credentials for sqlcluster. If a trigger with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

.EXAMPLE   
Copy-SqlServerTrigger -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

Shows what would happen if the command were executed using force.
#>
[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess = $true)] 
param(
	[parameter(Mandatory = $true)]
	[object]$Source,
	[parameter(Mandatory = $true)]
	[object]$Destination,
	[System.Management.Automation.PSCredential]$SourceSqlCredential,
	[System.Management.Automation.PSCredential]$DestinationSqlCredential,
	[switch]$force
)
DynamicParam  { if ($source) { return (Get-ParamSqlServerTriggers -SqlServer $Source -SqlCredential $SourceSqlCredential) } }
	
PROCESS {
	$triggers = $psboundparameters.Triggers
	
	$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
	$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential

	$source = $sourceserver.name
	$destination = $destserver.name	
	
	if (!(Test-SqlSa -SqlServer $sourceserver -SqlCredential $SourceSqlCredential)) { throw "Not a sysadmin on $source. Quitting." }
	if (!(Test-SqlSa -SqlServer $destserver -SqlCredential $DestinationSqlCredential)) { throw "Not a sysadmin on $destination. Quitting." }
	
	$servertriggers = $sourceserver.Triggers
	$desttriggers = $destserver.Triggers
	
	foreach ($trigger in $servertriggers) {
		if ($triggers.length -gt 0 -and $triggers -notcontains $trigger.name) { continue }
		if ($desttriggers.name -contains $trigger.name) {
			if ($force -eq $false) {
				Write-Warning "Server trigger $($trigger.name) exists at destination. Use -Force to drop and migrate."
			} else {
				If ($Pscmdlet.ShouldProcess($destination,"Dropping server trigger $($trigger.name) and recreating")) {
					try {
						Write-Output "Dropping server trigger $($trigger.name)"
						$destserver.triggers[$trigger.name].Drop()
						Write-Output "Copying server trigger $($trigger.name)"
						$destserver.ConnectionContext.ExecuteNonQuery($trigger.Script()) | Out-Null
					} catch { Write-Exception $_  }
				}
			}
		} else {
			If ($Pscmdlet.ShouldProcess($destination,"Creating server trigger $($trigger.name)")) {
				try { 
					Write-Output "Copying server trigger $($trigger.name)"
					$destserver.ConnectionContext.ExecuteNonQuery($trigger.Script()) | Out-Null
				 } catch {
					Write-Exception $_ 
				}
			}
		}
	}
}

END {
	$sourceserver.ConnectionContext.Disconnect()
	$destserver.ConnectionContext.Disconnect()
	If ($Pscmdlet.ShouldProcess("console","Showing finished message")) { Write-Output "Server trigger migration finished" }
}
}