function Get-DbaPermission {
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
The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

.PARAMETER ExcludeDatabase
The database(s) to exclude - this list is auto-populated from the server

.PARAMETER IncludeServerLevel
Shows also information on Server Level Permissions

.PARAMETER NoSystemObjects
Excludes all permissions on system securables

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.NOTES
Tags: Permissions, Databases
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
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential]
		$SqlCredential,
		[Alias("Databases")]
		[object[]]$Database,
		[object[]]$ExcludeDatabase,
		[switch]$IncludeServerLevel,
		[switch]$NoSystemObjects,
		[switch]$Silent
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
			Write-Message -Level Verbose -Message "Connecting to $instance"
			
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			if ($server.versionMajor -lt 9) {
				Write-Warning "Get-DbaPermission is only supported on SQL Server 2005 and above. Skipping $instance."
				Continue
			}

			if ($IncludeServerLevel) {
				Write-Message -Level Debug -Message "T-SQL: $ServPermsql"
				$server.Query($ServPermsql).Tables.Rows
			}

			$dbs = $server.Databases

			if ($Database) {
				$dbs = $dbs | Where-Object Name -In $Database
			}

			if ($ExcludeDatabase) {
				$dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
			}

			foreach ($db in $dbs) {
				Write-Message -Level Verbose -Message "Processing $db on $instance"

				if ($db.IsAccessible -eq $false) {
					Write-Warning "The database $db is not accessible. Skipping database."
					Continue
				}

				Write-Message -Level Debug -Message "T-SQL: $DBPermsql"
				$db.ExecuteWithResults($DBPermsql).Tables.Rows
			}
		}
	}
}
