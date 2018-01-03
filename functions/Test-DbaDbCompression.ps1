function Test-DbaDbCompression {
    <#
    .SYNOPSIS
        Returns tables and indexes with preferred compression setting.
     .DESCRIPTION
        This function returns the results of a full table/index compression analysis.
        This function returns the best option to date for either NONE, Page, or Row Compression.
        Remember Uptime is critical, the longer uptime, the more accurate the analysis is.
        You would probably be best if you utilized Get-DbaUptime first, before running this command.

        Test-DbaCompression script derived from GitHub and the tigertoolbox
        (https://github.com/Microsoft/tigertoolbox/tree/master/Evaluate-Compression-Gains)
        In the output, you will find the following information:
        Column Percent_Update shows the percentage of update operations on a specific table, index, or partition,
        relative to total operations on that object. The lower the percentage of Updates
        (that is, the table, index, or partition is infrequently updated), the better candidate it is for page compression.
        Column Percent_Scan shows the percentage of scan operations on a table, index, or partition, relative to total
        operations on that object. The higher the value of Scan (that is, the table, index, or partition is mostly scanned),
        the better candidate it is for page compression.
        Column Compression_Type_Recommendation can have four possible outputs indicating where there is most gain,
        if any: 'PAGE', 'ROW', 'NO_GAIN' or '?'. When the output is '?' this approach could not give a recommendation,
        so as a rule of thumb I would lean to ROW if the object suffers mainly UPDATES, or PAGE if mainly INSERTS,
        but this is where knowing your workload is essential. When the output is 'NO_GAIN' well, that means that according
        to sp_estimate_data_compression_savings no space gains will be attained when compressing, as in the above output example,
        where compressing would grow the affected object.

        Note: Note that this script will execute on the context of the current database.
        Also be aware that this may take awhile to execute on large objects, because if the IS locks taken by the
        sp_estimate_data_compression_savings cannot be honored, the SP will be blocked.

    .PARAMETER SqlInstance
        SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        SqlCredential object to connect as. If not specified, current Windows login will be used.

    .PARAMETER Database
        The database(s) to process - this list is autopopulated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is autopopulated from the server

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Author: Jason Squires (@js_0505, jstexasdba@gmail.com)
        Tags: Compression, Table, Database
        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
        https://dbatools.io/Test-DbaCompression

    .EXAMPLE
        Test-DbaCompression -SqlInstance localhost

        Returns all user database files and free space information for the local host

    .EXAMPLE
        Test-DbaCompression -SqlInstance ServerA -Database DBName | Out-GridView
        Returns results of all potential compression options for a single database
        with the recommendation of either Page or Row into and nicely formated GridView

    .EXAMPLE
        Test-DbaCompression -SqlInstance ServerA
        Returns results of all potential compression options for all databases
        with the recommendation of either Page or Row
    .EXAMPLE
        $cred = Get-Credential sqladmin
        Test-DbaCompression -SqlInstance ServerA -ExcludeDatabase Database -SqlCredential $cred
        Returns results of all potential compression options for all databases
        with the recommendation of either Page or Row

    .EXAMPLE
        $servers = 'Server1','Server2'
        foreach ($svr in $servers)
        {
            Test-DbaCompression -SqlInstance $svr | Export-Csv -Path C:\temp\CompressionAnalysisPAC.csv -Append
        }

        This produces a full analysis of all your servers listed and is pushed to a csv for you to
        analyize.
#>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch][Alias('Silent')]$EnableException
    )

    begin {
        Write-Message -Level System -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"
        $sql = "SET NOCOUNT ON;

IF OBJECT_ID('tempdb..##testdbacompression', 'U') IS NOT NULL
    DROP TABLE ##testdbacompression

IF OBJECT_ID('tempdb..##tmpEstimateRow', 'U') IS NOT NULL
    DROP TABLE ##tmpEstimateRow

IF OBJECT_ID('tempdb..##tmpEstimatePage', 'U') IS NOT NULL
    DROP TABLE ##tmpEstimatePage

CREATE TABLE ##testdbacompression (
    [Schema] SYSNAME
    ,[TableName] SYSNAME
    ,[IndexName] SYSNAME NULL
    ,[Partition] INT
    ,[IndexID] INT
    ,[IndexType] VARCHAR(12)
    ,[PercentScan] SMALLINT
    ,[PercentUpdate] SMALLINT
    ,[RowEstimatePercentOriginal] BIGINT
    ,[PageEstimatePercentOriginal] BIGINT
    ,[CompressionTypeRecommendation] VARCHAR(7)
    ,SizeCurrent BIGINT
    ,SizeRequested BIGINT
    ,PercentCompression NUMERIC(10, 2)
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

INSERT INTO ##testdbacompression (
    [Schema]
    ,[TableName]
    ,[IndexName]
    ,[Partition]
    ,[IndexID]
    ,[IndexType]
    ,[PercentScan]
    ,[PercentUpdate]
    )
SELECT s.NAME AS [Schema]
    ,o.NAME AS [TableName]
    ,x.NAME AS [IndexName]
    ,p.partition_number AS [Partition]
    ,x.Index_ID AS [IndexID]
    ,x.type_desc AS [IndexType]
    ,NULL AS [PercentScan]
    ,NULL AS [PercentUpdate]
FROM sys.objects o
INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
INNER JOIN sys.indexes x ON x.object_id = o.object_id
INNER JOIN sys.partitions p ON x.object_id = p.object_id
    AND x.Index_ID = p.Index_ID
WHERE objectproperty(o.object_id, 'IsUserTable') = 1
    AND p.data_compression_desc = 'NONE'
    AND p.rows > 0
ORDER BY [TableName] ASC;

DECLARE @schema SYSNAME
    ,@tbname SYSNAME
    ,@ixid INT

DECLARE cur CURSOR FAST_FORWARD
FOR
SELECT [Schema]
    ,[TableName]
    ,[IndexID]
FROM ##testdbacompression

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
UPDATE ##testdbacompression
SET  [PercentScan] = i.range_scan_count * 100.0 / NULLIF((i.range_scan_count + i.leaf_insert_count + i.leaf_delete_count + i.leaf_update_count + i.leaf_page_merge_count + i.singleton_lookup_count), 0)
    ,[PercentUpdate] = i.leaf_update_count * 100.0 / NULLIF((i.range_scan_count + i.leaf_insert_count + i.leaf_delete_count + i.leaf_update_count + i.leaf_page_merge_count + i.singleton_lookup_count), 0)
FROM sys.dm_db_index_operational_stats(db_id(), NULL, NULL, NULL) i
INNER JOIN ##testdbacompression tmp ON OBJECT_ID(tmp.TableName) = i.[object_id]
    AND tmp.IndexID = i.index_id;

WITH tmp_cte (
    objname
    ,schname
    ,indid
    ,pct_of_orig_row
    ,pct_of_orig_page
    ,SizeCurrent
    ,SizeRequested
    )
AS (
    SELECT tr.objname
        ,tr.schname
        ,tr.indid
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
    FROM ##tmpestimaterow tr
    INNER JOIN ##tmpestimatepage tp ON tr.objname = tp.objname
        AND tr.schname = tp.schname
        AND tr.indid = tp.indid
        AND tr.partnr = tp.partnr
    )
UPDATE ##testdbacompression
SET [RowEstimatePercentOriginal] = tcte.pct_of_orig_row
    ,[PageEstimatePercentOriginal] = tcte.pct_of_orig_page
    ,SizeCurrent = tcte.SizeCurrent
    ,SizeRequested = tcte.SizeRequested
    ,PercentCompression = 100 - (cast(tcte.[SizeRequested] AS NUMERIC(21, 2)) * 100 / (tcte.[SizeCurrent] - ABS(SIGN(tcte.[SizeCurrent])) + 1))
FROM tmp_cte tcte
    ,##testdbacompression tcomp
WHERE tcte.objname = tcomp.TableName
    AND tcte.schname = tcomp.[schema]
    AND tcte.indid = tcomp.IndexID;

WITH tmp_cte2 (
    TableName
    ,[schema]
    ,IndexID
    ,[CompressionTypeRecommendation]
    )
AS (
    SELECT TableName
        ,[schema]
        ,IndexID
        ,CASE
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
    FROM ##testdbacompression
    )
UPDATE ##testdbacompression
SET [CompressionTypeRecommendation] = tcte2.[CompressionTypeRecommendation]
FROM tmp_cte2 tcte2
    ,##testdbacompression tcomp2
WHERE tcte2.TableName = tcomp2.TableName
    AND tcte2.[schema] = tcomp2.[schema]
    AND tcte2.IndexID = tcomp2.IndexID;

SET NOCOUNT ON;

SELECT DBName = DB_Name()
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
FROM ##testdbacompression;

IF OBJECT_ID('tempdb..##setdbacompression', 'U') IS NOT NULL
    DROP TABLE ##testdbacompression

IF OBJECT_ID('tempdb..##tmpEstimateRow', 'U') IS NOT NULL
    DROP TABLE ##tmpEstimateRow

IF OBJECT_ID('tempdb..##tmpEstimatePage', 'U') IS NOT NULL
    DROP TABLE ##tmpEstimatePage;

"
    }

    process {

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level VeryVerbose -Message "Connecting to $instance" -Target $instance
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SourceSqlCredential -MinimumVersion 10
            }
            catch {
                Stop-Function -Message "Failed to process Instance $Instance" -ErrorRecord $_ -Target $instance -Continue
            }

            $Server.ConnectionContext.StatementTimeout = 0

            [long]$instanceVersionNumber = $($server.VersionString).Replace(".", "")


            #If SQL Server 2016 SP1 (13.0.4001.0) or higher every version supports compression.
            if ($Server.EngineEdition -ne "EnterpriseOrDeveloper" -and $instanceVersionNumber -lt 13040010) {
                Stop-Function -Message "Compresison before SQLServer 2016 SP1 (13.0.4001.0) is only supported by enterprise, developer or evaluation edition. $Server has version $($server.VersionString) and edition is $($Server.EngineEdition)." -Target $db -Continue
            }
            #If IncludeSystemDBs is true, include systemdbs
            #look at all databases, online/offline/accessible/inaccessible and tell user if a db can't be queried.
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
            }
            catch {
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
                        [pscustomobject]@{
                            ComputerName                  = $server.NetName
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
                            SizeCurrent                   = [dbasize]($row.SizeCurrentKB * 1024)
                            SizeRequested                 = [dbasize]($row.SizeRequestedKB * 1024)
                            PercentCompression            = $row.PercentCompression
                        }
                    }
                }
                catch {
                    Stop-Function -Message "Unable to query $instance - $db" -Target $db -ErrorRecord $_ -Continue
                }
            }
        }
    }
}
