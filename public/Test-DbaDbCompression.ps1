function Test-DbaDbCompression {
    <#
    .SYNOPSIS
        Analyzes user tables and indexes to recommend optimal compression settings for storage space reduction.
    .DESCRIPTION
        Performs comprehensive compression analysis on user tables and indexes to help DBAs identify storage optimization opportunities. Uses SQL Server's sp_estimate_data_compression_savings system procedure combined with workload pattern analysis to recommend the most effective compression type for each object.

        This function analyzes your database workload patterns (scan vs update ratios) and calculates potential space savings to recommend ROW compression, PAGE compression, or no compression. Longer server uptime provides more accurate workload statistics, so consider running Get-DbaUptime first to verify sufficient data collection time.

        The analysis examines operational statistics from sys.dm_db_index_operational_stats to determine usage patterns:
        - Percent_Update shows the percentage of update operations relative to total operations. Lower update percentages indicate better candidates for page compression.
        - Percent_Scan shows the percentage of scan operations relative to total operations. Higher scan percentages indicate better candidates for page compression.
        - Compression_Type_Recommendation provides specific guidance: 'PAGE', 'ROW', 'NO_GAIN' or '?' when the algorithm cannot determine the best option.

        The function automatically excludes tables that cannot be compressed: memory-optimized tables (SQL 2014+), tables with encrypted columns (SQL 2016+), graph tables (SQL 2017+), and tables with sparse columns. It only analyzes user tables with no existing compression and requires SQL Server 2016 SP1 or higher for non-Enterprise editions.

        Test-DbaDbCompression script derived from GitHub and the Tiger Team's repository: (https://github.com/Microsoft/tigertoolbox/tree/master/Evaluate-Compression-Gains)

        Be aware this may take considerable time on large databases as sp_estimate_data_compression_savings requires shared locks that can be blocked by concurrent activity. The analysis covers only ROW and PAGE compression options, not columnstore compression.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to analyze for compression opportunities. Accepts multiple database names and supports wildcards.
        Use this to focus analysis on specific databases rather than scanning all user databases on the instance.

    .PARAMETER ExcludeDatabase
        Specifies databases to skip during compression analysis. Helpful when you want to analyze most databases but exclude specific ones.
        Commonly used to skip databases that are already compressed, read-only, or contain sensitive data requiring separate analysis.

    .PARAMETER Schema
        Filters analysis to specific database schemas only. Accepts multiple schema names for targeted analysis.
        Use this when you need compression recommendations for tables in specific schemas like 'dbo', 'sales', or custom application schemas.

    .PARAMETER Table
        Filters analysis to specific table names only. Accepts multiple table names for focused compression analysis.
        Use this when investigating compression opportunities for known large tables or when validating compression recommendations for specific objects.

    .PARAMETER ResultSize
        Limits the number of objects analyzed per database to control analysis scope and execution time. No limit applied when unspecified.
        Use this on large databases to focus on the biggest storage consumers first, as compression analysis can be time-intensive on systems with thousands of tables.

    .PARAMETER Rank
        Determines how objects are prioritized when ResultSize limits are applied. Options are TotalPages (default), UsedPages, or TotalRows.
        TotalPages focuses on allocated storage, UsedPages targets actual data consumption, and TotalRows prioritizes by record count for different optimization strategies.

    .PARAMETER FilterBy
        Sets the granularity level for ResultSize filtering. Options are Partition (default), Index, or Table level filtering.
        Partition level provides most detailed analysis per partition, Index level groups by index, and Table level gives broader table-focused results.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .INPUTS
        Accepts a DbaInstanceParameter. Any collection of SQL Server Instance names or SMO objects can be piped to command.

    .OUTPUTS
        Returns a PSCustomObject with following fields: ComputerName, InstanceName, SqlInstance, Database, IndexName, Partition, IndexID, PercentScan, PercentUpdate, RowEstimatePercentOriginal, PageEstimatePercentOriginal, CompressionTypeRecommendation, SizeCurrent, SizeRequested, PercentCompression

    .NOTES
        Tags: Compression, Table
        Author: Jason Squires (@js_0505), jstexasdba@gmail.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaDbCompression

    .EXAMPLE
        PS C:\> Test-DbaDbCompression -SqlInstance localhost

        Returns results of all potential compression options for all databases for the default instance on the local host. Returns a recommendation of either Page, Row or NO_GAIN

    .EXAMPLE
        PS C:\> Test-DbaDbCompression -SqlInstance ServerA

        Returns results of all potential compression options for all databases on the instance ServerA

    .EXAMPLE
        PS C:\> Test-DbaDbCompression -SqlInstance ServerA -Database DBName | Out-GridView

        Returns results of all potential compression options for a single database DBName with the recommendation of either Page or Row or NO_GAIN in a nicely formatted GridView

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Test-DbaDbCompression -SqlInstance ServerA -ExcludeDatabase MyDatabase -SqlCredential $cred

        Returns results of all potential compression options for all databases except MyDatabase on instance ServerA using SQL credentials to authentication to ServerA.
        Returns the recommendation of either Page, Row or NO_GAIN

    .EXAMPLE
        PS C:\> Test-DbaDbCompression -SqlInstance ServerA -Schema Test -Table MyTable

        Returns results of all potential compression options for the Table Test.MyTable in instance ServerA on ServerA and ServerB.
        Returns the recommendation of either Page, Row or NO_GAIN.
        Returns a result for each partition of any Heap, Clustered or NonClustered index.

    .EXAMPLE
        PS C:\> Test-DbaDbCompression -SqlInstance ServerA, ServerB -ResultSize 10

        Returns results of all potential compression options for all databases on ServerA and ServerB.
        Returns the recommendation of either Page, Row or NO_GAIN.
        Returns results for the top 10 partitions by TotalPages used per database.

    .EXAMPLE
        PS C:\> ServerA | Test-DbaDbCompression -Schema Test -ResultSize 10 -Rank UsedPages -FilterBy Table

        Returns results of all potential compression options for all databases on ServerA containing a schema Test
        Returns results for the top 10 Tables by Used Pages per database.
        Results are split by Table, Index and Partition so more than 10 results may be returned.

    .EXAMPLE
        PS C:\> $servers = 'Server1','Server2'
        PS C:\> $servers | Test-DbaDbCompression -Database DBName | Out-GridView

        Returns results of all potential compression options for a single database DBName on Server1 or Server2
        Returns the recommendation of either Page, Row or NO_GAIN in a nicely formatted GridView

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Test-DbaDbCompression -SqlInstance ServerA -Database MyDB -SqlCredential $cred -Schema Test -Table Test1, Test2

        Returns results of all potential compression options for objects in Database MyDb on instance ServerA using SQL credentials to authentication to ServerA.
        Returns the recommendation of either Page, Row or NO_GAIN for tables with Schema Test and name in Test1 or Test2

    .EXAMPLE
        PS C:\> $servers = 'Server1','Server2'
        PS C:\> foreach ($svr in $servers) {
        >> Test-DbaDbCompression -SqlInstance $svr | Export-Csv -Path C:\temp\CompressionAnalysisPAC.csv -Append
        >> }

        This produces a full analysis of all your servers listed and is pushed to a csv for you to analyze.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$Schema,
        [string[]]$Table,
        [int]$ResultSize,
        [ValidateSet('TotalPages', 'UsedPages', 'TotalRows')]
        [string]$Rank = 'TotalPages',
        [ValidateSet('Partition', 'Index', 'Table')]
        [string]$FilterBy = 'Partition',
        [switch]$EnableException
    )

    begin {
        Write-Message -Level System -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"

        if ($Schema) {
            $sqlSchemaWhere = "AND s.name IN ('$($Schema -join "','")')"
        }

        if ($Table) {
            $sqlTableWhere = "AND t.name IN ('$($Table -join "','")')"
        }

        if ($ResultSize) {
            $sqlOrderBy = switch ($Rank) {
                UsedPages { 'UsedSpaceKB' }
                TotalRows { 'RowCounts' }
                default { 'TotalSpaceKB' }
            }

            if ($FilterBy -eq 'Table') {
                $sqlJoinFiltered = 'AND t.TableName = tdc.TableName COLLATE DATABASE_DEFAULT'
                $indexSQL = '0 as [IndexID]'
                $partitionSQL = '0 AS [Partition]'
                $groupBySQL = 's.Name, t.Name'
            } elseif ($FilterBy -eq 'Index') {
                $sqlJoinFiltered = 'AND t.TableName = tdc.TableName COLLATE DATABASE_DEFAULT AND t.IndexID = tdc.IndexID'
                $indexSQL = 'i.index_id as [IndexID]'
                $partitionSQL = '0 AS [Partition]'
                $groupBySQL = 's.Name, t.Name, i.index_id'
            } else {
                $sqlJoinFiltered = 'AND t.TableName = tdc.TableName COLLATE DATABASE_DEFAULT AND t.IndexID = tdc.IndexID AND t.[Partition] = tdc.[Partition]'
                $indexSQL = 'i.index_id as [IndexID]'
                $partitionSQL = 'p.partition_number AS [Partition]'
                $groupBySQL = 's.Name, t.Name, i.index_id, p.partition_number'
            }

            $sqlRestrict = "-- remove tables not in Top N
                With TopN(SchemaName, TableName, IndexID, [Partition], RowCounts, TotalSpaceKB, UsedSpaceKB) as
                (
                    SELECT TOP $ResultSize
                        s.name AS SchemaName,
                        t.name AS TableName,
                        $indexSQL,
                        $partitionSQL,
                        SUM(p.rows) AS RowCounts,
                        SUM(a.total_pages) * 8 AS TotalSpaceKB,
                        SUM(a.used_pages) * 8 AS UsedSpaceKB
                    FROM
                        sys.tables t
                    INNER JOIN
                        sys.indexes i ON t.object_id = i.object_id
                    INNER JOIN
                        sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
                    INNER JOIN
                        sys.allocation_units a ON p.partition_id = a.container_id
                    LEFT OUTER JOIN
                        sys.schemas s ON t.schema_id = s.schema_id
                    WHERE OBJECTPROPERTY(t.object_id, 'IsUserTable') = 1
                        AND p.data_compression_desc = 'NONE'
                        $sqlSchemaWhere
                        $sqlTableWhere
                    GROUP BY
                        $groupBySQL
                    ORDER BY
                        $sqlOrderBy DESC
                )
                DELETE tdc
                FROM ##TestDbaCompression tdc
                LEFT JOIN TopN t
                    ON t.SchemaName = tdc.[Schema] COLLATE DATABASE_DEFAULT
                    $sqlJoinFiltered
                WHERE t.IndexID IS NULL;"
        }
    }

    process {

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $Server.ConnectionContext.StatementTimeout = 0
            $sqlVersion = $(Get-DbaBuild -SqlInstance $server).Build.Major

            $sqlVersionRestrictions = @()

            if ($sqlVersion -ge 12) {
                $sqlVersionRestrictions += "
            BEGIN
                -- remove memory optimized tables
                DELETE tdc
                FROM ##TestDbaCompression tdc
                INNER JOIN sys.tables t
                    ON SCHEMA_NAME(t.schema_id) = tdc.[Schema] COLLATE DATABASE_DEFAULT
                    AND t.name = tdc.TableName COLLATE DATABASE_DEFAULT
                WHERE t.is_memory_optimized = 1
            END"
            }
            if ($sqlVersion -ge 13) {
                $sqlVersionRestrictions += "
            BEGIN
                -- remove tables with encrypted columns
                DELETE tdc
                FROM ##TestDbaCompression tdc
                INNER JOIN sys.tables t
                    ON SCHEMA_NAME(t.schema_id) = tdc.[Schema] COLLATE DATABASE_DEFAULT
                    AND t.name = tdc.TableName COLLATE DATABASE_DEFAULT
                INNER JOIN sys.columns c
                    ON t.object_id = c.object_id
                WHERE encryption_type IS NOT NULL
            END"
            }
            if ($sqlVersion -ge 14) {
                $sqlVersionRestrictions += "
            BEGIN
                -- remove graph (node/edge) tables
                DELETE tdc
                FROM ##TestDbaCompression tdc
                INNER JOIN sys.tables t
                    ON tdc.[Schema] = SCHEMA_NAME(t.schema_id) COLLATE DATABASE_DEFAULT
                    AND tdc.TableName = t.name COLLATE DATABASE_DEFAULT
                WHERE (is_node = 1 OR is_edge = 1)
            END"
            }
            $sql = "SET NOCOUNT ON;

IF OBJECT_ID('tempdb..##TestDbaCompression', 'U') IS NOT NULL
    DROP TABLE ##TestDbaCompression

IF OBJECT_ID('tempdb..##tmpEstimateRow', 'U') IS NOT NULL
    DROP TABLE ##tmpEstimateRow

IF OBJECT_ID('tempdb..##tmpEstimatePage', 'U') IS NOT NULL
    DROP TABLE ##tmpEstimatePage

CREATE TABLE ##TestDbaCompression (
    [Schema] SYSNAME
    ,[TableName] SYSNAME
    ,[ObjectId] INT
    ,[IndexName] SYSNAME NULL
    ,[Partition] INT
    ,[IndexID] INT
    ,[IndexType] VARCHAR(25)
    ,[RowCounts] BIGINT
    ,[PercentScan] SMALLINT
    ,[PercentUpdate] SMALLINT
    ,[RowEstimatePercentOriginal] BIGINT
    ,[PageEstimatePercentOriginal] BIGINT
    ,[CompressionTypeRecommendation] VARCHAR(7)
    ,[SizeCurrent] BIGINT
    ,[SizeRequested] BIGINT
    ,[PercentCompression] NUMERIC(10, 2)
    );

CREATE TABLE ##tmpEstimateRow (
    objname SYSNAME
    ,schname SYSNAME
    ,indid INT
    ,partnr INT
    ,SizeCurrent BIGINT
    ,SizeRequested BIGINT
    ,SampleCurrent BIGINT
    ,SampleRequested BIGINT
    );

CREATE TABLE ##tmpEstimatePage (
    objname SYSNAME
    ,schname SYSNAME
    ,indid INT
    ,partnr INT
    ,SizeCurrent BIGINT
    ,SizeRequested BIGINT
    ,SampleCurrent BIGINT
    ,SampleRequested BIGINT
    );

INSERT INTO ##TestDbaCompression (
    [Schema]
    ,[TableName]
    ,[ObjectId]
    ,[IndexName]
    ,[Partition]
    ,[IndexID]
    ,[IndexType]
    ,[RowCounts]
    ,[PercentScan]
    ,[PercentUpdate]
    )
    SELECT s.name AS [Schema]
    ,t.name AS [TableName]
    ,t.object_id AS [OBJECTID]
    ,x.name AS [IndexName]
    ,p.partition_number AS [Partition]
    ,x.index_id AS [IndexID]
    ,x.type_desc AS [IndexType]
    ,p.rows AS [RowCounts]
    ,NULL AS [PercentScan]
    ,NULL AS [PercentUpdate]
FROM sys.tables t
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
INNER JOIN sys.indexes x ON x.object_id = t.object_id
INNER JOIN sys.partitions p ON x.object_id = p.object_id
    AND x.index_id = p.index_id
WHERE OBJECTPROPERTY(t.object_id, 'IsUserTable') = 1
    AND p.data_compression_desc = 'NONE'
    $sqlSchemaWhere
    $sqlTableWhere
ORDER BY [TableName] ASC;

$sqlRestrict

BEGIN
    -- remove any tables with sparse columns
    DELETE tdc
    FROM ##TestDbaCompression tdc
    INNER JOIN sys.columns c
        ON tdc.ObjectId = c.object_id
    WHERE c.is_sparse = 1
END

$sqlVersionRestrictions

DECLARE @schema SYSNAME
    ,@tbname SYSNAME
    ,@ixid INT

DECLARE cur CURSOR FAST_FORWARD
FOR
SELECT [Schema]
    ,[TableName]
    ,[IndexID]
FROM ##TestDbaCompression

OPEN cur

FETCH NEXT
FROM cur
INTO @schema
    ,@tbname
    ,@ixid

WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @sqlcmd NVARCHAR(500)

    SET @sqlcmd = 'EXEC sp_estimate_data_compression_savings ''' + @schema + ''', ''' + @tbname + ''', ''' + CAST(@ixid AS VARCHAR) + ''', NULL, ''ROW''';

    INSERT INTO ##tmpEstimateRow (
        objname
        ,schname
        ,indid
        ,partnr
        ,SizeCurrent
        ,SizeRequested
        ,SampleCurrent
        ,SampleRequested
        )
    EXECUTE sp_executesql @sqlcmd

    SET @sqlcmd = 'EXEC sp_estimate_data_compression_savings ''' + @schema + ''', ''' + @tbname + ''', ''' + CAST(@ixid AS VARCHAR) + ''', NULL, ''PAGE''';

    INSERT INTO ##tmpEstimatePage (
        objname
        ,schname
        ,indid
        ,partnr
        ,SizeCurrent
        ,SizeRequested
        ,SampleCurrent
        ,SampleRequested
        )
    EXECUTE sp_executesql @sqlcmd

    FETCH NEXT
    FROM cur
    INTO @schema
        ,@tbname
        ,@ixid
END

CLOSE cur

DEALLOCATE cur;

--Update usage and partition_number - If database was restore the sys.dm_db_index_operational_stats will be empty until tables have accesses. Executing the sp_estimate_data_compression_savings first will make those entries appear
UPDATE ##TestDbaCompression
SET
 [PercentScan] =
     CASE WHEN (i.range_scan_count + i.leaf_insert_count + i.leaf_delete_count + i.leaf_update_count + i.leaf_page_merge_count + i.singleton_lookup_count) = 0 THEN 0
     ELSE i.range_scan_count * 100.0 / NULLIF((i.range_scan_count + i.leaf_insert_count + i.leaf_delete_count + i.leaf_update_count + i.leaf_page_merge_count + i.singleton_lookup_count), 0)
     END
 ,[PercentUpdate] =
    CASE WHEN (i.range_scan_count + i.leaf_insert_count + i.leaf_delete_count + i.leaf_update_count + i.leaf_page_merge_count + i.singleton_lookup_count) = 0 THEN 0
    ELSE i.leaf_update_count * 100.0 / NULLIF((i.range_scan_count + i.leaf_insert_count + i.leaf_delete_count + i.leaf_update_count + i.leaf_page_merge_count + i.singleton_lookup_count), 0)
    END
FROM sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL) i
INNER JOIN ##TestDbaCompression tmp
    ON tmp.ObjectId = i.object_id
    AND tmp.IndexID = i.index_id;


WITH tmp_cte (
    objname
    ,schname
    ,indid
    ,partnr
    ,pct_of_orig_row
    ,pct_of_orig_page
    ,SizeCurrent
    ,SizeRequested
    )
AS (
    SELECT tr.objname
        ,tr.schname
        ,tr.indid
        ,tr.partnr
        ,(tr.SampleRequested * 100) / CASE
            WHEN tr.SampleCurrent = 0
                THEN 1
            ELSE tr.SampleCurrent
            END AS pct_of_orig_row
        ,(tp.SampleRequested * 100) / CASE
            WHEN tp.SampleCurrent = 0
                THEN 1
            ELSE tp.SampleCurrent
            END AS pct_of_orig_page
        ,tr.SizeCurrent
        ,tr.SizeRequested
    FROM ##tmpEstimateRow tr
    INNER JOIN ##tmpEstimatePage tp ON tr.objname = tp.objname
        AND tr.schname = tp.schname
        AND tr.indid = tp.indid
        AND tr.partnr = tp.partnr
    )
UPDATE ##TestDbaCompression
SET [RowEstimatePercentOriginal] = tcte.pct_of_orig_row
    ,[PageEstimatePercentOriginal] = tcte.pct_of_orig_page
    ,SizeCurrent = tcte.SizeCurrent
    ,SizeRequested = tcte.SizeRequested
    ,PercentCompression = 100 - (CAST(tcte.[SizeRequested] AS NUMERIC(21, 2)) * 100 / (tcte.[SizeCurrent] - ABS(SIGN(tcte.[SizeCurrent])) + 1))
FROM tmp_cte tcte
    ,##TestDbaCompression tcomp
WHERE tcte.objname = tcomp.TableName
    AND tcte.schname = tcomp.[Schema]
    AND tcte.indid = tcomp.IndexID
    AND tcte.partnr = tcomp.Partition;

WITH tmp_cte2 (
    TableName
    ,[Schema]
    ,IndexID
    ,[CompressionTypeRecommendation]
    )
AS (
    SELECT TableName
        ,[Schema]
        ,IndexID
        ,CASE
            WHEN [RowCounts] = 0
                THEN '?'
            ELSE
                CASE
                    WHEN [RowEstimatePercentOriginal] >= 100
                        AND [PageEstimatePercentOriginal] >= 100
                        THEN 'NO_GAIN'
                    WHEN [PercentUpdate] >= 10
                        THEN 'ROW'
                    WHEN [PercentScan] <= 1
                        AND [PercentUpdate] <= 1
                        AND [RowEstimatePercentOriginal] < [PageEstimatePercentOriginal]
                        THEN 'ROW'
                    WHEN [PercentScan] <= 1
                        AND [PercentUpdate] <= 1
                        AND [RowEstimatePercentOriginal] > [PageEstimatePercentOriginal]
                        THEN 'PAGE'
                    WHEN [PercentScan] >= 60
                        AND [PercentUpdate] <= 5
                        THEN 'PAGE'
                    WHEN [PercentScan] <= 35
                        AND [PercentUpdate] <= 5
                        THEN '?'
                    ELSE 'ROW'
                END
        END
    FROM ##TestDbaCompression
    )
UPDATE ##TestDbaCompression
SET [CompressionTypeRecommendation] = tcte2.[CompressionTypeRecommendation]
FROM tmp_cte2 tcte2
    ,##TestDbaCompression tcomp2
WHERE tcte2.TableName = tcomp2.TableName
    AND tcte2.[Schema] = tcomp2.[Schema]
    AND tcte2.IndexID = tcomp2.IndexID;

SET NOCOUNT ON;

SELECT DBName = DB_NAME()
    ,[Schema]
    ,[TableName]
    ,[IndexName]
    ,[Partition]
    ,[IndexID]
    ,[IndexType]
    ,[PercentScan]
    ,[PercentUpdate]
    ,[RowEstimatePercentOriginal]
    ,[PageEstimatePercentOriginal]
    ,[CompressionTypeRecommendation]
    ,SizeCurrentKB = [SizeCurrent]
    ,SizeRequestedKB = [SizeRequested]
    ,PercentCompression
FROM ##TestDbaCompression;

IF OBJECT_ID('tempdb..##TestDbaCompression', 'U') IS NOT NULL
    DROP TABLE ##TestDbaCompression

IF OBJECT_ID('tempdb..##tmpEstimateRow', 'U') IS NOT NULL
    DROP TABLE ##tmpEstimateRow

IF OBJECT_ID('tempdb..##tmpEstimatePage', 'U') IS NOT NULL
    DROP TABLE ##tmpEstimatePage;

"
            Write-Message -Level Debug -Message "SQL Statement: $sql"
            [long]$instanceVersionNumber = $($server.VersionString).Replace(".", "")


            #If SQL Server 2016 SP1 (13.0.4001.0) or higher every version supports compression.
            if ($server.EngineEdition -ne "EnterpriseOrDeveloper" -and $instanceVersionNumber -lt 13040010) {
                Stop-Function -Message "Compression before SQLServer 2016 SP1 (13.0.4001.0) is only supported by enterprise, developer or evaluation edition. $server has version $($server.VersionString) and edition is $($server.EngineEdition)." -Target $db -Continue
            }
            #Filter Database list
            try {
                $dbs = $server.Databases | Where-Object IsAccessible

                if ($Database) {
                    $dbs = $dbs | Where-Object { $Database -contains $_.Name -and $_.IsSystemObject -eq 0 }
                }

                else {
                    $dbs = $dbs | Where-Object { $_.IsSystemObject -eq 0 }
                }

                if (Test-Bound "ExcludeDatabase") {
                    $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
                }
            } catch {
                Stop-Function -Message "Unable to gather list of databases for $instance" -Target $instance -ErrorRecord $_ -Continue
            }

            foreach ($db in $dbs) {
                try {
                    $dbCompatibilityLevel = [int]($db.CompatibilityLevel.ToString().Replace('Version', ''))

                    Write-Message -Level Verbose -Message "Querying $instance - $db"
                    if ($db.status -ne 'Normal' -or $db.IsAccessible -eq $false) {
                        Write-Message -Level Warning -Message "$db is not accessible." -Target $db
                        Continue
                    }

                    if ($dbCompatibilityLevel -lt 100) {
                        Stop-Function -Message "$db has a compatibility level lower than Version100 and will be skipped." -Target $db -Continue
                        Continue
                    }
                    #Execute query against individual database and add to output
                    foreach ($row in ($server.Query($sql, $db.Name))) {
                        [PSCustomObject]@{
                            ComputerName                  = $server.ComputerName
                            InstanceName                  = $server.ServiceName
                            SqlInstance                   = $server.DomainInstanceName
                            Database                      = $row.DBName
                            Schema                        = $row.Schema
                            TableName                     = $row.TableName
                            IndexName                     = $row.IndexName
                            Partition                     = $row.Partition
                            IndexID                       = $row.IndexID
                            IndexType                     = $row.IndexType
                            PercentScan                   = $row.PercentScan
                            PercentUpdate                 = $row.PercentUpdate
                            RowEstimatePercentOriginal    = $row.RowEstimatePercentOriginal
                            PageEstimatePercentOriginal   = $row.PageEstimatePercentOriginal
                            CompressionTypeRecommendation = $row.CompressionTypeRecommendation
                            SizeCurrent                   = [DbaSize]($row.SizeCurrentKB * 1024)
                            SizeRequested                 = [DbaSize]($row.SizeRequestedKB * 1024)
                            PercentCompression            = $row.PercentCompression
                        }
                    }
                } catch {
                    Stop-Function -Message "Unable to query $instance - $db" -Target $db -ErrorRecord $_ -Continue
                }
            }
        }
    }
}