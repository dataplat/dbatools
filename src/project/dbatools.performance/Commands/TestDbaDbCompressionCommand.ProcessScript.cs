#nullable enable

namespace Dataplat.Dbatools.Commands;

// Process-script constant - second partial per the 400-line law.
public sealed partial class TestDbaDbCompressionCommand
{

    // Process body carried as two compile-time concatenated const halves (byte-identical
    // composition) per the repo 400-line file law.
    private const string ProcessScript = ProcessScriptHead + "\n" + ProcessScriptTail;

    private const string ProcessScriptHead = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $__excludeDatabaseBound, $sqlSchemaWhere, $sqlTableWhere, $sqlRestrict, $StaleDatabase, $StaleDatabaseAssigned, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $__excludeDatabaseBound, $sqlSchemaWhere, $sqlTableWhere, $sqlRestrict, $StaleDatabase, $StaleDatabaseAssigned, $EnableException)
    # $db cross-record: source reads $db at the top of each instance iteration (before the per-instance
    # foreach) from the PREVIOUS instance's last db - a real DEF-012 carry. Assigned-flag gated so the
    # FIRST record (never-assigned) leaves $db undefined exactly as the source does (scope-walk parity).
    if ($null -ne $StaleDatabaseAssigned -and [bool]$StaleDatabaseAssigned) { $db = $StaleDatabase }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Test-DbaDbCompression
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
                $sqlVersionRestrictions += "
            BEGIN
                -- remove FileTables (SQL Server 2012+)
                DELETE tdc
                FROM ##TestDbaCompression tdc
                INNER JOIN sys.tables t
                    ON SCHEMA_NAME(t.schema_id) = tdc.[Schema] COLLATE DATABASE_DEFAULT
                    AND t.name = tdc.TableName COLLATE DATABASE_DEFAULT
                WHERE t.is_filetable = 1
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
                WHERE c.encryption_type IS NOT NULL
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
                WHERE (t.is_node = 1 OR t.is_edge = 1)
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

BEGIN
    -- remove tables with FileStream columns
    -- FileStream columns are incompatible with sp_estimate_data_compression_savings
    -- when RCSI or Snapshot Isolation is enabled
    DELETE tdc
    FROM ##TestDbaCompression tdc
    INNER JOIN sys.tables t
        ON SCHEMA_NAME(t.schema_id) = tdc.[Schema] COLLATE DATABASE_DEFAULT
        AND t.name = tdc.TableName COLLATE DATABASE_DEFAULT
    WHERE EXISTS (
        SELECT 1
        FROM sys.columns c
        WHERE c.object_id = t.object_id
        AND c.is_filestream = 1
    )
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

    SET @sqlcmd = 'EXEC sp_estimate_data_compression_savings ''' + @schema + ''', ''' + @tbname + ''', ''' + cast(@ixid AS VARCHAR) + ''', NULL, ''ROW''';

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

    SET @sqlcmd = 'EXEC sp_estimate_data_compression_savings ''' + @schema + ''', ''' + @tbname + ''', ''' + cast(@ixid AS VARCHAR) + ''', NULL, ''PAGE''';
""";
}
