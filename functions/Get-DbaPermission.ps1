Function Get-DbaPermission {
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

.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
Credential object used to connect to the SQL Server as a different user

.PARAMETER Database
The database(s) to process - this list is autopopulated from the server. If unspecified, all databases will be processed.

.PARAMETER Exclude
The database(s) to exclude - this list is autopopulated from the server

.PARAMETER IncludeServerLevel
Shows also information on Server Level Permissions

.PARAMETER NoSystemObjects
Excludes all permissions on system securables

.NOTES
Author: Klaas Vandenberghe ( @PowerDBAKlaas )
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
	
.LINK
https://dbatools.io/Get-DbaPermission

.EXAMPLE
Get-DbaPermission -SqlInstance ServerA\sql987

Returns a custom object with Server name, Database name, permission state, permission type, grantee and securable

.EXAMPLE
Get-DbaPermission -SqlInstance ServerA\sql987 | Format-Table -AutoSize

Returns a formatted table displaying Server, Database, permission state, permission type, grantee, granteetype, securable and securabletype

.EXAMPLE
Get-DbaPermission -SqlInstance ServerA\sql987 -NoSystemObjects -IncludeServerLevel

Returns a custom object with Server name, Database name, permission state, permission type, grantee and securable
in all databases and on the server level, but not on system securables
	
.EXAMPLE
Get-DbaPermission -SqlInstance sql2016 -Database master

Returns a custom object with permissions for the master database

#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[string[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$Exclude,
		[switch]$IncludeServerLevel,
		[switch]$NoSystemObjects
	)
	
	begin {
		if ($NoSystemObjects) {
			$ExcludeSystemObjectssql = "WHERE major_id > 0 "
		}
		
		$ServPermsql = "SELECT SERVERPROPERTY('MachineName') AS ComputerName, 
				       ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName, 
				       SERVERPROPERTY('ServerName') AS SqlInstance 
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

					$ExcludeSystemObjectssql;"
		
		$DBPermsql = "SELECT SERVERPROPERTY('MachineName') AS ComputerName, 
					ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName, 
					SERVERPROPERTY('ServerName') AS SqlInstance 
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
				;"
	}
	
	process {
		foreach ($instance in $SqlInstance) {
			Write-Verbose "Connecting to $instance"
			try {
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $sqlcredential
			}
			catch {
				Write-Warning "Can't connect to $instance"
				Continue
			}
			
			if ($server.versionMajor -lt 9) {
				Write-Warning "Get-DbaPermission is only supported on SQL Server 2005 and above. Skipping Instance."
				Continue
			}
			
			if ($IncludeServerLevel) {
				Write-Debug "T-SQL: $ServPermsql"
				$server.Databases["master"].ExecuteWithResults($ServPermsql).Tables.Rows
			}
			
			$dbs = $server.Databases
			
			if ($database) {
				$dbs = $dbs | Where-Object { $database -contains $_.Name }
			}
			
			if ($exclude) {
				$dbs = $dbs | Where-Object { $exclude -notcontains $_.Name }
			}
			
			# $dbs = $dbs | Where-Object {$_.IsAccessible}
			
			foreach ($db in $dbs) {
				Write-Verbose "Processing $($db.name) on $instance"
				
				if ($db.IsAccessible -eq $false) {
					Write-Warning "The database $($db.name) is not accessible. Skipping database."
					Continue
				}
				
				Write-Debug "T-SQL: $DBPermsql"
				$db.ExecuteWithResults($DBPermsql).Tables.Rows
			}
		}
	}
}

Register-DbaTeppArgumentCompleter -Command Get-DbaPermission -Parameter Database, Exclude