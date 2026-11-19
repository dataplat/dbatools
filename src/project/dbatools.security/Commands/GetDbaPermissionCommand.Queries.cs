#nullable enable

namespace Dataplat.Dbatools.Commands;

public sealed partial class GetDbaPermissionCommand
{
    private const string ServerPermissionSql = @"SELECT SERVERPROPERTY('MachineName') AS ComputerName,
                       ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                       SERVERPROPERTY('ServerName') AS SqlInstance
                        , [Database] = ''
                        , [PermState] = state_desc
                        , [PermissionName] = permission_name
                        , [SecurableType] = sp.class_desc
                        , [Securable] = CASE
                            WHEN class = 100 THEN @@SERVERNAME
                            WHEN class = 101 THEN targetPrincipal.name
                            WHEN class = 105 THEN (SELECT TOP (1) name FROM sys.endpoints WHERE endpoint_id = major_id)
                            WHEN class = 108 THEN (SELECT TOP (1) ag.name FROM sys.availability_replicas ar JOIN sys.availability_groups ag ON ar.group_id = ag.group_id WHERE ar.replica_metadata_id = major_id)
                            ELSE CONVERT(NVARCHAR, major_id)
                            END
                        , [Grantee] = SUSER_NAME(grantee_principal_id)
                        , [GranteeType] = pr.type_desc
                        , [revokeStatement] = 'REVOKE ' + permission_name + permissionScope.Clause + ' FROM ' + QUOTENAME(SUSER_NAME(grantee_principal_id))
                        , [grantStatement] = CASE WHEN sp.state_desc = 'GRANT_WITH_GRANT_OPTION' THEN 'GRANT' ELSE sp.state_desc END
                            + ' ' + permission_name + permissionScope.Clause
                            + CASE WHEN sp.state_desc = 'REVOKE' THEN ' FROM ' ELSE ' TO ' END + QUOTENAME(SUSER_NAME(grantee_principal_id))
                            + CASE WHEN sp.state_desc = 'GRANT_WITH_GRANT_OPTION' THEN ' WITH GRANT OPTION' ELSE '' END
                    FROM sys.server_permissions sp
                        JOIN sys.server_principals pr ON pr.principal_id = sp.grantee_principal_id
                        LEFT OUTER JOIN sys.server_principals targetPrincipal ON (sp.class = 101 AND targetPrincipal.principal_id = sp.major_id)
                        CROSS APPLY (SELECT CASE
                            WHEN sp.class = 101 THEN ' ON ' + CASE WHEN targetPrincipal.type = 'R' THEN 'SERVER ROLE::' ELSE 'LOGIN::' END + QUOTENAME(targetPrincipal.name)
                            WHEN sp.class = 105 THEN ' ON ENDPOINT::' + (SELECT TOP (1) QUOTENAME(name) FROM sys.endpoints WHERE endpoint_id = sp.major_id)
                            WHEN sp.class = 108 THEN ' ON AVAILABILITY GROUP::' + (SELECT TOP (1) QUOTENAME(ag.name) FROM sys.availability_replicas ar JOIN sys.availability_groups ag ON ar.group_id = ag.group_id WHERE ar.replica_metadata_id = sp.major_id)
                            ELSE ' ' + COALESCE(QUOTENAME(OBJECT_NAME(sp.major_id)), '')
                            END COLLATE DATABASE_DEFAULT AS Clause) permissionScope

                    {SystemFilter}

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
                    ;";

    private const string DatabasePermissionSql = @"SELECT SERVERPROPERTY('MachineName') AS ComputerName,
                    ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                    SERVERPROPERTY('ServerName') AS SqlInstance
                    , [Database] = DB_NAME()
                    , [PermState] = state_desc
                    , [PermissionName] = permission_name
                    , [SecurableType] = COALESCE(o.type_desc,dp.class_desc)
                    , [Securable] = CASE    WHEN class = 0 THEN DB_NAME()
                                            WHEN class = 1 THEN ISNULL(s.name + '.','')+OBJECT_NAME(major_id)
                                            WHEN class = 3 THEN SCHEMA_NAME(major_id)
                                            WHEN class = 4 THEN targetPrincipal.name
                                            WHEN class = 5 THEN (SELECT name FROM sys.assemblies WHERE assembly_id = dp.major_id)
                                            WHEN class = 6 THEN SCHEMA_NAME(t.schema_id)+'.' + t.name
                                            WHEN class = 23 THEN (SELECT name FROM sys.fulltext_catalogs WHERE fulltext_catalog_id = dp.major_id)
                                            WHEN class = 24 THEN (SELECT name FROM sys.symmetric_keys WHERE symmetric_key_id = dp.major_id)
                                            WHEN class = 25 THEN (SELECT name FROM sys.certificates WHERE certificate_id = dp.major_id)
                                            WHEN class = 26 THEN (SELECT name FROM sys.asymmetric_keys WHERE asymmetric_key_id = dp.major_id)
                                            END
                    , [Grantee] = USER_NAME(grantee_principal_id)
                    , [GranteeType] = pr.type_desc
                    , [RevokeStatement] = 'REVOKE ' + permission_name
                        + CASE WHEN class = 0 THEN ''
                            WHEN class = 3 THEN ' ON Schema::' + QUOTENAME(ISNULL(SCHEMA_NAME(dp.major_id) COLLATE DATABASE_DEFAULT,''))
                            WHEN class = 4 THEN ' ON ' + CASE targetPrincipal.type WHEN 'R' THEN 'ROLE::' WHEN 'A' THEN 'APPLICATION ROLE::' ELSE 'USER::' END + QUOTENAME(targetPrincipal.name)
                            WHEN class = 5 THEN ' ON ASSEMBLY::' + (SELECT QUOTENAME(name) FROM sys.assemblies WHERE assembly_id = dp.major_id)
                            WHEN class = 6 THEN ' ON TYPE::' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + '.' + QUOTENAME(t.name)
                            WHEN class = 23 THEN ' ON FULLTEXT CATALOG::' + (SELECT QUOTENAME(name) FROM sys.fulltext_catalogs WHERE fulltext_catalog_id = dp.major_id)
                            WHEN class = 24 THEN ' ON SYMMETRIC KEY::' + (SELECT QUOTENAME(name) FROM sys.symmetric_keys WHERE symmetric_key_id = dp.major_id)
                            WHEN class = 25 THEN ' ON CERTIFICATE::' + (SELECT QUOTENAME(name) FROM sys.certificates WHERE certificate_id = dp.major_id)
                            WHEN class = 26 THEN ' ON ASYMMETRIC KEY::' + (SELECT QUOTENAME(name) FROM sys.asymmetric_keys WHERE asymmetric_key_id = dp.major_id)
                            ELSE ' ON ' + ISNULL(QUOTENAME(SCHEMA_NAME(o.schema_id) COLLATE DATABASE_DEFAULT)+'.','') + QUOTENAME(OBJECT_NAME(major_id)) END
                        + CASE WHEN dp.class = 1 AND dp.minor_id > 0 THEN ' (' + QUOTENAME(COL_NAME(dp.major_id, dp.minor_id)) + ')' ELSE '' END
                        + ' FROM ' + QUOTENAME(USER_NAME(grantee_principal_id))
                    , [GrantStatement] = CASE WHEN dp.state_desc = 'GRANT_WITH_GRANT_OPTION' THEN 'GRANT' ELSE dp.state_desc END
                        + ' ' + permission_name
                        + CASE WHEN class = 0 THEN ''
                            WHEN class = 3 THEN ' ON Schema::' + QUOTENAME(ISNULL(SCHEMA_NAME(dp.major_id) COLLATE DATABASE_DEFAULT,''))
                            WHEN class = 4 THEN ' ON ' + CASE targetPrincipal.type WHEN 'R' THEN 'ROLE::' WHEN 'A' THEN 'APPLICATION ROLE::' ELSE 'USER::' END + QUOTENAME(targetPrincipal.name)
                            WHEN class = 5 THEN ' ON ASSEMBLY::' + (SELECT QUOTENAME(name) FROM sys.assemblies WHERE assembly_id = dp.major_id)
                            WHEN class = 6 THEN ' ON TYPE::' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + '.' + QUOTENAME(t.name)
                            WHEN class = 23 THEN ' ON FULLTEXT CATALOG::' + (SELECT QUOTENAME(name) FROM sys.fulltext_catalogs WHERE fulltext_catalog_id = dp.major_id)
                            WHEN class = 24 THEN ' ON SYMMETRIC KEY::' + (SELECT QUOTENAME(name) FROM sys.symmetric_keys WHERE symmetric_key_id = dp.major_id)
                            WHEN class = 25 THEN ' ON CERTIFICATE::' + (SELECT QUOTENAME(name) FROM sys.certificates WHERE certificate_id = dp.major_id)
                            WHEN class = 26 THEN ' ON ASYMMETRIC KEY::' + (SELECT QUOTENAME(name) FROM sys.asymmetric_keys WHERE asymmetric_key_id = dp.major_id)
                            ELSE ' ON ' + ISNULL(QUOTENAME(SCHEMA_NAME(o.schema_id) COLLATE DATABASE_DEFAULT)+'.','') + QUOTENAME(OBJECT_NAME(major_id)) END
                        + CASE WHEN dp.class = 1 AND dp.minor_id > 0 THEN ' (' + QUOTENAME(COL_NAME(dp.major_id, dp.minor_id)) + ')' ELSE '' END
                        + CASE WHEN dp.state_desc = 'REVOKE' THEN ' FROM ' ELSE ' TO ' END + QUOTENAME(USER_NAME(grantee_principal_id))
                        + CASE WHEN dp.state_desc = 'GRANT_WITH_GRANT_OPTION' THEN ' WITH GRANT OPTION' ELSE '' END
                    FROM sys.database_permissions dp
                    JOIN sys.database_principals pr ON pr.principal_id = dp.grantee_principal_id
                    LEFT OUTER JOIN sys.all_objects o ON (o.object_id = dp.major_id AND dp.class = 1)
                    LEFT OUTER JOIN sys.schemas s ON s.schema_id = o.schema_id
                    LEFT OUTER JOIN sys.database_principals targetPrincipal ON (targetPrincipal.principal_id = dp.major_id AND dp.class = 4)
                    LEFT OUTER JOIN sys.types t ON (t.user_type_id = dp.major_id AND dp.class = 6)

                {SystemFilter}

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
                ;";
}
