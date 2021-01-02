function Get-DbaHelpIndex {
    <#
    .SYNOPSIS
        Returns size, row and configuration information for indexes in databases.

    .DESCRIPTION
        This function will return detailed information on indexes (and optionally statistics) for all indexes in a database, or a given index should one be passed along.
        As this uses SQL Server DMVs to access the data it will only work in 2005 and up (sorry folks still running SQL Server 2000).
        For performance reasons certain statistics information will not be returned from SQL Server 2005 if an ObjectName is not provided.

        The data includes:
        - ObjectName: the table containing the index
        - IndexType: clustered/non-clustered/columnstore and whether the index is unique/primary key
        - KeyColumns: the key columns of the index
        - IncludeColumns: any include columns in the index
        - FilterDefinition: any filter that may have been used in the index
        - DataCompression: row/page/none depending upon whether or not compression has been used
        - IndexReads: the number of reads of the index since last restart or index rebuild
        - IndexUpdates: the number of writes to the index since last restart or index rebuild
        - SizeKB: the size the index in KB
        - IndexRows: the number of the rows in the index (note filtered indexes will have fewer rows than exist in the table)
        - IndexLookups: the number of lookups that have been performed (only applicable for the heap or clustered index)
        - MostRecentlyUsed: when the index was most recently queried (default to 1900 for when never read)
        - StatsSampleRows: the number of rows queried when the statistics were built/rebuilt (not included in SQL Server 2005 unless ObjectName is specified)
        - StatsRowMods: the number of changes to the statistics since the last rebuild
        - HistogramSteps: the number of steps in the statistics histogram (not included in SQL Server 2005 unless ObjectName is specified)
        - StatsLastUpdated: when the statistics were last rebuilt (not included in SQL Server 2005 unless ObjectName is specified)

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. This list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude. This list is auto-populated from the server.

    .PARAMETER ObjectName
        The name of a table for which you want to obtain the index information. If the two part naming convention for an object is not used it will use the default schema for the executing user. If not passed it will return data on all indexes in a given database.

    .PARAMETER IncludeStats
        If this switch is enabled, statistics as well as indexes will be returned in the output (statistics information such as the StatsRowMods will always be returned for indexes).

    .PARAMETER IncludeDataTypes
        If this switch is enabled, the output will include the data type of each column that makes up a part of the index definition (key and include columns).

    .PARAMETER IncludeFragmentation
        If this switch is enabled, the output will include fragmentation information.

    .PARAMETER InputObject
        Allows piping from Get-DbaDatabase

    .PARAMETER Raw
        If this switch is enabled, results may be less user-readable but more suitable for processing by other code.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Index
        Author: Nic Cain, https://sirsql.net/

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaHelpIndex

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB

        Returns information on all indexes on the MyDB database on the localhost.

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB,MyDB2

        Returns information on all indexes on the MyDB & MyDB2 databases.

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB -ObjectName dbo.Table1

        Returns index information on the object dbo.Table1 in the database MyDB.

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB -ObjectName dbo.Table1 -IncludeStats

        Returns information on the indexes and statistics for the table dbo.Table1 in the MyDB database.

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB -ObjectName dbo.Table1 -IncludeDataTypes

        Returns the index information for the table dbo.Table1 in the MyDB database, and includes the data types for the key and include columns.

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB -ObjectName dbo.Table1 -Raw

        Returns the index information for the table dbo.Table1 in the MyDB database, and returns the numerical data without localized separators.

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB -IncludeStats -Raw

        Returns the index information for all indexes in the MyDB database as well as their statistics, and formats the numerical data without localized separators.

    .EXAMPLE
        PS C:\> Get-DbaHelpIndex -SqlInstance localhost -Database MyDB -IncludeFragmentation

        Returns the index information for all indexes in the MyDB database as well as their fragmentation

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2017 -Database MyDB | Get-DbaHelpIndex

        Returns the index information for all indexes in the MyDB database

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [string]$ObjectName,
        [switch]$IncludeStats,
        [switch]$IncludeDataTypes,
        [switch]$Raw,
        [switch]$IncludeFragmentation,
        [switch]$EnableException
    )

    begin {

        #Add the table predicate to the query
        if (!$ObjectName) {
            $TablePredicate = "DECLARE @TableName NVARCHAR(256);";
        } else {
            $TablePredicate = "DECLARE @TableName NVARCHAR(256); SET @TableName = '$ObjectName';";
        }

        #Add Fragmentation info if requested
        $FragSelectColumn = ", NULL as avg_fragmentation_in_percent"
        $FragJoin = ''
        $OutputProperties = 'Database,Object,Index,IndexType,KeyColumns,IncludeColumns,FilterDefinition,DataCompression,IndexReads,IndexUpdates,SizeKB,IndexRows,IndexLookups,MostRecentlyUsed,StatsSampleRows,StatsRowMods,HistogramSteps,StatsLastUpdated'
        if ($IncludeFragmentation) {
            $FragSelectColumn = ', pstat.avg_fragmentation_in_percent'
            $FragJoin = "LEFT JOIN sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL , 'DETAILED') pstat
             ON pstat.database_id = ustat.database_id
             AND pstat.object_id = ustat.object_id
             AND pstat.index_id = ustat.index_id"
            $OutputProperties = 'Database,Object,Index,IndexType,KeyColumns,IncludeColumns,FilterDefinition,DataCompression,IndexReads,IndexUpdates,SizeKB,IndexRows,IndexLookups,MostRecentlyUsed,StatsSampleRows,StatsRowMods,HistogramSteps,StatsLastUpdated,IndexFragInPercent'
        }
        $OutputProperties = $OutputProperties.Split(',')
        #Figure out if we are including stats in the results
        if ($IncludeStats) {
            $IncludeStatsPredicate = "";
        } else {
            $IncludeStatsPredicate = "WHERE StatisticsName IS NULL";
        }

        #Data types being returns with the results?
        if ($IncludeDataTypes) {
            $IncludeDataTypesPredicate = 'DECLARE @IncludeDataTypes BIT; SET @IncludeDataTypes = 1';
        } else {
            $IncludeDataTypesPredicate = 'DECLARE @IncludeDataTypes BIT; SET @IncludeDataTypes = 0';
        }

        #region SizesQuery
        $SizesQuery = "
            SET NOCOUNT ON;
            SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

            $TablePredicate
            $IncludeDataTypesPredicate
            ;

        DECLARE @IndexUsageStats TABLE
            (
            object_id INT ,
            index_id INT ,
            user_scans BIGINT ,
            user_seeks BIGINT ,
            user_updates BIGINT ,
            user_lookups BIGINT ,
            last_user_lookup DATETIME2(0) ,
            last_user_scan DATETIME2(0) ,
            last_user_seek DATETIME2(0) ,
            avg_fragmentation_in_percent FLOAT
            );

        DECLARE @StatsInfo TABLE
            (
            object_id INT ,
            stats_id INT ,
            stats_column_name NVARCHAR(128) ,
            stats_column_id INT ,
            stats_name NVARCHAR(128) ,
            stats_last_updated DATETIME2(0) ,
            stats_sampled_rows BIGINT ,
            rowmods BIGINT ,
            histogramsteps INT ,
            StatsRows BIGINT ,
            FullObjectName NVARCHAR(256)
            );

        INSERT  INTO @IndexUsageStats
                ( object_id ,
                index_id ,
                user_scans ,
                user_seeks ,
                user_updates ,
                user_lookups ,
                last_user_lookup ,
                last_user_scan ,
                last_user_seek ,
                avg_fragmentation_in_percent
                )
                SELECT  ustat.object_id ,
                        ustat.index_id ,
                        ustat.user_scans ,
                        ustat.user_seeks ,
                        ustat.user_updates ,
                        ustat.user_lookups ,
                        ustat.last_user_lookup ,
                        ustat.last_user_scan ,
                        ustat.last_user_seek
                        $FragSelectColumn
                FROM    sys.dm_db_index_usage_stats ustat
                $FragJoin
                WHERE   ustat.database_id = DB_ID();

        INSERT  INTO @StatsInfo
                ( object_id ,
                stats_id ,
                stats_column_name ,
                stats_column_id ,
                stats_name ,
                stats_last_updated ,
                stats_sampled_rows ,
                rowmods ,
                histogramsteps ,
                StatsRows ,
                FullObjectName
                )
                SELECT  s.object_id ,
                        s.stats_id ,
                        c.name ,
                        sc.stats_column_id ,
                        s.name ,
                        sp.last_updated ,
                        sp.rows_sampled ,
                        sp.modification_counter ,
                        sp.steps ,
                        sp.rows ,
                        QUOTENAME(sch.name) + '.' + QUOTENAME(t.name) AS FullObjectName
                FROM    [sys].[stats] AS [s]
                        INNER JOIN sys.stats_columns sc ON s.stats_id = sc.stats_id
                                                        AND s.object_id = sc.object_id
                        INNER JOIN sys.columns c ON c.object_id = sc.object_id
                                                    AND c.column_id = sc.column_id
                        INNER JOIN sys.tables t ON c.object_id = t.object_id
                        INNER JOIN sys.schemas sch ON sch.schema_id = t.schema_id
                        OUTER APPLY sys.dm_db_stats_properties([s].[object_id],
                                                            [s].[stats_id]) AS [sp]
                WHERE   s.object_id = CASE WHEN @TableName IS NULL THEN s.object_id
                                        else OBJECT_ID(@TableName)
                                    END;


        ;
        WITH    cteStatsInfo
                AS ( SELECT   object_id ,
                                si.stats_id ,
                                si.stats_name ,
                                STUFF((SELECT   N', ' + stats_column_name
                                    FROM     @StatsInfo si2
                                    WHERE    si2.object_id = si.object_id
                                                AND si2.stats_id = si.stats_id
                                    ORDER BY si2.stats_column_id
                                FOR   XML PATH(N'') ,
                                        TYPE).value(N'.[1]', N'nvarchar(1000)'), 1,
                                    2, N'') AS StatsColumns ,
                                MAX(si.stats_sampled_rows) AS SampleRows ,
                                MAX(si.rowmods) AS RowMods ,
                                MAX(si.histogramsteps) AS HistogramSteps ,
                                MAX(si.stats_last_updated) AS StatsLastUpdated ,
                                MAX(si.StatsRows) AS StatsRows,
                                FullObjectName
                    FROM     @StatsInfo si
                    GROUP BY si.object_id ,
                                si.stats_id ,
                                si.stats_name ,
                                si.FullObjectName
                    ),
                cteIndexSizes
                AS ( SELECT   object_id ,
                                index_id ,
                                CASE WHEN index_id < 2
                                    THEN ( ( SUM(in_row_data_page_count
                                                + lob_used_page_count
                                                + row_overflow_used_page_count)
                                            * 8192 ) / 1024 )
                                    else ( ( SUM(used_page_count) * 8192 ) / 1024 )
                                END AS SizeKB
                    FROM     sys.dm_db_partition_stats
                    GROUP BY object_id ,
                                index_id
                    ),
                cteRows
                AS ( SELECT   object_id ,
                                index_id ,
                                SUM(rows) AS IndexRows
                    FROM     sys.partitions
                    GROUP BY object_id ,
                                index_id
                    ),
                cteIndex
                AS ( SELECT   OBJECT_NAME(c.object_id) AS ObjectName ,
                                c.object_id ,
                                c.index_id ,
                                i.name COLLATE SQL_Latin1_General_CP1_CI_AS AS name ,
                                c.index_column_id ,
                                c.column_id ,
                                c.is_included_column ,
                                CASE WHEN @IncludeDataTypes = 0
                                        AND c.is_descending_key = 1
                                    THEN sc.name + ' DESC'
                                    WHEN @IncludeDataTypes = 0
                                        AND c.is_descending_key = 0 THEN sc.name
                                    WHEN @IncludeDataTypes = 1
                                        AND c.is_descending_key = 1
                                        AND c.is_included_column = 0
                                    THEN sc.name + ' DESC (' + t.name + ') '
                                    WHEN @IncludeDataTypes = 1
                                        AND c.is_descending_key = 0
                                        AND c.is_included_column = 0
                                    THEN sc.name + ' (' + t.name + ')'
                                    else sc.name
                                END AS ColumnName ,
                                i.filter_definition ,
                                ISNULL(dd.user_scans, 0) AS user_scans ,
                                ISNULL(dd.user_seeks, 0) AS user_seeks ,
                                ISNULL(dd.user_updates, 0) AS user_updates ,
                                ISNULL(dd.user_lookups, 0) AS user_lookups ,
                                CONVERT(DATETIME2(0), ISNULL(dd.last_user_lookup,
                                                            '1901-01-01')) AS LastLookup ,
                                CONVERT(DATETIME2(0), ISNULL(dd.last_user_scan,
                                                            '1901-01-01')) AS LastScan ,
                                CONVERT(DATETIME2(0), ISNULL(dd.last_user_seek,
                                                            '1901-01-01')) AS LastSeek ,
                                i.fill_factor ,
                                c.is_descending_key ,
                                p.data_compression_desc ,
                                i.type_desc ,
                                i.is_unique ,
                                i.is_unique_constraint ,
                                i.is_primary_key ,
                                ci.SizeKB ,
                                cr.IndexRows ,
                                QUOTENAME(sch.name) + '.' + QUOTENAME(tbl.name) AS FullObjectName ,
                                ISNULL(dd.avg_fragmentation_in_percent, 0) as avg_fragmentation_in_percent
                    FROM     sys.indexes i
                                JOIN sys.index_columns c ON i.object_id = c.object_id
                                                            AND i.index_id = c.index_id
                                JOIN sys.columns sc ON c.object_id = sc.object_id
                                                    AND c.column_id = sc.column_id
                                INNER JOIN sys.tables tbl ON c.object_id = tbl.object_id
                                INNER JOIN sys.schemas sch ON sch.schema_id = tbl.schema_id
                                LEFT JOIN sys.types t ON sc.user_type_id = t.user_type_id
                                LEFT JOIN @IndexUsageStats dd ON i.object_id = dd.object_id
                                                                AND i.index_id = dd.index_id --and dd.database_id = db_id()
                                JOIN sys.partitions p ON i.object_id = p.object_id
                                                        AND i.index_id = p.index_id
                                JOIN cteIndexSizes ci ON i.object_id = ci.object_id
                                                        AND i.index_id = ci.index_id
                                JOIN cteRows cr ON i.object_id = cr.object_id
                                                AND i.index_id = cr.index_id
                    WHERE    i.object_id = CASE WHEN @TableName IS NULL
                                                THEN i.object_id
                                                else OBJECT_ID(@TableName)
                                            END
                    ),
                cteResults
                AS ( SELECT   ci.FullObjectName ,
                                ci.object_id ,
                                MAX(index_id) AS Index_Id ,
                                ci.type_desc
                                + CASE WHEN ci.is_primary_key = 1
                                    THEN ' (PRIMARY KEY)'
                                    WHEN ci.is_unique_constraint = 1
                                    THEN ' (UNIQUE CONSTRAINT)'
                                    WHEN ci.is_unique = 1 THEN ' (UNIQUE)'
                                    else ''
                                END AS IndexType ,
                                name AS IndexName ,
                                STUFF((SELECT   N', ' + ColumnName
                                    FROM     cteIndex ci2
                                    WHERE    ci2.name = ci.name
                                                AND ci2.is_included_column = 0
                                    GROUP BY ci2.index_column_id ,
                                                ci2.ColumnName
                                    ORDER BY ci2.index_column_id
                                FOR   XML PATH(N'') ,
                                        TYPE).value(N'.[1]', N'nvarchar(1000)'), 1,
                                    2, N'') AS KeyColumns ,
                                ISNULL(STUFF((SELECT    N',  ' + ColumnName
                                            FROM      cteIndex ci3
                                            WHERE     ci3.name = ci.name
                                                        AND ci3.is_included_column = 1
                                            GROUP BY  ci3.index_column_id ,
                                                        ci3.ColumnName
                                            ORDER BY  ci3.index_column_id
                                    FOR   XML PATH(N'') ,
                                                TYPE).value(N'.[1]',
                                                            N'nvarchar(1000)'), 1, 2,
                                            N''), '') AS IncludeColumns ,
                                ISNULL(filter_definition, '') AS FilterDefinition ,
                                ci.fill_factor ,
                                CASE WHEN ci.data_compression_desc = 'NONE' THEN ''
                                    else ci.data_compression_desc
                                END AS DataCompression ,
                                MAX(ci.user_seeks) + MAX(ci.user_scans)
                                + MAX(ci.user_lookups) AS IndexReads ,
                                MAX(ci.user_lookups) AS IndexLookups ,
                                ci.user_updates AS IndexUpdates ,
                                ci.SizeKB AS SizeKB ,
                                ci.IndexRows AS IndexRows ,
                                CASE WHEN LastScan > LastSeek
                                        AND LastScan > LastLookup THEN LastScan
                                    WHEN LastSeek > LastScan
                                        AND LastSeek > LastLookup THEN LastSeek
                                    WHEN LastLookup > LastScan
                                        AND LastLookup > LastSeek THEN LastLookup
                                    else ''
                                END AS MostRecentlyUsed ,
                                AVG(ci.avg_fragmentation_in_percent) as avg_fragmentation_in_percent
                    FROM     cteIndex ci
                    GROUP BY ci.ObjectName ,
                                ci.name ,
                                ci.filter_definition ,
                                ci.object_id ,
                                ci.LastLookup ,
                                ci.LastSeek ,
                                ci.LastScan ,
                                ci.user_updates ,
                                ci.fill_factor ,
                                ci.data_compression_desc ,
                                ci.type_desc ,
                                ci.is_primary_key ,
                                ci.is_unique ,
                                ci.is_unique_constraint ,
                                ci.SizeKB ,
                                ci.IndexRows ,
                                ci.FullObjectName
                    ),
                AllResults
                AS ( SELECT   c.FullObjectName ,
                                IndexType ,
                                ISNULL(IndexName, si.stats_name) AS IndexName ,
                                NULL as StatisticsName ,
                                ISNULL(KeyColumns, si.StatsColumns) AS KeyColumns ,
                                ISNULL(IncludeColumns, '') AS IncludeColumns ,
                                FilterDefinition ,
                                fill_factor AS [FillFactor] ,
                                DataCompression ,
                                IndexReads ,
                                IndexUpdates ,
                                SizeKB ,
                                IndexRows ,
                                IndexLookups ,
                                MostRecentlyUsed ,
                                SampleRows AS StatsSampleRows ,
                                RowMods AS StatsRowMods ,
                                si.HistogramSteps ,
                                si.StatsLastUpdated ,
                                avg_fragmentation_in_percent AS IndexFragInPercent,
                                1 AS Ordering
                    FROM     cteResults c
                                INNER JOIN cteStatsInfo si ON si.object_id = c.object_id
                                                            AND si.stats_id = c.Index_Id
                    UNION
                    SELECT   QUOTENAME(sch.name) + '.' + QUOTENAME(tbl.name) AS FullObjectName ,
                                '' ,
                                '' ,
                                stats_name ,
                                StatsColumns ,
                                '' ,
                                '' AS FilterDefinition ,
                                '' AS Fill_Factor ,
                                '' AS DataCompression ,
                                '' AS IndexReads ,
                                '' AS IndexUpdates ,
                                '' AS SizeKB ,
                                StatsRows AS IndexRows ,
                                '' AS IndexLookups ,
                                '' AS MostRecentlyUsed ,
                                SampleRows AS StatsSampleRows ,
                                RowMods AS StatsRowMods ,
                                csi.HistogramSteps ,
                                csi.StatsLastUpdated ,
                                '' AS IndexFragInPercent ,
                                2
                    FROM     cteStatsInfo csi
                    INNER JOIN sys.tables tbl ON csi.object_id = tbl.object_id
                                INNER JOIN sys.schemas sch ON sch.schema_id = tbl.schema_id
                    WHERE    stats_id NOT IN (
                                SELECT  stats_id
                                FROM    cteResults c
                                        INNER JOIN cteStatsInfo si ON si.object_id = c.object_id
                                                                    AND si.stats_id = c.Index_Id )
                    )
            SELECT  FullObjectName ,
                    IndexType ,
                    IndexName ,
                    StatisticsName ,
                    KeyColumns ,
                    ISNULL(IncludeColumns, '') AS IncludeColumns ,
                    FilterDefinition ,
                    [FillFactor] AS [FillFactor] ,
                    DataCompression ,
                    IndexReads ,
                    IndexUpdates ,
                    SizeKB ,
                    IndexRows ,
                    IndexLookups ,
                    MostRecentlyUsed ,
                    StatsSampleRows ,
                    StatsRowMods ,
                    HistogramSteps ,
                    StatsLastUpdated ,
                    IndexFragInPercent
            FROM    AllResults
                    $IncludeStatsPredicate
        OPTION  ( RECOMPILE );
        "
        #endRegion SizesQuery


        #region sizesQuery2005
        $SizesQuery2005 = "
        SET NOCOUNT ON;
        SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

        $TablePredicate
        $IncludeDataTypesPredicate
        ;

        DECLARE @AllResults TABLE
            (
                RowNum INT ,
                FullObjectName	NVARCHAR(300) ,
                IndexType	NVARCHAR(256) ,
                IndexName	NVARCHAR(256) ,
                KeyColumns	NVARCHAR(2000) ,
                IncludeColumns	NVARCHAR(2000) ,
                FilterDefinition	NVARCHAR(100) ,
                [FillFactor]	TINYINT ,
                DataCompression	CHAR(4) ,
                IndexReads	BIGINT ,
                IndexUpdates	BIGINT ,
                SizeKB	BIGINT ,
                IndexRows	BIGINT ,
                IndexLookups	BIGINT ,
                MostRecentlyUsed	DATETIME ,
                StatsSampleRows	BIGINT ,
                StatsRowMods	BIGINT ,
                HistogramSteps	INT	,
                StatsLastUpdated	DATETIME ,
                object_id BIGINT ,
                index_id BIGINT
            );

        DECLARE @IndexUsageStats TABLE
            (
            object_id INT ,
            index_id INT ,
            user_scans BIGINT ,
            user_seeks BIGINT ,
            user_updates BIGINT ,
            user_lookups BIGINT ,
            last_user_lookup DATETIME ,
            last_user_scan DATETIME ,
            last_user_seek DATETIME ,
            avg_fragmentation_in_percent FLOAT
            );

        DECLARE @StatsInfo TABLE
            (
            object_id INT ,
            stats_id INT ,
            stats_column_name NVARCHAR(128) ,
            stats_column_id INT ,
            stats_name NVARCHAR(128) ,
            stats_last_updated DATETIME ,
            stats_sampled_rows BIGINT ,
            rowmods BIGINT ,
            histogramsteps INT ,
            StatsRows BIGINT ,
            FullObjectName NVARCHAR(256)
            );

        INSERT  INTO @IndexUsageStats
                ( object_id ,
                index_id ,
                user_scans ,
                user_seeks ,
                user_updates ,
                user_lookups ,
                last_user_lookup ,
                last_user_scan ,
                last_user_seek ,
                avg_fragmentation_in_percent
                )
                SELECT  ustat.object_id ,
                        ustat.index_id ,
                        ustat.user_scans ,
                        ustat.user_seeks ,
                        ustat.user_updates ,
                        ustat.user_lookups ,
                        ustat.last_user_lookup ,
                        ustat.last_user_scan ,
                        ustat.last_user_seek
                        $FragSelectColumn
                FROM    sys.dm_db_index_usage_stats ustat
                $FragJoin
                WHERE   database_id = DB_ID();


        INSERT  INTO @StatsInfo
                ( object_id ,
                stats_id ,
                stats_column_name ,
                stats_column_id ,
                stats_name ,
                stats_last_updated ,
                stats_sampled_rows ,
                rowmods ,
                histogramsteps ,
                StatsRows ,
                FullObjectName
                )
                SELECT  s.object_id ,
                        s.stats_id ,
                        c.name ,
                        sc.stats_column_id ,
                        s.name ,
                        NULL AS last_updated ,
                        NULL AS rows_sampled ,
                        NULL AS modification_counter ,
                        NULL AS steps ,
                        NULL AS rows ,
                        QUOTENAME(sch.name) + '.' + QUOTENAME(t.name) AS FullObjectName
                FROM    [sys].[stats] AS [s]
                        INNER JOIN sys.stats_columns sc ON s.stats_id = sc.stats_id
                                                        AND s.object_id = sc.object_id
                        INNER JOIN sys.columns c ON c.object_id = sc.object_id
                                                    AND c.column_id = sc.column_id
                        INNER JOIN sys.tables t ON c.object_id = t.object_id
                        INNER JOIN sys.schemas sch ON sch.schema_id = t.schema_id
                    --   OUTER APPLY sys.dm_db_stats_properties([s].[object_id],
                    --                                        [s].[stats_id]) AS [sp]
                WHERE   s.object_id = CASE WHEN @TableName IS NULL THEN s.object_id
                                        else OBJECT_ID(@TableName)
                                    END;


        ;
        WITH    cteStatsInfo
                AS ( SELECT   object_id ,
                                si.stats_id ,
                                si.stats_name ,
                                STUFF((SELECT   N', ' + stats_column_name
                                    FROM     @StatsInfo si2
                                    WHERE    si2.object_id = si.object_id
                                                AND si2.stats_id = si.stats_id
                                    ORDER BY si2.stats_column_id
                                FOR   XML PATH(N'') ,
                                        TYPE).value(N'.[1]', N'nvarchar(1000)'), 1,
                                    2, N'') AS StatsColumns ,
                                MAX(si.stats_sampled_rows) AS SampleRows ,
                                MAX(si.rowmods) AS RowMods ,
                                MAX(si.histogramsteps) AS HistogramSteps ,
                                MAX(si.stats_last_updated) AS StatsLastUpdated ,
                                MAX(si.StatsRows) AS StatsRows,
                                FullObjectName
                    FROM     @StatsInfo si
                    GROUP BY si.object_id ,
                                si.stats_id ,
                                si.stats_name ,
                                si.FullObjectName
                    ),
                cteIndexSizes
                AS ( SELECT   object_id ,
                                index_id ,
                                CASE WHEN index_id < 2
                                    THEN ( ( SUM(in_row_data_page_count
                                                + lob_used_page_count
                                                + row_overflow_used_page_count)
                                            * 8192 ) / 1024 )
                                    else ( ( SUM(used_page_count) * 8192 ) / 1024 )
                                END AS SizeKB
                    FROM     sys.dm_db_partition_stats
                    GROUP BY object_id ,
                                index_id
                    ),
                cteRows
                AS ( SELECT   object_id ,
                                index_id ,
                                SUM(rows) AS IndexRows
                    FROM     sys.partitions
                    GROUP BY object_id ,
                                index_id
                    ),
                cteIndex
                AS ( SELECT   OBJECT_NAME(c.object_id) AS ObjectName ,
                                c.object_id ,
                                c.index_id ,
                                i.name COLLATE SQL_Latin1_General_CP1_CI_AS AS name ,
                                c.index_column_id ,
                                c.column_id ,
                                c.is_included_column ,
                                CASE WHEN @IncludeDataTypes = 0
                                        AND c.is_descending_key = 1
                                    THEN sc.name + ' DESC'
                                    WHEN @IncludeDataTypes = 0
                                        AND c.is_descending_key = 0 THEN sc.name
                                    WHEN @IncludeDataTypes = 1
                                        AND c.is_descending_key = 1
                                        AND c.is_included_column = 0
                                    THEN sc.name + ' DESC (' + t.name + ') '
                                    WHEN @IncludeDataTypes = 1
                                        AND c.is_descending_key = 0
                                        AND c.is_included_column = 0
                                    THEN sc.name + ' (' + t.name + ')'
                                    else sc.name
                                END AS ColumnName ,
                                '' AS filter_definition ,
                                ISNULL(dd.user_scans, 0) AS user_scans ,
                                ISNULL(dd.user_seeks, 0) AS user_seeks ,
                                ISNULL(dd.user_updates, 0) AS user_updates ,
                                ISNULL(dd.user_lookups, 0) AS user_lookups ,
                                CONVERT(DATETIME, ISNULL(dd.last_user_lookup,
                                                            '1901-01-01')) AS LastLookup ,
                                CONVERT(DATETIME, ISNULL(dd.last_user_scan,
                                                            '1901-01-01')) AS LastScan ,
                                CONVERT(DATETIME, ISNULL(dd.last_user_seek,
                                                            '1901-01-01')) AS LastSeek ,
                                i.fill_factor ,
                                c.is_descending_key ,
                                'NONE' as data_compression_desc ,
                                i.type_desc ,
                                i.is_unique ,
                                i.is_unique_constraint ,
                                i.is_primary_key ,
                                ci.SizeKB ,
                                cr.IndexRows ,
                                QUOTENAME(sch.name) + '.' + QUOTENAME(tbl.name) AS FullObjectName ,
                                ISNULL(dd.avg_fragmentation_in_percent, 0) as avg_fragmentation_in_percent
                    FROM     sys.indexes i
                                JOIN sys.index_columns c ON i.object_id = c.object_id
                                                            AND i.index_id = c.index_id
                                JOIN sys.columns sc ON c.object_id = sc.object_id
                                                    AND c.column_id = sc.column_id
                                INNER JOIN sys.tables tbl ON c.object_id = tbl.object_id
                                INNER JOIN sys.schemas sch ON sch.schema_id = tbl.schema_id
                                LEFT JOIN sys.types t ON sc.user_type_id = t.user_type_id
                                LEFT JOIN @IndexUsageStats dd ON i.object_id = dd.object_id
                                                                AND i.index_id = dd.index_id --and dd.database_id = db_id()
                                JOIN sys.partitions p ON i.object_id = p.object_id
                                                        AND i.index_id = p.index_id
                                JOIN cteIndexSizes ci ON i.object_id = ci.object_id
                                                        AND i.index_id = ci.index_id
                                JOIN cteRows cr ON i.object_id = cr.object_id
                                                AND i.index_id = cr.index_id
                    WHERE    i.object_id = CASE WHEN @TableName IS NULL
                                                THEN i.object_id
                                                else OBJECT_ID(@TableName)
                                            END
                    ),
                cteResults
                AS ( SELECT   ci.FullObjectName ,
                                ci.object_id ,
                                MAX(index_id) AS Index_Id ,
                                ci.type_desc
                                + CASE WHEN ci.is_primary_key = 1
                                    THEN ' (PRIMARY KEY)'
                                    WHEN ci.is_unique_constraint = 1
                                    THEN ' (UNIQUE CONSTRAINT)'
                                    WHEN ci.is_unique = 1 THEN ' (UNIQUE)'
                                    else ''
                                END AS IndexType ,
                                name AS IndexName ,
                                STUFF((SELECT   N', ' + ColumnName
                                    FROM     cteIndex ci2
                                    WHERE    ci2.name = ci.name
                                                AND ci2.is_included_column = 0
                                    GROUP BY ci2.index_column_id ,
                                                ci2.ColumnName
                                    ORDER BY ci2.index_column_id
                                FOR   XML PATH(N'') ,
                                        TYPE).value(N'.[1]', N'nvarchar(1000)'), 1,
                                    2, N'') AS KeyColumns ,
                                ISNULL(STUFF((SELECT    N',  ' + ColumnName
                                            FROM      cteIndex ci3
                                            WHERE     ci3.name = ci.name
                                                        AND ci3.is_included_column = 1
                                            GROUP BY  ci3.index_column_id ,
                                                        ci3.ColumnName
                                            ORDER BY  ci3.index_column_id
                                    FOR   XML PATH(N'') ,
                                                TYPE).value(N'.[1]',
                                                            N'nvarchar(1000)'), 1, 2,
                                            N''), '') AS IncludeColumns ,
                                ISNULL(filter_definition, '') AS FilterDefinition ,
                                ci.fill_factor ,
                                CASE WHEN ci.data_compression_desc = 'NONE' THEN ''
                                    else ci.data_compression_desc
                                END AS DataCompression ,
                                MAX(ci.user_seeks) + MAX(ci.user_scans)
                                + MAX(ci.user_lookups) AS IndexReads ,
                                MAX(ci.user_lookups) AS IndexLookups ,
                                ci.user_updates AS IndexUpdates ,
                                ci.SizeKB AS SizeKB ,
                                ci.IndexRows AS IndexRows ,
                                CASE WHEN LastScan > LastSeek
                                        AND LastScan > LastLookup THEN LastScan
                                    WHEN LastSeek > LastScan
                                        AND LastSeek > LastLookup THEN LastSeek
                                    WHEN LastLookup > LastScan
                                        AND LastLookup > LastSeek THEN LastLookup
                                    else ''
                                END AS MostRecentlyUsed ,
                                AVG(ci.avg_fragmentation_in_percent) as avg_fragmentation_in_percent
                    FROM     cteIndex ci
                    GROUP BY ci.ObjectName ,
                                ci.name ,
                                ci.filter_definition ,
                                ci.object_id ,
                                ci.LastLookup ,
                                ci.LastSeek ,
                                ci.LastScan ,
                                ci.user_updates ,
                                ci.fill_factor ,
                                ci.data_compression_desc ,
                                ci.type_desc ,
                                ci.is_primary_key ,
                                ci.is_unique ,
                                ci.is_unique_constraint ,
                                ci.SizeKB ,
                                ci.IndexRows ,
                                ci.FullObjectName
                    ), AllResults AS
                        (		 SELECT   c.FullObjectName ,
                                ISNULL(IndexType, 'STATISTICS') AS IndexType ,
                                ISNULL(IndexName, '') AS IndexName ,
                                ISNULL(KeyColumns, '') AS KeyColumns ,
                                ISNULL(IncludeColumns, '') AS IncludeColumns ,
                                FilterDefinition ,
                                fill_factor AS [FillFactor] ,
                                DataCompression ,
                                IndexReads ,
                                IndexUpdates ,
                                SizeKB ,
                                IndexRows ,
                                IndexLookups ,
                                MostRecentlyUsed ,
                                NULL AS StatsSampleRows ,
                                NULL AS StatsRowMods ,
                                NULL AS HistogramSteps ,
                                NULL AS StatsLastUpdated ,
                                avg_fragmentation_in_percent as IndexFragInPercent,
                                1 AS Ordering ,
                                c.object_id ,
                                c.Index_Id
                    FROM     cteResults c
                                INNER JOIN cteStatsInfo si ON si.object_id = c.object_id
                                                            AND si.stats_id = c.Index_Id
                        UNION
                    SELECT   QUOTENAME(sch.name) + '.' + QUOTENAME(tbl.name) AS FullObjectName ,
                                'STATISTICS' ,
                                stats_name ,
                                StatsColumns ,
                                '' ,
                                '' AS FilterDefinition ,
                                '' AS Fill_Factor ,
                                '' AS DataCompression ,
                                '' AS IndexReads ,
                                '' AS IndexUpdates ,
                                '' AS SizeKB ,
                                StatsRows AS IndexRows ,
                                '' AS IndexLookups ,
                                '' AS MostRecentlyUsed ,
                                SampleRows AS StatsSampleRows ,
                                RowMods AS StatsRowMods ,
                                csi.HistogramSteps ,
                                csi.StatsLastUpdated ,
                                '' as IndexFragInPercent,
                                2 ,
                                csi.object_id ,
                                csi.stats_id
                    FROM     cteStatsInfo csi
                    INNER JOIN sys.tables tbl ON csi.object_id = tbl.object_id
                                INNER JOIN sys.schemas sch ON sch.schema_id = tbl.schema_id
                                LEFT JOIN (SELECT si.object_id, si.stats_id
                                            FROM    cteResults c
                                            INNER JOIN cteStatsInfo si ON si.object_id = c.object_id
                                                                    AND si.stats_id = c.Index_Id ) AS x on csi.object_id = x.object_id and csi.stats_id = x.stats_id
                        WHERE x.object_id is null
                    )
            INSERT INTO @AllResults
            SELECT  row_number() OVER (ORDER BY FullObjectName) AS RowNum ,
                    FullObjectName ,
                    ISNULL(IndexType, 'STATISTICS') AS IndexType ,
                    IndexName ,
                    KeyColumns ,
                    ISNULL(IncludeColumns, '') AS IncludeColumns ,
                    FilterDefinition ,
                    [FillFactor] AS [FillFactor] ,
                    DataCompression ,
                    IndexReads ,
                    IndexUpdates ,
                    SizeKB ,
                    IndexRows ,
                    IndexLookups ,
                    MostRecentlyUsed ,
                    StatsSampleRows ,
                    StatsRowMods ,
                    HistogramSteps ,
                    StatsLastUpdated ,
                    IndexFragInPercent ,
                    object_id ,
                    index_id
            FROM    AllResults
                    $IncludeStatsPredicate
        OPTION  ( RECOMPILE );

        /* Only update the stats data on 2005 for a single table, otherwise the run time for this is a potential problem for large table/index volumes */
        if @TableName IS NOT NULL
        BEGIN

            DECLARE @StatsInfo2005 TABLE (Name nvarchar(128), Updated DATETIME, Rows BIGINT, RowsSampled BIGINT, Steps INT, Density INT, AverageKeyLength INT, StringIndex NVARCHAR(20))

            DECLARE @SqlCall NVARCHAR(2000), @RowNum INT;
            SELECT @RowNum = min(RowNum) FROM @AllResults;
            WHILE @RowNum IS NOT NULL
            BEGIN
                SELECT @SqlCall = 'dbcc show_statistics('+FullObjectName+', '+IndexName+') with stat_header' FROM @AllResults WHERE RowNum = @RowNum;
                INSERT INTO @StatsInfo2005 exec (@SqlCall);
                UPDATE @AllResults
                    SET StatsSampleRows = RowsSampled,
                    HistogramSteps = Steps,
                    StatsLastUpdated = Updated
                    FROM @StatsInfo2005
                    WHERE RowNum = @RowNum;
                DELETE FROM @StatsInfo2005
                SELECT @RowNum = min(RowNum) FROM @AllResults WHERE RowNum > @RowNum;
            END;

        END;

        UPDATE a
        SET a.StatsRowMods = i.rowmodctr
        FROM @AllResults a
            JOIN sys.sysindexes i ON a.object_id = i.id AND a.index_id = i.indid;

        SELECT	FullObjectName ,
                IndexType ,
                IndexName ,
                KeyColumns ,
                IncludeColumns ,
                FilterDefinition ,
                [FillFactor] ,
                DataCompression ,
                IndexReads ,
                IndexUpdates ,
                SizeKB ,
                IndexRows ,
                IndexLookups ,
                MostRecentlyUsed ,
                StatsSampleRows ,
                StatsRowMods ,
                HistogramSteps ,
                StatsLastUpdated ,
                IndexFragInPercent
        FROM @AllResults;"

        #endregion sizesQuery2005
    }
    process {
        Write-Message -Level Debug -Message $SizesQuery
        Write-Message -Level Debug -Message $SizesQuery2005

        foreach ($instance in $SqlInstance) {

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $InputObject += Get-DbaDatabase -SqlInstance $server -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent

            #Need to check the version of SQL
            if ($server.versionMajor -ge 10) {
                $indexesQuery = $SizesQuery
            } else {
                $indexesQuery = $SizesQuery2005
            }

            if (!$db.IsAccessible) {
                Stop-Function -Message "$db is not accessible. Skipping." -Continue
            }

            Write-Message -Level Debug -Message "$indexesQuery"
            try {
                $IndexDetails = $db.Query($indexesQuery)

                if (!$Raw) {
                    foreach ($detail in $IndexDetails) {
                        $recentlyused = [datetime]$detail.MostRecentlyUsed

                        if ($recentlyused.year -eq 1900) {
                            $recentlyused = $null
                        }

                        [pscustomobject]@{
                            ComputerName       = $server.ComputerName
                            InstanceName       = $server.ServiceName
                            SqlInstance        = $server.DomainInstanceName
                            Database           = $db.Name
                            Object             = $detail.FullObjectName
                            Index              = $detail.IndexName
                            IndexType          = $detail.IndexType
                            Statistics         = $detail.StatisticsName
                            KeyColumns         = $detail.KeyColumns
                            IncludeColumns     = $detail.IncludeColumns
                            FilterDefinition   = $detail.FilterDefinition
                            DataCompression    = $detail.DataCompression
                            IndexReads         = "{0:N0}" -f $detail.IndexReads
                            IndexUpdates       = "{0:N0}" -f $detail.IndexUpdates
                            Size               = "{0:N0}" -f $detail.SizeKB
                            IndexRows          = "{0:N0}" -f $detail.IndexRows
                            IndexLookups       = "{0:N0}" -f $detail.IndexLookups
                            MostRecentlyUsed   = $recentlyused
                            StatsSampleRows    = "{0:N0}" -f $detail.StatsSampleRows
                            StatsRowMods       = "{0:N0}" -f $detail.StatsRowMods
                            HistogramSteps     = $detail.HistogramSteps
                            StatsLastUpdated   = $detail.StatsLastUpdated
                            IndexFragInPercent = "{0:F2}" -f $detail.IndexFragInPercent
                        }
                    }
                }

                else {
                    foreach ($detail in $IndexDetails) {
                        $recentlyused = [datetime]$detail.MostRecentlyUsed

                        if ($recentlyused.year -eq 1900) {
                            $recentlyused = $null
                        }

                        [pscustomobject]@{
                            ComputerName       = $server.ComputerName
                            InstanceName       = $server.ServiceName
                            SqlInstance        = $server.DomainInstanceName
                            Database           = $db.Name
                            Object             = $detail.FullObjectName
                            Index              = $detail.IndexName
                            IndexType          = $detail.IndexType
                            Statistics         = $detail.StatisticsName
                            KeyColumns         = $detail.KeyColumns
                            IncludeColumns     = $detail.IncludeColumns
                            FilterDefinition   = $detail.FilterDefinition
                            DataCompression    = $detail.DataCompression
                            IndexReads         = $detail.IndexReads
                            IndexUpdates       = $detail.IndexUpdates
                            Size               = [dbasize]($detail.SizeKB * 1024)
                            IndexRows          = $detail.IndexRows
                            IndexLookups       = $detail.IndexLookups
                            MostRecentlyUsed   = $recentlyused
                            StatsSampleRows    = $detail.StatsSampleRows
                            StatsRowMods       = $detail.StatsRowMods
                            HistogramSteps     = $detail.HistogramSteps
                            StatsLastUpdated   = $detail.StatsLastUpdated
                            IndexFragInPercent = $detail.IndexFragInPercent
                        }
                    }
                }
            } catch {
                Stop-Function -Continue -ErrorRecord $_ -Message "Cannot process $db on $server"
            }
        }
    }
}