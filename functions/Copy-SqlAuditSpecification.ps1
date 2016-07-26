Function Copy-SqlAuditSpecification
{
<#
.SYNOPSIS 
Copy-SqlAuditSpecification migrates server audit specifications from one SQL Server to another. 

.DESCRIPTION
By default, all audits are copied. The -ServerAuditSpecifications parameter is autopopulated for command-line completion and can be used to copy only specific audits.

If the audit specification already exists on the destination, it will be skipped unless -Force is used. 

.PARAMETER Source
Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER Destination
Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

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
https://dbatools.io/Copy-SqlAuditSpecification

.EXAMPLE   
Copy-SqlAuditSpecification -Source sqlserver2014a -Destination sqlcluster

Copies all server audits from sqlserver2014a to sqlcluster, using Windows credentials. If audits with the same name exist on sqlcluster, they will be skipped.

.EXAMPLE   
Copy-SqlAuditSpecification -Source sqlserver2014a -Destination sqlcluster -ServerAuditSpecifications tg_noDbDrop -SourceSqlCredential $cred -Force

Copies a single audit, the tg_noDbDrop audit from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If an audit with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

.EXAMPLE   
Copy-SqlAuditSpecification -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

Shows what would happen if the command were executed using force.
#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[object]$Source,
		[parameter(Mandatory = $true)]
		[object]$Destination,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[switch]$Force
	)
	DynamicParam { if ($source) { return (Get-ParamSqlServerServerAuditSpecifications -SqlServer $Source -SqlCredential $SourceSqlCredential) } }
	
	BEGIN
	{
		
		$auditspecs = $psboundparameters.ServerAuditSpecifications
		
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
		if (!(Test-SqlSa -SqlServer $sourceserver -SqlCredential $SourceSqlCredential)) { throw "Not a sysadmin on $source. Quitting." }
		if (!(Test-SqlSa -SqlServer $destserver -SqlCredential $DestinationSqlCredential)) { throw "Not a sysadmin on $destination. Quitting." }
		
		if ($sourceserver.versionMajor -lt 10 -or $destserver.versionMajor -lt 10)
		{
			throw "Server Audit Specifications are only supported in SQL Server 2008 and above. Quitting."
			
		}
		
		$serverauditspecs = $sourceserver.ServerAuditSpecifications
		$destaudits = $destserver.ServerAuditSpecifications
		
	}
	PROCESS
	{
		
		
		foreach ($auditspec in $serverauditspecs)
		{
			$auditspecname = $auditspec.name
			if ($auditspecs.length -gt 0 -and $auditspecs -notcontains $auditspecname) { continue }
			
			$destserver.Audits.Refresh()
			
			if ($destserver.Audits.Name -notcontains $auditspec.AuditName)
			{
				Write-Warning "Audit $($auditspec.AuditName) does not exist on $Destination. Skipping $auditspecname."
				continue
			}
			
			if ($destaudits.name -contains $auditspecname)
			{
				if ($force -eq $false)
				{
					Write-Warning "Server audit $auditspecname exists at destination. Use -Force to drop and migrate."
					continue
				}
				else
				{
					If ($Pscmdlet.ShouldProcess($destination, "Dropping server audit $auditspecname and recreating"))
					{
						try
						{
							Write-Verbose "Dropping server audit $auditspecname"
							$destserver.ServerAuditSpecifications[$auditspecname].Drop()
						}
						catch { 
							Write-Exception $_ 
							continue
						}
					}
				}
			}
			
			If ($Pscmdlet.ShouldProcess($destination, "Creating server audit $auditspecname"))
			{
				try
				{
					Write-Output "Copying server audit $auditspecname"
					$destserver.ConnectionContext.ExecuteNonQuery($auditspec.Script()) | Out-Null
				}
				catch
				{
					Write-Exception $_
				}
			}

		}
	}
	
	END
	{
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Server audit migration finished" }
	}
}