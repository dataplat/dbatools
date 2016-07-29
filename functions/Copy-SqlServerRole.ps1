Function Copy-SqlServerRole
{
<#
.SYNOPSIS 
Copy-SqlServerRole migrates server roles from one SQL Server to another. 

.DESCRIPTION
By default, all roles are copied. The -Roles parameter is autopopulated for command-line completion and can be used to copy only specific roles.

If the role already exists on the destination, it will be skipped unless -Force is used. 

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
https://dbatools.io/Copy-SqlServerRole 

.EXAMPLE   
Copy-SqlServerRole -Source sqlserver2014a -Destination sqlcluster

Copies all server roles from sqlserver2014a to sqlcluster, using Windows credentials. If roles with the same name exist on sqlcluster, they will be skipped.

.EXAMPLE   
Copy-SqlServerRole -Source sqlserver2014a -Destination sqlcluster -Role tg_noDbDrop -SourceSqlCredential $cred -Force

Copies a single role, the tg_noDbDrop role from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a role with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

.EXAMPLE   
Copy-SqlServerRole -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

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
	DynamicParam { if ($source) { return (Get-ParamSqlServerRoles -SqlServer $Source -SqlCredential $SourceSqlCredential) } }
	
BEGIN {
		
		$roles = $psboundparameters.Roles
		
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
		$serverroles = $sourceserver.Roles
		$destroles = $destserver.Roles
}
	PROCESS
	{
		throw "This function is not quite ready yet."
		
		foreach ($role in $serverroles)
		{
			$rolename = $role.name
			if ($roles.length -gt 0 -and $roles -notcontains $rolename) { continue }
			
			if ($destroles.name -contains $rolename)
			{
				if ($role.IsFixedRole -eq $true -or $rolename -eq "public") { continue }
				
				if ($force -eq $false)
				{
					Write-Warning "Server role $rolename exists at destination. Use -Force to drop and migrate."
					continue
				}
				else
				{
					If ($Pscmdlet.ShouldProcess($destination, "Dropping server role $rolename"))
					{
						try
						{
							Write-Verbose "Dropping server role $rolename"
							$destserver.roles[$rolename].Drop()
						}
						catch
						{
							Write-Exception $_
						}
					}
				}
			}
			
			If ($Pscmdlet.ShouldProcess($destination, "Creating server role $rolename"))
			{
				try
				{
					Write-Output "Copying server role $rolename"
					$destserver.ConnectionContext.ExecuteNonQuery($role.Script()) | Out-Null
					$destserver.Refresh()
					$destserver.roles.Refresh()
					$newrole = $destserver.roles[$rolename]
					
					try { $rolemembers = $role.EnumMemberNames() }
					catch { $rolemembers = $role.EnumServerRoleMembers() }
					
					foreach ($rolename in $rolemembers)
					{
						if ($destserver.logins[$rolename] -ne $null)
						{
							$newrole.AddMember($rolename)
						}
					}
					
					if ($sourceserver.versionMajor -ge 9 -and $destserver.versionMajor -ge 9)
					{
						# These operations are only supported by SQL Server 2005 and above.
						# Securables: Connect SQL, View any database, Administer Bulk Operations, etc.
						
						$perms = $sourceserver.EnumServerPermissions($($rolename))
						foreach ($perm in $perms)
						{
							
							<#
							SO HARD. I must be overthinking this.
							
							Here's some equivs for database level. It's hard to find 
							$permissionset1 = New-Object Microsoft.SqlServer.Management.Smo.ObjectPermissionSet([Microsoft.SqlServer.Management.Smo.ObjectPermission]::Select)
							$permissionset1.Add([Microsoft.SqlServer.Management.Smo.ObjectPermission]::Select)
							$hrschema = $database.Schemas["HumanResources"] 
							$hrschema.Grant($permissionset1, $dbrole.Name)
							
							$permissionType = $perm.PermissionType
							$permissionState = $perm.PermissionState
							
							if ($perm.PermissionState -eq "Grant")
							{
								$permstate = 0
							}
							else
							{
								$permstate = 1
							}
							
							$permissionSet = New-Object Microsoft.SqlServer.Management.Smo.ObjectPermissionSet([Microsoft.SqlServer.Management.Smo.ObjectPermission]::$permissionType)
							
							#identify permission
							$permissionSet = New-Object Microsoft.SqlServer.Management.Smo.ObjectPermissionSet([Microsoft.SqlServer.Management.Smo.ObjectPermission]::Connect)
							if (PermissionState)
							$role.Grant($permissionSet, $rolename, 1)
							
							#grant permission
							$endpoint.Grant($permissionSet, $endpointAccount)
							
							
							PermissionType  : ALTER
							Grantee         : Endpoint-Admins
							GranteeType     : ServerRole
							Grantor         : BASE\ctrlb
							GrantorType     : Login
							PermissionState : Grant
							ColumnName      :
							ObjectClass     : Endpoint
							ObjectName      : endpoint_mirroring
							ObjectSchema    :
							ObjectID        : 65536
							#>
							$permstate = $perm.permissionstate
							if ($permstate -eq "GrantWithGrant") { $grantwithgrant = $true; $permstate = "grant" }
							else { $grantwithgrant = $false }
							$permset = New-Object Microsoft.SqlServer.Management.Smo.ObjectPermissionSet($perm.permissiontype)
							If ($Pscmdlet.ShouldProcess($destination, "Performing $permstate on $($perm.permissiontype) for $rolename"))
							{
								try
								{
									$destserver.PSObject.Methods[$permstate].Invoke($permset, $rolename, $grantwithgrant)
									Write-Output "Successfully performed $permstate $($perm.permissiontype) to $rolename"
								}
								catch
								{
									Write-Warning "Failed to $permstate $($perm.permissiontype) to $rolename"
									Write-Exception $_
								}
							}
							
							# for Syncs
							$destperms = $destserver.EnumServerPermissions($rolename)
							foreach ($perm in $destperms)
							{
								$permstate = $perm.permissionstate
								$sourceperm = $perms | Where-Object { $_.PermissionType -eq $perm.Permissiontype -and $_.PermissionState -eq $permstate }
								if ($sourceperm -eq $null)
								{
									If ($Pscmdlet.ShouldProcess($destination, "Performing Revoke on $($perm.permissiontype) for $rolename"))
									{
										try
										{
											$permset = New-Object Microsoft.SqlServer.Management.Smo.ObjectPermissionSet($perm.permissiontype)
											if ($permstate -eq "GrantWithGrant") { $grantwithgrant = $true; $permstate = "grant" }
											else { $grantwithgrant = $false }
											$destserver.PSObject.Methods["Revoke"].Invoke($permset, $rolename, $false, $grantwithgrant)
											Write-Output "Successfully revoked $($perm.permissiontype) from $rolename"
										}
										catch
										{
											Write-Warning "Failed to revoke $($perm.permissiontype) from $rolename"
											Write-Exception $_
										}
									}
								}
							}
						}
					}
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
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Server role migration finished" }
	}
}