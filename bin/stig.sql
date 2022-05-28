USE tempdb;
                GO

                IF EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'STIG')
                BEGIN
	                DROP SCHEMA STIG
                END
                GO

                CREATE SCHEMA STIG
                GO

            /*
            Objects defined in this file:
            VIEW STIG.database_role_members
                Based on the system view sys.database_role_members, this presents the list of
                database role memberships using roles' and users' names rather than their id numbers.
                Although membership in database roles is hierarchical, this view lists only the direct memberships.
            FUNCTION STIG.database_roles_of(@database_principal sysname)
                Given the name of a database principal (user or role), this table-valued function returns
                a list of all the roles it belongs to, both directly and indirectly.
            FUNCTION STIG.members_of_db_role(@database_role sysname)
                Given the name of a database role, this table-valued function returns
                a list of all the roles and users that belong to it, both directly and indirectly.
            VIEW STIG.database_permissions
                Based on the system view sys.database_permissions, this provides additional, descriptive material.
                The list includes only those permissions explicitly granted (or denied) to a database user or role;
                it does not include permissions that are implicit or inherited from a higher-level role.
                Securable items that exist but have no explicit permissions assigned are included in the
                list, with the columns that describe the grantor and grantee left null.
            FUNCTION STIG.database_effective_permissions(@Grantee sysname)
                Given the name of a database principal (user or role), this table-valued function
                returns information about permissions granted (or denied) to that user or database role,
                either directly or inherited from a higher-level role.
            VIEW STIG.server_role_members
                Based on the system view sys.server_role_members, this presents the list of
                server role memberships using roles' and users' names rather than their id numbers.
                Although membership in server roles is hierarchical, this view lists only the direct memberships.
            FUNCTION STIG.server_roles_of(@server_principal sysname)
                Given the name of a server principal (login or role), this table-valued function returns
                a list of all the roles it belongs to, both directly and indirectly.
            FUNCTION STIG.members_of_server_role(@server_role sysname)
                Given the name of a server role, this table-valued function returns
                a list of all the roles and logins that belong to it, both directly and indirectly.
            VIEW STIG.server_permissions
                Based on the system view sys.server_permissions, this provides additional, descriptive material.
                The list includes only those permissions explicitly granted (or denied) to a server login or role;
                it does not include permissions that are implicit or inherited from a higher-level role.
                Securable items that exist but have no explicit permissions assigned are included in the
                list, with columns describing the grantor and grantee left null.
            FUNCTION STIG.server_effective_permissions(@Grantee sysname)
                Given the name of a server principal (login or server role), this table-valued function
                returns information about permissions granted (or denied) to that login or role,
                either directly or inherited from a higher-level role.
            */


            BEGIN TRY DROP VIEW STIG.database_role_members END TRY BEGIN CATCH END CATCH;
            GO

            CREATE VIEW STIG.database_role_members
            --  Based on the system view sys.database_role_members, this presents the list of
            --  database role memberships using roles' and users' names rather than their id numbers.
            --  Although membership in database roles is hierarchical, this view lists only the direct memberships.
            AS SELECT
                R.name  AS [Role],
                M.name  AS [Member]
            FROM
                [<TARGETDB>].sys.database_role_members X
                INNER JOIN [<TARGETDB>].sys.database_principals R ON R.principal_id = X.role_principal_id
                INNER JOIN [<TARGETDB>].sys.database_principals M ON M.principal_id = X.member_principal_id
            ;
            GO


            BEGIN TRY DROP FUNCTION STIG.database_roles_of END TRY BEGIN CATCH END CATCH;
            GO

            CREATE FUNCTION STIG.database_roles_of(@database_principal sysname)
            --  Membership in database roles is hierarchical.
            --  Given the name of a database principal (user or role), this table-valued function returns
            --  a list of all the roles it belongs to, both directly and indirectly.
                RETURNS @T TABLE
                    (
                    [Member]            sysname,
                    [Role]              sysname,
                    [via Member]        sysname,
                    [Membership Chain]  nvarchar(max)
                    )
            AS BEGIN;
                WITH Membership AS
                (
                SELECT
                    [Member] AS [Member],
                    [Role],
                    [Member] AS [via Member],
                    CAST([Member] AS varchar(max)) + ' < ' + CAST([Role] AS varchar(max)) AS [Membership Chain]
                FROM
                    STIG.database_role_members
                WHERE
                    [Member] = @database_principal

                UNION ALL

                SELECT
                    X.[Member],
                    R.[Role],
                    R.[Member] AS [via Member],
                    X.[Membership Chain] + ' < ' + CAST(R.[Role] AS varchar(max)) AS [Membership Chain]
                FROM
                    Membership X
                    INNER JOIN STIG.database_role_members R ON X.[Role] = R.[Member]
                )
                INSERT INTO @T SELECT * FROM Membership;
            ExitFunction:
                RETURN;
            END;
            GO


            BEGIN TRY DROP FUNCTION STIG.members_of_db_role END TRY BEGIN CATCH END CATCH;
            GO

            CREATE FUNCTION STIG.members_of_db_role(@database_role sysname)
            --  Membership in database roles is hierarchical.
            --  Given the name of a database role, this table-valued function returns
            --  a list of all the roles and users that belong to it, both directly and indirectly.
                RETURNS @T TABLE
                    (
                    [Role]              sysname,
                    [Member]            sysname,
                    [via Role]          sysname,
                    [Membership Chain]  nvarchar(max)
                    )
            AS BEGIN;
                WITH Membership AS
                (
                SELECT
                    [Role] AS [Role],
                    [Member],
                    [Role] AS [via Role],
                    CAST([Role] AS varchar(max)) + ' > ' + CAST([Member] AS varchar(max)) AS [Membership Chain]
                FROM
                    STIG.database_role_members
                WHERE
                    [Role] = @database_role

                UNION ALL

                SELECT
                    X.[Role] AS [Role],
                    R.[Member],
                    R.[Role] AS [via Role],
                    X.[Membership Chain] + ' > ' + CAST(R.[Member] AS varchar(max)) AS [Membership Chain]
                FROM
                    Membership X
                    INNER JOIN STIG.database_role_members R ON X.[Member] = R.[Role]
                )
                INSERT INTO @T SELECT * FROM Membership;
            ExitFunction:
                RETURN;
            END;
            GO




            BEGIN TRY DROP VIEW STIG.database_permissions END TRY BEGIN CATCH END CATCH;
            GO

            CREATE VIEW STIG.database_permissions
            --  Based on the system view sys.database_permissions, this provides additional, descriptive material.
            --  The list includes only those permissions explicitly granted (or denied) to a database user or role;
            --  it does not include permissions that are implicit or inherited from a higher-level role.
            --  Securable items that exist but have no explicit permissions assigned are included in the
            --  list, with the columns that describe the grantor and grantee left null.
            AS SELECT DISTINCT
                @@SERVERNAME        AS [Current Server],
                @@SERVICENAME       AS [Current Instance],
                '<QUOTETARGETDB>'   AS [Current DB],
                SYSTEM_USER         AS [Current Login],
                USER                AS [Current User],

                CASE
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'OBJECT_OR_COLUMN'             THEN CASE WHEN DP.minor_id > 0 THEN 'COLUMN' ELSE OB.type_desc END
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NOT NULL                      THEN DP.class_desc
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND DB.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'DATABASE'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND OB.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'OBJECT_OR_COLUMN'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND SC.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'SCHEMA'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND PR.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'DATABASE_PRINCIPAL'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND AY.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'ASSEMBLY'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND TP.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'TYPE'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND XS.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'XML_SCHEMA_COLLECTION'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND MT.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'MESSAGE_TYPE'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND VC.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'SERVICE_CONTRACT'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND SV.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'SERVICE'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND RS.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'REMOTE_SERVICE_BINDING'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND RT.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'ROUTE'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND FT.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'FULLTEXT_CATALOG'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND SK.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'SYMMETRIC_KEY'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND AK.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'ASYMMETRIC_KEY'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND CT.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'CERTIFICATE'
                    ELSE NULL
                END                 AS [Securable Type or Class],
                CASE
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'DATABASE'                     THEN PS.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'OBJECT_OR_COLUMN'             THEN schema_name(OB.schema_id)
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'SCHEMA'                       THEN P3.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'DATABASE_PRINCIPAL'           THEN coalesce(PR.default_schema_name, PE.name)
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'ASSEMBLY'                     THEN P4.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'TYPE'                         THEN schema_name(TP.schema_id)
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'XML_SCHEMA_COLLECTION'        THEN schema_name(XS.schema_id)
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'MESSAGE_TYPE'                 THEN P5.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'SERVICE_CONTRACT'             THEN P6.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'SERVICE'                      THEN P7.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'REMOTE_SERVICE_BINDING'       THEN P8.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'ROUTE'                        THEN P9.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'FULLTEXT_CATALOG'             THEN PA.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'SYMMETRIC_KEY'                THEN PB.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'ASYMMETRIC_KEY'               THEN PC.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'CERTIFICATE'                  THEN PD.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND DB.name IS NOT NULL  THEN PS.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND OB.name IS NOT NULL  THEN schema_name(OB.schema_id)
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND SC.name IS NOT NULL  THEN P3.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND PR.name IS NOT NULL  THEN PR.default_schema_name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND AY.name IS NOT NULL  THEN P4.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND TP.name IS NOT NULL  THEN schema_name(TP.schema_id)
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND XS.name IS NOT NULL  THEN schema_name(XS.schema_id)
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND MT.name IS NOT NULL  THEN P5.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND VC.name IS NOT NULL  THEN P6.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND SV.name IS NOT NULL  THEN P7.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND RS.name IS NOT NULL  THEN P8.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND RT.name IS NOT NULL  THEN P9.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND FT.name IS NOT NULL  THEN PA.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND SK.name IS NOT NULL  THEN PB.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND AK.name IS NOT NULL  THEN PC.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND CT.name IS NOT NULL  THEN PD.name COLLATE DATABASE_DEFAULT
                    ELSE NULL
                END                 AS [Schema/Owner],
                CASE
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'DATABASE'                     THEN DB.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'OBJECT_OR_COLUMN'             THEN OB.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'SCHEMA'                       THEN SC.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'DATABASE_PRINCIPAL'           THEN PR.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'ASSEMBLY'                     THEN AY.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'TYPE'                         THEN TP.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'XML_SCHEMA_COLLECTION'        THEN XS.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'MESSAGE_TYPE'                 THEN cast(MT.name as sql_variant)
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'SERVICE_CONTRACT'             THEN cast(VC.name as sql_variant)
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'SERVICE'                      THEN cast(SV.name as sql_variant)
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'REMOTE_SERVICE_BINDING'       THEN RS.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'ROUTE'                        THEN RT.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'FULLTEXT_CATALOG'             THEN FT.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'SYMMETRIC_KEY'                THEN SK.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'ASYMMETRIC_KEY'               THEN AK.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'CERTIFICATE'                  THEN CT.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND DB.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN DB.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND OB.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN OB.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND SC.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN SC.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND PR.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN PR.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND AY.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN AY.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND TP.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN TP.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND XS.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN XS.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND MT.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN cast(MT.name as sql_variant)
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND VC.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN cast(VC.name as sql_variant)
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND SV.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN cast(SV.name as sql_variant)
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND RS.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN RS.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND RT.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN RT.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND FT.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN FT.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND SK.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN SK.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND AK.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN AK.name COLLATE DATABASE_DEFAULT
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND CT.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN CT.name COLLATE DATABASE_DEFAULT
                    ELSE NULL
                END                 AS [Securable],
                CM.name             AS [Column],
                P1.type_desc        AS [Grantee Type],
                P1.name             AS [Grantee],
                DP.permission_name  AS [Permission],
                DP.state_desc       AS [State],
                P2.name             AS [Grantor],
                P2.type_desc        AS [Grantor Type],
                CASE
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'DATABASE'                     THEN 'sys.databases'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'OBJECT_OR_COLUMN'             THEN 'sys.all_objects'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'SCHEMA'                       THEN 'sys.schemas'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'DATABASE_PRINCIPAL'           THEN 'sys.database_principals'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'ASSEMBLY'                     THEN 'sys.assemblies'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'TYPE'                         THEN 'sys.types'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'XML_SCHEMA_COLLECTION'        THEN 'sys.xml_schema_collections'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'MESSAGE_TYPE'                 THEN 'sys.service_message_types'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'SERVICE_CONTRACT'             THEN 'sys.database_principals'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'SERVICE'                      THEN 'sys.services'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'REMOTE_SERVICE_BINDING'       THEN 'sys.remote_service_bindings'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'ROUTE'                        THEN 'sys.routes'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'FULLTEXT_CATALOG'             THEN 'sys.database_principals'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'SYMMETRIC_KEY'                THEN 'sys.symmetric_keys'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'ASYMMETRIC_KEY'               THEN 'sys.asymmetric_keys'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT = 'CERTIFICATE'                  THEN 'sys.certificates'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND DB.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'sys.databases'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND OB.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'sys.all_objects'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND SC.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'sys.schemas'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND PR.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'sys.database_principals'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND AY.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'sys.assemblies'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND TP.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'sys.types'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND XS.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'sys.xml_schema_collections'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND MT.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'sys.service_message_types'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND VC.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'sys.database_principals'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND SV.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'sys.services'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND RS.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'sys.remote_service_bindings'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND RT.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'sys.routes'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND FT.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'sys.database_principals'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND SK.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'sys.symmetric_keys'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND AK.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'sys.asymmetric_keys'
                    WHEN DP.class_desc COLLATE DATABASE_DEFAULT IS NULL AND CT.name COLLATE DATABASE_DEFAULT IS NOT NULL  THEN 'sys.certificates'
                    ELSE '<QUOTETARGETDB>.sys.database_permissions'
                END                 AS [Source View]
            FROM
                [<TARGETDB>].sys.database_permissions DP
                LEFT OUTER JOIN [<TARGETDB>].sys.database_principals P1
                    ON  P1.principal_id = DP.grantee_principal_id
                LEFT OUTER JOIN [<TARGETDB>].sys.database_principals P2
                    ON  P2.principal_id = DP.grantor_principal_id

                FULL OUTER JOIN [<TARGETDB>].sys.databases DB
                    ON  DB.database_id = db_id(db_name(DP.major_id))
                    AND DP.class_desc = 'DATABASE'
                LEFT OUTER JOIN [<TARGETDB>].sys.server_principals PS
                    ON  PS.sid = DB.owner_sid

                FULL OUTER JOIN [<TARGETDB>].sys.all_objects OB
                    ON  DP.major_id   = OB.[object_id]
                    AND DP.class_desc = 'OBJECT_OR_COLUMN'
                LEFT OUTER JOIN [<TARGETDB>].sys.all_columns CM
                    ON  CM.[object_id] = DP.major_id
                    AND CM.[column_id] = DP.minor_id

                FULL OUTER JOIN [<TARGETDB>].sys.schemas SC
                    ON  DP.major_id   = SC.[schema_id]
                    AND DP.class_desc = 'SCHEMA'
                LEFT OUTER JOIN [<TARGETDB>].sys.database_principals P3
                    ON  P3.principal_id = SC.principal_id

                FULL OUTER JOIN [<TARGETDB>].sys.database_principals PR
                    ON  DP.major_id   = PR.principal_id
                    AND DP.class_desc = 'DATABASE_PRINCIPAL'
                LEFT OUTER JOIN [<TARGETDB>].sys.database_principals PE
                    ON  PE.principal_id = PR.owning_principal_id

                FULL OUTER JOIN [<TARGETDB>].sys.assemblies AY
                    ON  DP.major_id   = AY.assembly_id
                    AND DP.class_desc = 'ASSEMBLY'
                LEFT OUTER JOIN [<TARGETDB>].sys.database_principals P4
                    ON  P4.principal_id = AY.principal_id

                FULL OUTER JOIN [<TARGETDB>].sys.types TP
                    ON  DP.major_id   = TP.user_type_id
                    AND DP.class_desc = 'TYPE'

                FULL OUTER JOIN [<TARGETDB>].sys.xml_schema_collections XS
                    ON  DP.major_id   = XS.xml_collection_id
                    AND DP.class_desc = 'XML_SCHEMA_COLLECTION'

                FULL OUTER JOIN [<TARGETDB>].sys.service_message_types MT
                    ON  DP.major_id   = MT.message_type_id
                    AND DP.class_desc = 'MESSAGE_TYPE'
                LEFT OUTER JOIN [<TARGETDB>].sys.database_principals P5
                    ON  P5.principal_id = MT.principal_id

                FULL OUTER JOIN [<TARGETDB>].sys.service_contracts VC
                    ON  DP.major_id   = VC.service_contract_id
                    AND DP.class_desc = 'SERVICE_CONTRACT'
                LEFT OUTER JOIN [<TARGETDB>].sys.database_principals P6
                    ON  P6.principal_id = VC.principal_id

                FULL OUTER JOIN [<TARGETDB>].sys.services SV
                    ON  DP.major_id   = SV.service_id
                    AND DP.class_desc = 'SERVICE'
                LEFT OUTER JOIN [<TARGETDB>].sys.database_principals P7
                    ON  P7.principal_id = SV.principal_id

                FULL OUTER JOIN [<TARGETDB>].sys.remote_service_bindings RS
                    ON  DP.major_id   = RS.remote_service_binding_id
                    AND DP.class_desc = 'REMOTE_SERVICE_BINDING'
                LEFT OUTER JOIN [<TARGETDB>].sys.database_principals P8
                    ON  P8.principal_id = RS.principal_id

                FULL OUTER JOIN [<TARGETDB>].sys.routes RT
                    ON  DP.major_id   = RT.route_id
                    AND DP.class_desc = 'ROUTE'
                LEFT OUTER JOIN [<TARGETDB>].sys.database_principals P9
                    ON  P9.principal_id = RT.principal_id

                FULL OUTER JOIN [<TARGETDB>].sys.fulltext_catalogs FT
                    ON  DP.major_id   = FT.fulltext_catalog_id
                    AND DP.class_desc = 'FULLTEXT_CATALOG'
                LEFT OUTER JOIN [<TARGETDB>].sys.database_principals PA
                    ON  PA.principal_id = FT.principal_id

                FULL OUTER JOIN [<TARGETDB>].sys.symmetric_keys SK
                    ON  DP.major_id   = SK.symmetric_key_id
                    AND DP.class_desc = 'SYMMETRIC_KEY'
                LEFT OUTER JOIN [<TARGETDB>].sys.database_principals PB
                    ON  PB.principal_id = SK.principal_id

                FULL OUTER JOIN [<TARGETDB>].sys.asymmetric_keys AK
                    ON  DP.major_id   = AK.asymmetric_key_id
                    AND DP.class_desc = 'ASYMMETRIC_KEY'
                LEFT OUTER JOIN [<TARGETDB>].sys.database_principals PC
                    ON  PC.principal_id = AK.principal_id

                FULL OUTER JOIN [<TARGETDB>].sys.certificates CT
                    ON  DP.major_id   = CT.certificate_id
                    AND DP.class_desc = 'CERTIFICATE'
                LEFT OUTER JOIN [<TARGETDB>].sys.database_principals PD
                    ON  PD.principal_id = CT.principal_id
            ;
            GO



            BEGIN TRY DROP FUNCTION STIG.database_effective_permissions END TRY BEGIN CATCH END CATCH;
            GO

            CREATE FUNCTION STIG.database_effective_permissions(@Grantee sysname)
            --  Given the name of a database principal (user or role), this table-valued function
            --  returns information about permissions granted (or denied) to that user or database role,
            --  either directly or inherited from a higher-level role.
                RETURNS @T TABLE
                    (
                    [Current Server]            sysname         null,
                    [Current Instance]          sysname         null,
                    [Current DB]                sysname         null,
                    [Current Login]             sysname         null,
                    [Current User]              sysname         null,
                    [Securable Type or Class]   nvarchar(60)    null,
                    [Schema/Owner]              sysname         null,
                    [Securable]                 sql_variant     null,
                    [Column]                    sysname         null,
                    [Effective Grantee]         sysname         null,
                    [Membership Chain]          nvarchar(max)   null,
                    [Direct Grantee]            sysname         null,
                    [Direct Grantee Type]       nvarchar(60)    null,
                    [Permission]                sysname         null,
                    [State]                     nvarchar(60)    null,
                    [Grantor]                   sysname         null,
                    [Grantor Type]              nvarchar(60)    null,
                    [source view]               sysname         null
                    )
            AS BEGIN;
                WITH Targets AS
                (
                SELECT [Role] AS [Principal], [Membership Chain], len([Membership Chain]) AS [Membership Chain Length] FROM STIG.database_roles_of(@Grantee)
                UNION ALL
                SELECT @Grantee AS [Principal], @Grantee AS [Membership Chain], len(@Grantee) AS [Membership Chain Length]
                )
                INSERT INTO @T
                    SELECT TOP 100000000
                        P.[Current Server],
                        P.[Current Instance],
                        P.[Current DB],
                        P.[Current Login],
                        P.[Current User],
                        P.[Securable Type or Class],
                        P.[Schema/Owner],
                        P.[Securable],
                        P.[Column],
                        @Grantee                AS [Effective Grantee],
                        T.[Membership Chain]    AS [Membership Chain],
                        P.[Grantee]             AS [Direct Grantee],
                        P.[Grantee Type]        AS [Direct Grantee Type],
                        P.[Permission],
                        P.[State],
                        P.[Grantor],
                        P.[Grantor Type],
                        P.[Source View]
                    FROM
                        STIG.database_permissions P
                        INNER JOIN Targets T ON T.[Principal] COLLATE DATABASE_DEFAULT = P.[Grantee] COLLATE DATABASE_DEFAULT
                    ORDER BY
                        P.[Securable Type or Class],
                        P.[Schema/Owner],
                        P.[Securable],
                        P.[Column],
                        T.[Membership Chain Length]
                    ;
                    UPDATE T
                    SET [State] = [State] + ' (schema denied)'
                    FROM @T T
                    WHERE
                        T.[State] <> 'DENY'
                    AND    T.[Securable Type or Class] <> 'SCHEMA'
                    AND 0 <
                        (
                        SELECT count(*) FROM @T X
                        WHERE
                            X.[Securable Type or Class] = 'SCHEMA'
                        AND X.[Securable]               = T.[Schema/Owner]
                        AND X.[Permission]              = T.[Permission]
                        AND X.[State]                   = 'DENY'
                        )
                    ;
                    UPDATE T
                    SET [State] = [State] + ' (denied)'
                    FROM @T T
                    WHERE
                        T.[State] <> 'DENY'
                    AND 0 <
                        (
                        SELECT count(*) FROM @T X
                        WHERE
                            X.[Securable Type or Class] = T.[Securable Type or Class]
                        AND    X.[Schema/Owner]         = T.[Schema/Owner]
                        AND X.[Securable]               = T.[Securable]
                        AND    (X.[Column] = T.[Column] OR (X.[Column] IS NULL) AND (T.[Column] IS NULL))
                        AND X.[Permission]              = T.[Permission]
                        AND X.[State]                   = 'DENY'
                        )
                    ;
                    UPDATE T
                    SET [State] = [State] + ' (column(s) denied)'
                    FROM @T T
                    WHERE T.[Securable Type or Class] <> 'COLUMN'
                    AND 0 <
                        (
                        SELECT count(*) FROM @T X
                        WHERE
                            X.[Securable Type or Class] = 'COLUMN'
                        AND X.[Schema/Owner]            = T.[Schema/Owner]
                        AND X.[Securable]               = T.[Securable]
                        AND X.[Permission]              = T.[Permission]
                        AND X.[State]                   = 'DENY'
                        )
                    ;
            ExitFunction:
                RETURN;
            END;
            GO



            BEGIN TRY DROP VIEW STIG.server_role_members END TRY BEGIN CATCH END CATCH;
            GO

            CREATE VIEW STIG.server_role_members
            --  Based on the system view sys.server_role_members, this presents the list of
            --  server role memberships using roles' and logins' names rather than their id numbers.
            --  Although membership in server roles is hierarchical, this view lists only the direct memberships.
            AS SELECT
                R.name    AS [Role],
                M.name    AS [Member]
            FROM
                [<TARGETDB>].sys.server_role_members X
                INNER JOIN [<TARGETDB>].sys.server_principals R ON R.principal_id = X.role_principal_id
                INNER JOIN [<TARGETDB>].sys.server_principals M ON M.principal_id = X.member_principal_id
            ;
            GO


            BEGIN TRY DROP FUNCTION STIG.server_roles_of END TRY BEGIN CATCH END CATCH;
            GO

            CREATE FUNCTION STIG.server_roles_of(@server_principal sysname)
            --  Membership in server roles is hierarchical.
            --  Given the name of a server principal (login or role), this table-valued function returns
            --  a list of all the roles it belongs to, both directly and indirectly.
                RETURNS @T TABLE
                    (
                    [Member]            sysname,
                    [Role]              sysname,
                    [via Member]        sysname,
                    [Membership Chain]  nvarchar(max)
                    )
            AS BEGIN;
                WITH Membership AS
                (
                SELECT
                    [Member] AS [Member],
                    [Role],
                    [Member] AS [via Member],
                    CAST([Member] AS varchar(max)) + ' < ' + CAST([Role] AS varchar(max)) AS [Membership Chain]
                FROM
                    STIG.server_role_members
                WHERE
                    [Member] = @server_principal

                UNION ALL

                SELECT
                    X.[Member],
                    R.[Role],
                    R.[Member] AS [via Member],
                    X.[Membership Chain] + ' < ' + CAST(R.[Role] AS varchar(max)) AS [Membership Chain]
                FROM
                    Membership X
                    INNER JOIN STIG.server_role_members R ON X.[Role] = R.[Member]
                )
                INSERT INTO @T SELECT * FROM Membership;
            ExitFunction:
                RETURN;
            END;
            GO


            BEGIN TRY DROP FUNCTION STIG.members_of_server_role END TRY BEGIN CATCH END CATCH;
            GO

            CREATE FUNCTION STIG.members_of_server_role(@server_role sysname)
            --  Membership in server roles is hierarchical.
            --  Given the name of a server role, this table-valued function returns
            --  a list of all the roles and logins that belong to it, both directly and indirectly.
                RETURNS @T TABLE
                    (
                    [Role]              sysname,
                    [Member]            sysname,
                    [via Role]          sysname,
                    [Membership Chain]  nvarchar(max)
                    )
            AS BEGIN;
                WITH Membership AS
                (
                SELECT
                    [Role] AS [Role],
                    [Member],
                    [Role] AS [via Role],
                    CAST([Role] AS varchar(max)) + ' > ' + CAST([Member] AS varchar(max)) AS [Membership Chain]
                FROM
                    STIG.server_role_members
                WHERE
                    [Role] = @server_role

                UNION ALL

                SELECT
                    X.[Role] AS [Role],
                    R.[Member],
                    R.[Role] AS [via Role],
                    X.[Membership Chain] + ' > ' + CAST(R.[Member] AS varchar(max)) AS [Membership Chain]
                FROM
                    Membership X
                    INNER JOIN STIG.server_role_members R ON X.[Member] = R.[Role]
                )
                INSERT INTO @T SELECT * FROM Membership;
            ExitFunction:
                RETURN;
            END;
            GO



            BEGIN TRY DROP VIEW STIG.server_permissions END TRY BEGIN CATCH END CATCH;
            GO

            CREATE VIEW STIG.server_permissions
            --  Based on the system view sys.server_permissions, this provides additional, descriptive material.
            --  The list includes only those permissions explicitly granted (or denied) to a server login or role;
            --  it does not include permissions that are implicit or inherited from a higher-level role.
            --  Securable items that exist but have no explicit permissions assigned are included in the
            --  list, with columns describing the grantor and grantee left null.
            AS SELECT DISTINCT
                @@SERVERNAME          AS [Current Server],
                @@SERVICENAME         AS [Current Instance],
                '<QUOTETARGETDB>'     AS [Current DB],
                SYSTEM_USER           AS [Current Login],
                USER                  AS [Current User],
                CASE
                    WHEN SP.class_desc IS NOT NULL THEN
                        CASE
                            WHEN SP.class_desc = 'SERVER' AND S.is_linked = 0 THEN 'SERVER'
                            WHEN SP.class_desc = 'SERVER' AND S.is_linked = 1 THEN 'SERVER (linked)'
                            ELSE SP.class_desc
                        END
                    WHEN E.name IS NOT NULL THEN 'ENDPOINT'
                    WHEN S.name IS NOT NULL AND S.is_linked = 0 THEN 'SERVER'
                    WHEN S.name IS NOT NULL AND S.is_linked = 1 THEN 'SERVER (linked)'
                    WHEN P.name IS NOT NULL THEN 'SERVER_PRINCIPAL'
                    ELSE '???'
                END                    AS [Securable Class],
                CASE
                    WHEN E.name IS NOT NULL THEN E.name
                    WHEN S.name IS NOT NULL THEN S.name
                    WHEN P.name IS NOT NULL THEN P.name
                    ELSE '???'
                END                    AS [Securable],
                P1.name                AS [Grantee],
                P1.type_desc           AS [Grantee Type],
                SP.permission_name     AS [Permission],
                SP.state_desc          AS [State],
                P2.name                AS [Grantor],
                P2.type_desc           AS [Grantor Type],
                CASE
                    WHEN SP.class_desc = 'SERVER'                       THEN 'sys.servers'
                    WHEN SP.class_desc = 'ENDPOINT'                     THEN 'sys.endpoints'
                    WHEN SP.class_desc = 'SERVER_PRINCIPAL'             THEN 'sys.server_principals'
                    WHEN SP.class_desc IS NULL AND S.name IS NOT NULL   THEN 'sys.servers'
                    WHEN SP.class_desc IS NULL AND E.name IS NOT NULL   THEN 'sys.endpoints'
                    WHEN SP.class_desc IS NULL AND P.name IS NOT NULL   THEN 'sys.server_principals'
                    ELSE 'sys.server_permissions'
                END                 AS [Source View]
            FROM
                [<TARGETDB>].sys.server_permissions SP
                INNER JOIN [<TARGETDB>].sys.server_principals P1
                    ON P1.principal_id = SP.grantee_principal_id
                INNER JOIN [<TARGETDB>].sys.server_principals P2
                    ON P2.principal_id = SP.grantor_principal_id

                FULL OUTER JOIN sys.servers S
                    ON  SP.class_desc = 'SERVER'
                    AND S.server_id = SP.major_id

                FULL OUTER JOIN [<TARGETDB>].sys.endpoints E
                    ON  SP.class_desc = 'ENDPOINT'
                    AND E.endpoint_id = SP.major_id

                FULL OUTER JOIN [<TARGETDB>].sys.server_principals P
                    ON  SP.class_desc = 'SERVER_PRINCIPAL'
                    AND P.principal_id = SP.major_id
            ;
            GO


            BEGIN TRY DROP FUNCTION STIG.server_effective_permissions END TRY BEGIN CATCH END CATCH;
            GO

            CREATE FUNCTION STIG.server_effective_permissions(@Grantee sysname)
            --  Given the name of a server principal (login or server role), this table-valued function
            --  returns information about permissions granted (or denied) to that login or role,
            --  either directly or inherited from a higher-level role.
                RETURNS @T TABLE
                    (
                    [Current Server]            sysname         null,
                    [Current Instance]          sysname         null,
                    [Current DB]                sysname         null,
                    [Current Login]             sysname         null,
                    [Current User]              sysname         null,
                    [Securable Class]           nvarchar(60)    null,
                    [Securable]                 sql_variant     null,
                    [Effective Grantee]         sysname         null,
                    [Membership Chain]          nvarchar(max)   null,
                    [Direct Grantee]            sysname         null,
                    [Direct Grantee Type]       nvarchar(60)    null,
                    [Permission]                sysname         null,
                    [State]                     nvarchar(60)    null,
                    [Grantor]                   sysname         null,
                    [Grantor Type]              nvarchar(60)    null,
                    [source view]               sysname         null
                    )
            AS BEGIN;
                WITH Targets AS
                (
                SELECT [Role] AS [Principal], [Membership Chain], len([Membership Chain]) AS [Membership Chain Length] FROM STIG.server_roles_of(@Grantee)
                UNION ALL
                SELECT @Grantee AS [Principal], @Grantee AS [Membership Chain], len(@Grantee) AS [Membership Chain Length]
                )
                INSERT INTO @T
                    SELECT TOP 100000000
                        P.[Current Server],
                        P.[Current Instance],
                        P.[Current DB],
                        P.[Current Login],
                        P.[Current User],
                        P.[Securable Class],
                        P.[Securable],
                        @Grantee                AS [Effective Grantee],
                        T.[Membership Chain]    AS [Membership Chain],
                        P.[Grantee]             AS [Direct Grantee],
                        P.[Grantee Type]        AS [Direct Grantee Type],
                        P.[Permission],
                        P.[State],
                        P.[Grantor],
                        P.[Grantor Type],
                        P.[Source View]
                    FROM
                        STIG.server_permissions P
                        INNER JOIN Targets T ON T.[Principal] = P.[Grantee]
                    ORDER BY
                        P.[Securable Class],
                        P.[Securable],
                        T.[Membership Chain Length]
                    ;
                    UPDATE T
                    SET [State] = [State] + ' (denied)'
                    FROM @T T
                    WHERE
                        T.[State] <> 'DENY'
                    AND 0 <
                        (
                        SELECT count(*) FROM @T X
                        WHERE
                            X.[Securable Class] = T.[Securable Class]
                        AND X.[Securable]       = T.[Securable]
                        AND X.[Permission]      = T.[Permission]
                        AND X.[State]           = 'DENY'
                        )
                    ;
            ExitFunction:
                RETURN;
            END;
            GO
