Function Get-DbaPermission
{
<#
.SYNOPSIS
Get a list of Server and Database level permissions

.DESCRIPTION
Retrieves a list of permissions

Permissions link principals to securables.
Principals exist on Windows, Instance and Database level.
Securables exist on Instance and Database level.
A permission state can be GRANT, DENY or REVOKE.
The permission type can be SELECT, CONNECT, EXECUTE and more.
	
See https://msdn.microsoft.com/en-us/library/ms191291.aspx for more information

.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER Credential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Databases
Return information for only specific databases

.PARAMETER Exclude
Return information for all but these specific databases

.PARAMETER Detailed
Shows detailed information

.PARAMETER IncludeServerLevel
Shows also information on Server Level Permissions

.PARAMETER NoSystemObjects
Excludes all permissions on system securables

.NOTES
Author: Klaas Vandenberghe ( @PowerDBAKlaas )
	
dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

	
.LINK
https://dbatools.io/Get-DbaPermission

.EXAMPLE
Get-DbaPermission -SqlServer ServerA\sql987

Returns a custom object with Server name, Database name, permission state, permission type, grantee and securable

.EXAMPLE
Get-DbaPermission -SqlServer ServerA\sql987 -Detailed | Format-Table -AutoSize

Returns a formatted table displaying Server, Database, permission state, permission type, grantee, granteetype, securable and securabletype

.EXAMPLE
Get-DbaPermission -SqlServer ServerA\sql987 -NoSystemObjects -IncludeServerLevel

Returns a custom object with Server name, Database name, permission state, permission type, grantee and securable
in all databases and on the server level, but not on system securables
	
.EXAMPLE
Get-DbaPermission -SqlServer sql2016 -Databases master

Returns a custom object with permissions for the master database

#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string[]]$SqlServer,
		[PsCredential]$Credential,
		[switch]$Detailed,
		[switch]$IncludeServerLevel,
		[switch]$NoSystemObjects
	)
	
	DynamicParam
	{
		if ($SqlServer)
		{
			return Get-ParamSqlDatabases -SqlServer $SqlServer[0] -SqlCredential $Credential
		}
	}
	
	BEGIN
	{
		# Convert from RuntimeDefinedParameter object to regular array
		$databases = $psboundparameters.Databases
		$exclude = $psboundparameters.Exclude
		
		if ($NoSystemObjects)
		{
			$ExcludeSystemObjectssql = "WHERE major_id > 0 "
		}
		$ServPermsql = @"
SELECT	  
	  [Server] = @@SERVERNAME
    , [Database] = ''
    , [PermState] = state_desc
	, [PermissionName] = permission_name
	, [SecurableType] = COALESCE(O.type_desc,sp.class_desc)
	, [Securable] = CASE	WHEN class = 100 THEN @@SERVERNAME
							WHEN class = 105 THEN OBJECT_NAME(major_id)
							ELSE OBJECT_NAME(major_id)
							END
	, [Grantee] = SUSER_NAME(grantee_principal_id)
	, [GranteeType] = pr.type_desc

FROM sys.server_permissions sp
	JOIN sys.server_principals pr ON pr.principal_id = sp.grantee_principal_id
	LEFT OUTER JOIN sys.all_objects o ON o.object_id = sp.major_id

$ExcludeSystemObjectssql

;
"@
		
		$DBPermsql = @"
SELECT
	  [Server] = @@SERVERNAME
	, [Database] = DB_NAME()
	, [PermState] = state_desc
    , [PermissionName] = permission_name
	, [SecurableType] = COALESCE(O.type_desc,dp.class_desc)
    , [Securable] = CASE	WHEN class = 0 THEN DB_NAME()
							WHEN class = 1 THEN ISNULL(s.name + '.','')+OBJECT_NAME(major_id)
							WHEN class = 3 THEN SCHEMA_NAME(major_id) END
    , [Grantee] = USER_NAME(grantee_principal_id)
	, [GranteeType] = pr.type_desc

FROM sys.database_permissions dp
	JOIN sys.database_principals pr ON pr.principal_id = dp.grantee_principal_id
	LEFT OUTER JOIN sys.all_objects o ON o.object_id = dp.major_id
	LEFT OUTER JOIN sys.schemas s ON s.schema_id = o.schema_id

$ExcludeSystemObjectssql

;
"@
	}
	
	PROCESS
	{
		foreach ($servername in $SqlServer)
		{
			try
			{
				$server = Connect-SqlServer -SqlServer $servername -SqlCredential $Credential
			}
			catch
			{
				if ($SqlServer.count -eq 1)
				{
					throw $_
				}
				else
				{
					Write-Warning "Can't connect to $servername. Moving on."
					Continue
				}
			}
			
			if ($server.versionMajor -lt 9)
			{
				Write-Warning "Get-DbaPermission is only supported on SQL Server 2005 and above. Skipping Instance."
				Continue
			}
			
			if ($IncludeServerLevel)
			{
				Write-Debug "T-SQL: $ServPermsql"
				
				$resultTable = $null
				$resultTable = $server.Databases["master"].ExecuteWithResults($ServPermsql).Tables[0]
				foreach ($row in $resultTable)
				{
					$obj = [PSCustomObject]@{
						Server = $row.Server
						Database = ""
						PermState = $row.PermState
						PermName = $row.PermissionName
						Securable = $row.Securable
						Grantee = $row.Grantee
						SecurableType = $row.SecurableType
						GranteeType = $row.GranteeType
					}
					if ($detailed) { $obj }
					else { $obj | Select-Object Server, Database, PermState, PermName, Securable, Grantee }
				}
			}
			
			$dbs = $server.Databases
			
			if ($databases.count -gt 0)
			{
				$dbs = $dbs | Where-Object { $databases -contains $_.Name }
			}
			
			if ($exclude.count -gt 0)
			{
				$dbs = $dbs | Where-Object { $exclude -notcontains $_.Name }
			}
			
			#			$dbs = $dbs | Where-Object {$_.IsAccessible}
			
			foreach ($db in $dbs)
			{
				Write-Verbose "Processing $($db.name) on $servername"
				
				if ($db.IsAccessible -eq $false)
				{
					Write-Warning "The database $($db.name) is not accessible. Skipping database."
					Continue
				}
				
				
				Write-Debug "T-SQL: $DBPermsql"
				
				$resultTable = $null
				$resultTable = $db.ExecuteWithResults($DBPermsql).Tables[0]
				foreach ($row in $resultTable)
				{
					$obj = [PSCustomObject]@{
						Server = $row.Server
						Database = $row.Database
						PermState = $row.PermState
						PermName = $row.PermissionName
						Securable = $row.Securable
						Grantee = $row.Grantee
						SecurableType = $row.SecurableType
						GranteeType = $row.GranteeType
					}
					if ($detailed) { $obj }
					else { $obj | Select-Object Server, Database, PermState, PermName, Securable, Grantee }
				}
			}
		}
	}
	END
	{ }
}
