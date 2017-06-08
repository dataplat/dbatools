Function Export-SqlUser {
<#
.SYNOPSIS
Exports users creation and its permissions to a T-SQL file or host.

.DESCRIPTION
Exports users creation and its permissions to a T-SQL file or host. Export includes user, create and add to role(s), database level permissions, object level permissions.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER SqlInstance
The SQL Server instance name. SQL Server 2000 and above supported.
	
.PARAMETER SqlCredential
Allows you to login to servers using alternative credentials

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter

Windows Authentication will be used if SqlCredential is not specified

.PARAMETER User 
Export only the specified database user(s). If not specified will export all users from the database(s)

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.PARAMETER DestinationVersion
To say to which version the script should be generated. If not specified will use database compatibility level

.PARAMETER FilePath
The file to write to.

.PARAMETER NoClobber
Do not overwrite file
	
.PARAMETER Append
Append to file
	
.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.EXAMPLE
Export-SqlUser -SqlServer sql2005 -FilePath C:\temp\sql2005-users.sql

Exports SQL for the users in server "sql2005" and writes them to the file "C:\temp\sql2005-users.sql"

.EXAMPLE
Export-SqlUser -SqlServer sqlserver2014a $scred -FilePath C:\temp\users.sql -Append

Authenticates to sqlserver2014a using SQL Authentication. Exports all users to C:\temp\users.sql, and appends to the file if it exists. If not, the file will be created.

.EXAMPLE
Export-SqlUser -SqlServer sqlserver2014a -User User1, User2 -FilePath C:\temp\users.sql

Exports ONLY users User1 and User2 fron sqlsever2014a to the file  C:\temp\users.sql

.EXAMPLE
Export-SqlUser -SqlServer sqlserver2008 -User User1 -FilePath C:\temp\users.sql -DestinationVersion SQLServer2016

Exports user User1 fron sqlsever2008 to the file  C:\temp\users.sql with sintax to run on SQL Server 2016

.NOTES
Original Author: Claudio Silva (@ClaudioESSilva)
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.


.LINK
https://dbatools.io/Export-SqlUser
#>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	[OutputType([String])]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object]$SqlInstance,
		[object[]]$User,
		[ValidateSet('SQLServer2000', 'SQLServer2005', 'SQLServer2008/2008R2', 'SQLServer2012', 'SQLServer2014', 'SQLServer2016')]
		[string]$DestinationVersion,
		[Alias("OutFile", "Path", "FileName")]
		[string]$FilePath,
		[System.Management.Automation.PSCredential]$sqlCredential,
		[Alias("NoOverwrite")]
		[switch]$NoClobber,
		[switch]$Append,
		[switch]$Silent
	)
	
	dynamicparam {
		if ($sqlInstance) {
			return Get-ParamSqlDatabases -SqlServer $sqlInstance -SqlCredential $sqlCredential
		}
	}
	begin {
		if ($FilePath.Length -gt 0) {
			if ($FilePath -notlike "*\*") { $FilePath = ".\$filepath" }
			$directory = Split-Path $FilePath
			$exists = Test-Path $directory
			
			if ($exists -eq $false) {
				throw "Parent directory $directory does not exist"
			}
			
			Write-Message -Level Output -Message "Attempting to connect to SQL Servers.."
		}
		
		$outsql = @()
		
		$versions = @{
			'SQLServer2000' = 'Version80'
			'SQLServer2005' = 'Version90'
			'SQLServer2008/2008R2' = 'Version100'
			'SQLServer2012' = 'Version110'
			'SQLServer2014' = 'Version120'
			'SQLServer2016' = 'Version130'
		}
		
		$versionName = @{
			'Version80' = 'SQLServer2000'
			'Version90' = 'SQLServer2005'
			'Version100' = 'SQLServer2008/2008R2'
			'Version110' = 'SQLServer2012'
			'Version120' = 'SQLServer2014'
			'Version130' = 'SQLServer2016'
		}
		# Convert from RuntimeDefinedParameter object to regular array
		$databases = $psboundparameters.Databases
		$exclude = $psboundparameters.Exclude
		
	}
	process {
		
		try {
			Write-Message -Level Verbose -Message "Connecting to $sqlinstance"
			$server = Connect-SqlServer -SqlServer $sqlinstance -SqlCredential $sqlcredential
		}
		catch {
			Stop-Function -Message "Failed to connect to $instance : $($_.Exception.Message)" -Continue -Target $instance -InnerErrorRecord $_
		}
		
		if ($databases.Count -eq 0) {
			$databases = $server.Databases | Where-Object { $exclude -notcontains $_.Name -and $_.IsAccessible -eq $true }
		}
		else {
			if ($pipedatabase.Length -gt 0) {
				$source = $pipedatabase[0].parent.name
				$databases = $pipedatabase.name
			}
			else {
				$databases = $server.Databases | Where-Object { $exclude -notcontains $_.Name -and $_.IsAccessible -eq $true -and ($databases -contains $_.Name) }
			}
		}
		
		if (@($databases).Count -gt 0) {
			
			#Database Permissions
			foreach ($db in $databases) {
				if ([string]::IsNullOrEmpty($destinationVersion)) {
					#Get compatibility level for scripting the objects
					$scriptVersion = $db.CompatibilityLevel
				}
				else {
					$scriptVersion = $versions[$destinationVersion]
				}
				$versionNameDesc = $versionName[$scriptVersion.ToString()]
				
				#Options
				$scriptingOptions = New-DbaScriptingOption
				$scriptingOptions.TargetServerVersion = [Microsoft.SqlServer.Management.Smo.SqlServerVersion]::$scriptVersion
				$scriptingOptions.AllowSystemObjects = $false
				$scriptingOptions.IncludeDatabaseRoleMemberships = $true
				$scriptingOptions.ContinueScriptingOnError = $false
				$scriptingOptions.IncludeDatabaseContext = $false
				
				Write-Message -Level Output -Message "Validating users on database $db"
				
				if ($User.Count -eq 0) {
					$users = $db.Users | Where-Object { $_.IsSystemObject -eq $false -and $_.Name -notlike "##*" }
				}
				else {
					if ($pipedatabase.Length -gt 0) {
						$source = $pipedatabase[3].parent.name
						$users = $pipedatabase.name
					}
					else {
						$users = $db.Users | Where-Object { $User -contains $_.Name -and $_.IsSystemObject -eq $false -and $_.Name -notlike "##*" }
					}
				}
				
				if ($users.Count -gt 0) {
					foreach ($dbuser in $users) {
						#setting database
						$outsql += "USE [" + $db.Name + "]"
						
						try {
							#Fixed Roles #Dependency Issue. Create Role, before add to role.
							foreach ($rolePermission in ($db.Roles | Where-Object { $_.IsFixedRole -eq $false })) {
								foreach ($rolePermissionScript in $rolePermission.Script($scriptingOptions)) {
									#$roleScript = $rolePermission.Script($scriptingOptions)
									$outsql += "$($rolePermissionScript.ToString())"
								}
							}
							
							#Database Create User(s) and add to Role(s)
							foreach ($dbUserPermissionScript in $dbuser.Script($scriptingOptions)) {
								if ($dbuserPermissionScript.Contains("sp_addrolemember")) {
									$execute = "EXEC "
								}
								else {
									$execute = ""
								}
								$outsql += "$execute$($dbUserPermissionScript.ToString())"
							}
							
							#Database Permissions
							foreach ($databasePermission in $db.EnumDatabasePermissions() | Where-Object { @("sa", "dbo", "information_schema", "sys") -notcontains $_.Grantee -and $_.Grantee -notlike "##*" -and ($dbuser.Name -contains $_.Grantee) }) {
								if ($databasePermission.PermissionState -eq "GrantWithGrant") {
									$withGrant = " WITH GRANT OPTION"
									$grantDatabasePermission = 'GRANT'
								}
								else {
									$withGrant = " "
									$grantDatabasePermission = $databasePermission.PermissionState.ToString().ToUpper()
								}
								
								$outsql += "$($grantDatabasePermission) $($databasePermission.PermissionType) TO [$($databasePermission.Grantee)]$withGrant AS [$($databasePermission.Grantor)];"
							}
							
							
							#Database Object Permissions
							# NB: This is a bit of a mess for a couple of reasons
							# 1. $db.EnumObjectPermissions() doesn't enumerate all object types
							# 2. Some (x)Collection types can have EnumObjectPermissions() called
							#    on them directly (e.g. AssemblyCollection); others can't (e.g.
							#    ApplicationRoleCollection). Those that can't we iterate the
							#    collection explicitly and add each object's permission.
							
							$perms = New-Object System.Collections.ArrayList
							
							$null = $perms.AddRange($db.EnumObjectPermissions($dbuser.Name))
							
							foreach ($item in $db.ApplicationRoles) {
								$null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
							}
							
							foreach ($item in $db.Assemblies) {
								$null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
							}
							
							foreach ($item in $db.Certificates) {
								$null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
							}
							
							foreach ($item in $db.DatabaseRoles) {
								$null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
							}
							
							foreach ($item in $db.FullTextCatalogs) {
								$null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
							}
							
							foreach ($item in $db.FullTextStopLists) {
								$null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
							}
							
							foreach ($item in $db.SearchPropertyLists) {
								$null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
							}
							
							foreach ($item in $db.ServiceBroker.MessageTypes) {
								$null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
							}
							
							foreach ($item in $db.RemoteServiceBindings) {
								$null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
							}
							
							foreach ($item in $db.ServiceBroker.Routes) {
								$null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
							}
							
							foreach ($item in $db.ServiceBroker.ServiceContracts) {
								$null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
							}
							
							foreach ($item in $db.ServiceBroker.Services) {
								$null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
							}
							
							if ($scriptVersion -ne "Version80") {
								foreach ($item in $db.AsymmetricKeys) {
									$null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
								}
							}
							
							foreach ($item in $db.SymmetricKeys) {
								$null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
							}
							
							foreach ($item in $db.XmlSchemaCollections) {
								$null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
							}
							
							foreach ($objectPermission in $perms | Where-Object { @("sa", "dbo", "information_schema", "sys") -notcontains $_.Grantee -and $_.Grantee -notlike "##*" -and $_.Grantee -eq $dbuser.Name }) {
								switch ($objectPermission.ObjectClass) {
									'ApplicationRole'
									{
										$object = 'APPLICATION ROLE::[{0}]' -f $objectPermission.ObjectName
									}
									'AsymmetricKey'
									{
										$object = 'ASYMMETRIC KEY::[{0}]' -f $objectPermission.ObjectName
									}
									'Certificate'
									{
										$object = 'CERTIFICATE::[{0}]' -f $objectPermission.ObjectName
									}
									'DatabaseRole'
									{
										$object = 'ROLE::[{0}]' -f $objectPermission.ObjectName
									}
									'FullTextCatalog'
									{
										$object = 'FULLTEXT CATALOG::[{0}]' -f $objectPermission.ObjectName
									}
									'FullTextStopList'
									{
										$object = 'FULLTEXT STOPLIST::[{0}]' -f $objectPermission.ObjectName
									}
									'MessageType'
									{
										$object = 'Message Type::[{0}]' -f $objectPermission.ObjectName
									}
									'ObjectOrColumn'
									{
										
										if ($scriptVersion -ne "Version80") {
											$object = 'OBJECT::[{0}].[{1}]' -f $objectPermission.ObjectSchema, $objectPermission.ObjectName
											if ($null -ne $objectPermission.ColumnName) {
												$object += '([{0}])' -f $objectPermission.ColumnName
											}
										}
										#At SQL Server 2000 OBJECT did not exists
										else {
											$object = '[{0}].[{1}]' -f $objectPermission.ObjectSchema, $objectPermission.ObjectName
										}
									}
									'RemoteServiceBinding'
									{
										$object = 'REMOTE SERVICE BINDING::[{0}]' -f $objectPermission.ObjectName
									}
									'Schema'
									{
										$object = 'SCHEMA::[{0}]' -f $objectPermission.ObjectName
									}
									'SearchPropertyList'
									{
										$object = 'SEARCH PROPERTY LIST::[{0}]' -f $objectPermission.ObjectName
									}
									'Service'
									{
										$object = 'SERVICE::[{0}]' -f $objectPermission.ObjectName
									}
									'ServiceContract'
									{
										$object = 'CONTRACT::[{0}]' -f $objectPermission.ObjectName
									}
									'ServiceRoute'
									{
										$object = 'ROUTE::[{0}]' -f $objectPermission.ObjectName
									}
									'SqlAssembly'
									{
										$object = 'ASSEMBLY::[{0}]' -f $objectPermission.ObjectName
									}
									'SymmetricKey'
									{
										$object = 'SYMMETRIC KEY::[{0}]' -f $objectPermission.ObjectName
									}
									'User'
									{
										$object = 'USER::[{0}]' -f $objectPermission.ObjectName
									}
									'UserDefinedType'
									{
										$object = 'TYPE::[{0}].[{1}]' -f $objectPermission.ObjectSchema, $objectPermission.ObjectName
									}
									'XmlNamespace'
									{
										$object = 'XML SCHEMA COLLECTION::[{0}]' -f $objectPermission.ObjectName
									}
								}
								
								if ($objectPermission.PermissionState -eq "GrantWithGrant") {
									$withGrant = " WITH GRANT OPTION"
									$grantObjectPermission = 'GRANT'
								}
								else {
									$withGrant = " "
									$grantObjectPermission = $objectPermission.PermissionState.ToString().ToUpper()
								}
								
								$outsql += "$grantObjectPermission $($objectPermission.PermissionType) ON $object TO [$($objectPermission.Grantee)]$withGrant AS [$($objectPermission.Grantor)];"
							}
							
						}
						catch {
							Stop-Function -Message "This user may be using functionality from $($versionName[$db.CompatibilityLevel.ToString()]) that does not exist on the destination version ($versionNameDesc)." -Continue -InnerErrorRecord $_ -Target $db
						}
					}
				}
				else {
					Write-Message -Level Output -Message "No users found on database '$db'"
				}
				
				#reset collection
				$users = $null
			}
		}
		else {
			Write-Message -Level Output -Message "No users found on instance '$server'"
		}
	}
	
	end {
		$sql = $outsql -join "`r`nGO`r`n"
		#add the final GO
		$sql += "`r`nGO"
		
		if ($FilePath.Length -gt 0) {
			$sql | Out-File -Encoding UTF8 -FilePath $FilePath -Append:$Append -NoClobber:$NoClobber
		}
		else {
			return $sql
		}
	}
}
