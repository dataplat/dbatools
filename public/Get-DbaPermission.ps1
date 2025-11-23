function Get-DbaPermission {
    <#
    .SYNOPSIS
        Retrieves explicit and implicit permissions across SQL Server instances and databases for security auditing

    .DESCRIPTION
        Retrieves comprehensive permission information from SQL Server instances and databases, including both explicit permissions and implicit permissions from fixed roles.

        This function queries sys.server_permissions and sys.database_permissions to capture all granted, denied, and revoked permissions across server and database levels.
        Perfect for security audits, compliance reporting, troubleshooting access issues, and planning permission migrations between environments.

        The output includes permission state (GRANT/DENY/REVOKE), permission type (SELECT, CONNECT, EXECUTE, etc.), grantee information, and the specific securable being protected.
        Also captures implicit CONTROL permissions for dbo users, db_owner role members, and schema owners that aren't explicitly stored in system tables.
        Each result includes ready-to-use GRANT and REVOKE statements for easy permission replication or cleanup.

        Permissions link principals (logins, users, roles) to securables (servers, databases, schemas, objects).
        Principals exist at Windows, instance, and database levels, while securables exist at instance and database levels.

        See https://msdn.microsoft.com/en-us/library/ms191291.aspx for more information about SQL Server permissions

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Defaults to localhost.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to analyze for permissions. Accepts wildcards and multiple database names.
        When omitted, all accessible databases on the instance are processed, which is useful for comprehensive security audits.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from permission analysis. Accepts wildcards and multiple database names.
        Commonly used to skip system databases like TempDB or exclude sensitive databases from security reports.

    .PARAMETER IncludeServerLevel
        Includes server-level permissions in the output, such as CONTROL SERVER, VIEW SERVER STATE, and fixed server roles like sysadmin.
        Essential for complete security audits as it captures instance-wide permissions that affect all databases.

    .PARAMETER ExcludeSystemObjects
        Excludes permissions on system objects like system tables, views, and stored procedures from the output.
        Use this when focusing on user-created objects to reduce noise in permission reports and compliance audits.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Permissions, Instance, Database, Security
        Author: Klaas Vandenberghe (@PowerDBAKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaPermission

    .EXAMPLE
        PS C:\> Get-DbaPermission -SqlInstance ServerA\sql987

        Returns a custom object with Server name, Database name, permission state, permission type, grantee and securable.

    .EXAMPLE
        PS C:\> Get-DbaPermission -SqlInstance ServerA\sql987 | Format-Table -AutoSize

        Returns a formatted table displaying Server, Database, permission state, permission type, grantee, granteetype, securable and securabletype.

    .EXAMPLE
        PS C:\> Get-DbaPermission -SqlInstance ServerA\sql987 -ExcludeSystemObjects -IncludeServerLevel

        Returns a custom object with Server name, Database name, permission state, permission type, grantee and securable
        in all databases and on the server level, but not on system securables.

    .EXAMPLE
        PS C:\> Get-DbaPermission -SqlInstance sql2016 -Database master

        Returns a custom object with permissions for the master database.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$IncludeServerLevel,
        [switch]$ExcludeSystemObjects,
        [switch]$EnableException
    )
    begin {
        if ($ExcludeSystemObjects) {
            $ExcludeSystemObjectssql = "WHERE major_id > 0 "
        }

        $ServPermsql = "SELECT SERVERPROPERTY('MachineName') AS ComputerName,
                       ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                       SERVERPROPERTY('ServerName') AS SqlInstance
                        , [Database] = ''
                        , [PermState] = state_desc
                        , [PermissionName] = permission_name
                        , [SecurableType] = COALESCE(o.type_desc,sp.class_desc)
                        , [Securable] = CASE
                            WHEN class = 100 THEN @@SERVERNAME
                            WHEN class = 101 THEN SUSER_NAME(major_id)
                            WHEN class = 105 THEN (SELECT TOP (1) name FROM sys.endpoints WHERE endpoint_id = major_id)
                            WHEN class = 108 THEN (SELECT TOP (1) ag.name FROM sys.availability_replicas ar JOIN sys.availability_groups ag ON ar.group_id = ag.group_id WHERE ar.replica_metadata_id = major_id)
                            ELSE CONVERT(NVARCHAR, major_id)
                            END
                        , [Grantee] = SUSER_NAME(grantee_principal_id)
                        , [GranteeType] = pr.type_desc
                        , [revokeStatement] = 'REVOKE ' + permission_name + ' ' + COALESCE(OBJECT_NAME(major_id),'') + ' FROM [' + SUSER_NAME(grantee_principal_id) + ']'
                        , [grantStatement] = 'GRANT ' + permission_name + ' ' + COALESCE(OBJECT_NAME(major_id),'') + ' TO [' + SUSER_NAME(grantee_principal_id) + ']'
                            + CASE WHEN sp.state_desc = 'GRANT_WITH_GRANT_OPTION' THEN ' WITH GRANT OPTION' ELSE '' END
                    FROM sys.server_permissions sp
                        JOIN sys.server_principals pr ON pr.principal_id = sp.grantee_principal_id
                        LEFT OUTER JOIN sys.all_objects o ON o.object_id = sp.major_id

                    $ExcludeSystemObjectssql

                    UNION ALL
                    SELECT    SERVERPROPERTY('MachineName') AS ComputerName
                            , ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName
                            , SERVERPROPERTY('ServerName') AS SqlInstance
                            , [database] = ''
                            , [PermState] = 'GRANT'
                            , [PermissionName] = pb.[permission_name]
                            , [SecurableType] = pb.class_desc
                            , [Securable] = @@SERVERNAME
                            , [Grantee] = spr.name
                            , [GranteeType] = spr.type_desc
                            , [revokestatement] = ''
                            , [grantstatement] = ''
                    FROM sys.server_principals AS spr
                    INNER JOIN sys.fn_builtin_permissions('SERVER') AS pb ON
                        spr.[name]='bulkadmin' AND pb.[permission_name]='ADMINISTER BULK OPERATIONS'
                        OR
                        spr.[name]='dbcreator' AND pb.[permission_name]='CREATE ANY DATABASE'
                        OR
                        spr.[name]='diskadmin' AND pb.[permission_name]='ALTER RESOURCES'
                        OR
                        spr.[name]='processadmin' AND pb.[permission_name] IN ('ALTER ANY CONNECTION', 'ALTER SERVER STATE')
                        OR
                        spr.[name]='sysadmin' AND pb.[permission_name]='CONTROL SERVER'
                        OR
                        spr.[name]='securityadmin' AND pb.[permission_name]='ALTER ANY LOGIN'
                        OR
                        spr.[name]='serveradmin'  AND pb.[permission_name] IN ('ALTER ANY ENDPOINT', 'ALTER RESOURCES','ALTER SERVER STATE', 'ALTER SETTINGS','SHUTDOWN', 'VIEW SERVER STATE')
                        OR
                        spr.[name]='setupadmin' AND pb.[permission_name]='ALTER ANY LINKED SERVER'
                    WHERE spr.[type]='R'
                    ;"

        $DBPermsql = "SELECT SERVERPROPERTY('MachineName') AS ComputerName,
                    ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                    SERVERPROPERTY('ServerName') AS SqlInstance
                    , [Database] = DB_NAME()
                    , [PermState] = state_desc
                    , [PermissionName] = permission_name
                    , [SecurableType] = COALESCE(o.type_desc,dp.class_desc)
                    , [Securable] = CASE    WHEN class = 0 THEN DB_NAME()
                                            WHEN class = 1 THEN ISNULL(s.name + '.','')+OBJECT_NAME(major_id)
                                            WHEN class = 3 THEN SCHEMA_NAME(major_id)
                                            WHEN class = 6 THEN SCHEMA_NAME(t.schema_id)+'.' + t.name
                                            END
                    , [Grantee] = USER_NAME(grantee_principal_id)
                    , [GranteeType] = pr.type_desc
                    , [RevokeStatement] = CASE WHEN class = 3 THEN 'REVOKE ' + permission_name + ' ON Schema::[' + ISNULL(SCHEMA_NAME(dp.major_id) COLLATE DATABASE_DEFAULT,'') + '] FROM [' + USER_NAME(grantee_principal_id) +']'
                                            ELSE 'REVOKE ' + permission_name + ' ON [' + ISNULL(SCHEMA_NAME(o.schema_id) COLLATE DATABASE_DEFAULT+'].[','')+OBJECT_NAME(major_id)+ '] FROM [' + USER_NAME(grantee_principal_id) +']'
                                            END
                    , [GrantStatement] = CASE WHEN class = 3 THEN state_desc + ' ' + permission_name + ' ON Schema::[' + ISNULL(SCHEMA_NAME(dp.major_id) COLLATE DATABASE_DEFAULT,'') + '] TO [' + USER_NAME(grantee_principal_id) + ']'
                                            ELSE state_desc + ' ' + permission_name + ' ON [' + ISNULL(SCHEMA_NAME(o.schema_id) COLLATE DATABASE_DEFAULT+'].[','')+OBJECT_NAME(major_id)+ '] TO [' + USER_NAME(grantee_principal_id) + ']'
                                            END
                        + CASE WHEN dp.state_desc = 'GRANT_WITH_GRANT_OPTION' THEN ' WITH GRANT OPTION' ELSE '' END
                    FROM sys.database_permissions dp
                    JOIN sys.database_principals pr ON pr.principal_id = dp.grantee_principal_id
                    LEFT OUTER JOIN sys.all_objects o ON (o.object_id = dp.major_id AND dp.class NOT IN (0, 3))
                    LEFT OUTER JOIN sys.schemas s ON s.schema_id = o.schema_id
                    LEFT OUTER JOIN sys.types t on t.user_type_id = dp.major_id

                $ExcludeSystemObjectssql

                UNION ALL
                SELECT    SERVERPROPERTY('MachineName') AS ComputerName
                        , ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName
                        , SERVERPROPERTY('ServerName') AS SqlInstance
                        , [database] = DB_NAME()
                        , [PermState] = ''
                        , [PermissionName] = p.[permission_name]
                        , [SecurableType] = p.class_desc
                        , [Securable] = DB_NAME()
                        , [Grantee] = dp.name
                        , [GranteeType] = dp.type_desc
                        , [revokestatement] = ''
                        , [grantstatement] = ''
                FROM sys.database_principals AS dp
                INNER JOIN sys.fn_builtin_permissions('DATABASE') AS p ON
                    dp.[name]='db_accessadmin' AND p.[permission_name] IN ('ALTER ANY USER', 'CREATE SCHEMA')
                    OR
                    dp.[name]='db_backupoperator' AND p.[permission_name] IN ('BACKUP DATABASE', 'BACKUP LOG', 'CHECKPOINT')
                    OR
                    dp.[name] IN ('db_datareader', 'db_denydatareader') AND p.[permission_name]='SELECT'
                    OR
                    dp.[name] IN ('db_datawriter', 'db_denydatawriter') AND p.[permission_name] IN ('INSERT', 'DELETE', 'UPDATE')
                    OR
                    dp.[name]='db_ddladmin' AND
                    p.[permission_name] IN ('ALTER ANY ASSEMBLY', 'ALTER ANY ASYMMETRIC KEY',
                                            'ALTER ANY CERTIFICATE', 'ALTER ANY CONTRACT',
                                            'ALTER ANY DATABASE DDL TRIGGER', 'ALTER ANY DATABASE EVENT',
                                            'NOTIFICATION', 'ALTER ANY DATASPACE', 'ALTER ANY FULLTEXT CATALOG',
                                            'ALTER ANY MESSAGE TYPE', 'ALTER ANY REMOTE SERVICE BINDING',
                                            'ALTER ANY ROUTE', 'ALTER ANY SCHEMA', 'ALTER ANY SERVICE',
                                            'ALTER ANY SYMMETRIC KEY', 'CHECKPOINT', 'CREATE AGGREGATE',
                                            'CREATE DEFAULT', 'CREATE FUNCTION', 'CREATE PROCEDURE',
                                            'CREATE QUEUE', 'CREATE RULE', 'CREATE SYNONYM', 'CREATE TABLE',
                                            'CREATE TYPE', 'CREATE VIEW', 'CREATE XML SCHEMA COLLECTION',
                                            'REFERENCES')
                    OR
                    dp.[name]='db_owner' AND p.[permission_name]='CONTROL'
                    OR
                    dp.[name]='db_securityadmin' AND p.[permission_name] IN ('ALTER ANY APPLICATION ROLE', 'ALTER ANY ROLE', 'CREATE SCHEMA', 'VIEW DEFINITION')

                WHERE dp.[type]='R'
                    AND dp.is_fixed_role=1
                UNION ALL -- include the dbo user
                SELECT
                    [ComputerName]        = SERVERPROPERTY('MachineName')
                ,    [InstanceName]        = ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER')
                ,    [SqlInstance]        = SERVERPROPERTY('ServerName')
                ,    [database]            = DB_NAME()
                ,    [PermState]            = ''
                ,    [PermissionName]    = 'CONTROL'
                ,    [SecurableType]        = 'DATABASE'
                ,    [Securable]            = DB_NAME()
                ,    [Grantee]            = SUSER_SNAME(owner_sid)
                ,    [GranteeType]        = 'DATABASE OWNER (dbo user)'
                ,    [revokestatement]    = ''
                ,    [grantstatement]    = ''
                FROM
                    sys.databases
                WHERE
                    name = DB_NAME()
                UNION ALL -- include the users with the db_owner role
                SELECT
                    [ComputerName]        = SERVERPROPERTY('MachineName')
                ,    [InstanceName]        = ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER')
                ,    [SqlInstance]        = SERVERPROPERTY('ServerName')
                ,    [database]            = DB_NAME()
                ,    [PermState]            = ''
                ,    [PermissionName]    = 'CONTROL'
                ,    [SecurableType]        = 'DATABASE'
                ,    [Securable]            = DB_NAME()
                ,    [Grantee]            = databaseUser.name
                ,    [GranteeType]        = 'DATABASE OWNER (db_owner role)'
                ,    [revokestatement]    = ''
                ,    [grantstatement]    = ''
                FROM
                (
                    SELECT
                        member_principal_id
                    FROM
                        sys.database_role_members AS roleMembers
                    INNER JOIN
                        sys.database_principals AS roleFilter
                            ON roleMembers.role_principal_id = roleFilter.principal_id
                            AND roleFilter.name = 'db_owner'
                ) dbOwner
                INNER JOIN
                    sys.database_principals AS databaseUser
                        ON dbOwner.member_principal_id = databaseUser.principal_id
                WHERE
                    databaseUser.name <> 'dbo'
                UNION ALL -- include the schema owners
                SELECT
                    [ComputerName]        = SERVERPROPERTY('MachineName')
                ,    [InstanceName]        = ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER')
                ,    [SqlInstance]        = SERVERPROPERTY('ServerName')
                ,    [database]            = DB_NAME()
                ,    [PermState]            = ''
                ,    [PermissionName]    = 'CONTROL'
                ,    [SecurableType]        = 'SCHEMA'
                ,    [Securable]            = name
                ,    [Grantee]            = USER_NAME(principal_id)
                ,    [GranteeType]        = 'SCHEMA OWNER'
                ,    [revokestatement]    = ''
                ,    [grantstatement]    = ''
                FROM
                    sys.schemas
                WHERE
                    name NOT IN (SELECT name FROM sys.database_principals WHERE type = 'R')
                AND name NOT IN ('dbo', 'guest', 'INFORMATION_SCHEMA', 'sys')
                ;"
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($IncludeServerLevel) {
                Write-Message -Level Debug -Message "T-SQL: $ServPermsql"
                $server.Query($ServPermsql)
            }

            $dbs = $server.Databases

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $db on $instance."

                if ($db.IsAccessible -eq $false) {
                    Write-Message -Level Warning -Message "The database $db is not accessible. Skipping database."
                    Continue
                }

                Write-Message -Level Debug -Message "T-SQL: $DBPermsql"
                try {
                    $db.ExecuteWithResults($DBPermsql).Tables.Rows
                } catch {
                    Stop-Function -Message "Failure executing against $($db.Name) on $instance" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}