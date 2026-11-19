#nullable enable

namespace Dataplat.Dbatools.Commands;

// Second half of the process body (see ProcessScript partial).
public sealed partial class TestDbaDbCompressionCommand
{
    private const string ProcessScriptTail = """

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
            Write-Message -Level Debug -Message "SQL Statement: $sql" -FunctionName Test-DbaDbCompression -ModuleName "dbatools"
            [long]$instanceVersionNumber = $($server.VersionString).Replace(".", "")


            #If SQL Server 2016 SP1 (13.0.4001.0) or higher every version supports compression.
            if ($server.EngineEdition -ne "EnterpriseOrDeveloper" -and $instanceVersionNumber -lt 13040010) {
                Stop-Function -Message "Compression before SQLServer 2016 SP1 (13.0.4001.0) is only supported by enterprise, developer or evaluation edition. $server has version $($server.VersionString) and edition is $($server.EngineEdition)." -Target $db -Continue -FunctionName Test-DbaDbCompression
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

                if ($__excludeDatabaseBound) {
                    $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
                }
            } catch {
                Stop-Function -Message "Unable to gather list of databases for $instance" -Target $instance -ErrorRecord $_ -Continue -FunctionName Test-DbaDbCompression
            }

            foreach ($db in $dbs) {
                try {
                    $dbCompatibilityLevel = [int]($db.CompatibilityLevel.ToString().Replace('Version', ''))

                    Write-Message -Level Verbose -Message "Querying $instance - $db" -FunctionName Test-DbaDbCompression -ModuleName "dbatools"
                    if ($db.status -ne 'Normal' -or $db.IsAccessible -eq $false) {
                        Write-Message -Level Warning -Message "$db is not accessible." -Target $db -FunctionName Test-DbaDbCompression -ModuleName "dbatools"
                        Continue
                    }

                    if ($dbCompatibilityLevel -lt 100) {
                        Stop-Function -Message "$db has a compatibility level lower than Version100 and will be skipped." -Target $db -Continue -FunctionName Test-DbaDbCompression
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
                    Stop-Function -Message "Unable to query $instance - $db" -Target $db -ErrorRecord $_ -Continue -FunctionName Test-DbaDbCompression
                }
            }
        }

    [pscustomobject]@{
        __dbatoolsTdcProcessCarrier = $true
        StaleDatabase = $(if ([bool](Get-Variable -Name db -Scope 0 -ErrorAction Ignore)) { $db } else { $null }); StaleDatabaseAssigned = [bool](Get-Variable -Name db -Scope 0 -ErrorAction Ignore)
    }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $__excludeDatabaseBound $sqlSchemaWhere $sqlTableWhere $sqlRestrict $StaleDatabase $StaleDatabaseAssigned $EnableException @__commonParameters 3>&1 2>&1
""";
}
