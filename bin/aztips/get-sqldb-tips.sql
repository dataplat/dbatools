/*
Returns a set of tips to improve database design, health, and performance in Azure SQL Database.
For the latest version of the script, see https://aka.ms/sqldbtips
For a detailed description, see https://aka.ms/sqldbtipswiki
*/

-- Set to 1 to output tips as a JSON value
DECLARE @JSONOutput bit = 0;

-- Debug flag to return all tips regardless of database state
DECLARE @ReturnAllTips bit = 0;

-- Next three variables apply to "Top queries" (1320) hint, adjust if needed

-- The length of recent time interval to use when determining top queries. Default is last 1 hour.
-- Setting this to NULL disables the "Top queries" hint
DECLARE @QueryStoreIntervalMinutes int = 60;
/*
1 hour = 60 minutes
3 hours = 180 minutes
6 hours = 360 minutes
12 hours = 720 minutes
1 day = 1440 minutes
3 days = 4320 minutes
1 week = 10080 minutes
2 weeks = 20160 minutes
4 weeks = 40320 minutes
*/

-- To get top queries for a custom time interval, specify the start and end time here, in UTC
DECLARE @QueryStoreCustomTimeStart datetimeoffset -- = '2021-01-01 00:01 +00:00';
DECLARE @QueryStoreCustomTimeEnd datetimeoffset -- = '2021-12-31 23:59 +00:00';

-- Configurable thresholds
DECLARE

-- 1100: Minimum table size to be considered
@GuidLeadingColumnObjectMinSizeMB int = 1024,

-- 1120: The ratio of used space to database MAXSIZE that is considered as being too high
@UsedToMaxsizeSpaceThresholdRatio decimal(3,2) = 0.8,

-- 1130: The ratio of allocated space to database MAXSIZE that is considered as being too high
@AllocatedToMaxsizeSpaceThresholdRatio decimal(3,2) = 0.8,

-- 1140: The ratio of used space to allocated space that is considered as being too low
@UsedToAllocatedSpaceThresholdRatio decimal(3,2) = 0.3,

-- 1140: Minimum database size to be considered
@UsedToAllocatedSpaceDbMinSizeMB int = 10240,

-- 1150: Minimum percentage of CPU RG delay to be considered as significant CPU throttling
@CPUThrottlingDelayThresholdPercent decimal(5,2) = 20,

-- 1170: The ratio of all index reads to index writes that is considered as being too low
@IndexReadWriteThresholdRatio decimal(3,2) = 0.1,

-- 1180: The maximum ratio of updates to all operations to define "infrequent updates"
@CompressionPartitionUpdateRatioThreshold1 decimal(3,2) = 0.2,

-- 1180: The maximum ratio of updates to all operations to define "more frequent but not frequent enough updates"
@CompressionPartitionUpdateRatioThreshold2 decimal(3,2) = 0.5,

-- 1180: The minimum ratio of scans to all operations to define "frequent enough scans"
@CompressionPartitionScanRatioThreshold1 decimal(3,2) = 0.5,

-- 1180: Maximum CPU usage percentage to be considered as sufficient CPU headroom
@CompressionCPUHeadroomThreshold1 decimal(5,2) = 60,

-- 1180: Minimum CPU usage percentage to be considered as insufficient CPU headroom
@CompressionCPUHeadroomThreshold2 decimal(5,2) = 80,

-- 1180: Minimum required number of resource stats sampling intervals
@CompressionMinResourceStatSamples smallint = 30,

-- 1180: Minimum ratio of compressible to not compressible allocations for compression to be worthwhile
@CompressionMinEligibleRatio decimal(3,2) = 0.3,

-- 1190: Minimum log rate as percentage of SLO limit that is considered as being too high
@HighLogRateThresholdPercent decimal(5,2) = 80,

-- 1200: Minimum required per-db size of single-use plans to be considered as significant
@SingleUsePlanSizeThresholdMB int = 512,

-- 1200: The minimum ratio of single-use plans size to total plan size per database to be considered as significant
@SingleUseTotalPlanSizeRatioThreshold decimal(3,2) = 0.3,

-- 1210: The minimum user impact for a missing index to be considered as significant
@MissingIndexAvgUserImpactThreshold decimal(5,2) = 80,

-- 1220: The minimum size of redo queue on secondaries to be considered as significant
@RedoQueueSizeThresholdMB int = 1024,

-- 1230: The minimum ratio of governed IOPS issued to workload group IOPS limit that is considered significant
@GroupIORGAtLimitThresholdRatio decimal(3,2) = 0.9,

-- 1240: The minimum ratio of IO RG delay time to total IO stall time that is considered significant
@GroupIORGImpactRatio decimal(3,2) = 0.8,

-- 1250: The minimum ratio of governed IOPS issued to resource pool IOPS limit that is considered significant
@PoolIORGAtLimitThresholdRatio decimal(3,2) = 0.9,

-- 1260: The minimum ratio of IO RG delay time to total IO stall time that is considered significant
@PoolIORGImpactRatio decimal(3,2) = 0.8,

-- 1270: The minimum size of persistent version store (PVS) to be considered significant
@PVSMinimumSizeThresholdGB int = 100,

-- 1270: The minimum ratio of PVS size to database maxsize to be considered significant
@PVSToMaxSizeMinThresholdRatio decimal(3,2) = 0.3,

-- 1290: The minimum table size to be considered
@CCICandidateMinSizeGB int = 10,

-- 1300: The minimum geo-replication lag to be considered significant
@HighGeoReplLagMinThresholdSeconds int = 10,

-- 1300: The length of time window that defines recent geo-replicated transactions
@RecentGeoReplTranTimeWindowLengthSeconds int = 300,

-- 1310: The number of empty partitions at head end considered required
@MinEmptyPartitionCount tinyint = 2,

-- 1320: The number of top queries along each dimension (duration, CPU time, etc.) to consider
@QueryStoreTopQueryCount tinyint = 2,

-- 1330: The ratio of tempdb allocated data space to data MAXSIZE that is considered as being too high
@TempdbDataAllocatedToMaxsizeThresholdRatio decimal(3,2) = 0.8,

-- 1340: The ratio of tempdb used space to MAXSIZE that is considered as being too high
@TempdbDataUsedToMaxsizeThresholdRatio decimal(3,2) = 0.8,

-- 1350: The ratio of tempdb allocated log space to log MAXSIZE that is considered as being too high
@TempdbLogAllocatedToMaxsizeThresholdRatio decimal(3,2) = 0.6,

-- 1360: The minimum ratio of workload group workers used to maximum workers per workload group considered as being too high
@HighGroupWorkerUtilizationThresholdRatio decimal(3,2) = 0.8,

-- 1370: The minimum ratio of resource pool workers used to maximum workers per resource pool considered as being too high
@HighPoolWorkerUtilizationThresholdRatio decimal(3,2) = 0.7,

-- 1380: The length of recent time interval to use when filtering network connectivity ring buffer events
@NotableNetworkEventsIntervalMinutes int = 120,

-- 1380: Minimum duration of login considered too long
@NotableNetworkEventsSlowLoginThresholdMs int = 5000,

-- 1390: Minimum instance CPU percentage considered too high
@HighInstanceCPUThresholdPercent decimal(5,2) = 90,

-- 1390: Minimum duration of a high instance CPU period considered significant
@HighInstanceCPUMinThresholdSeconds int = 300,

-- 1400: Minimum change in object cardinality to be considered significant, expressed as a ratio of cardinality at last stats update to current cardinality
@StaleStatsCardinalityChangeMinDifference decimal(3,2) = 0.5,

-- 1400: The min ratio of mod count to object cardinality to be considered significant
@StaleStatsMinModificationCountRatio decimal(3,2) = 0.1,

-- 1400: The minimum number of days since last stats update to be considered significant
@StaleStatsMinAgeThresholdDays smallint = 30,

-- 1410: The minimum number of rows in a table for the lack of indexes to be considered significant
@NoIndexTablesMinRowCountThreshold int = 500,

-- 1410: The minimum ratio of the number of no-index tables to the total number of tables to be considered significant
@NoIndexMinTableCountRatio decimal(3,2) = 0.2,

-- 1420: The minimum ratio of total time spend waiting on locks during the interval to the interval duration to be considered significant
@LockBlockingTimeThresholdRatio decimal(3,2) = 0.1,

-- 1420: The minumum number of blocked tasks observed at the time of each 20-second snapshot to be considered significant
@LockBlockingBlockedTaskThreshold int = 1,

-- 1430: The minimum number of requests in an interval to start considering if query optimizations are high
@QueryOptimizationRequestCountThreshold smallint = 100,

-- 1430: The minimum ratio of query optimizations to the number of requests to be considered significant
@QueryOptimizationRequestThresholdRatio decimal(3,2) = 0.15,

-- 1450: The minimum local storage usage ratio to be considered significant
@MinLocalStorageQuotaUsageRatio decimal(3,2) = 0.85,

-- 1490: Values below this fill factor are considered too low
@FillFactorThreshold tinyint = 90,

-- 1510: The ratio of the remaining identity/sequence range to initial identity range (or maximum sequence range) that is considered too low
@IdentitySequenceRangeExhaustionThresholdRatio decimal(3,2) = 0.2,

-- 1540: The minimum number of total page compression attempts per partition of an index to consider it in this tip
@PageCompressionAttemptsThreshold int = 100,

-- 1540: The ratio of successful page compression attempts to total page compression attempts that is considered too low
@MinPageCompressionSuccessRatio decimal(3,2) = 0.5
;

DECLARE @ExecStartTime datetimeoffset = SYSDATETIMEOFFSET();

DECLARE @TipDefinition table (
                             tip_id smallint NOT NULL PRIMARY KEY,
                             tip_name nvarchar(60) NOT NULL UNIQUE,
                             confidence_percent decimal(3,0) NOT NULL CHECK (confidence_percent BETWEEN 0 AND 100),
                             tip_url nvarchar(200) NOT NULL,
                             required_permission varchar(50) NOT NULL,
                             execute_indicator bit NOT NULL
                             );
DECLARE @DetectedTip table (
                           tip_id smallint NOT NULL PRIMARY KEY,
                           details nvarchar(max) NULL
                           );
DECLARE @SkippedTip table (
                          tip_id smallint NOT NULL PRIMARY KEY,
                          reason nvarchar(30) NOT NULL DEFAULT ('lock timeout')
                          );

DECLARE @CRLF char(2) = CONCAT(CHAR(13), CHAR(10)),
        @NbspCRLF nchar(3) = CONCAT(NCHAR(160), NCHAR(13), NCHAR(10));

DECLARE @ViewServerStateIndicator bit = 1;

SET NOCOUNT ON;
SET LOCK_TIMEOUT 3000; -- abort if another request holds a lock on metadata for too long

BEGIN TRY

DECLARE @EngineEdition int = CAST(SERVERPROPERTY('EngineEdition') AS int);

IF @EngineEdition NOT IN (5,8)
    THROW 50005, 'This script is for Azure SQL Database and Azure SQL Managed Instance only.', 1;

-- Bail out if current CPU utilization is very high, to avoid impacting workloads
IF EXISTS (
          SELECT 1
          FROM (
               SELECT avg_cpu_percent,
                      avg_instance_cpu_percent,
                      LEAD(end_time) OVER (ORDER BY end_time) AS next_end_time
               FROM sys.dm_db_resource_stats
               ) AS rs
          WHERE next_end_time IS NULL
                AND
                (
                rs.avg_cpu_percent > 95
                OR
                rs.avg_instance_cpu_percent > 97
                )
          )
    THROW 50010, 'CPU utilization is too high. Execute the script at a later time.', 1;

IF DB_NAME() = 'master' AND @EngineEdition = 5
    THROW 50015, 'Execute this script in a user database, not in the ''master'' database.', 1;

-- Define all tips
INSERT INTO @TipDefinition (execute_indicator, tip_id, tip_name, confidence_percent, tip_url, required_permission)
VALUES
(1, 1000, 'Reduce MAXDOP on all replicas',                             90, 'https://aka.ms/sqldbtipswiki#tip_id-1000', 'VIEW DATABASE STATE'),
(1, 1010, 'Reduce MAXDOP on primary',                                  90, 'https://aka.ms/sqldbtipswiki#tip_id-1010', 'VIEW DATABASE STATE'),
(1, 1020, 'Reduce MAXDOP on secondaries',                              90, 'https://aka.ms/sqldbtipswiki#tip_id-1020', 'VIEW DATABASE STATE'),
(1, 1030, 'Database compatibility level is not the latest',            70, 'https://aka.ms/sqldbtipswiki#tip_id-1030', 'VIEW DATABASE STATE'),
(1, 1040, 'Enable auto-create statistics',                             95, 'https://aka.ms/sqldbtipswiki#tip_id-1040', 'VIEW DATABASE STATE'),
(1, 1050, 'Enable auto-update statistics',                             95, 'https://aka.ms/sqldbtipswiki#tip_id-1050', 'VIEW DATABASE STATE'),
(1, 1060, 'Enable Read Committed Snapshot Isolation (RCSI)',           80, 'https://aka.ms/sqldbtipswiki#tip_id-1060', 'VIEW DATABASE STATE'),
(1, 1070, 'Enable Query Store',                                        90, 'https://aka.ms/sqldbtipswiki#tip_id-1070', 'VIEW DATABASE STATE'),
(1, 1071, 'Change Query Store operation mode to read-write',           90, 'https://aka.ms/sqldbtipswiki#tip_id-1071', 'VIEW DATABASE STATE'),
(1, 1072, 'Change Query Store capture mode from NONE to AUTO/ALL',     90, 'https://aka.ms/sqldbtipswiki#tip_id-1072', 'VIEW DATABASE STATE'),
(1, 1080, 'Disable AUTO_SHRINK',                                       95, 'https://aka.ms/sqldbtipswiki#tip_id-1080', 'VIEW DATABASE STATE'),
(1, 1100, 'Avoid GUID leading columns in btree indexes',               60, 'https://aka.ms/sqldbtipswiki#tip_id-1100', 'VIEW DATABASE STATE'),
(1, 1110, 'Enable FLGP auto-tuning',                                   95, 'https://aka.ms/sqldbtipswiki#tip_id-1110', 'VIEW DATABASE STATE'),
(1, 1120, 'Used data size is close to MAXSIZE',                        95, 'https://aka.ms/sqldbtipswiki#tip_id-1120', 'VIEW DATABASE STATE'),
(1, 1130, 'Allocated data size is close to MAXSIZE',                   60, 'https://aka.ms/sqldbtipswiki#tip_id-1130', 'VIEW DATABASE STATE'),
(1, 1140, 'Allocated data size is much larger than used data size',    50, 'https://aka.ms/sqldbtipswiki#tip_id-1140', 'VIEW DATABASE STATE'),
(1, 1150, 'Recent CPU throttling found',                               90, 'https://aka.ms/sqldbtipswiki#tip_id-1150', 'VIEW SERVER STATE'),
(1, 1160, 'Recent out of memory errors found',                         80, 'https://aka.ms/sqldbtipswiki#tip_id-1160', 'VIEW SERVER STATE'),
(1, 1165, 'Recent memory grant waits and timeouts found',              70, 'https://aka.ms/sqldbtipswiki#tip_id-1165', 'VIEW SERVER STATE'),
(1, 1170, 'Nonclustered indexes with low reads found',                 60, 'https://aka.ms/sqldbtipswiki#tip_id-1170', 'VIEW SERVER STATE'),
(1, 1180, 'ROW or PAGE compression opportunities may exist',           65, 'https://aka.ms/sqldbtipswiki#tip_id-1180', 'VIEW SERVER STATE'),
(1, 1190, 'Transaction log IO is close to limit',                      70, 'https://aka.ms/sqldbtipswiki#tip_id-1190', 'VIEW DATABASE STATE'),
(1, 1200, 'Plan cache is bloated by single-use plans',                 90, 'https://aka.ms/sqldbtipswiki#tip_id-1200', 'VIEW DATABASE STATE'),
(1, 1210, 'Missing indexes may be impacting performance',              70, 'https://aka.ms/sqldbtipswiki#tip_id-1210', 'VIEW SERVER STATE'),
(1, 1220, 'Redo queue on a secondary replica is large',                60, 'https://aka.ms/sqldbtipswiki#tip_id-1220', 'VIEW DATABASE STATE'),
(1, 1230, 'Data IOPS are close to workload group limit',               70, 'https://aka.ms/sqldbtipswiki#tip_id-1230', 'VIEW SERVER STATE'),
(1, 1240, 'Workload group IO governance impact is significant',        40, 'https://aka.ms/sqldbtipswiki#tip_id-1240', 'VIEW SERVER STATE'),
(1, 1250, 'Data IOPS are close to resource pool limit',                70, 'https://aka.ms/sqldbtipswiki#tip_id-1250', 'VIEW SERVER STATE'),
(1, 1260, 'Resource pool IO governance impact is significant',         40, 'https://aka.ms/sqldbtipswiki#tip_id-1260', 'VIEW SERVER STATE'),
(1, 1270, 'Persistent Version Store size is large',                    70, 'https://aka.ms/sqldbtipswiki#tip_id-1270', 'VIEW SERVER STATE'),
(1, 1280, 'Paused resumable index operations found',                   90, 'https://aka.ms/sqldbtipswiki#tip_id-1280', 'VIEW DATABASE STATE'),
(1, 1290, 'Clustered columnstore candidates found',                    50, 'https://aka.ms/sqldbtipswiki#tip_id-1290', 'VIEW SERVER STATE'),
(1, 1300, 'Geo-replication state may be unhealthy',                    70, 'https://aka.ms/sqldbtipswiki#tip_id-1300', 'VIEW DATABASE STATE'),
(1, 1310, 'Last partitions are not empty',                             80, 'https://aka.ms/sqldbtipswiki#tip_id-1310', 'VIEW DATABASE STATE'),
(1, 1320, 'Top queries should be investigated and tuned',              90, 'https://aka.ms/sqldbtipswiki#tip_id-1320', 'VIEW DATABASE STATE'),
(1, 1330, 'Tempdb data allocated size is close to MAXSIZE',            70, 'https://aka.ms/sqldbtipswiki#tip_id-1330', 'tempdb.VIEW DATABASE STATE'),
(1, 1340, 'Tempdb data used size is close to MAXSIZE',                 95, 'https://aka.ms/sqldbtipswiki#tip_id-1340', 'tempdb.VIEW DATABASE STATE'),
(1, 1350, 'Tempdb log allocated size is close to MAXSIZE',             80, 'https://aka.ms/sqldbtipswiki#tip_id-1350', 'tempdb.VIEW DATABASE STATE'),
(1, 1360, 'Worker utilization is close to workload group limit',       80, 'https://aka.ms/sqldbtipswiki#tip_id-1360', 'VIEW SERVER STATE'),
(1, 1370, 'Worker utilization is close to resource pool limit',        80, 'https://aka.ms/sqldbtipswiki#tip_id-1370', 'VIEW SERVER STATE'),
(1, 1380, 'Notable network connectivity events found',                 30, 'https://aka.ms/sqldbtipswiki#tip_id-1380', 'VIEW SERVER STATE'),
(1, 1390, 'Instance CPU utilization is high',                          60, 'https://aka.ms/sqldbtipswiki#tip_id-1390', 'VIEW DATABASE STATE'),
(1, 1400, 'Some statistics may be out of date',                        70, 'https://aka.ms/sqldbtipswiki#tip_id-1400', 'VIEW DATABASE STATE'),
(1, 1410, 'Many tables do not have any indexes',                       60, 'https://aka.ms/sqldbtipswiki#tip_id-1410', 'VIEW DATABASE STATE'),
(1, 1420, 'Significant lock blocking has recently occurred',           70, 'https://aka.ms/sqldbtipswiki#tip_id-1420', 'VIEW SERVER STATE'),
(1, 1430, 'The number of recent query optimizations is high',          80, 'https://aka.ms/sqldbtipswiki#tip_id-1430', 'VIEW SERVER STATE'),
(1, 1440, 'Row locks or page locks are disabled for some indexes',     90, 'https://aka.ms/sqldbtipswiki#tip_id-1440', 'VIEW DATABASE STATE'),
(1, 1450, 'Allocated local storage is close to maximum local storage', 90, 'https://aka.ms/sqldbtipswiki#tip_id-1450', 'VIEW SERVER STATE'),
(1, 1460, 'Column collation does not match database collation',        70, 'https://aka.ms/sqldbtipswiki#tip_id-1460', 'VIEW DATABASE STATE'),
(1, 1470, 'Indexes with excessively large keys found',                 90, 'https://aka.ms/sqldbtipswiki#tip_id-1470', 'VIEW DATABASE STATE'),
(1, 1480, 'Disabled indexes found',                                    90, 'https://aka.ms/sqldbtipswiki#tip_id-1480', 'VIEW DATABASE STATE'),
(1, 1490, 'Indexes with low fill factor found',                        80, 'https://aka.ms/sqldbtipswiki#tip_id-1490', 'VIEW DATABASE STATE'),
(1, 1500, 'Non-unique clustered indexes found',                        65, 'https://aka.ms/sqldbtipswiki#tip_id-1500', 'VIEW DATABASE STATE'),
(1, 1510, 'Most of the IDENTITY range is used',                        95, 'https://aka.ms/sqldbtipswiki#tip_id-1510', 'VIEW DATABASE STATE'),
(1, 1520, 'Most of the sequence range is used',                        95, 'https://aka.ms/sqldbtipswiki#tip_id-1520', 'VIEW DATABASE STATE'),
(1, 1530, 'Disabled or not trusted constraints found',                 90, 'https://aka.ms/sqldbtipswiki#tip_id-1530', 'VIEW DATABASE STATE'),
(1, 1540, 'Page compression is ineffective for some indexes',          90, 'https://aka.ms/sqldbtipswiki#tip_id-1540', 'VIEW SERVER STATE')
;

-- Top queries
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1320) AND execute_indicator = 1)
BEGIN

BEGIN TRY

DROP TABLE IF EXISTS #query_wait_stats_summary;

CREATE TABLE #query_wait_stats_summary
(
query_hash binary(8) PRIMARY KEY,
ranked_wait_categories varchar(max) NOT NULL
);

DECLARE @QueryStoreTimeFrom datetimeoffset = IIF(
                                                (@QueryStoreCustomTimeStart IS NULL OR @QueryStoreCustomTimeEnd IS NULL) AND @QueryStoreIntervalMinutes IS NOT NULL,
                                                DATEADD(minute, -@QueryStoreIntervalMinutes, SYSDATETIMEOFFSET()),
                                                @QueryStoreCustomTimeStart
                                                ),
        @QueryStoreTimeThru datetimeoffset = IIF(
                                                (@QueryStoreCustomTimeStart IS NULL OR @QueryStoreCustomTimeEnd IS NULL) AND @QueryStoreIntervalMinutes IS NOT NULL,
                                                SYSDATETIMEOFFSET(),
                                                @QueryStoreCustomTimeEnd
                                                );

-- Opportunistically update statistics on Query Store internal tables
BEGIN TRY

UPDATE STATISTICS sys.plan_persist_context_settings;
UPDATE STATISTICS sys.plan_persist_plan;
UPDATE STATISTICS sys.plan_persist_plan_feedback;
UPDATE STATISTICS sys.plan_persist_query;
UPDATE STATISTICS sys.plan_persist_query_hints;
UPDATE STATISTICS sys.plan_persist_query_template_parameterization;
UPDATE STATISTICS sys.plan_persist_query_text;
UPDATE STATISTICS sys.plan_persist_runtime_stats;
UPDATE STATISTICS sys.plan_persist_runtime_stats_interval;
UPDATE STATISTICS sys.plan_persist_wait_stats;

END TRY
BEGIN CATCH
    RAISERROR('Query Store statistics not updated, possibly due to insufficient permissions', 10, 1);
END CATCH;

-- query wait stats aggregated by query hash and wait category
WITH
query_wait_stats AS
(
SELECT q.query_hash,
       ws.wait_category_desc,
       SUM(ws.total_query_wait_time_ms) AS total_query_wait_time_ms
FROM sys.query_store_query AS q
INNER JOIN sys.query_store_plan AS p
ON q.query_id = p.query_id
INNER JOIN sys.query_store_wait_stats AS ws
ON p.plan_id = ws.plan_id
INNER JOIN sys.query_store_runtime_stats_interval AS rsi
ON ws.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE q.is_internal_query = 0
      AND
      q.is_clouddb_internal_query = 0
      AND
      rsi.start_time >= @QueryStoreTimeFrom
      AND
      rsi.start_time <= @QueryStoreTimeThru
GROUP BY q.query_hash,
         ws.wait_category_desc
),
query_wait_stats_ratio AS
(
SELECT query_hash,
       total_query_wait_time_ms,
       CONCAT(
             wait_category_desc,
             ' (',
             CAST(CAST(total_query_wait_time_ms * 1. / SUM(total_query_wait_time_ms) OVER (PARTITION BY query_hash) AS decimal(4,3)) AS varchar(5)),
             ')'
             ) AS wait_category_desc -- append relative wait weight to category name
FROM query_wait_stats
),
-- query wait stats aggregated by query hash, with concatenated list of wait categories ranked with longest first
query_wait_stats_summary AS
(
SELECT query_hash,
       STRING_AGG(wait_category_desc, ' | ')
       WITHIN GROUP (ORDER BY total_query_wait_time_ms DESC)
       AS ranked_wait_categories
FROM query_wait_stats_ratio
GROUP BY query_hash
)
INSERT INTO #query_wait_stats_summary (query_hash, ranked_wait_categories) -- persist into a temp table for perf reasons
SELECT query_hash, ranked_wait_categories
FROM query_wait_stats_summary
OPTION (RECOMPILE);

UPDATE STATISTICS #query_wait_stats_summary;

-- query runtime stats aggregated by query hash
WITH
query_runtime_stats AS
(
SELECT q.query_hash,
       COUNT(DISTINCT(q.query_id)) AS count_queries,
       MAX(q.query_id) AS query_id,
       COUNT(DISTINCT(p.plan_id)) AS count_plans,
       MAX(p.plan_id) AS plan_id,
       SUM(IIF(rs.execution_type_desc = 'Regular', rs.count_executions, 0)) AS count_regular_executions,
       SUM(IIF(rs.execution_type_desc = 'Aborted', rs.count_executions, 0)) AS count_aborted_executions,
       SUM(IIF(rs.execution_type_desc = 'Exception', rs.count_executions, 0)) AS count_exception_executions,
       SUM(rs.count_executions) AS count_executions,
       SUM(rs.avg_cpu_time * rs.count_executions) AS total_cpu_time,
       SUM(rs.avg_duration * rs.count_executions) AS total_duration,
       SUM(rs.avg_logical_io_reads * rs.count_executions) AS total_logical_io_reads,
       SUM(rs.avg_physical_io_reads * rs.count_executions) AS total_physical_io_reads,
       SUM(rs.avg_query_max_used_memory * rs.count_executions) AS total_query_max_used_memory,
       SUM(rs.avg_log_bytes_used * rs.count_executions) AS total_log_bytes_used,
       SUM(rs.avg_tempdb_space_used * rs.count_executions) AS total_tempdb_space_used,
       SUM(rs.avg_dop * rs.count_executions) AS total_dop
FROM sys.query_store_query AS q
INNER JOIN sys.query_store_plan AS p
ON q.query_id = p.query_id
INNER JOIN sys.query_store_runtime_stats AS rs
ON p.plan_id = rs.plan_id
INNER JOIN sys.query_store_runtime_stats_interval AS rsi
ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE q.is_internal_query = 0
      AND
      q.is_clouddb_internal_query = 0
      AND
      rsi.start_time >= @QueryStoreTimeFrom
      AND
      rsi.start_time <= @QueryStoreTimeThru
GROUP BY q.query_hash
),
-- rank queries along multiple dimensions (cpu, duration, etc.), without ties
query_rank AS
(
SELECT rs.query_hash,
       rs.count_queries,
       rs.query_id,
       rs.count_plans,
       rs.plan_id,
       rs.count_regular_executions,
       rs.count_aborted_executions,
       rs.count_exception_executions,
       ROW_NUMBER() OVER (ORDER BY rs.total_cpu_time DESC) AS cpu_time_rank,
       ROW_NUMBER() OVER (ORDER BY rs.total_duration DESC) AS duration_rank,
       ROW_NUMBER() OVER (ORDER BY rs.total_logical_io_reads DESC) AS logical_io_reads_rank,
       ROW_NUMBER() OVER (ORDER BY rs.total_physical_io_reads DESC) AS physical_io_reads_rank,
       ROW_NUMBER() OVER (ORDER BY rs.count_executions DESC) AS executions_rank,
       ROW_NUMBER() OVER (ORDER BY rs.total_query_max_used_memory DESC) AS total_query_max_used_memory_rank,
       ROW_NUMBER() OVER (ORDER BY rs.total_log_bytes_used DESC) AS total_log_bytes_used_rank,
       ROW_NUMBER() OVER (ORDER BY rs.total_tempdb_space_used DESC) AS total_tempdb_space_used_rank,
       ROW_NUMBER() OVER (ORDER BY rs.total_dop DESC) AS total_dop_rank,
       -- if total_cpu_time for a query is 2 times less than for the immediately higher query in the rank order, do not consider it a top query
       -- top_cpu_cutoff_indicator = 0 signifies a top query; the query where top_cpu_cutoff_indicator is 1 and any query with lower rank will be filtered out
       IIF(rs.total_cpu_time * 1. / NULLIF(LEAD(rs.total_cpu_time) OVER (ORDER BY rs.total_cpu_time), 0) < 0.5, 1, 0) AS top_cpu_cutoff_indicator,
       IIF(rs.total_duration * 1. / NULLIF(LEAD(rs.total_duration) OVER (ORDER BY rs.total_duration), 0) < 0.5, 1, 0) AS top_duration_cutoff_indicator,
       IIF(rs.total_logical_io_reads * 1. / NULLIF(LEAD(rs.total_logical_io_reads) OVER (ORDER BY rs.total_logical_io_reads), 0) < 0.5, 1, 0) AS top_logical_io_reads_cutoff_indicator,
       IIF(rs.total_physical_io_reads * 1. / NULLIF(LEAD(rs.total_physical_io_reads) OVER (ORDER BY rs.total_physical_io_reads), 0) < 0.5, 1, 0) AS top_physical_io_reads_cutoff_indicator,
       IIF(rs.count_executions * 1. / NULLIF(LEAD(rs.count_executions) OVER (ORDER BY rs.count_executions), 0) < 0.5, 1, 0) AS top_executions_cutoff_indicator,
       IIF(rs.total_query_max_used_memory * 1. / NULLIF(LEAD(rs.total_query_max_used_memory) OVER (ORDER BY rs.total_query_max_used_memory), 0) < 0.5, 1, 0) AS top_memory_cutoff_indicator,
       IIF(rs.total_log_bytes_used * 1. / NULLIF(LEAD(rs.total_log_bytes_used) OVER (ORDER BY rs.total_log_bytes_used), 0) < 0.5, 1, 0) AS top_log_bytes_cutoff_indicator,
       IIF(rs.total_tempdb_space_used * 1. / NULLIF(LEAD(rs.total_tempdb_space_used) OVER (ORDER BY rs.total_tempdb_space_used), 0) < 0.5, 1, 0) AS top_tempdb_cutoff_indicator,
       IIF(rs.total_dop * 1. / NULLIF(LEAD(rs.total_dop) OVER (ORDER BY rs.total_dop), 0) < 0.5, 1, 0) AS top_dop_cutoff_indicator,
       ws.ranked_wait_categories
FROM query_runtime_stats AS rs
LEFT JOIN #query_wait_stats_summary AS ws -- outer join in case wait stats collection is not enabled or waits are not available otherwise
ON rs.query_hash = ws.query_hash
),
-- add running sums of cut off indicators along rank order; indicators will remain 0 for top queries, and >0 otherwise
top_query_rank AS
(
SELECT *,
       SUM(top_cpu_cutoff_indicator) OVER (ORDER BY cpu_time_rank ROWS UNBOUNDED PRECEDING) AS top_cpu_indicator,
       SUM(top_duration_cutoff_indicator) OVER (ORDER BY duration_rank ROWS UNBOUNDED PRECEDING) AS top_duration_indicator,
       SUM(top_logical_io_reads_cutoff_indicator) OVER (ORDER BY logical_io_reads_rank ROWS UNBOUNDED PRECEDING) AS top_logical_io_indicator,
       SUM(top_physical_io_reads_cutoff_indicator) OVER (ORDER BY physical_io_reads_rank ROWS UNBOUNDED PRECEDING) AS top_physical_io_indicator,
       SUM(top_executions_cutoff_indicator) OVER (ORDER BY executions_rank ROWS UNBOUNDED PRECEDING) AS top_executions_indicator,
       SUM(top_memory_cutoff_indicator) OVER (ORDER BY total_query_max_used_memory_rank ROWS UNBOUNDED PRECEDING) AS top_memory_indicator,
       SUM(top_log_bytes_cutoff_indicator) OVER (ORDER BY total_log_bytes_used_rank ROWS UNBOUNDED PRECEDING) AS top_log_bytes_indicator,
       SUM(top_tempdb_cutoff_indicator) OVER (ORDER BY total_tempdb_space_used_rank ROWS UNBOUNDED PRECEDING) AS top_tempdb_indicator,
       SUM(top_dop_cutoff_indicator) OVER (ORDER BY total_dop_rank ROWS UNBOUNDED PRECEDING) AS top_dop_indicator
FROM query_rank
),
-- restrict to a union of queries that are top queries on some dimension; then, restrict further to top-within-top N queries along any dimension
top_query AS
(
SELECT query_hash,
       count_queries,
       query_id,
       count_plans,
       plan_id,
       count_regular_executions,
       count_aborted_executions,
       count_exception_executions,
       cpu_time_rank,
       duration_rank,
       logical_io_reads_rank,
       physical_io_reads_rank,
       executions_rank,
       total_query_max_used_memory_rank,
       total_log_bytes_used_rank,
       total_tempdb_space_used_rank,
       total_dop_rank,
       ranked_wait_categories
FROM top_query_rank
WHERE (
      top_cpu_indicator = 0
      OR
      top_duration_indicator = 0
      OR
      top_executions_indicator = 0
      OR
      top_logical_io_indicator = 0
      OR
      top_physical_io_indicator = 0
      OR
      top_memory_indicator = 0
      OR
      top_log_bytes_indicator = 0
      OR
      top_tempdb_indicator = 0
      OR
      top_dop_indicator = 0
      )
      AND
      (
      cpu_time_rank <= @QueryStoreTopQueryCount
      OR
      duration_rank <= @QueryStoreTopQueryCount
      OR
      executions_rank <= @QueryStoreTopQueryCount
      OR
      logical_io_reads_rank <= @QueryStoreTopQueryCount
      OR
      physical_io_reads_rank <= @QueryStoreTopQueryCount
      OR
      total_query_max_used_memory_rank <= @QueryStoreTopQueryCount
      OR
      total_log_bytes_used_rank <= @QueryStoreTopQueryCount
      OR
      total_tempdb_space_used_rank <= @QueryStoreTopQueryCount
      OR
      total_dop_rank <= @QueryStoreTopQueryCount
      )
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1320 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'server: ', @@SERVERNAME,
             ', database: ', DB_NAME(),
             ', SLO: ', rg.slo_name,
             ', updateability: ', CAST(DATABASEPROPERTYEX(DB_NAME(), 'Updateability') AS nvarchar(10)),
             ', logical database GUID: ', rg.logical_database_guid,
             ', physical database GUID: ', rg.physical_database_guid,
             ', script execution timestamp (UTC): ', CONVERT(varchar(20), SYSUTCDATETIME(), 120),
             @CRLF, @CRLF,
             STRING_AGG(
                       CAST(CONCAT(
                                  'query hash: ', CONVERT(varchar(30), query_hash, 1),
                                  ', query_id: ', CAST(query_id AS varchar(11)), IIF(count_queries > 1, CONCAT(' (+', CAST(count_queries - 1 AS varchar(11)), ')'), ''),
                                  ', plan_id: ', CAST(plan_id AS varchar(11)), IIF(count_plans > 1, CONCAT(' (+', CAST(count_plans - 1 AS varchar(11)), ')'), ''),
                                  ', executions: (regular: ', CAST(count_regular_executions AS varchar(11)), ', aborted: ', CAST(count_aborted_executions AS varchar(11)), ', exception: ', CAST(count_exception_executions AS varchar(11)), ')',
                                  ', CPU time rank: ', CAST(cpu_time_rank AS varchar(11)),
                                  ', duration rank: ', CAST(duration_rank AS varchar(11)),
                                  ', executions rank: ', CAST(executions_rank AS varchar(11)),
                                  ', logical IO reads rank: ', CAST(logical_io_reads_rank AS varchar(11)),
                                  ', physical IO reads rank: ', CAST(physical_io_reads_rank AS varchar(11)),
                                  ', max used memory rank: ', CAST(total_query_max_used_memory_rank AS varchar(11)),
                                  ', log bytes used rank: ', CAST(total_log_bytes_used_rank AS varchar(11)),
                                  ', tempdb used rank: ', CAST(total_tempdb_space_used_rank AS varchar(11)),
                                  ', parallelism rank: ', CAST(total_dop_rank AS varchar(11)),
                                  ', weighted wait categories: ', ISNULL(ranked_wait_categories, '-')
                                  ) AS nvarchar(max)), @CRLF
                       )
                       WITHIN GROUP (ORDER BY duration_rank),
             @CRLF
             )
       AS details
FROM top_query
CROSS JOIN sys.dm_user_db_resource_governance AS rg
WHERE rg.database_id = DB_ID()
GROUP BY rg.slo_name,
         rg.logical_database_guid,
         rg.physical_database_guid
HAVING COUNT(1) > 0
OPTION (RECOMPILE);

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1320);
    ELSE
        THROW;
END CATCH;

END;

-- MAXDOP
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1000,1010,1020) AND execute_indicator = 1)

WITH maxdop_config AS
(
SELECT c.value,
       c.value_for_secondary
FROM sys.database_scoped_configurations AS c
CROSS JOIN sys.dm_user_db_resource_governance AS g
WHERE
      @EngineEdition = 5
      AND
      c.name = N'MAXDOP'
      AND
      g.database_id = DB_ID()
      AND
      g.cpu_limit > 8
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT t.tip_id,
       CONCAT(
             @NbspCRLF,
             'MAXDOP for primary: ', CAST(mc.value AS varchar(2)), @CRLF,
             'MAXDOP for secondary: ', ISNULL(CAST(mc.value_for_secondary AS varchar(4)), 'NULL'), @CRLF
             )
       AS details
FROM maxdop_config AS mc
INNER JOIN (
           VALUES (1000),(1010),(1020)
           ) AS t (tip_id)
ON (t.tip_id = 1000 AND mc.value NOT BETWEEN 1 AND 8 AND (mc.value_for_secondary IS NULL OR mc.value_for_secondary NOT BETWEEN 1 AND 8))
   OR
   (t.tip_id = 1010 AND mc.value NOT BETWEEN 1 AND 8 AND mc.value_for_secondary BETWEEN 1 AND 8)
   OR
   (t.tip_id = 1020 AND mc.value BETWEEN 1 AND 8 AND mc.value_for_secondary NOT BETWEEN 1 AND 8)
INNER JOIN @TipDefinition AS td
ON t.tip_id = td.tip_id
WHERE td.execute_indicator = 1
;

-- Compatibility level
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1030) AND execute_indicator = 1)

BEGIN TRY

INSERT INTO @DetectedTip (tip_id, details)
SELECT 1030 AS tip_id,
       CONCAT(@NbspCRLF, 'Present database compatibility level: ', CAST(d.compatibility_level AS varchar(3)), @CRLF) AS details
FROM sys.dm_exec_valid_use_hints AS h
CROSS JOIN sys.databases AS d
WHERE h.name LIKE 'QUERY[_]OPTIMIZER[_]COMPATIBILITY[_]LEVEL[_]%'
      AND
      d.name = DB_NAME()
      AND
      TRY_CAST(RIGHT(h.name, CHARINDEX('_', REVERSE(h.name)) - 1) AS smallint) > d.compatibility_level
GROUP BY d.compatibility_level
HAVING COUNT(1) > 1 -- Consider the last two compat levels (including the one possibly in preview) as current
;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1030);
    ELSE
        THROW;
END CATCH;

-- Auto-stats
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1040,1050) AND execute_indicator = 1)

BEGIN TRY

WITH autostats AS
(
SELECT t.tip_id
FROM sys.databases AS d
INNER JOIN (
           VALUES (1040),(1050)
           ) AS t (tip_id)
ON (t.tip_id = 1040 AND d.is_auto_create_stats_on = 0)
   OR
   (t.tip_id = 1050 AND d.is_auto_update_stats_on = 0)
INNER JOIN @TipDefinition AS td
ON t.tip_id = td.tip_id
WHERE d.name = DB_NAME()
      AND
      (
      d.is_auto_create_stats_on = 0
      OR
      d.is_auto_update_stats_on = 0
      )
      AND
      td.execute_indicator = 1
)
INSERT INTO @DetectedTip (tip_id)
SELECT tip_id
FROM autostats;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1040),(1050);
    ELSE
        THROW;
END CATCH;

-- RCSI
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1060) AND execute_indicator = 1)

BEGIN TRY

INSERT INTO @DetectedTip (tip_id)
SELECT 1060 AS tip_id
FROM sys.databases
WHERE name = DB_NAME()
      AND
      is_read_committed_snapshot_on = 0;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1060);
    ELSE
        THROW;
END CATCH;

-- Query Store state
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1070,1071,1072) AND execute_indicator = 1)

BEGIN TRY

INSERT INTO @DetectedTip (tip_id, details)
SELECT t.tip_id,
       IIF(
          t.tip_id = 1071 AND qso.desired_state_desc = 'READ_WRITE',
          CONCAT(
                @NbspCRLF,
                CASE qso.readonly_reason
                    WHEN 1 THEN 'Database is in read-only mode.'
                    WHEN 2 THEN 'Database is in single-user mode.'
                    WHEN 4 THEN 'Database in in emergency mode.'
                    WHEN 8 THEN 'Database is a read-only replica.'
                    WHEN 65536 THEN 'The size of Query Store has reached the limit set by MAX_STORAGE_SIZE_MB option.'
                    WHEN 131072 THEN 'The number of queries in Query Store has reached the limit for the service objective. Remove unneeded queries or scale up to a higher service objective.'
                    WHEN 262144 THEN 'The size of in-memory Query Store data has reached maximum limit. Query Store will be in read-only state while this data is being persisted in the database.'
                    WHEN 524288 THEN 'Database has reached its maximum size limit.'
                END,
                @CRLF
                ),
           NULL
           )
       AS details
FROM sys.database_query_store_options AS qso
INNER JOIN (
           VALUES (1070),(1071),(1072)
           ) AS t (tip_id)
ON (t.tip_id = 1070 AND qso.actual_state_desc = 'OFF')
   OR
   (t.tip_id = 1071 AND qso.actual_state_desc = 'READ_ONLY')
   OR
   (t.tip_id = 1072 AND qso.query_capture_mode_desc = 'NONE')
INNER JOIN @TipDefinition AS td
ON t.tip_id = td.tip_id
WHERE DATABASEPROPERTYEX(DB_NAME(), 'Updateability') = 'READ_WRITE' -- only produce this on primary
      AND
      td.execute_indicator = 1
;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1070),(1071),(1072);
    ELSE
        THROW;
END CATCH;

-- Auto-shrink
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1080) AND execute_indicator = 1)

BEGIN TRY

INSERT INTO @DetectedTip (tip_id)
SELECT 1080 AS tip_id
FROM sys.databases
WHERE name = DB_NAME()
      AND
      is_auto_shrink_on = 1;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1080);
    ELSE
        THROW;
END CATCH;

-- Btree indexes with uniqueidentifier leading column
-- This and all other tips querying sys.dm_db_partition_stats may be silently skipped
-- when running with limited permissions and not holding both VIEW DATABASE STATE and VIEW DEFINITION.
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1100) AND execute_indicator = 1)

BEGIN TRY

WITH
partition_size AS
(
SELECT object_id,
       used_page_count,
       row_count
FROM sys.dm_db_partition_stats
WHERE index_id IN (0,1)
UNION
-- special index types
SELECT it.parent_object_id,
       ps.used_page_count,
       0 AS row_count
FROM sys.dm_db_partition_stats AS ps
INNER JOIN sys.internal_tables AS it
ON ps.object_id = it.object_id
WHERE it.internal_type_desc IN (
                               'XML_INDEX_NODES','SELECTIVE_XML_INDEX_NODE_TABLE', -- XML indexes
                               'EXTENDED_INDEXES', -- spatial indexes
                               'FULLTEXT_INDEX_MAP','FULLTEXT_AVDL','FULLTEXT_COMP_FRAGMENT','FULLTEXT_DOCID_STATUS','FULLTEXT_INDEXED_DOCID','FULLTEXT_DOCID_FILTER','FULLTEXT_DOCID_MAP', -- fulltext indexes
                               'SEMPLAT_DOCUMENT_INDEX_TABLE','SEMPLAT_TAG_INDEX_TABLE' -- semantic search indexes
                               )
),
object_size AS
(
SELECT object_id,
       SUM(used_page_count) * 8 / 1024. AS object_size_mb,
       SUM(row_count) AS object_row_count
FROM partition_size
GROUP BY object_id
),
guid_index AS
(
SELECT QUOTENAME(OBJECT_SCHEMA_NAME(o.object_id)) COLLATE DATABASE_DEFAULT AS schema_name,
       QUOTENAME(o.name) COLLATE DATABASE_DEFAULT AS object_name,
       QUOTENAME(i.name) COLLATE DATABASE_DEFAULT AS index_name,
       i.type_desc COLLATE DATABASE_DEFAULT AS index_type,
       o.object_id,
       i.index_id,
       os.object_size_mb,
       os.object_row_count
FROM sys.objects AS o
INNER JOIN sys.indexes AS i
ON o.object_id = i.object_id
INNER JOIN sys.index_columns AS ic
ON i.object_id = ic.object_id
   AND
   i.index_id = ic.index_id
INNER JOIN sys.columns AS c
ON i.object_id = c.object_id
   AND
   ic.object_id = c.object_id
   AND
   ic.column_id = c.column_id
INNER JOIN sys.types AS t
ON c.system_type_id = t.system_type_id
INNER JOIN object_size AS os
ON o.object_id = os.object_id
WHERE i.type_desc IN ('CLUSTERED','NONCLUSTERED') -- Btree indexes
      AND
      ic.key_ordinal = 1 -- leading column
      AND
      t.name = 'uniqueidentifier'
      AND
      i.is_hypothetical = 0
      AND
      i.is_disabled = 0
      AND
      o.is_ms_shipped = 0
      AND
      os.object_size_mb > @GuidLeadingColumnObjectMinSizeMB -- consider larger tables only
      AND
      -- data type is uniqueidentifier or an alias data type derived from uniqueidentifier
      EXISTS (
             SELECT 1
             FROM sys.types AS t1
             LEFT JOIN sys.types AS t2
             ON t1.system_type_id = t2.system_type_id
             WHERE t1.name = 'uniqueidentifier'
                   AND
                   c.user_type_id = t2.user_type_id
             )
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1100 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'Total indexes: ', FORMAT(COUNT(1), '#,0'),
             @CRLF, @CRLF,
             STRING_AGG(
                       CAST(CONCAT(
                                  'schema: ', schema_name,
                                  ', object: ', object_name,
                                  ', object size (MB): ', FORMAT(object_size_mb, '#,0.00'),
                                  ', object row count: ', FORMAT(object_row_count, '#,0'),
                                  ', index: ', index_name,
                                  ', type: ', index_type
                                  ) AS nvarchar(max)), @CRLF
                       )
                       WITHIN GROUP (ORDER BY schema_name, object_name, index_type, index_name),
             @CRLF
             )
       AS details
FROM guid_index
HAVING COUNT(1) > 0;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1100);
    ELSE
        THROW;
END CATCH;

-- FLGP auto-tuning
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1110 AS tip_id,
       CONCAT(@NbspCRLF, 'Reason: ' + NULLIF(reason_desc, ''), @CRLF) AS details
FROM sys.database_automatic_tuning_options
WHERE name = 'FORCE_LAST_GOOD_PLAN'
      AND
      actual_state_desc <> 'ON'
      AND
      DATABASEPROPERTYEX(DB_NAME(), 'Updateability') = 'READ_WRITE' -- only produce this on primary
;

-- Used space close to maxsize
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1120) AND execute_indicator = 1)

WITH space_used AS
(
SELECT SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS bigint) * 8 / 1024.) AS space_used_mb,
       CAST(DATABASEPROPERTYEX(DB_NAME(), 'MaxSizeInBytes') AS bigint) / 1024. / 1024 AS max_size_mb
FROM sys.database_files
WHERE @EngineEdition = 5
      AND
      type_desc = 'ROWS'
      AND
      CAST(DATABASEPROPERTYEX(DB_NAME(), 'MaxSizeInBytes') AS bigint) <> -1 -- not applicable to Hyperscale
HAVING COUNT(1) > 0
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1120 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'Used data size (MB): ', FORMAT(space_used_mb, '#,0.00'),
             ', maximum data size (MB): ', FORMAT(max_size_mb, '#,0.00'),
             @CRLF
             )
FROM space_used
WHERE space_used_mb > @UsedToMaxsizeSpaceThresholdRatio * max_size_mb -- used space > n% of db maxsize
;

-- Allocated space close to maxsize
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1130) AND execute_indicator = 1)

WITH space_allocated AS
(
SELECT SUM(CAST(size AS bigint) * 8 / 1024.) AS space_allocated_mb,
       CAST(DATABASEPROPERTYEX(DB_NAME(), 'MaxSizeInBytes') AS bigint) / 1024. / 1024 AS max_size_mb
FROM sys.database_files
WHERE @EngineEdition = 5
      AND
      type_desc = 'ROWS'
      AND
      CAST(DATABASEPROPERTYEX(DB_NAME(), 'MaxSizeInBytes') AS bigint) <> -1 -- not applicable to Hyperscale
      AND
      DATABASEPROPERTYEX(DB_NAME(), 'Edition') IN ('Premium','BusinessCritical') -- not relevant for remote storage SLOs
HAVING COUNT(1) > 0
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1130 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'Allocated data size (MB): ', FORMAT(space_allocated_mb, '#,0.00'),
             ', maximum data size (MB): ', FORMAT(max_size_mb, '#,0.00'),
             @CRLF
             )
FROM space_allocated
WHERE space_allocated_mb > @AllocatedToMaxsizeSpaceThresholdRatio * max_size_mb -- allocated space > n% of db maxsize
;

-- Allocated space >> used space
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1140) AND execute_indicator = 1)

WITH allocated_used_space AS
(
SELECT SUM(CAST(size AS bigint) * 8 / 1024.) AS space_allocated_mb,
       SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS bigint)) * 8 / 1024. AS space_used_mb
FROM sys.database_files
WHERE type_desc = 'ROWS'
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1140 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'Used data size (MB): ', FORMAT(space_used_mb, '#,0.00'),
             ', allocated data size (MB): ', FORMAT(space_allocated_mb, '#,0.00'),
             @CRLF
             )
FROM allocated_used_space
WHERE space_used_mb > @UsedToAllocatedSpaceDbMinSizeMB -- not relevant for small databases
      AND
      @UsedToAllocatedSpaceThresholdRatio * space_allocated_mb > space_used_mb -- allocated space is more than N times used space
      AND
      DATABASEPROPERTYEX(DB_NAME(), 'Edition') IN ('Premium','BusinessCritical') -- not relevant for remote storage SLOs
;

-- High log rate
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1190) AND execute_indicator = 1)

WITH
log_rate_snapshot AS
(
SELECT end_time,
       avg_log_write_percent,
       IIF(avg_log_write_percent > @HighLogRateThresholdPercent, 1, 0) AS high_log_rate_indicator
FROM sys.dm_db_resource_stats
WHERE @EngineEdition = 5
      AND
      DATABASEPROPERTYEX(DB_NAME(), 'Updateability') = 'READ_WRITE' -- only produce this on primary
),
pre_packed_log_rate_snapshot AS
(
SELECT end_time,
       avg_log_write_percent,
       high_log_rate_indicator,
       ROW_NUMBER() OVER (ORDER BY end_time) -- row number across all readings, in increasing chronological order
       -
       SUM(high_log_rate_indicator) OVER (ORDER BY end_time ROWS UNBOUNDED PRECEDING) -- running count of all intervals where log rate exceeded the threshold
       AS grouping_helper -- this difference remains constant while log rate is above the threshold, and can be used to collapse/pack an interval using aggregation
FROM log_rate_snapshot
),
packed_log_rate_snapshot AS
(
SELECT MIN(end_time) AS min_end_time,
       MAX(end_time) AS max_end_time,
       MAX(avg_log_write_percent) AS max_log_write_percent
FROM pre_packed_log_rate_snapshot
WHERE high_log_rate_indicator = 1
GROUP BY grouping_helper
),
log_rate_top_stat AS
(
SELECT MAX(DATEDIFF(second, min_end_time, max_end_time)) AS top_log_rate_duration_seconds,
       MAX(max_log_write_percent) AS top_log_write_percent,
       COUNT(1) AS count_high_log_write_intervals
FROM packed_log_rate_snapshot
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1190 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'In the last hour, there were ', count_high_log_write_intervals,
             ' interval(s) with transaction log IO staying above ', @HighLogRateThresholdPercent,
             '% of the service objective limit. The longest such interval lasted ', FORMAT(top_log_rate_duration_seconds, '#,0'),
             ' seconds, and the maximum log IO was ', FORMAT(top_log_write_percent, '#,0.00'),
             '%.',
             @CRLF
             ) AS details
FROM log_rate_top_stat
WHERE count_high_log_write_intervals > 0
;

-- Plan cache bloat from single-use plans
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1200) AND execute_indicator = 1)

WITH plan_cache_db_summary AS
(
SELECT t.dbid AS database_id, -- In an elastic pool, return data for all databases
       DB_NAME(t.dbid) AS database_name,
       SUM(IIF(cp.usecounts = 1, cp.size_in_bytes / 1024. / 1024, 0)) AS single_use_db_plan_cache_size_mb,
       SUM(cp.size_in_bytes / 1024. / 1024) AS total_db_plan_cache_size_mb
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS t
WHERE cp.objtype IN ('Adhoc','Prepared')
      AND
      cp.cacheobjtype = 'Compiled Plan'
      AND
      t.dbid BETWEEN 5 AND 32700 -- exclude system databases
GROUP BY t.dbid
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1200 AS tip_id,
       CONCAT(
             @NbspCRLF,
             STRING_AGG(
                       CAST(CONCAT(
                                  'database (id: ', database_id,
                                  ', name: ' + QUOTENAME(database_name), -- database name is only available for current database, include for usability if available
                                  '), single use plans take ', FORMAT(single_use_db_plan_cache_size_mb, 'N'),
                                  ' MB, or ', FORMAT(single_use_db_plan_cache_size_mb / total_db_plan_cache_size_mb, 'P'),
                                  ' of total cached plans for this database.'
                                  ) AS nvarchar(max)), @CRLF
                       )
                       WITHIN GROUP (ORDER BY database_name DESC, database_id),
             @CRLF
             )
       AS details
FROM plan_cache_db_summary
WHERE single_use_db_plan_cache_size_mb >= @SingleUsePlanSizeThresholdMB -- sufficiently large total size of single-use plans for a database
      AND
      single_use_db_plan_cache_size_mb * 1. / total_db_plan_cache_size_mb > @SingleUseTotalPlanSizeRatioThreshold -- single-use plans take more than n% of total plan cache size
HAVING COUNT(1) > 0
;

-- Redo queue is large
-- Applicable to Premium/Business Critical read scale-out replicas and all non-Hyperscale geo-replicas
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1220) AND execute_indicator = 1)

INSERT INTO @DetectedTip (tip_id, details)
SELECT 1220 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'Current redo queue size: ',
             FORMAT(redo_queue_size / 1024., 'N'),
             ' MB. Most recent sampling of redo rate: ',
             FORMAT(redo_rate / 1024., 'N'),
             ' MB/s.',
             @CRLF
             )
       AS details
FROM sys.dm_database_replica_states
WHERE is_primary_replica = 0 -- redo details only available on secondary
      AND
      is_local = 1
      AND
      redo_queue_size / 1024. > @RedoQueueSizeThresholdMB
;

-- Paused resumable index DDL
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1280) AND execute_indicator = 1)

BEGIN TRY

WITH resumable_index_op AS
(
SELECT OBJECT_SCHEMA_NAME(iro.object_id) AS schema_name,
       OBJECT_NAME(iro.object_id) AS object_name,
       iro.name AS index_name,
       i.type_desc AS index_type,
       iro.percent_complete,
       iro.start_time,
       iro.last_pause_time,
       iro.total_execution_time AS total_execution_time_minutes,
       iro.page_count * 8 / 1024. AS index_operation_allocated_space_mb,
       IIF(CAST(dsc.value AS int) = 0, NULL, DATEDIFF(minute, CURRENT_TIMESTAMP, DATEADD(minute, CAST(dsc.value AS int), iro.last_pause_time))) AS time_to_auto_abort_minutes,
       iro.sql_text
FROM sys.index_resumable_operations AS iro
LEFT JOIN sys.indexes AS i -- new index being created will not be present, thus using outer join
ON iro.object_id = i.object_id
   AND
   iro.index_id = i.index_id
CROSS JOIN sys.database_scoped_configurations AS dsc
WHERE iro.state_desc = 'PAUSED'
      AND
      dsc.name = 'PAUSED_RESUMABLE_INDEX_ABORT_DURATION_MINUTES'
      AND
      DATABASEPROPERTYEX(DB_NAME(), 'Updateability') = 'READ_WRITE' -- only produce this on primary
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1280 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'Total resumable index operations: ', FORMAT(COUNT(1), '#,0'),
             @CRLF, @CRLF,
             STRING_AGG(
                       CAST(CONCAT(
                                  'schema name: ', QUOTENAME(schema_name) COLLATE DATABASE_DEFAULT, @CRLF,
                                  'object name: ', QUOTENAME(object_name) COLLATE DATABASE_DEFAULT, @CRLF,
                                  'index name: ', QUOTENAME(index_name) COLLATE DATABASE_DEFAULT, @CRLF,
                                  'index type: ' + index_type COLLATE DATABASE_DEFAULT + CHAR(13) + CHAR(10),
                                  'percent complete: ', FORMAT(percent_complete, '#,0.00'), '%', @CRLF,
                                  'start time: ', CONVERT(varchar(20), start_time, 120), @CRLF,
                                  'last pause time: ', CONVERT(varchar(20), last_pause_time, 120), @CRLF,
                                  'total execution time (minutes): ', FORMAT(total_execution_time_minutes, '#,0'), @CRLF,
                                  'space allocated by resumable index operation (MB): ', FORMAT(index_operation_allocated_space_mb, '#,0.00'), @CRLF,
                                  'time remaining to auto-abort (minutes): ' + FORMAT(time_to_auto_abort_minutes, '#,0') + CHAR(13) + CHAR(10),
                                  'index operation SQL statement: ', sql_text COLLATE DATABASE_DEFAULT, @CRLF
                                  ) AS nvarchar(max)), @CRLF
                       )
                       WITHIN GROUP (ORDER BY schema_name, object_name, index_name),
             @CRLF
             )
FROM resumable_index_op
HAVING COUNT(1) > 0;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1280);
    ELSE
        THROW;
END CATCH;

-- Geo-replication health
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1300) AND execute_indicator = 1)

BEGIN TRY

WITH
geo_replication_link_details AS
(
SELECT STRING_AGG(
                 CAST(CONCAT(
                            'link GUID: ', link_guid, ', ',
                            'local server: ' + QUOTENAME(@@SERVERNAME) + ', ',
                            'local database: ' + QUOTENAME(DB_NAME()) + ', ',
                            'partner server: ' + QUOTENAME(partner_server) + ', ',
                            'partner database: ' + QUOTENAME(partner_database) + ', ',
                            'geo-replication role: ' + role_desc + ', ',
                            'last replication time: ' + CAST(last_replication AS varchar(40)) + ', ',
                            'geo-replication lag (seconds): ' + FORMAT(replication_lag_sec, '#,0') + ', ',
                            'geo-replication state: ' + replication_state_desc
                            ) AS nvarchar(max)), @CRLF
                 )
                 WITHIN GROUP (ORDER BY partner_server, partner_database)
       AS details
FROM sys.dm_geo_replication_link_status
WHERE (replication_state_desc <> 'CATCH_UP' OR replication_state_desc IS NULL)
      OR
      -- high replication lag for recent transactions
      (
      replication_state_desc = 'CATCH_UP'
      AND
      replication_lag_sec > @HighGeoReplLagMinThresholdSeconds
      AND
      last_replication > DATEADD(second, -@RecentGeoReplTranTimeWindowLengthSeconds, SYSDATETIMEOFFSET())
      )
HAVING COUNT(1) > 0
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1300 AS tip_id,
       CONCAT(
             @NbspCRLF,
             details,
             @CRLF
             )
FROM geo_replication_link_details;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1300);
    ELSE
        THROW;
END CATCH;

-- Last partitions are not empty
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1310) AND execute_indicator = 1)

BEGIN TRY

WITH
partition_stat AS
(
SELECT object_id,
       partition_number,
       reserved_page_count * 8 / 1024. AS size_mb,
       row_count,
       COUNT(1) OVER (PARTITION BY object_id) AS partition_count
FROM sys.dm_db_partition_stats
WHERE index_id IN (0,1)
),
object_last_partition AS
(
SELECT QUOTENAME(OBJECT_SCHEMA_NAME(ps.object_id)) COLLATE DATABASE_DEFAULT AS schema_name,
       QUOTENAME(OBJECT_NAME(ps.object_id)) COLLATE DATABASE_DEFAULT AS object_name,
       ps.partition_count,
       ps.partition_number,
       SUM(ps.row_count) AS partition_rows,
       SUM(ps.size_mb) AS partition_size_mb
FROM partition_stat AS ps
INNER JOIN sys.objects AS o
ON ps.object_id = o.object_id
WHERE ps.partition_count > 1
      AND
      ps.partition_count - ps.partition_number < @MinEmptyPartitionCount -- Consider last n partitions
      AND
      o.is_ms_shipped = 0
GROUP BY ps.object_id,
         ps.partition_count,
         ps.partition_number
HAVING SUM(ps.row_count) > 0
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1310 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'Total partitions: ', FORMAT(COUNT(1), '#,0'),
             @CRLF, @CRLF,
             STRING_AGG(
                       CAST(CONCAT(
                                  'schema: ', schema_name, ', ',
                                  'object: ', object_name, ', ',
                                  'partition number: ', FORMAT(partition_number, '#,0'),
                                  ' out of  ', FORMAT(partition_count, '#,0'), ', ',
                                  'partition rows: ', FORMAT(partition_rows, '#,0'), ', ',
                                  'partition size (MB): ', FORMAT(partition_size_mb, '#,0.00')
                                  ) AS nvarchar(max)), @CRLF
                       )
                       WITHIN GROUP (ORDER BY schema_name, object_name, partition_number),
             @CRLF
             )
       AS details
FROM object_last_partition
HAVING COUNT(1) > 0;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1310);
    ELSE
        THROW;
END CATCH;

-- High instance CPU
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1390) AND execute_indicator = 1)

WITH
instance_cpu_snapshot AS
(
SELECT end_time,
       avg_instance_cpu_percent,
       IIF(avg_instance_cpu_percent > @HighInstanceCPUThresholdPercent, 1, 0) AS high_instance_cpu_indicator
FROM sys.dm_db_resource_stats
WHERE @EngineEdition = 5
),
pre_packed_instance_cpu_snapshot AS
(
SELECT end_time,
       avg_instance_cpu_percent,
       high_instance_cpu_indicator,
       ROW_NUMBER() OVER (ORDER BY end_time) -- row number across all readings, in increasing chronological order
       -
       SUM(high_instance_cpu_indicator) OVER (ORDER BY end_time ROWS UNBOUNDED PRECEDING) -- running count of all intervals where log rate exceeded the threshold
       AS grouping_helper -- this difference remains constant while log rate is above the threshold, and can be used to collapse/pack an interval using aggregation
FROM instance_cpu_snapshot
),
packed_instance_cpu_snapshot AS
(
SELECT MIN(end_time) AS min_end_time,
       MAX(end_time) AS max_end_time,
       MAX(avg_instance_cpu_percent) AS max_instance_cpu_percent
FROM pre_packed_instance_cpu_snapshot
WHERE high_instance_cpu_indicator = 1
GROUP BY grouping_helper
HAVING DATEDIFF(second, MIN(end_time), MAX(end_time)) > @HighInstanceCPUMinThresholdSeconds
),
instance_cpu_top_stat AS
(
SELECT MAX(DATEDIFF(second, min_end_time, max_end_time)) AS top_instance_cpu_duration_seconds,
       MAX(max_instance_cpu_percent) AS top_instance_cpu_percent,
       COUNT(1) AS count_high_instance_cpu_intervals
FROM packed_instance_cpu_snapshot
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1390 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'In the last hour, there were ', count_high_instance_cpu_intervals,
             ' interval(s) with instance CPU utilization staying above ', @HighInstanceCPUThresholdPercent,
             '% for at least ' , FORMAT(@HighInstanceCPUMinThresholdSeconds, '#,0'),
             ' seconds. The longest such interval lasted ', FORMAT(top_instance_cpu_duration_seconds, '#,0'),
             ' seconds, and the maximum instance CPU utilization was ', FORMAT(top_instance_cpu_percent, '#,0.00'),
             '%.',
             @CRLF
             ) AS details
FROM instance_cpu_top_stat
WHERE count_high_instance_cpu_intervals > 0
;

-- Stale stats
-- This may be silently skipped if running with limited permissions.
-- VIEW SERVER STATE is insufficient to query sys.dm_db_stats_properties(),
-- sysadmin or db_owner or SELECT on columns is required.
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1400) AND execute_indicator = 1)

BEGIN TRY

WITH
object_row_count AS
(
SELECT object_id,
       SUM(row_count) AS object_row_count
FROM sys.dm_db_partition_stats
WHERE index_id IN (0,1) -- clustered index or heap
GROUP BY object_id
),
stale_stats AS
(
SELECT OBJECT_SCHEMA_NAME(s.object_id) COLLATE DATABASE_DEFAULT AS schema_name,
       OBJECT_NAME(s.object_id) COLLATE DATABASE_DEFAULT AS object_name,
       s.name COLLATE DATABASE_DEFAULT AS statistics_name,
       s.auto_created,
       s.user_created,
       s.no_recompute,
       s.is_temporary,
       s.is_incremental,
       s.has_persisted_sample,
       s.has_filter,
       sp.last_updated,
       sp.unfiltered_rows,
       sp.rows_sampled,
       orc.object_row_count,
       sp.modification_counter
FROM sys.stats AS s
INNER JOIN sys.objects AS o
ON s.object_id = o.object_id
INNER JOIN object_row_count AS orc
ON o.object_id = orc.object_id
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS sp
WHERE (
      o.is_ms_shipped = 0
      OR
      (OBJECT_SCHEMA_NAME(s.object_id) = 'sys' AND o.name LIKE 'plan[_]persist[_]%') -- include Query Store system tables
      )
      AND
      (
      -- object cardinality has changed substantially since last stats update
      ABS(ISNULL(sp.unfiltered_rows, 0) - orc.object_row_count) / NULLIF(((ISNULL(sp.unfiltered_rows, 0) + orc.object_row_count) / 2), 0) > @StaleStatsCardinalityChangeMinDifference
      OR
      -- no stats blob created
      (sp.last_updated IS NULL AND orc.object_row_count > 0)
      OR
      -- naive: stats for an object with many modifications not updated for a substantial time interval
      (sp.modification_counter > @StaleStatsMinModificationCountRatio * orc.object_row_count AND DATEDIFF(day, sp.last_updated, SYSDATETIME()) > @StaleStatsMinAgeThresholdDays)
      )
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1400 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'Total potentially out of date statistics: ', FORMAT(COUNT(1), '#,0'),
             @CRLF, @CRLF,
             STRING_AGG(
                       CAST(CONCAT(
                                  schema_name, '.',
                                  object_name, '.',
                                  statistics_name,
                                  ', last updated: ', ISNULL(FORMAT(last_updated, 's'), '-'),
                                  ', last update rows: ', ISNULL(FORMAT(unfiltered_rows, '#,0'), '-'),
                                  ', last update sampled rows: ', ISNULL(FORMAT(rows_sampled, '#,0'), '-'),
                                  ', current rows: ', FORMAT(object_row_count, '#,0'),
                                  ', modifications: ', ISNULL(FORMAT(modification_counter, '#,0'), '-'),
                                  ', attributes: '
                                  +
                                  NULLIF(
                                        CONCAT_WS(
                                                 ',',
                                                 IIF(auto_created = 1, 'auto-created', NULL),
                                                 IIF(user_created = 1, 'user-created', NULL),
                                                 IIF(no_recompute = 1, 'no_recompute', NULL),
                                                 IIF(is_temporary = 1, 'temporary', NULL),
                                                 IIF(is_incremental = 1, 'incremental', NULL),
                                                 IIF(has_filter = 1, 'filtered', NULL),
                                                 IIF(has_persisted_sample = 1, 'persisted sample', NULL)
                                                 )
                                        , '')
                                  ) AS nvarchar(max)), @CRLF
                       ) WITHIN GROUP (ORDER BY schema_name, object_name, statistics_name),
             @CRLF
             )
       AS details
FROM stale_stats
HAVING COUNT(1) > 0;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1400);
    ELSE
        THROW;
END CATCH;

-- Many tables with no indexes
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1410) AND execute_indicator = 1)

BEGIN TRY

WITH
object_row_count AS
(
SELECT object_id,
       SUM(row_count) AS object_row_count
FROM sys.dm_db_partition_stats
WHERE index_id IN (0,1) -- clustered index or heap
GROUP BY object_id
),
indexed_table AS
(
SELECT QUOTENAME(OBJECT_SCHEMA_NAME(t.object_id)) COLLATE DATABASE_DEFAULT AS schema_name,
       QUOTENAME(t.name) COLLATE DATABASE_DEFAULT AS table_name,
       IIF(
          ISNULL(i.no_index_indicator, 0) = 1
          AND
          -- exclude small tables
          orc.object_row_count > @NoIndexTablesMinRowCountThreshold,
          1,
          0
          )
       AS no_index_indicator
FROM sys.tables AS t
INNER JOIN object_row_count AS orc
ON t.object_id = orc.object_id
OUTER APPLY (
            SELECT TOP (1) 1 AS no_index_indicator
            FROM sys.indexes AS i
            WHERE i.object_id = t.object_id
                  AND
                  i.type_desc = 'HEAP'
                  AND
                  NOT EXISTS (
                             SELECT 1
                             FROM sys.indexes AS ni
                             WHERE ni.object_id = i.object_id
                                   AND
                                   ni.type_desc IN ('NONCLUSTERED','XML','SPATIAL','NONCLUSTERED COLUMNSTORE','NONCLUSTERED HASH')
                             )
            ) AS i
WHERE t.is_ms_shipped = 0
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1410 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'Total tables: ', FORMAT(COUNT(1), '#,0'),
             @CRLF, @CRLF,
             'Tables with ', FORMAT(@NoIndexTablesMinRowCountThreshold, '#,0'),
             ' or more rows and no indexes: ', FORMAT(SUM(no_index_indicator), '#,0'),
             @CRLF, @CRLF,
             STRING_AGG(CAST(
                            IIF(
                               no_index_indicator = 1,
                               CONCAT(schema_name, '.', table_name),
                               NULL
                               )
                            AS nvarchar(max)
                            ),
                       @CRLF
                       ) WITHIN GROUP (ORDER BY schema_name, table_name),
             @CRLF
             )
       AS details
FROM indexed_table
HAVING SUM(no_index_indicator) > @NoIndexMinTableCountRatio * COUNT(1);

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1410);
    ELSE
        THROW;
END CATCH;

-- Disabled page or row locks
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1440) AND execute_indicator = 1)

BEGIN TRY

WITH lock_index AS
(
SELECT QUOTENAME(OBJECT_SCHEMA_NAME(o.object_id)) COLLATE DATABASE_DEFAULT AS schema_name,
       QUOTENAME(o.name) COLLATE DATABASE_DEFAULT AS object_name,
       QUOTENAME(i.name) COLLATE DATABASE_DEFAULT AS index_name,
       i.allow_row_locks,
       i.allow_page_locks
FROM sys.indexes AS i
INNER JOIN sys.objects AS o
ON i.object_id = o.object_id
WHERE o.is_ms_shipped = 0
      AND
      i.is_hypothetical = 0
      AND
      i.type_desc NOT IN ('CLUSTERED COLUMNSTORE','NONCLUSTERED COLUMNSTORE')
      AND
      NOT EXISTS (
                 SELECT 1
                 FROM sys.tables AS t
                 WHERE t.object_id = o.object_id
                       AND
                       t.is_memory_optimized = 1
                 )
      AND
      (
      i.allow_row_locks = 0
      OR
      i.allow_page_locks = 0
      )
),
index_agg AS
(
SELECT STRING_AGG(
                 CAST(CONCAT(
                            schema_name, '.',
                            object_name, '.',
                            index_name,
                            ': ',
                            CONCAT_WS(
                                     ', ',
                                     IIF(allow_row_locks = 0, 'row locks disabled', NULL),
                                     IIF(allow_page_locks = 0, 'page locks disabled', NULL)
                                     )
                            ) AS nvarchar(max)), @CRLF
                 ) WITHIN GROUP (ORDER BY schema_name, object_name, index_name)
       AS details,
       COUNT(1) AS index_count
FROM lock_index
HAVING COUNT(1) > 0
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1440 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'Total indexes: ', FORMAT(index_count, '#,0'),
             @CRLF, @CRLF,
             ia.details,
             @CRLF
             ) AS details
FROM index_agg AS ia
WHERE ia.details IS NOT NULL;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1440);
    ELSE
        THROW;
END CATCH;

-- Database-column collation mismatches
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1460) AND execute_indicator = 1)

BEGIN TRY

WITH
table_column AS
(
SELECT o.object_id,
       c.column_id,
       c.name COLLATE DATABASE_DEFAULT AS column_name,
       c.collation_name COLLATE DATABASE_DEFAULT AS column_collation,
       CAST(DATABASEPROPERTYEX(DB_NAME(), 'Collation') AS sysname) COLLATE DATABASE_DEFAULT AS database_collation
FROM sys.objects AS o
INNER JOIN sys.columns AS c
ON o.object_id = c.object_id
WHERE o.is_ms_shipped = 0
      AND
      o.type_desc IN ('USER_TABLE','VIEW')
),
collation_mismatch_table AS
(
SELECT object_id,
       QUOTENAME(OBJECT_SCHEMA_NAME(object_id)) COLLATE DATABASE_DEFAULT AS schema_name,
       QUOTENAME(OBJECT_NAME(object_id)) COLLATE DATABASE_DEFAULT AS object_name,
       column_collation,
       MIN(database_collation) AS database_collation,
       STRING_AGG(CAST(QUOTENAME(column_name) AS nvarchar(max)), ',') WITHIN GROUP (ORDER BY column_id) AS column_list
FROM table_column
WHERE column_collation <> database_collation
GROUP BY object_id,
         column_collation
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1460 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'Database collation: ', MIN(database_collation), @CRLF,
             'Total objects with mismatched collation columns: ', FORMAT(COUNT(DISTINCT(object_id)), '#,0'),
             @CRLF, @CRLF,
             STRING_AGG(CAST(
                            CONCAT(schema_name, '.', object_name, ': ', column_list, ' (', column_collation, ')')
                            AS nvarchar(max)
                            ),
                       @CRLF
                       ) WITHIN GROUP (ORDER BY schema_name, object_name, column_collation),
             @CRLF
             )
       AS details
FROM collation_mismatch_table
HAVING COUNT(1) > 0;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1460);
    ELSE
        THROW;
END CATCH;

-- Excessively large index keys
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1470) AND execute_indicator = 1)

BEGIN TRY

WITH
large_key_index AS
(
SELECT QUOTENAME(OBJECT_SCHEMA_NAME(o.object_id)) COLLATE DATABASE_DEFAULT AS schema_name,
       QUOTENAME(OBJECT_NAME(o.object_id)) COLLATE DATABASE_DEFAULT AS object_name,
       QUOTENAME(i.name) COLLATE DATABASE_DEFAULT AS index_name,
       i.type_desc COLLATE DATABASE_DEFAULT AS index_type,
       SUM(c.max_length) AS index_key_length_bytes,
       STRING_AGG(CAST(QUOTENAME(c.name) COLLATE DATABASE_DEFAULT AS nvarchar(max)), ',') WITHIN GROUP (ORDER BY ic.key_ordinal) AS column_list
FROM sys.objects AS o
INNER JOIN sys.indexes AS i
ON o.object_id = i.object_id
INNER JOIN sys.index_columns AS ic
ON i.object_id = ic.object_id
   AND
   i.index_id = ic.index_id
INNER JOIN sys.columns AS c
ON o.object_id = c.object_id
   AND
   ic.column_id = c.column_id
WHERE o.is_ms_shipped = 0
      AND
      o.type_desc IN ('USER_TABLE','VIEW')
      AND
      i.type_desc IN ('CLUSTERED','NONCLUSTERED')
      AND
      ic.key_ordinal > 0
GROUP BY o.object_id,
         i.index_id,
         i.name,
         i.type_desc
HAVING SUM(c.max_length) > IIF(i.type_desc = 'CLUSTERED', 900, 1700)
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1470 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'Total indexes with excessively large keys: ', FORMAT(COUNT(1), '#,0'),
             @CRLF, @CRLF,
             STRING_AGG(CAST(
                            CONCAT(
                                  'schema: ', schema_name,
                                  ', object: ', object_name,
                                  ', index: ' +  index_name,
                                  ', index type: ', index_type,
                                  ', index key columns: ', column_list,
                                  ', index key length (bytes): ', FORMAT(index_key_length_bytes, '#,0')
                                  )
                            AS nvarchar(max)
                            ),
                       @CRLF
                       ) WITHIN GROUP (ORDER BY schema_name, object_name),
             @CRLF
             )
       AS details
FROM large_key_index
HAVING COUNT(1) > 0;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1470);
    ELSE
        THROW;
END CATCH;

-- Indexes: disabled, low fill factor, and non-unique clustered
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1480,1490,1500) AND execute_indicator = 1)

BEGIN TRY

WITH
index_size AS
(
SELECT p.object_id,
       p.index_id,
       SUM(ps.used_page_count) * 8 / 1024. AS total_index_size_mb
FROM sys.partitions AS p
INNER JOIN sys.dm_db_partition_stats AS ps
ON p.partition_id = ps.partition_id
   AND
   p.object_id = ps.object_id
   AND
   p.index_id = ps.index_id
GROUP BY p.object_id,
         p.index_id
),
candidate_index AS
(
SELECT QUOTENAME(OBJECT_SCHEMA_NAME(o.object_id)) COLLATE DATABASE_DEFAULT AS schema_name,
       QUOTENAME(OBJECT_NAME(o.object_id)) COLLATE DATABASE_DEFAULT AS object_name,
       QUOTENAME(i.name) COLLATE DATABASE_DEFAULT AS index_name,
       i.type_desc COLLATE DATABASE_DEFAULT AS index_type,
       i.is_disabled,
       i.fill_factor,
       IIF(i.fill_factor > 0 AND i.fill_factor < @FillFactorThreshold, 1, 0) AS is_low_fill_factor,
       IIF(i.type_desc = 'CLUSTERED' AND i.is_unique = 0, 1, 0) AS is_non_unique_clustered,
       ins.total_index_size_mb
FROM sys.objects AS o
INNER JOIN sys.indexes AS i
ON o.object_id = i.object_id
INNER JOIN index_size AS ins
ON o.object_id = ins.object_id
   AND
   i.index_id = ins.index_id
WHERE o.is_ms_shipped = 0
      AND
      o.type_desc IN ('USER_TABLE','VIEW')
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT td.tip_id,
       CONCAT(
             @NbspCRLF,
             'Total indexes: ', FORMAT(COUNT(1), '#,0'),
             @CRLF, @CRLF,
             STRING_AGG(CAST(
                            CONCAT(
                                  'schema: ', schema_name,
                                  ', object: ', object_name,
                                  ', index: ' +  index_name,
                                  IIF(ci.is_non_unique_clustered = 1 AND td.tip_id = 1500, '', CONCAT(', index type: ', index_type)),
                                  ', index size (MB): ', FORMAT(total_index_size_mb, '#,0.00'),
                                  IIF(ci.is_low_fill_factor = 1 AND td.tip_id = 1490, CONCAT(', fill_factor: ', ci.fill_factor), '')
                                  )
                            AS nvarchar(max)
                            ),
                       @CRLF
                       ) WITHIN GROUP (ORDER BY schema_name, object_name, index_name),
             @CRLF
             )
       AS details
FROM candidate_index AS ci
CROSS JOIN @TipDefinition AS td
WHERE td.execute_indicator = 1
      AND
      (
      (td.tip_id = 1480 AND ci.is_disabled = 1)
      OR
      (td.tip_id = 1490 AND ci.is_low_fill_factor = 1)
      OR
      (td.tip_id = 1500 AND ci.is_non_unique_clustered = 1)
      )
GROUP BY td.tip_id
HAVING COUNT(1) > 0;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1480),(1490),(1500);
    ELSE
        THROW;
END CATCH;

-- IDENTITY columns close to running out of numbers
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1510) AND execute_indicator = 1)

BEGIN TRY

WITH
data_type_range AS
(
SELECT *
FROM (
     VALUES (48, 0, 255), -- tinyint
            (52, -32768, 32767), -- smallint
            (56, -2147483648, 2147483647), -- int
            (127, -9223372036854775808, 9223372036854775807), -- bigint
            (106, -99999999999999999999999999999999999999, 99999999999999999999999999999999999999), -- decimal
            (108, -99999999999999999999999999999999999999, 99999999999999999999999999999999999999) -- numeric
     ) AS dt (system_type_id, range_min, range_max)
),
identity_column AS
(
SELECT QUOTENAME(OBJECT_SCHEMA_NAME(t.object_id)) COLLATE DATABASE_DEFAULT AS schema_name,
       QUOTENAME(OBJECT_NAME(t.object_id)) COLLATE DATABASE_DEFAULT AS table_name,
       QUOTENAME(c.name) AS column_name,
       tp.name AS system_type_name,
       IDENT_CURRENT(CONCAT(OBJECT_SCHEMA_NAME(t.object_id),'.',t.name)) AS current_identity_value,
       IDENT_INCR(CONCAT(OBJECT_SCHEMA_NAME(t.object_id),'.',t.name)) AS identity_increment,
       IDENT_SEED(CONCAT(OBJECT_SCHEMA_NAME(t.object_id),'.',t.name)) AS identity_seed,
       dtr.range_min,
       dtr.range_max,
       CAST(dtr.range_min AS float) AS range_min_float,
       CAST(dtr.range_max AS float) AS range_max_float
FROM sys.tables AS t
INNER JOIN sys.columns AS c
ON t.object_id = c.object_id
INNER JOIN sys.types AS tp
ON c.system_type_id = tp.system_type_id
INNER JOIN data_type_range AS dtr
ON c.system_type_id = dtr.system_type_id
WHERE c.is_identity = 1
      AND
      t.is_ms_shipped = 0
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1510 AS tip_id,
       CONCAT(
             @NbspCRLF,
             STRING_AGG(CAST(
                            CONCAT(
                                  'schema: ', schema_name,
                                  ', table: ', table_name,
                                  ', column: ', column_name,
                                  ', data type: ' , system_type_name,
                                  ', initial identity value: ', FORMAT(identity_seed, '#,0'),
                                  ', current identity value: ', FORMAT(current_identity_value, '#,0'),
                                  ', identity increment: ', FORMAT(identity_increment, '#,0'),
                                  ', data type range: ', FORMAT(range_min, '#,0'), ' to ', FORMAT(range_max, '#,0'),
                                  ', remaining contiguous range: ', FORMAT(IIF(identity_increment > 0, range_max_float - current_identity_value, range_min_float - current_identity_value), '#,0')
                                  )
                            AS nvarchar(max)
                            ),
                       @CRLF
                       ) WITHIN GROUP (ORDER BY schema_name, table_name),
             @CRLF
             )
       AS details
FROM identity_column
WHERE -- less than x% of the initial identity range remains
      CASE WHEN identity_increment > 0 THEN (range_max_float - current_identity_value) / IIF((range_max_float - identity_seed) = 0, range_max_float - 1, range_max_float - identity_seed)
           WHEN identity_increment < 0 THEN (range_min_float - current_identity_value) / IIF((range_min_float - identity_seed) = 0, range_min_float + 1, range_min_float - identity_seed)
      END < @IdentitySequenceRangeExhaustionThresholdRatio
HAVING COUNT(1) > 0;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1510);
    ELSE
        THROW;
END CATCH;

-- Sequences close to running out of numbers
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1520) AND execute_indicator = 1)

BEGIN TRY

WITH
sequence_object AS
(
SELECT QUOTENAME(OBJECT_SCHEMA_NAME(s.object_id)) COLLATE DATABASE_DEFAULT AS schema_name,
       QUOTENAME(OBJECT_NAME(s.object_id)) COLLATE DATABASE_DEFAULT AS sequence_name,
       tp.name AS system_type_name,
       -- use float to work around sql_variant not supporting arithmetic expressions
       CAST(s.current_value AS float) AS current_value,
       CAST(s.start_value AS float) AS start_value,
       CAST(s.minimum_value AS float) AS minimum_value,
       CAST(s.maximum_value AS float) AS maximum_value,
       CAST(s.increment AS float) AS increment,
       s.is_exhausted
FROM sys.sequences AS s
INNER JOIN sys.types AS tp
ON s.system_type_id = tp.system_type_id
WHERE s.is_ms_shipped = 0
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1520 AS tip_id,
       CONCAT(
             @NbspCRLF,
             STRING_AGG(CAST(
                            CONCAT(
                                  'schema: ', schema_name,
                                  ', sequence: ', sequence_name,
                                  ', data type: ' , system_type_name,
                                  ', start value: ', FORMAT(start_value, '#,0'),
                                  ', current value: ', FORMAT(current_value, '#,0'),
                                  ', increment: ', FORMAT(increment, '#,0'),
                                  ', full range: ', FORMAT(minimum_value, '#,0'), ' to ', FORMAT(maximum_value, '#,0'),
                                  ', remaining contiguous range: ', FORMAT(IIF(increment > 0, maximum_value - current_value, minimum_value - current_value), '#,0'),
                                  ', exhausted: ', IIF(is_exhausted = 1, 'Yes', 'No')
                                  )
                            AS nvarchar(max)
                            ),
                       @CRLF
                       ) WITHIN GROUP (ORDER BY schema_name, sequence_name),
             @CRLF
             )
       AS details
FROM sequence_object
WHERE -- less than x% of the maximum sequence range remains
      CASE WHEN increment > 0 THEN (maximum_value - current_value) / (maximum_value - start_value)
           WHEN increment < 0 THEN (minimum_value - current_value) / (minimum_value - start_value)
      END < @IdentitySequenceRangeExhaustionThresholdRatio
HAVING COUNT(1) > 0;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1520);
    ELSE
        THROW;
END CATCH;

-- Disabled or untrusted constraints
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1530) AND execute_indicator = 1)

BEGIN TRY

WITH
fk_check_constraint AS
(
SELECT parent_object_id,
       name,
       type_desc,
       is_disabled,
       is_not_trusted,
       is_ms_shipped
FROM sys.foreign_keys
UNION
SELECT parent_object_id,
       name,
       type_desc,
       is_disabled,
       is_not_trusted,
       is_ms_shipped
FROM sys.check_constraints
),
eligible_constraint AS
(
SELECT QUOTENAME(OBJECT_SCHEMA_NAME(t.object_id)) COLLATE DATABASE_DEFAULT AS schema_name,
       QUOTENAME(OBJECT_NAME(t.object_id)) COLLATE DATABASE_DEFAULT AS table_name,
       QUOTENAME(fcc.name) COLLATE DATABASE_DEFAULT AS constraint_name,
       fcc.type_desc AS constraint_type,
       fcc.is_disabled,
       fcc.is_not_trusted
FROM sys.tables AS t
INNER JOIN fk_check_constraint AS fcc
ON t.object_id = fcc.parent_object_id
WHERE t.is_ms_shipped = 0
      AND
      fcc.is_ms_shipped = 0
      AND
      (
      fcc.is_disabled = 1
      OR
      fcc.is_not_trusted = 1
      )
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1530 AS tip_id,
       CONCAT(
             @NbspCRLF,
             STRING_AGG(CAST(
                            CONCAT(
                                  'schema: ', schema_name,
                                  ', table: ', table_name,
                                  ', constraint name: ', constraint_name,
                                  ', constraint type: ', constraint_type,
                                  ', attributes: ',
                                   CONCAT_WS(
                                            ', ',
                                            IIF(is_disabled = 1, 'disabled', NULL),
                                            IIF(is_not_trusted = 1, 'not trusted', NULL)
                                            )
                                  )
                            AS nvarchar(max)
                            ),
                       @CRLF
                       ) WITHIN GROUP (ORDER BY schema_name, table_name, constraint_type, constraint_name),
             @CRLF
             )
       AS details
FROM eligible_constraint
HAVING COUNT(1) > 0;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1530);
    ELSE
        THROW;
END CATCH;

-- When not running as server admin and without membership in ##MS_ServerStateReader## we do not have
-- VIEW DATABASE STATE on tempdb, which is required to execute tempdb.sys.sp_spaceused
-- and query tempdb.sys.dm_db_log_space_usage to determine tempdb used data and log space.
-- Evaluate these tempdb tips only if the required permission is held.
IF EXISTS (
          SELECT 1
          FROM tempdb.sys.fn_my_permissions(default, 'DATABASE')
          WHERE entity_name = 'database'
                AND
                permission_name = 'VIEW DATABASE STATE'
          )
BEGIN

-- tempdb data and log size close to maxsize
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1330,1340,1350) AND execute_indicator = 1)
BEGIN

BEGIN TRY

-- get tempdb used (aka reserved) size
DROP TABLE IF EXISTS #tempdb_space_used;

CREATE TABLE #tempdb_space_used
(
database_name sysname NULL,
database_size varchar(18) NULL,
unallocated_space varchar(18) NULL,
reserved varchar(18) NULL,
data varchar(18) NULL,
index_size varchar(18) NULL,
unused varchar(18) NULL
);

INSERT INTO #tempdb_space_used
EXEC tempdb.sys.sp_spaceused @oneresultset = 1;

IF @@ROWCOUNT <> 1
    THROW 50020, 'tempdb.sys.sp_spaceused returned the number of rows other than 1.', 1;

WITH tempdb_file_size AS
(
SELECT type_desc AS file_type,
       SUM(CAST(size AS bigint) * 8 / 1024.) AS allocated_size_mb,
       SUM(CAST(max_size AS bigint) * 8 / 1024.) AS max_size_mb,
       SUM(IIF(type_desc = 'ROWS', 1, NULL)) AS count_files
FROM tempdb.sys.database_files
WHERE type_desc IN ('ROWS','LOG')
GROUP BY type_desc
),
tempdb_tip AS
(
SELECT tfs.file_type,
       tt.space_type,
       tfs.allocated_size_mb,
       CASE tt.file_type WHEN 'ROWS'
                         THEN TRY_CAST(LEFT(tsu.reserved, LEN(tsu.reserved) - 3) AS decimal) / 1024.
                         WHEN 'LOG'
                         THEN lsu.used_log_space_in_bytes / 1024. / 1024
       END
       AS used_size_mb,
       tfs.max_size_mb,
       tfs.count_files
FROM tempdb_file_size AS tfs
INNER JOIN (
           VALUES ('ROWS', 'allocated'),
                  ('ROWS', 'used'),
                  ('LOG', 'allocated')
           ) AS tt (file_type, space_type)
ON tfs.file_type = tt.file_type
LEFT JOIN #tempdb_space_used AS tsu
ON tfs.file_type = 'ROWS'
LEFT JOIN tempdb.sys.dm_db_log_space_usage AS lsu
ON tt.file_type = 'LOG'
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT td.tip_id,
       CONCAT(
             @NbspCRLF,
             'tempdb ', CASE tt.file_type WHEN 'ROWS' THEN 'data' WHEN 'LOG' THEN 'log' END , ' used size (MB): ', FORMAT(tt.used_size_mb, '#,0.00'),
             ', tempdb ', CASE tt.file_type WHEN 'ROWS' THEN 'data' WHEN 'LOG' THEN 'log' END , ' allocated size (MB): ', FORMAT(tt.allocated_size_mb, '#,0.00'),
             ', tempdb ', CASE tt.file_type WHEN 'ROWS' THEN 'data' WHEN 'LOG' THEN 'log' END, ' MAXSIZE (MB): ', FORMAT(tt.max_size_mb, '#,0.00'),
             ', tempdb data files: ' + CAST(tt.count_files AS varchar(11)),
             @CRLF
             )
       AS details
FROM tempdb_tip AS tt
INNER JOIN @TipDefinition AS td
ON CASE WHEN tt.file_type = 'ROWS' AND tt.space_type = 'allocated' THEN 1330
        WHEN tt.file_type = 'ROWS' AND tt.space_type = 'used' THEN 1340
        WHEN tt.file_type = 'LOG' THEN 1350
   END = td.tip_id
WHERE (
      (tt.file_type = 'ROWS' AND tt.space_type = 'allocated' AND tt.allocated_size_mb / NULLIF(tt.max_size_mb, 0) > @TempdbDataAllocatedToMaxsizeThresholdRatio)
      OR
      (tt.file_type = 'ROWS' AND tt.space_type = 'used' AND tt.used_size_mb / NULLIF(tt.max_size_mb, 0) > @TempdbDataUsedToMaxsizeThresholdRatio)
      OR
      (tt.file_type = 'LOG'  AND tt.space_type = 'allocated' AND tt.allocated_size_mb / NULLIF(tt.max_size_mb, 0) > @TempdbLogAllocatedToMaxsizeThresholdRatio)
      )
      AND
      td.execute_indicator = 1;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1330),(1340),(1350);
    ELSE
        THROW;
END CATCH;

END;

END
ELSE
    INSERT INTO @SkippedTip (tip_id, reason)
    VALUES (1330,'insufficient permissions'),
           (1340,'insufficient permissions'),
           (1350,'insufficient permissions');

-- For tips that follow, VIEW DATABASE STATE is insufficient.
-- Determine if we have VIEW SERVER STATE empirically, given the absense of metadata to determine that otherwise.
BEGIN TRY
    DECLARE @a int = (SELECT 1 FROM sys.dm_os_sys_info);
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 0
        SELECT @ViewServerStateIndicator = 0;
END CATCH;

-- Proceed with the rest of the tips only if required permission is held

IF @ViewServerStateIndicator = 1
BEGIN -- begin tips requiring VIEW SERVER STATE

-- Recent CPU throttling
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1150) AND execute_indicator = 1)

WITH cpu_throttling AS
(
SELECT SUM(duration_ms) / 60000 AS recent_history_duration_minutes,
       SUM(IIF(delta_cpu_active_ms > 0 AND delta_cpu_delayed_ms > 0, 1, 0)) AS count_cpu_delayed_intervals,
       CAST(AVG(IIF(delta_cpu_active_ms > 0 AND delta_cpu_delayed_ms > 0, CAST(delta_cpu_delayed_ms AS decimal(12,0)) / delta_cpu_active_ms, NULL)) * 100 AS decimal(5,2)) AS avg_cpu_delay_percent
FROM sys.dm_resource_governor_workload_groups_history_ex
WHERE @EngineEdition = 5
      AND
      name like 'UserPrimaryGroup.DB%'
      AND
      TRY_CAST(RIGHT(name, LEN(name) - LEN('UserPrimaryGroup.DB') - 2) AS int) = DB_ID()
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1150 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'In the last ', recent_history_duration_minutes,
             ' minutes, there were ', count_cpu_delayed_intervals,
             ' occurrence(s) of CPU throttling. On average, CPU was throttled by ', FORMAT(avg_cpu_delay_percent, '#,0.00'), '%.',
             @CRLF
             ) AS details
FROM cpu_throttling
WHERE avg_cpu_delay_percent > @CPUThrottlingDelayThresholdPercent
;

-- Recent out of memory errors
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1160) AND execute_indicator = 1)

WITH oom AS
(
SELECT SUM(duration_ms) / 60000 AS recent_history_duration_minutes,
       SUM(IIF(delta_out_of_memory_count >= 0, delta_out_of_memory_count, 0)) AS count_oom
FROM sys.dm_resource_governor_resource_pools_history_ex
WHERE @EngineEdition = 5
      AND
      -- Consider user resource pool only
      (
      name LIKE 'SloSharedPool%'
      OR
      name LIKE 'UserPool%'
      )
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1160 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'In the last ', recent_history_duration_minutes,
             ' minutes, there were ', count_oom,
             ' out of memory errors in the ',
             IIF(dso.service_objective = 'ElasticPool', CONCAT(QUOTENAME(dso.elastic_pool_name), ' elastic pool.'), CONCAT(QUOTENAME(DB_NAME(dso.database_id)), ' database.')),
             @CRLF
             ) AS details
FROM oom
CROSS JOIN sys.database_service_objectives AS dso
WHERE count_oom > 0
      AND
      dso.database_id = DB_ID()
;

-- Recent memory grant waits and timeouts
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1165) AND execute_indicator = 1)

WITH memgrant AS
(
SELECT SUM(duration_ms) / 60000 AS recent_history_duration_minutes,
       SUM(IIF(delta_memgrant_waiter_count >= 0, delta_memgrant_waiter_count, 0)) AS count_memgrant_waiter,
       SUM(IIF(delta_memgrant_timeout_count >= 0, delta_memgrant_timeout_count, 0)) AS count_memgrant_timeout
FROM sys.dm_resource_governor_resource_pools_history_ex
WHERE @EngineEdition = 5
      AND
      -- Consider user resource pool only
      (
      name LIKE 'SloSharedPool%'
      OR
      name LIKE 'UserPool%'
      )
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1165 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'In the last ', recent_history_duration_minutes,
             ' minutes, there were ', count_memgrant_waiter,
             ' requests waiting for a memory grant, and ', count_memgrant_timeout,
             ' memory grant timeouts in the ',
             IIF(dso.service_objective = 'ElasticPool', CONCAT(QUOTENAME(dso.elastic_pool_name), ' elastic pool.'), CONCAT(QUOTENAME(DB_NAME(dso.database_id)), ' database.')),
             @CRLF
             ) AS details
FROM memgrant
CROSS JOIN sys.database_service_objectives AS dso
WHERE (count_memgrant_waiter > 0 OR count_memgrant_timeout > 0)
      AND
      dso.database_id = DB_ID()
;

-- Little used nonclustered indexes
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1170) AND execute_indicator = 1)

BEGIN TRY

WITH index_size AS
(
SELECT p.object_id,
       p.index_id,
       SUM(ps.used_page_count) * 8 / 1024. AS total_index_size_mb
FROM sys.partitions AS p
INNER JOIN sys.dm_db_partition_stats AS ps
ON p.partition_id = ps.partition_id
   AND
   p.object_id = ps.object_id
   AND
   p.index_id = ps.index_id
GROUP BY p.object_id,
         p.index_id
),
index_usage AS
(
SELECT QUOTENAME(OBJECT_SCHEMA_NAME(o.object_id)) COLLATE DATABASE_DEFAULT AS schema_name,
       QUOTENAME(o.name) COLLATE DATABASE_DEFAULT AS object_name,
       QUOTENAME(i.name) COLLATE DATABASE_DEFAULT AS index_name,
       ius.user_seeks,
       ius.user_scans,
       ius.user_lookups,
       ius.user_updates,
       ins.total_index_size_mb
FROM sys.dm_db_index_usage_stats AS ius
INNER JOIN sys.indexes AS i
ON ius.object_id = i.object_id
   AND
   ius.index_id = i.index_id
INNER JOIN index_size AS ins
ON i.object_id = ins.object_id
   AND
   i.index_id = ins.index_id
INNER JOIN sys.objects AS o
ON i.object_id = o.object_id
   AND
   ius.object_id = o.object_id
WHERE ius.database_id = DB_ID()
      AND
      i.type_desc = 'NONCLUSTERED'
      AND
      i.is_primary_key = 0
      AND
      i.is_unique_constraint = 0
      AND
      i.is_unique = 0
      AND
      o.is_ms_shipped = 0
      AND
      (ius.user_seeks + ius.user_scans + ius.user_lookups) * 1. / NULLIF(ius.user_updates, 0) < @IndexReadWriteThresholdRatio
),
index_usage_agg AS
(
SELECT STRING_AGG(
                 CAST(CONCAT(
                            schema_name, '.',
                            object_name, '.',
                            index_name,
                            ' (reads: ', FORMAT(user_seeks + user_scans + user_lookups, '#,0'), ' | writes: ', FORMAT(user_updates, '#,0'), ' | size (MB): ', FORMAT(total_index_size_mb, '#,0.00'), ')'
                            ) AS nvarchar(max)), @CRLF
                 ) WITHIN GROUP (ORDER BY schema_name, object_name, index_name)
       AS details,
       COUNT(1) AS index_count
FROM index_usage
HAVING COUNT(1) > 0
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1170 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'Since database engine startup at ', CONVERT(varchar(20), si.sqlserver_start_time, 120),
             ' UTC:',
             REPLICATE(@CRLF, 2),
             'Total indexes: ', FORMAT(index_count, '#,0'),
             @CRLF, @CRLF,
             iua.details,
             @CRLF
             ) AS details
FROM index_usage_agg AS iua
CROSS JOIN sys.dm_os_sys_info AS si
WHERE iua.details IS NOT NULL;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1170);
    ELSE
        THROW;
END CATCH;

-- Compression candidates
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1180) AND execute_indicator = 1)

BEGIN TRY

WITH
recent_cpu_usage AS
(
SELECT AVG(avg_cpu_percent) AS avg_cpu_percent,
       DATEDIFF(minute, MIN(end_time), MAX(end_time)) AS recent_cpu_minutes
FROM sys.dm_db_resource_stats
),
partition_size AS
(
SELECT p.object_id,
       p.index_id,
       p.partition_number,
       p.data_compression_desc,
       SUM(ps.used_page_count) * 8 / 1024. AS total_partition_size_mb,
       SUM(ps.in_row_used_page_count) * 8 / 1024. AS in_row_partition_size_mb,
       SUM(ps.row_overflow_used_page_count) * 8 / 1024. AS row_overflow_partition_size_mb,
       SUM(ps.lob_used_page_count) * 8 / 1024. AS lob_partition_size_mb
FROM sys.partitions AS p
INNER JOIN sys.dm_db_partition_stats AS ps
ON p.partition_id = ps.partition_id
   AND
   p.object_id = ps.object_id
   AND
   p.index_id = ps.index_id
GROUP BY p.object_id,
         p.index_id,
         p.partition_number,
         p.data_compression_desc
),
-- Look at index stats for each partition of an index
partition_stats AS
(
SELECT o.object_id,
       i.name AS index_name,
       i.type_desc AS index_type,
       p.partition_number,
       p.total_partition_size_mb,
       p.in_row_partition_size_mb,
       p.row_overflow_partition_size_mb,
       p.lob_partition_size_mb,
       p.in_row_partition_size_mb / NULLIF(p.total_partition_size_mb, 0) AS compression_eligible_ratio, -- overflow and LOB allocations are not compressible
       p.data_compression_desc,
       ios.leaf_update_count * 1. / NULLIF((ios.range_scan_count + ios.leaf_insert_count + ios.leaf_delete_count + ios.leaf_update_count + ios.leaf_page_merge_count + ios.singleton_lookup_count), 0) AS update_ratio,
       ios.range_scan_count * 1. / NULLIF((ios.range_scan_count + ios.leaf_insert_count + ios.leaf_delete_count + ios.leaf_update_count + ios.leaf_page_merge_count + ios.singleton_lookup_count), 0) AS scan_ratio
FROM sys.objects AS o
INNER JOIN sys.indexes AS i
ON o.object_id = i.object_id
INNER JOIN partition_size AS p
ON i.object_id = p.object_id
   AND
   i.index_id = p.index_id
CROSS APPLY sys.dm_db_index_operational_stats(DB_ID(), o.object_id, i.index_id, p.partition_number) AS ios -- assumption: a representative workload has populated index operational stats
WHERE i.type_desc IN ('CLUSTERED','NONCLUSTERED','HEAP')
      AND
      p.data_compression_desc IN ('NONE','ROW') -- partitions already PAGE compressed are out of scope
      AND
      o.is_ms_shipped = 0
      AND
      i.is_hypothetical = 0
      AND
      i.is_disabled = 0
      AND
      NOT EXISTS (
                 SELECT 1
                 FROM sys.tables AS t
                 WHERE t.object_id = o.object_id
                       AND
                       (
                       t.is_external = 1
                       OR
                       t.is_memory_optimized = 1
                       )
                 )
      AND
      DATABASEPROPERTYEX(DB_NAME(), 'Updateability') = 'READ_WRITE' -- only produce this on primary
),
partition_compression AS
(
SELECT ps.object_id,
       ps.index_name,
       ps.index_type,
       ps.partition_number,
       ps.total_partition_size_mb,
       ps.in_row_partition_size_mb,
       ps.row_overflow_partition_size_mb,
       ps.lob_partition_size_mb,
       SUM(ps.total_partition_size_mb) OVER (PARTITION BY object_id) AS object_size_mb,
       ps.data_compression_desc AS present_compression_type,
       CASE WHEN -- do not choose page compression when no index stats are available and update_ratio and scan_ratio are NULL, due to low confidence
                 (
                 ps.update_ratio < @CompressionPartitionUpdateRatioThreshold1 -- infrequently updated
                 OR
                 (
                 ps.update_ratio BETWEEN @CompressionPartitionUpdateRatioThreshold1 AND @CompressionPartitionUpdateRatioThreshold2
                 AND
                 ps.scan_ratio > @CompressionPartitionScanRatioThreshold1
                 ) -- more frequently updated but also more frequently scanned
                 )
                 AND
                 rcu.avg_cpu_percent < @CompressionCPUHeadroomThreshold1 -- there is ample CPU headroom
                 AND
                 rcu.recent_cpu_minutes > @CompressionMinResourceStatSamples -- there is a sufficient number of CPU usage stats
                 AND
                 ps.compression_eligible_ratio >= @CompressionMinEligibleRatio
            THEN 'PAGE'
            WHEN rcu.avg_cpu_percent < @CompressionCPUHeadroomThreshold2 -- there is some CPU headroom
                 AND
                 rcu.recent_cpu_minutes > @CompressionMinResourceStatSamples -- there is a sufficient number of CPU usage stats
                 AND
                 ps.compression_eligible_ratio >= @CompressionMinEligibleRatio
            THEN 'ROW'
            WHEN rcu.avg_cpu_percent > @CompressionCPUHeadroomThreshold2 -- there is no CPU headroom, can't use compression
                 AND
                 rcu.recent_cpu_minutes > @CompressionMinResourceStatSamples -- there is a sufficient number of CPU usage stats
            THEN 'NONE'
            ELSE NULL -- not enough CPU usage stats to decide
       END
       AS new_compression_type
FROM partition_stats AS ps
CROSS JOIN recent_cpu_usage AS rcu
),
partition_compression_interval
AS
(
SELECT object_id,
       index_name,
       index_type,
       present_compression_type,
       new_compression_type,
       partition_number,
       total_partition_size_mb,
       in_row_partition_size_mb,
       row_overflow_partition_size_mb,
       lob_partition_size_mb,
       object_size_mb,
       partition_number - ROW_NUMBER() OVER (
                                            PARTITION BY object_id, index_name, new_compression_type
                                            ORDER BY partition_number
                                            )
       AS interval_group -- used to pack contiguous partition intervals for the same object, index, compression type
FROM partition_compression
WHERE new_compression_type IS NOT NULL
),
packed_partition_group AS
(
SELECT QUOTENAME(OBJECT_SCHEMA_NAME(object_id)) COLLATE DATABASE_DEFAULT AS schema_name,
       QUOTENAME(OBJECT_NAME(object_id)) COLLATE DATABASE_DEFAULT AS object_name,
       QUOTENAME(index_name) COLLATE DATABASE_DEFAULT AS index_name,
       index_type COLLATE DATABASE_DEFAULT AS index_type,
       present_compression_type,
       new_compression_type,
       SUM(total_partition_size_mb) AS partition_range_total_size_mb,
       SUM(in_row_partition_size_mb) AS partition_range_in_row_size_mb,
       SUM(row_overflow_partition_size_mb) AS partition_range_row_overflow_size_mb,
       SUM(lob_partition_size_mb) AS partition_range_lob_size_mb,
       CONCAT(MIN(partition_number), '-', MAX(partition_number)) AS partition_range,
       MIN(object_size_mb) AS object_size_mb
FROM partition_compression_interval
GROUP BY object_id,
         index_name,
         index_type,
         present_compression_type,
         new_compression_type,
         interval_group
HAVING COUNT(1) > 0
),
packed_partition_group_agg AS
(
SELECT STRING_AGG(
                 CAST(CONCAT(
                            'schema: ', schema_name,
                            ', object: ', object_name,
                            ', index: ' +  index_name,
                            ', index type: ', index_type,
                            ', object size (MB): ', FORMAT(object_size_mb, 'N'),
                            ', partition range: ', partition_range,
                            ', partition range total size (MB): ', FORMAT(partition_range_total_size_mb, 'N'),
                            ' (in-row: ', FORMAT(partition_range_in_row_size_mb, 'N'),
                            ', row overflow: ', FORMAT(partition_range_row_overflow_size_mb, 'N'),
                            ', LOB: ', FORMAT(partition_range_lob_size_mb, 'N'),
                            '), present compression type: ', present_compression_type,
                            ', suggested compression type: ', new_compression_type,
                            ', index rebuild statement: ', CONCAT(
                                                                 'ALTER INDEX ', index_name, ' ON ', schema_name, '.', object_name,
                                                                 ' REBUILD', IIF(partition_range = '1-1', '', CONCAT(' PARTITION = <', partition_range, '>')),
                                                                 ' WITH (', 'DATA_COMPRESSION = ', new_compression_type, ',',
                                                                 ' ONLINE = ON (WAIT_AT_LOW_PRIORITY (MAX_DURATION = 15 MINUTES, ABORT_AFTER_WAIT = SELF)), RESUMABLE = ON);'
                                                                 )
                            ) AS nvarchar(max)), @CRLF
                 )
                 WITHIN GROUP (ORDER BY object_size_mb DESC, object_name, index_name, partition_range, partition_range_total_size_mb, new_compression_type)
       AS details
FROM packed_partition_group
HAVING COUNT(1) > 0
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1180 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'Since database engine startup at ', CONVERT(varchar(20), si.sqlserver_start_time, 120),
             ' UTC:',
             @CRLF,
             ppga.details,
             @CRLF
             ) AS details
FROM packed_partition_group_agg AS ppga
CROSS JOIN sys.dm_os_sys_info AS si
WHERE ppga.details IS NOT NULL
;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1180);
    ELSE
        THROW;
END CATCH;

-- Page compression wasting CPU
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1540) AND execute_indicator = 1)

BEGIN TRY

WITH
partition_size AS
(
SELECT p.object_id,
       p.index_id,
       p.partition_number,
       p.data_compression_desc,
       SUM(ps.used_page_count) * 8 / 1024. AS total_partition_size_mb,
       SUM(ps.in_row_used_page_count) * 8 / 1024. AS in_row_partition_size_mb,
       SUM(ps.row_overflow_used_page_count) * 8 / 1024. AS row_overflow_partition_size_mb,
       SUM(ps.lob_used_page_count) * 8 / 1024. AS lob_partition_size_mb
FROM sys.partitions AS p
INNER JOIN sys.dm_db_partition_stats AS ps
ON p.partition_id = ps.partition_id
   AND
   p.object_id = ps.object_id
   AND
   p.index_id = ps.index_id
GROUP BY p.object_id,
         p.index_id,
         p.partition_number,
         p.data_compression_desc
),
-- Look at index stats for each partition of an index
partition_stats AS
(
SELECT o.object_id,
       i.name AS index_name,
       i.type_desc AS index_type,
       p.partition_number,
       p.total_partition_size_mb,
       p.in_row_partition_size_mb,
       p.row_overflow_partition_size_mb,
       p.lob_partition_size_mb,
       SUM(p.total_partition_size_mb) OVER (PARTITION BY o.object_id) AS object_size_mb,
       p.partition_number - ROW_NUMBER() OVER (
                                              PARTITION BY o.object_id, i.name
                                              ORDER BY p.partition_number
                                              )
       AS interval_group, -- used to pack contiguous partition intervals for the same object and index
       ios.page_compression_attempt_count,
       ios.page_compression_success_count
FROM sys.objects AS o
INNER JOIN sys.indexes AS i
ON o.object_id = i.object_id
INNER JOIN partition_size AS p
ON i.object_id = p.object_id
   AND
   i.index_id = p.index_id
CROSS APPLY sys.dm_db_index_operational_stats(DB_ID(), o.object_id, i.index_id, p.partition_number) AS ios -- assumption: a representative workload has populated index operational stats
WHERE i.type_desc IN ('CLUSTERED','NONCLUSTERED','HEAP')
      AND
      p.data_compression_desc = 'PAGE'
      AND
      o.is_ms_shipped = 0
      AND
      i.is_hypothetical = 0
      AND
      i.is_disabled = 0
      AND
      DATABASEPROPERTYEX(DB_NAME(), 'Updateability') = 'READ_WRITE' -- only produce this on primary
      AND
      ios.page_compression_attempt_count > @PageCompressionAttemptsThreshold
      AND
      ios.page_compression_success_count * 1.0 < @MinPageCompressionSuccessRatio * ios.page_compression_attempt_count
),
packed_partition_group AS
(
SELECT QUOTENAME(OBJECT_SCHEMA_NAME(object_id)) COLLATE DATABASE_DEFAULT AS schema_name,
       QUOTENAME(OBJECT_NAME(object_id)) COLLATE DATABASE_DEFAULT AS object_name,
       QUOTENAME(index_name) COLLATE DATABASE_DEFAULT AS index_name,
       index_type COLLATE DATABASE_DEFAULT AS index_type,
       SUM(total_partition_size_mb) AS partition_range_total_size_mb,
       SUM(in_row_partition_size_mb) AS partition_range_in_row_size_mb,
       SUM(row_overflow_partition_size_mb) AS partition_range_row_overflow_size_mb,
       SUM(lob_partition_size_mb) AS partition_range_lob_size_mb,
       SUM(page_compression_attempt_count) AS page_compression_attempt_count,
       SUM(page_compression_success_count) AS page_compression_success_count,
       CONCAT(MIN(partition_number), '-', MAX(partition_number)) AS partition_range,
       MIN(object_size_mb) AS object_size_mb
FROM partition_stats
GROUP BY object_id,
         index_name,
         index_type,
         interval_group
HAVING COUNT(1) > 0
),
packed_partition_group_agg AS
(
SELECT STRING_AGG(
                 CAST(CONCAT(
                            'schema: ', schema_name,
                            ', object: ', object_name,
                            ', index: ' +  index_name,
                            ', index type: ', index_type,
                            ', object size (MB): ', FORMAT(object_size_mb, 'N'),
                            ', partition range: ', partition_range,
                            ', partition range total size (MB): ', FORMAT(partition_range_total_size_mb, 'N'),
                            ' (in-row: ', FORMAT(partition_range_in_row_size_mb, 'N'),
                            ', row overflow: ', FORMAT(partition_range_row_overflow_size_mb, 'N'),
                            ', LOB: ', FORMAT(partition_range_lob_size_mb, 'N'),
                            '), page compression total attempts: ', FORMAT(page_compression_attempt_count, '#,0'),
                            ', page compression successful attempts: ', FORMAT(page_compression_success_count, '#,0')
                            ) AS nvarchar(max)), @CRLF
                 )
                 WITHIN GROUP (ORDER BY object_size_mb DESC, object_name, index_name, partition_range, partition_range_total_size_mb)
       AS details
FROM packed_partition_group
HAVING COUNT(1) > 0
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1540 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'Since database engine startup at ', CONVERT(varchar(20), si.sqlserver_start_time, 120),
             ' UTC:',
             @CRLF,
             ppga.details,
             @CRLF
             ) AS details
FROM packed_partition_group_agg AS ppga
CROSS JOIN sys.dm_os_sys_info AS si
WHERE ppga.details IS NOT NULL
;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1540);
    ELSE
        THROW;
END CATCH;

-- Missing indexes
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1210) AND execute_indicator = 1)

BEGIN TRY

WITH missing_index_agg AS
(
SELECT STRING_AGG(
                 CAST(CONCAT(
                            'object_name: ',
                            d.statement,
                            ', equality columns: ' + d.equality_columns,
                            ', inequality columns: ' + d.inequality_columns,
                            ', included columns: ' + d.included_columns,
                            ', unique compiles: ', FORMAT(gs.unique_compiles, '#,0'),
                            ', user seeks: ', FORMAT(gs.user_seeks, '#,0'),
                            ', user scans: ', FORMAT(gs.user_scans, '#,0'),
                            ', avg user impact: ', gs.avg_user_impact, '%.'
                            ) AS nvarchar(max)), @CRLF
                 )
                 WITHIN GROUP (ORDER BY avg_user_impact DESC, statement)
       AS details,
       COUNT(1) AS index_count
FROM sys.dm_db_missing_index_group_stats AS gs
INNER JOIN sys.dm_db_missing_index_groups AS g
ON gs.group_handle = g.index_group_handle
INNER JOIN sys.dm_db_missing_index_details AS d
ON g.index_handle = d.index_handle
WHERE gs.avg_user_impact > @MissingIndexAvgUserImpactThreshold
HAVING COUNT(1) > 0
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1210 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'Since database engine startup at ', CONVERT(varchar(20), si.sqlserver_start_time, 120),
             ' UTC:',
             REPLICATE(@CRLF, 2),
             'Total indexes: ', FORMAT(index_count, '#,0'),
             @CRLF, @CRLF,
             mia.details,
             @CRLF
             ) AS details
FROM missing_index_agg AS mia
CROSS JOIN sys.dm_os_sys_info AS si
WHERE mia.details IS NOT NULL;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1210);
    ELSE
        THROW;
END CATCH;

-- Data IO reaching user workload group SLO limit, or significant IO RG impact at user workload group level
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1230,1240) AND execute_indicator = 1)

WITH
io_rg_snapshot AS
(
SELECT wgh.snapshot_time,
       wgh.duration_ms,
       wgh.delta_reads_issued / (wgh.duration_ms / 1000.) AS read_iops,
       wgh.delta_writes_issued / (wgh.duration_ms / 1000.) AS write_iops, -- this is commonly zero, most writes are background writes to data files
       (wgh.delta_read_bytes / (wgh.duration_ms / 1000.)) / 1024. / 1024 AS read_throughput_mbps,
       wgh.delta_background_writes / (wgh.duration_ms / 1000.) AS background_write_iops, -- checkpoint, lazy writer, PVS
       (wgh.delta_background_write_bytes / (wgh.duration_ms / 1000.)) / 1024. / 1024 AS background_write_throughput_mbps,
       wgh.delta_read_stall_queued_ms, -- time spent in SQL IO RG
       wgh.delta_read_stall_ms, -- total time spent completing the IO, including SQL IO RG time
       rg.primary_group_max_io, -- workload group IOPS limit
       IIF(
          wgh.delta_reads_issued
          +
          IIF(rg.govern_background_io = 0, wgh.delta_background_writes, 0) -- depending on SLO, background write IO may or may not be accounted toward workload group IOPS limit
          >
          CAST(rg.primary_group_max_io AS bigint) * wgh.duration_ms / 1000 * @GroupIORGAtLimitThresholdRatio, -- over n% of IOPS budget for this interval
          1,
          0
          ) AS reached_iops_limit_indicator,
       IIF(
          wgh.delta_read_stall_queued_ms * 1. / NULLIF(wgh.delta_read_stall_ms, 0)
          >
          @GroupIORGImpactRatio,
          1,
          0
          ) AS significant_io_rg_impact_indicator -- over n% of IO stall is spent in SQL IO RG
FROM sys.dm_resource_governor_workload_groups_history_ex AS wgh
CROSS JOIN sys.dm_user_db_resource_governance AS rg
WHERE @EngineEdition = 5
      AND
      rg.database_id = DB_ID()
      AND
      wgh.name like 'UserPrimaryGroup.DB%'
      AND
      TRY_CAST(RIGHT(wgh.name, LEN(wgh.name) - LEN('UserPrimaryGroup.DB') - 2) AS int) = DB_ID()
),
pre_packed_io_rg_snapshot AS
(
SELECT SUM(duration_ms) OVER (ORDER BY (SELECT 'no order')) / 60000 AS recent_history_duration_minutes,
       duration_ms,
       snapshot_time,
       read_iops,
       write_iops,
       background_write_iops,
       delta_read_stall_queued_ms,
       delta_read_stall_ms,
       read_throughput_mbps,
       background_write_throughput_mbps,
       primary_group_max_io,
       reached_iops_limit_indicator,
       significant_io_rg_impact_indicator,
       ROW_NUMBER() OVER (ORDER BY snapshot_time) -- row number across all readings, in increasing chronological order
       -
       SUM(reached_iops_limit_indicator) OVER (ORDER BY snapshot_time ROWS UNBOUNDED PRECEDING) -- running count of all intervals where the threshold was exceeded
       AS limit_grouping_helper, -- this difference remains constant while the threshold is exceeded, and can be used to collapse/pack an interval using aggregation
       ROW_NUMBER() OVER (ORDER BY snapshot_time)
       -
       SUM(significant_io_rg_impact_indicator) OVER (ORDER BY snapshot_time ROWS UNBOUNDED PRECEDING)
       AS impact_grouping_helper
FROM io_rg_snapshot
),
-- each row is an interval where IOPS was continuously at limit, with aggregated IO stats
packed_io_rg_snapshot_limit AS
(
SELECT MIN(recent_history_duration_minutes) AS recent_history_duration_minutes,
       MIN(snapshot_time) AS min_snapshot_time,
       MAX(snapshot_time) AS max_snapshot_time,
       AVG(duration_ms) AS avg_snapshot_duration_ms,
       SUM(delta_read_stall_queued_ms) AS total_read_queued_time_ms,
       SUM(delta_read_stall_ms) AS total_read_time_ms,
       AVG(read_iops) AS avg_read_iops,
       MAX(read_iops) AS max_read_iops,
       AVG(write_iops) AS avg_write_iops,
       MAX(write_iops) AS max_write_iops,
       AVG(background_write_iops) AS avg_background_write_iops,
       MAX(background_write_iops) AS max_background_write_iops,
       AVG(read_throughput_mbps) AS avg_read_throughput_mbps,
       MAX(read_throughput_mbps) AS max_read_throughput_mbps,
       AVG(background_write_throughput_mbps) AS avg_background_write_throughput_mbps,
       MAX(background_write_throughput_mbps) AS max_background_write_throughput_mbps,
       MIN(primary_group_max_io) AS primary_group_max_io
FROM pre_packed_io_rg_snapshot
WHERE reached_iops_limit_indicator = 1
GROUP BY limit_grouping_helper
),
-- each row is an interval where IO RG impact remained over the significance threshold, with aggregated IO stats
packed_io_rg_snapshot_impact AS
(
SELECT MIN(recent_history_duration_minutes) AS recent_history_duration_minutes,
       MIN(snapshot_time) AS min_snapshot_time,
       MAX(snapshot_time) AS max_snapshot_time,
       AVG(duration_ms) AS avg_snapshot_duration_ms,
       SUM(delta_read_stall_queued_ms) AS total_read_queued_time_ms,
       SUM(delta_read_stall_ms) AS total_read_time_ms,
       AVG(read_iops) AS avg_read_iops,
       MAX(read_iops) AS max_read_iops,
       AVG(write_iops) AS avg_write_iops,
       MAX(write_iops) AS max_write_iops,
       AVG(background_write_iops) AS avg_background_write_iops,
       MAX(background_write_iops) AS max_background_write_iops,
       AVG(read_throughput_mbps) AS avg_read_throughput_mbps,
       MAX(read_throughput_mbps) AS max_read_throughput_mbps,
       AVG(background_write_throughput_mbps) AS avg_background_write_throughput_mbps,
       MAX(background_write_throughput_mbps) AS max_background_write_throughput_mbps,
       MIN(primary_group_max_io) AS primary_group_max_io
FROM pre_packed_io_rg_snapshot
WHERE significant_io_rg_impact_indicator = 1
GROUP BY impact_grouping_helper
),
-- one row, a summary across all intervals where IOPS was continuously at limit
packed_io_rg_snapshot_limit_agg AS
(
SELECT MIN(recent_history_duration_minutes) AS recent_history_duration_minutes,
       MAX(DATEDIFF(second, min_snapshot_time, max_snapshot_time) + avg_snapshot_duration_ms / 1000.) AS longest_io_rg_at_limit_duration_seconds,
       COUNT(1) AS count_io_rg_at_limit_intervals,
       SUM(total_read_time_ms) AS total_read_time_ms,
       SUM(total_read_queued_time_ms) AS total_read_queued_time_ms,
       AVG(avg_read_iops) AS avg_read_iops,
       MAX(max_read_iops) AS max_read_iops,
       AVG(avg_write_iops) AS avg_write_iops,
       MAX(max_write_iops) AS max_write_iops,
       AVG(avg_background_write_iops) AS avg_background_write_iops,
       MAX(max_background_write_iops) AS max_background_write_iops,
       AVG(avg_read_throughput_mbps) AS avg_read_throughput_mbps,
       MAX(max_read_throughput_mbps) AS max_read_throughput_mbps,
       AVG(avg_background_write_throughput_mbps) AS avg_background_write_throughput_mbps,
       MAX(max_background_write_throughput_mbps) AS max_background_write_throughput_mbps,
       MIN(primary_group_max_io) AS primary_group_max_io
FROM packed_io_rg_snapshot_limit
),
-- one row, a summary across all intervals where IO RG impact remained over the significance threshold
packed_io_rg_snapshot_impact_agg AS
(
SELECT MIN(recent_history_duration_minutes) AS recent_history_duration_minutes,
       MAX(DATEDIFF(second, min_snapshot_time, max_snapshot_time) + avg_snapshot_duration_ms / 1000.) AS longest_io_rg_impact_duration_seconds,
       COUNT(1) AS count_io_rg_impact_intervals,
       SUM(total_read_time_ms) AS total_read_time_ms,
       SUM(total_read_queued_time_ms) AS total_read_queued_time_ms,
       AVG(avg_read_iops) AS avg_read_iops,
       MAX(max_read_iops) AS max_read_iops,
       AVG(avg_write_iops) AS avg_write_iops,
       MAX(max_write_iops) AS max_write_iops,
       AVG(avg_background_write_iops) AS avg_background_write_iops,
       MAX(max_background_write_iops) AS max_background_write_iops,
       AVG(avg_read_throughput_mbps) AS avg_read_throughput_mbps,
       MAX(max_read_throughput_mbps) AS max_read_throughput_mbps,
       AVG(avg_background_write_throughput_mbps) AS avg_background_write_throughput_mbps,
       MAX(max_background_write_throughput_mbps) AS max_background_write_throughput_mbps
FROM packed_io_rg_snapshot_impact
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT td.tip_id,
       CONCAT(
             @NbspCRLF,
             'In the last ', l.recent_history_duration_minutes,
             ' minutes, there were ', l.count_io_rg_at_limit_intervals,
             ' time interval(s) when total data IO approached the workload group (database-level) IOPS limit of the service objective, ', FORMAT(l.primary_group_max_io, '#,0'), ' IOPS.', @CRLF,  @CRLF,
             'Aggregated across these intervals, IO statistics were: ', @CRLF, @CRLF,
             'longest interval duration: ', FORMAT(l.longest_io_rg_at_limit_duration_seconds, '#,0'), ' seconds; ', @CRLF,
             'total read IO time: ', FORMAT(l.total_read_time_ms, '#,0'), ' milliseconds; ', @CRLF,
             'total queued read IO time: ', FORMAT(l.total_read_queued_time_ms, '#,0'), ' milliseconds; ', @CRLF,
             'average read IOPS: ', FORMAT(l.avg_read_iops, '#,0'), '; ', @CRLF,
             'maximum read IOPS: ', FORMAT(l.max_read_iops, '#,0'), '; ', @CRLF,
             'average write IOPS: ', FORMAT(l.avg_write_iops, '#,0'), '; ', @CRLF,
             'maximum write IOPS: ', FORMAT(l.max_write_iops, '#,0'), '; ', @CRLF,
             'average background write IOPS: ', FORMAT(l.avg_background_write_iops, '#,0'), '; ', @CRLF,
             'maximum background write IOPS: ', FORMAT(l.max_background_write_iops, '#,0'), '; ', @CRLF,
             'average read IO throughput: ', FORMAT(l.avg_read_throughput_mbps, '#,0.00'), ' MBps; ', @CRLF,
             'maximum read IO throughput: ', FORMAT(l.max_read_throughput_mbps, '#,0.00'), ' MBps; ', @CRLF,
             'average background write IO throughput: ', FORMAT(l.avg_background_write_throughput_mbps, '#,0.00'), ' MBps; ', @CRLF,
             'maximum background write IO throughput: ', FORMAT(l.max_background_write_throughput_mbps, '#,0.00'), ' MBps.',
             @CRLF
             )
       AS details
FROM packed_io_rg_snapshot_limit_agg AS l
INNER JOIN @TipDefinition AS td
ON td.tip_id = 1230
WHERE l.count_io_rg_at_limit_intervals > 0
      AND
      td.execute_indicator = 1
UNION
SELECT td.tip_id,
       CONCAT(
             @NbspCRLF,
             'In the last ', i.recent_history_duration_minutes,
             ' minutes, there were ', i.count_io_rg_impact_intervals,
             ' time interval(s) when workload group (database-level) resource governance for the selected service objective was significantly delaying IO requests.', @CRLF, @CRLF,
             'Aggregated across these intervals, IO statistics were: ', @CRLF, @CRLF,
             'longest interval duration: ', FORMAT(i.longest_io_rg_impact_duration_seconds, '#,0'), ' seconds; ', @CRLF,
             'total read IO time: ', FORMAT(i.total_read_time_ms, '#,0'), ' milliseconds; ', @CRLF,
             'total queued read IO time: ', FORMAT(i.total_read_queued_time_ms, '#,0'), ' milliseconds; ', @CRLF,
             'average read IOPS: ', FORMAT(i.avg_read_iops, '#,0'), '; ', @CRLF,
             'maximum read IOPS: ', FORMAT(i.max_read_iops, '#,0'), '; ', @CRLF,
             'average write IOPS: ', FORMAT(i.avg_write_iops, '#,0'), '; ', @CRLF,
             'maximum write IOPS: ', FORMAT(i.max_write_iops, '#,0'), '; ', @CRLF,
             'average background write IOPS: ', FORMAT(i.avg_background_write_iops, '#,0'), '; ', @CRLF,
             'maximum background write IOPS: ', FORMAT(i.max_background_write_iops, '#,0'), '; ', @CRLF,
             'average read IO throughput: ', FORMAT(i.avg_read_throughput_mbps, '#,0.00'), ' MBps; ', @CRLF,
             'maximum read IO throughput: ', FORMAT(i.max_read_throughput_mbps, '#,0.00'), ' MBps; ', @CRLF,
             'average background write IO throughput: ', FORMAT(i.avg_background_write_throughput_mbps, '#,0.00'), ' MBps; ', @CRLF,
             'maximum background write IO throughput: ', FORMAT(i.max_background_write_throughput_mbps, '#,0.00'), ' MBps.',
             @CRLF
             )
       AS details
FROM packed_io_rg_snapshot_impact_agg AS i
INNER JOIN @TipDefinition AS td
ON td.tip_id = 1240
WHERE i.count_io_rg_impact_intervals > 0
      AND
      td.execute_indicator = 1
;

-- Data IO reaching user resource pool SLO limit, or significant IO RG impact at user resource pool level
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1250,1260) AND execute_indicator = 1)

WITH
io_rg_snapshot AS
(
SELECT rph.snapshot_time,
       rph.duration_ms,
       rph.delta_read_io_issued / (rph.duration_ms / 1000.) AS read_iops,
       rph.delta_write_io_issued / (rph.duration_ms / 1000.) AS write_iops, -- this is commonly zero, most writes are background writes to data files
       (rph.delta_read_bytes / (rph.duration_ms / 1000.)) / 1024. / 1024 AS read_throughput_mbps,
       rph.delta_read_io_stall_queued_ms, -- time spent in SQL IO RG
       rph.delta_read_io_stall_ms, -- total time spent completing the IO, including SQL IO RG time
       rg.pool_max_io, -- resource pool IOPS limit
       IIF(
          rph.delta_read_io_issued
          >
          CAST(rg.pool_max_io AS bigint) * rph.duration_ms / 1000 * @PoolIORGAtLimitThresholdRatio, -- over n% of IOPS budget for this interval
          1,
          0
          ) AS reached_iops_limit_indicator,
       IIF(
          rph.delta_read_io_stall_queued_ms * 1. / NULLIF(rph.delta_read_io_stall_ms, 0)
          >
          @PoolIORGImpactRatio,
          1,
          0
          ) AS significant_io_rg_impact_indicator -- over n% of IO stall is spent in SQL IO RG
FROM sys.dm_resource_governor_resource_pools_history_ex AS rph
CROSS JOIN sys.dm_user_db_resource_governance AS rg
WHERE @EngineEdition = 5
      AND
      rg.database_id = DB_ID()
      AND
      -- Consider user resource pool only
      (
      rph.name LIKE 'SloSharedPool%'
      OR
      rph.name LIKE 'UserPool%'
      )
      AND
      rg.pool_max_io > 0 -- resource pool IO is governed
),
pre_packed_io_rg_snapshot AS
(
SELECT SUM(duration_ms) OVER (ORDER BY (SELECT 'no order')) / 60000 AS recent_history_duration_minutes,
       duration_ms,
       snapshot_time,
       read_iops,
       write_iops,
       delta_read_io_stall_queued_ms,
       delta_read_io_stall_ms,
       read_throughput_mbps,
       pool_max_io,
       reached_iops_limit_indicator,
       significant_io_rg_impact_indicator,
       ROW_NUMBER() OVER (ORDER BY snapshot_time) -- row number across all readings, in increasing chronological order
       -
       SUM(reached_iops_limit_indicator) OVER (ORDER BY snapshot_time ROWS UNBOUNDED PRECEDING) -- running count of all intervals where the threshold was exceeded
       AS limit_grouping_helper, -- this difference remains constant while the threshold is exceeded, and can be used to collapse/pack an interval using aggregation
       ROW_NUMBER() OVER (ORDER BY snapshot_time)
       -
       SUM(significant_io_rg_impact_indicator) OVER (ORDER BY snapshot_time ROWS UNBOUNDED PRECEDING)
       AS impact_grouping_helper
FROM io_rg_snapshot
),
-- each row is an interval where IOPS was continuously at limit, with aggregated IO stats
packed_io_rg_snapshot_limit AS
(
SELECT MIN(recent_history_duration_minutes) AS recent_history_duration_minutes,
       MIN(snapshot_time) AS min_snapshot_time,
       MAX(snapshot_time) AS max_snapshot_time,
       AVG(duration_ms) AS avg_snapshot_duration_ms,
       SUM(delta_read_io_stall_queued_ms) AS total_read_queued_time_ms,
       SUM(delta_read_io_stall_ms) AS total_read_time_ms,
       AVG(read_iops) AS avg_read_iops,
       MAX(read_iops) AS max_read_iops,
       AVG(write_iops) AS avg_write_iops,
       MAX(write_iops) AS max_write_iops,
       AVG(read_throughput_mbps) AS avg_read_throughput_mbps,
       MAX(read_throughput_mbps) AS max_read_throughput_mbps,
       MIN(pool_max_io) AS pool_max_io
FROM pre_packed_io_rg_snapshot
WHERE reached_iops_limit_indicator = 1
GROUP BY limit_grouping_helper
),
-- each row is an interval where IO RG impact remained over the significance threshold, with aggregated IO stats
packed_io_rg_snapshot_impact AS
(
SELECT MIN(recent_history_duration_minutes) AS recent_history_duration_minutes,
       MIN(snapshot_time) AS min_snapshot_time,
       MAX(snapshot_time) AS max_snapshot_time,
       AVG(duration_ms) AS avg_snapshot_duration_ms,
       SUM(delta_read_io_stall_queued_ms) AS total_read_queued_time_ms,
       SUM(delta_read_io_stall_ms) AS total_read_time_ms,
       AVG(read_iops) AS avg_read_iops,
       MAX(read_iops) AS max_read_iops,
       AVG(write_iops) AS avg_write_iops,
       MAX(write_iops) AS max_write_iops,
       AVG(read_throughput_mbps) AS avg_read_throughput_mbps,
       MAX(read_throughput_mbps) AS max_read_throughput_mbps,
       MIN(pool_max_io) AS pool_max_io
FROM pre_packed_io_rg_snapshot
WHERE significant_io_rg_impact_indicator = 1
GROUP BY impact_grouping_helper
),
-- one row, a summary across all intervals where IOPS was continuously at limit
packed_io_rg_snapshot_limit_agg AS
(
SELECT MIN(recent_history_duration_minutes) AS recent_history_duration_minutes,
       MAX(DATEDIFF(second, min_snapshot_time, max_snapshot_time) + avg_snapshot_duration_ms / 1000.) AS longest_io_rg_at_limit_duration_seconds,
       COUNT(1) AS count_io_rg_at_limit_intervals,
       SUM(total_read_time_ms) AS total_read_time_ms,
       SUM(total_read_queued_time_ms) AS total_read_queued_time_ms,
       AVG(avg_read_iops) AS avg_read_iops,
       MAX(max_read_iops) AS max_read_iops,
       AVG(avg_write_iops) AS avg_write_iops,
       MAX(max_write_iops) AS max_write_iops,
       AVG(avg_read_throughput_mbps) AS avg_read_throughput_mbps,
       MAX(max_read_throughput_mbps) AS max_read_throughput_mbps,
       MIN(pool_max_io) AS pool_max_io
FROM packed_io_rg_snapshot_limit
),
-- one row, a summary across all intervals where IO RG impact remained over the significance threshold
packed_io_rg_snapshot_impact_agg AS
(
SELECT MIN(recent_history_duration_minutes) AS recent_history_duration_minutes,
       MAX(DATEDIFF(second, min_snapshot_time, max_snapshot_time) + avg_snapshot_duration_ms / 1000.) AS longest_io_rg_impact_duration_seconds,
       COUNT(1) AS count_io_rg_impact_intervals,
       SUM(total_read_time_ms) AS total_read_time_ms,
       SUM(total_read_queued_time_ms) AS total_read_queued_time_ms,
       AVG(avg_read_iops) AS avg_read_iops,
       MAX(max_read_iops) AS max_read_iops,
       AVG(avg_write_iops) AS avg_write_iops,
       MAX(max_write_iops) AS max_write_iops,
       AVG(avg_read_throughput_mbps) AS avg_read_throughput_mbps,
       MAX(max_read_throughput_mbps) AS max_read_throughput_mbps
FROM packed_io_rg_snapshot_impact
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT td.tip_id,
       CONCAT(
             @NbspCRLF,
             'In the last ', l.recent_history_duration_minutes,
             ' minutes, there were ', l.count_io_rg_at_limit_intervals,
             ' time interval(s) when total data IO approached the resource pool IOPS limit of the service objective ', IIF(dso.service_objective = 'ElasticPool', CONCAT('for elastic pool ', QUOTENAME(dso.elastic_pool_name)), ''), ', ', FORMAT(l.pool_max_io, '#,0'), ' IOPS.', @CRLF, @CRLF,
             'Aggregated across these intervals, IO statistics were: ', @CRLF, @CRLF,
             'longest interval duration: ', FORMAT(l.longest_io_rg_at_limit_duration_seconds, '#,0'), ' seconds; ', @CRLF,
             'total read IO time: ', FORMAT(l.total_read_time_ms, '#,0'), ' milliseconds; ', @CRLF,
             'total queued read IO time: ', FORMAT(l.total_read_queued_time_ms, '#,0'), ' milliseconds; ', @CRLF,
             'average read IOPS: ', FORMAT(l.avg_read_iops, '#,0'), '; ', @CRLF,
             'maximum read IOPS: ', FORMAT(l.max_read_iops, '#,0'), '; ', @CRLF,
             'average write IOPS: ', FORMAT(l.avg_write_iops, '#,0'), '; ', @CRLF,
             'maximum write IOPS: ', FORMAT(l.max_write_iops, '#,0'), '; ', @CRLF,
             'average read IO throughput: ', FORMAT(l.avg_read_throughput_mbps, '#,0.00'), ' MBps; ', @CRLF,
             'maximum read IO throughput: ', FORMAT(l.max_read_throughput_mbps, '#,0.00'), ' MBps.',
             @CRLF
             )
       AS details
FROM packed_io_rg_snapshot_limit_agg AS l
INNER JOIN @TipDefinition AS td
ON td.tip_id = 1250
CROSS JOIN sys.database_service_objectives AS dso
WHERE l.count_io_rg_at_limit_intervals > 0
      AND
      dso.database_id = DB_ID()
      AND
      td.execute_indicator = 1
UNION
SELECT td.tip_id,
       CONCAT(
             @NbspCRLF,
             'In the last ', i.recent_history_duration_minutes,
             ' minutes, there were ', i.count_io_rg_impact_intervals,
             ' time interval(s) when resource pool resource governance for the selected service objective was significantly delaying IO requests', IIF(dso.service_objective = 'ElasticPool', CONCAT(' for elastic pool ', QUOTENAME(dso.elastic_pool_name)), ''), '.', @CRLF, @CRLF,
             'Aggregated across these intervals, IO statistics were: ', @CRLF, @CRLF,
             'longest interval duration: ', FORMAT(i.longest_io_rg_impact_duration_seconds, '#,0'), ' seconds; ', @CRLF,
             'total read IO time: ', FORMAT(i.total_read_time_ms, '#,0'), ' milliseconds; ', @CRLF,
             'total queued read IO time: ', FORMAT(i.total_read_queued_time_ms, '#,0'), ' milliseconds; ', @CRLF,
             'average read IOPS: ', FORMAT(i.avg_read_iops, '#,0'), '; ', @CRLF,
             'maximum read IOPS: ', FORMAT(i.max_read_iops, '#,0'), '; ', @CRLF,
             'average write IOPS: ', FORMAT(i.avg_write_iops, '#,0'), '; ', @CRLF,
             'maximum write IOPS: ', FORMAT(i.max_write_iops, '#,0'), '; ', @CRLF,
             'average read IO throughput: ', FORMAT(i.avg_read_throughput_mbps, '#,0.00'), ' MBps; ', @CRLF,
             'maximum read IO throughput: ', FORMAT(i.max_read_throughput_mbps, '#,0.00'), ' MBps.',
             @CRLF
             )
       AS details
FROM packed_io_rg_snapshot_impact_agg AS i
INNER JOIN @TipDefinition AS td
ON td.tip_id = 1260
CROSS JOIN sys.database_service_objectives AS dso
WHERE i.count_io_rg_impact_intervals > 0
      AND
      dso.database_id = DB_ID()
      AND
      td.execute_indicator = 1
;

-- Large PVS
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1270) AND execute_indicator = 1)

BEGIN TRY

WITH
db_size AS
(
SELECT SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS bigint) * 8 / 1024. / 1024) AS space_used_gb,
       SUM(CAST(size AS bigint) * 8 / 1024. / 1024) AS space_allocated_gb,
       NULLIF(CAST(DATABASEPROPERTYEX(DB_NAME(), 'MaxSizeInBytes') AS bigint), -1) / 1024. / 1024 / 1024 AS max_size_gb
FROM sys.database_files
WHERE type_desc = 'ROWS'
),
pvs_db_stats AS
(
SELECT pvss.persistent_version_store_size_kb / 1024. / 1024 AS persistent_version_store_size_gb,
       pvss.online_index_version_store_size_kb / 1024. / 1024 AS online_index_version_store_size_gb,
       ds.space_used_gb,
       ds.space_allocated_gb,
       ds.max_size_gb,
       pvss.current_aborted_transaction_count,
       pvss.aborted_version_cleaner_start_time,
       pvss.aborted_version_cleaner_end_time,
       dt.database_transaction_begin_time AS oldest_transaction_begin_time,
       asdt.session_id AS active_transaction_session_id,
       asdt.elapsed_time_seconds AS active_transaction_elapsed_time_seconds
FROM sys.dm_tran_persistent_version_store_stats AS pvss
CROSS JOIN db_size AS ds
LEFT JOIN sys.dm_tran_database_transactions AS dt
ON pvss.oldest_active_transaction_id = dt.transaction_id
   AND
   pvss.database_id = dt.database_id
LEFT JOIN sys.dm_tran_active_snapshot_database_transactions AS asdt
ON pvss.min_transaction_timestamp = asdt.transaction_sequence_num
   OR
   pvss.online_index_min_transaction_timestamp = asdt.transaction_sequence_num
WHERE pvss.database_id = DB_ID()
      AND
      (
      pvss.persistent_version_store_size_kb > @PVSMinimumSizeThresholdGB * 1024 * 1024 -- PVS is larger than n GB
      OR
      (
      -- compare PVS size to database MAXSIZE, or to allocated size when MAXSIZE is not defined (Hyperscale, Managed Instance)
      pvss.persistent_version_store_size_kb >= @PVSToMaxSizeMinThresholdRatio * COALESCE(ds.max_size_gb, ds.space_allocated_gb) * 1024 * 1024 -- PVS is larger than n% of database max/allocated size
      AND
      pvss.persistent_version_store_size_kb > 1048576 -- don't consider PVS smaller than 1 GB as large
      )
      )
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1270 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'PVS size (GB): ', FORMAT(persistent_version_store_size_gb, 'N'), @CRLF,
             'online index version store size (GB): ', FORMAT(online_index_version_store_size_gb, 'N'), @CRLF,
             'used data size (GB): ', FORMAT(space_used_gb, 'N'), @CRLF,
             'allocated data size (GB): ', FORMAT(space_allocated_gb, 'N'), @CRLF,
             'maximum database size (GB): ' + FORMAT(max_size_gb, 'N') + @CRLF, -- omit for Hyperscale and MI as not applicable
             'current aborted transaction count: ', FORMAT(current_aborted_transaction_count, '#,0'), @CRLF,
             'aborted transaction version cleaner start time (UTC): ', ISNULL(CONVERT(varchar(20), aborted_version_cleaner_start_time, 120), '-'), @CRLF,
             'aborted transaction version cleaner end time (UTC): ', ISNULL(CONVERT(varchar(20), aborted_version_cleaner_end_time, 120), '-'), @CRLF,
             'oldest transaction begin time (UTC): ',  ISNULL(CONVERT(varchar(30), oldest_transaction_begin_time, 121), '-'), @CRLF,
             'active transaction session_id: ', ISNULL(CAST(active_transaction_session_id AS varchar(11)), '-'), @CRLF,
             'active transaction elapsed time (seconds): ', ISNULL(CAST(active_transaction_elapsed_time_seconds AS varchar(11)), '-'),
             @CRLF
             )
       AS details
FROM pvs_db_stats;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1270);
    ELSE
        THROW;
END CATCH;

-- CCI candidates
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1290) AND execute_indicator = 1)

BEGIN TRY

WITH
any_partition AS
(
SELECT p.object_id,
       p.index_id,
       p.partition_number,
       p.rows,
       p.data_compression_desc,
       ps.used_page_count * 8 / 1024. AS partition_size_mb,
       MAX(IIF(p.data_compression_desc IN ('COLUMNSTORE','COLUMNSTORE_ARCHIVE'), 1, 0)) OVER (PARTITION BY p.object_id) AS object_has_columnstore_indexes,
       MAX(IIF(p.rows >= 102400, 1, 0)) OVER (PARTITION BY p.object_id) AS object_has_columnstore_compressible_partitions
FROM sys.partitions AS p
INNER JOIN sys.dm_db_partition_stats AS ps
ON p.partition_id = ps.partition_id
   AND
   p.object_id = ps.object_id
   AND
   p.index_id = ps.index_id
WHERE -- restrict to objects that do not have column data types not supported for CCI
      NOT EXISTS (
                 SELECT 1
                 FROM sys.columns AS c
                 INNER JOIN sys.types AS t
                 ON c.system_type_id = t.system_type_id
                 WHERE c.object_id = p.object_id
                       AND
                       t.name IN ('text','ntext','image','timestamp','sql_variant','hierarchyid','geometry','geography','xml')
                 )
),
candidate_partition AS
(
SELECT object_id,
       index_id,
       partition_number,
       rows,
       partition_size_mb
FROM any_partition
WHERE data_compression_desc IN ('NONE','ROW','PAGE')
      AND
      -- an object with any kind of columnstore is not a candidate
      object_has_columnstore_indexes = 0
      AND
      object_has_columnstore_compressible_partitions = 1
      AND
      DATABASEPROPERTYEX(DB_NAME(), 'Updateability') = 'READ_WRITE' -- only produce this on primary
),
table_operational_stats AS -- summarize operational stats for heap, CI, and NCI
(
SELECT cp.object_id,
       SUM(IIF(cp.index_id IN (0,1), partition_size_mb, 0)) AS table_size_mb, -- exclude NCI size
       SUM(IIF(cp.index_id IN (0,1), 1, 0)) AS partition_count,
       SUM(ios.leaf_insert_count) AS lead_insert_count,
       SUM(ios.leaf_update_count) AS leaf_update_count,
       SUM(ios.leaf_delete_count + ios.leaf_ghost_count) AS leaf_delete_count,
       SUM(ios.range_scan_count) AS range_scan_count,
       SUM(ios.singleton_lookup_count) AS singleton_lookup_count
FROM candidate_partition AS cp
CROSS APPLY sys.dm_db_index_operational_stats(DB_ID(), cp.object_id, cp.index_id, cp.partition_number) AS ios -- assumption: a representative workload has populated index operational stats for relevant tables
GROUP BY cp.object_id
),
cci_candidate_table AS
(
SELECT QUOTENAME(OBJECT_SCHEMA_NAME(t.object_id)) COLLATE DATABASE_DEFAULT AS schema_name,
       QUOTENAME(t.name) COLLATE DATABASE_DEFAULT AS table_name,
       tos.table_size_mb,
       tos.partition_count,
       tos.lead_insert_count AS insert_count,
       tos.leaf_update_count AS update_count,
       tos.leaf_delete_count AS delete_count,
       tos.singleton_lookup_count AS singleton_lookup_count,
       tos.range_scan_count AS range_scan_count,
       ius.user_seeks AS seek_count,
       ius.user_scans AS full_scan_count,
       ius.user_lookups AS lookup_count
FROM sys.tables AS t
INNER JOIN sys.indexes AS i
ON t.object_id = i.object_id
INNER JOIN table_operational_stats AS tos
ON t.object_id = tos.object_id
INNER JOIN sys.dm_db_index_usage_stats AS ius
ON t.object_id = ius.object_id
   AND
   i.index_id = ius.index_id
WHERE i.type IN (0,1) -- clustered index or heap
      AND
      tos.table_size_mb > @CCICandidateMinSizeGB * 1024. -- consider sufficiently large tables only
      AND
      t.is_ms_shipped = 0
      AND
      -- conservatively require a CCI candidate to have no updates, seeks, or lookups
      tos.leaf_update_count = 0
      AND
      tos.singleton_lookup_count = 0
      AND
      ius.user_lookups = 0
      AND
      ius.user_seeks = 0
      AND
      ius.user_scans > 0 -- require a CCI candidate to have some full scans
),
cci_candidate_details AS
(
SELECT STRING_AGG(
                 CAST(CONCAT(
                            'schema: ', schema_name, ', ',
                            'table: ', table_name, ', ',
                            'table size (MB): ', FORMAT(table_size_mb, '#,0.00'), ', ',
                            'partition count: ', FORMAT(partition_count, '#,0'), ', ',
                            'inserts: ', FORMAT(insert_count, '#,0'), ', ',
                            'updates: ', FORMAT(update_count, '#,0'), ', ',
                            'deletes: ', FORMAT(delete_count, '#,0'), ', ',
                            'singleton lookups: ', FORMAT(singleton_lookup_count, '#,0'), ', ',
                            'range scans: ', FORMAT(range_scan_count, '#,0'), ', ',
                            'seeks: ', FORMAT(seek_count, '#,0'), ', ',
                            'full scans: ', FORMAT(full_scan_count, '#,0'), ', ',
                            'lookups: ', FORMAT(lookup_count, '#,0')
                            ) AS nvarchar(max)), @CRLF
                 )
                 WITHIN GROUP (ORDER BY schema_name, table_name)
       AS details,
       COUNT(1) AS cci_candidate_count
FROM cci_candidate_table
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1290 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'Since database engine startup at ', CONVERT(varchar(20), si.sqlserver_start_time, 120),
             ' UTC:',
             REPLICATE(@CRLF, 2),
             'Total CCI candidates: ', FORMAT(cci_candidate_count, '#,0'),
             @CRLF, @CRLF,
             ccd.details,
             @CRLF
             ) AS details
FROM cci_candidate_details AS ccd
CROSS JOIN sys.dm_os_sys_info AS si
WHERE ccd.details IS NOT NULL;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1290);
    ELSE
        THROW;
END CATCH;

-- Workload group workers close to limit
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1360) AND execute_indicator = 1)

WITH
worker_snapshot AS
(
SELECT snapshot_time,
       duration_ms,
       active_worker_count,
       max_worker,
       IIF(active_worker_count * 1. / NULLIF(max_worker, 0) > @HighGroupWorkerUtilizationThresholdRatio, 1, 0) AS high_worker_utilization_indicator
FROM sys.dm_resource_governor_workload_groups_history_ex
WHERE @EngineEdition = 5
      AND
      name like 'UserPrimaryGroup.DB%'
      AND
      TRY_CAST(RIGHT(name, LEN(name) - LEN('UserPrimaryGroup.DB') - 2) AS int) = DB_ID()
),
pre_packed_worker_snapshot AS
(
SELECT SUM(duration_ms) OVER (ORDER BY (SELECT 'no order')) / 60000 AS recent_history_duration_minutes,
       snapshot_time,
       active_worker_count,
       max_worker,
       high_worker_utilization_indicator,
       ROW_NUMBER() OVER (ORDER BY snapshot_time) -- row number across all readings, in increasing chronological order
       -
       SUM(high_worker_utilization_indicator) OVER (ORDER BY snapshot_time ROWS UNBOUNDED PRECEDING) -- running count of all intervals where worker utilization exceeded the threshold
       AS grouping_helper -- this difference remains constant while worker utilization is above the threshold, and can be used to collapse/pack an interval using aggregation
FROM worker_snapshot
),
packed_worker_snapshot AS
(
SELECT MIN(snapshot_time) AS min_snapshot_time,
       MAX(snapshot_time) AS max_snapshot_time,
       AVG(active_worker_count) AS avg_worker_count,
       MAX(active_worker_count) AS max_worker_count,
       MIN(max_worker) AS worker_limit,
       MIN(recent_history_duration_minutes) AS recent_history_duration_minutes
FROM pre_packed_worker_snapshot
WHERE high_worker_utilization_indicator = 1
GROUP BY grouping_helper
),
worker_top_stat AS
(
SELECT MIN(recent_history_duration_minutes) AS recent_history_duration_minutes,
       MIN(worker_limit) AS worker_limit,
       MAX(DATEDIFF(second, min_snapshot_time, max_snapshot_time)) AS longest_high_worker_duration_seconds,
       AVG(avg_worker_count) AS avg_worker_count,
       MAX(max_worker_count) AS max_worker_count,
       COUNT(1) AS count_high_worker_intervals
FROM packed_worker_snapshot
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1360 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'In the last ', recent_history_duration_minutes,
             ' minutes, there were ', count_high_worker_intervals,
             ' interval(s) with worker utilization staying above ', FORMAT(@HighGroupWorkerUtilizationThresholdRatio, 'P'),
             ' of the workload group worker limit of ', FORMAT(worker_limit, '#,0'),
             ' workers. The longest such interval lasted ', FORMAT(longest_high_worker_duration_seconds, '#,0'),
             ' seconds. Across all such intervals, the average number of workers used was ', FORMAT(avg_worker_count, '#,0.00'),
             ' and the maximum number of workers used was ', FORMAT(max_worker_count, '#,0'),
             '.',
             @CRLF
             ) AS details
FROM worker_top_stat
WHERE count_high_worker_intervals > 0
;

-- Resource pool workers close to limit
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1370) AND execute_indicator = 1)

WITH
worker_snapshot AS
(
SELECT snapshot_time,
       duration_ms,
       active_worker_count,
       active_worker_count * 100. / NULLIF(max_worker_percent, 0) AS max_worker,
       IIF(max_worker_percent > @HighPoolWorkerUtilizationThresholdRatio * 100., 1, 0) AS high_worker_utilization_indicator
FROM sys.dm_resource_governor_resource_pools_history_ex
WHERE @EngineEdition = 5
      AND
      -- Consider user resource pool only
      (
      name LIKE 'SloSharedPool%'
      OR
      name LIKE 'UserPool%'
      )
),
pre_packed_worker_snapshot AS
(
SELECT SUM(duration_ms) OVER (ORDER BY (SELECT 'no order')) / 60000 AS recent_history_duration_minutes,
       snapshot_time,
       active_worker_count,
       max_worker,
       high_worker_utilization_indicator,
       ROW_NUMBER() OVER (ORDER BY snapshot_time) -- row number across all readings, in increasing chronological order
       -
       SUM(high_worker_utilization_indicator) OVER (ORDER BY snapshot_time ROWS UNBOUNDED PRECEDING) -- running count of all intervals where worker utilization exceeded the threshold
       AS grouping_helper -- this difference remains constant while worker utilization is above the threshold, and can be used to collapse/pack an interval using aggregation
FROM worker_snapshot
),
packed_worker_snapshot AS
(
SELECT MIN(snapshot_time) AS min_snapshot_time,
       MAX(snapshot_time) AS max_snapshot_time,
       AVG(active_worker_count) AS avg_worker_count,
       MAX(active_worker_count) AS max_worker_count,
       MIN(max_worker) AS worker_limit,
       MIN(recent_history_duration_minutes) AS recent_history_duration_minutes
FROM pre_packed_worker_snapshot
WHERE high_worker_utilization_indicator = 1
GROUP BY grouping_helper
),
worker_top_stat AS
(
SELECT MIN(recent_history_duration_minutes) AS recent_history_duration_minutes,
       MIN(worker_limit) AS worker_limit,
       MAX(DATEDIFF(second, min_snapshot_time, max_snapshot_time)) AS longest_high_worker_duration_seconds,
       AVG(avg_worker_count) AS avg_worker_count,
       MAX(max_worker_count) AS max_worker_count,
       COUNT(1) AS count_high_worker_intervals
FROM packed_worker_snapshot
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1370 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'In the last ', recent_history_duration_minutes,
             ' minutes, there were ', count_high_worker_intervals,
             ' interval(s) with worker utilization staying above ', FORMAT(@HighPoolWorkerUtilizationThresholdRatio, 'P'),
             ' of the resource pool worker limit of approximately ', FORMAT(worker_limit, '#,0'),
             ' workers. The longest such interval lasted ', FORMAT(longest_high_worker_duration_seconds, '#,0'),
             ' seconds. Across all such intervals, the average number of workers used was ', FORMAT(avg_worker_count, '#,0.00'),
             ' and the maximum number of workers used was ', FORMAT(max_worker_count, '#,0'),
             '.',
             @CRLF
             ) AS details
FROM worker_top_stat
WHERE count_high_worker_intervals > 0
;

-- Notable connectivity events
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1380) AND execute_indicator = 1)
BEGIN

BEGIN TRY

DECLARE @crb TABLE (
                   event_time datetime NOT NULL,
                   record xml NOT NULL
                   );

-- stage XML in a table variable to enable parallelism when processing XQuery expressions
WITH crb AS
(
SELECT DATEADD(second, -0.001 * (si.cpu_ticks/(si.cpu_ticks/si.ms_ticks) - rb.timestamp), CURRENT_TIMESTAMP) AS event_time,
       TRY_CAST(rb.record AS XML) AS record
FROM sys.dm_os_ring_buffers AS rb
CROSS JOIN sys.dm_os_sys_info AS si
WHERE rb.ring_buffer_type = 'RING_BUFFER_CONNECTIVITY'
)
INSERT INTO @crb (event_time, record)
SELECT event_time, record
FROM crb
WHERE event_time > DATEADD(minute, -@NotableNetworkEventsIntervalMinutes, CURRENT_TIMESTAMP) -- ignore older events
;

DROP TABLE IF EXISTS ##tips_connectivity_event;

WITH connectivity_event AS
(
SELECT event_time,
       record
FROM @crb
WHERE record IS NOT NULL
),
shredded_connectivity_event AS
(
SELECT event_time,
       record.value('(./Record/ConnectivityTraceRecord/RemoteHost/text())[1]','varchar(30)') AS remote_host,
       record.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/TotalTime/text())[1]','int') AS login_total_time_ms,
       record.value('(./Record/ConnectivityTraceRecord/RecordType/text())[1]','varchar(50)') AS record_type,
       record.value('(./Record/ConnectivityTraceRecord/RecordSource/text())[1]','varchar(50)') AS record_source,
       record.value('(./Record/ConnectivityTraceRecord/TdsDisconnectFlags/PhysicalConnectionIsKilled/text())[1]','bit') AS physical_connection_is_killed,
       record.value('(./Record/ConnectivityTraceRecord/TdsDisconnectFlags/DisconnectDueToReadError/text())[1]','bit') AS disconnect_due_to_read_error,
       record.value('(./Record/ConnectivityTraceRecord/TdsDisconnectFlags/NetworkErrorFoundInInputStream/text())[1]','bit') AS network_error_found_in_input_stream,
       record.value('(./Record/ConnectivityTraceRecord/TdsDisconnectFlags/ErrorFoundBeforeLogin/text())[1]','bit') AS error_found_before_login,
       record.value('(./Record/ConnectivityTraceRecord/TdsDisconnectFlags/SessionIsKilled/text())[1]','bit') AS session_is_killed,
       record.value('(./Record/ConnectivityTraceRecord/Spid/text())[1]','int') AS spid,
       record.value('(./Record/ConnectivityTraceRecord/OSError/text())[1]','int') AS os_error,
       record.value('(./Record/ConnectivityTraceRecord/SniConsumerError/text())[1]','int') AS sni_consumer_error,
       record.value('(./Record/ConnectivityTraceRecord/State/text())[1]','int') AS state,
       record.value('(./Record/ConnectivityTraceRecord/RemotePort/text())[1]','int') AS remote_port,
       record.value('(./Record/ConnectivityTraceRecord/LocalHost/text())[1]','varchar(30)') AS local_host,
       record.value('(./Record/ConnectivityTraceRecord/LocalPort/text())[1]','int') AS local_port,
       record.value('(./Record/ConnectivityTraceRecord/TdsBufInfo/InputBufError/text())[1]','int') AS input_buf_error,
       record.value('(./Record/ConnectivityTraceRecord/TdsBufInfo/OutputBufError/text())[1]','int') AS output_buf_error,
       record.value('(./Record/ConnectivityTraceRecord/TdsBuffersInformation/TdsInputBufferError/text())[1]','int') AS tds_input_buffer_error,
       record.value('(./Record/ConnectivityTraceRecord/TdsBuffersInformation/TdsOutputBufferError/text())[1]','int') AS tds_output_buffer_error,
       record.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/EnqueueTime/text())[1]','int') AS login_enqueue_time_ms,
       record.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/NetWritesTime/text())[1]','int') AS login_net_writes_time_ms,
       record.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/NetReadsTime/text())[1]','int') AS login_net_reads_time_ms,
       record.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/Ssl/TotalTime/text())[1]','int') AS login_ssl_total_time_ms,
       record.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/TriggerAndResGovTime/TotalTime/text())[1]','int') AS login_trigger_rg_total_time_ms,
       record.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/TriggerAndResGovTime/FindLogin/text())[1]','int') AS login_trigger_rg_find_login_time_ms,
       record.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/TriggerAndResGovTime/LogonTriggers/text())[1]','int') AS login_trigger_rg_logon_triggers_time_ms,
       record.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/TriggerAndResGovTime/ExecClassifier/text())[1]','int') AS login_trigger_rg_exec_classifier_time_ms,
       record.value('(./Record/ConnectivityTraceRecord/LoginTimersInMilliseconds/TriggerAndResGovTime/SessionRecover/text())[1]','int') AS login_trigger_rg_session_recover_time_ms
FROM connectivity_event
)
SELECT sce.event_time,
       sce.record_type,
       sce.record_source,
       sce.spid,
       sce.os_error,
       sce.sni_consumer_error,
       m.text AS sni_consumer_error_message,
       sce.state AS sni_consumer_error_state,
       sce.remote_host,
       sce.remote_port,
       sce.local_host,
       sce.local_port,
       COALESCE(sce.tds_input_buffer_error, sce.input_buf_error) AS tds_input_buffer_error,
       COALESCE(sce.tds_output_buffer_error, sce.output_buf_error) AS tds_output_buffer_error,
       sce.physical_connection_is_killed,
       sce.disconnect_due_to_read_error,
       sce.network_error_found_in_input_stream,
       sce.error_found_before_login,
       sce.session_is_killed,
       sce.login_total_time_ms,
       sce.login_enqueue_time_ms,
       sce.login_net_writes_time_ms,
       sce.login_net_reads_time_ms,
       sce.login_ssl_total_time_ms,
       sce.login_trigger_rg_total_time_ms,
       sce.login_trigger_rg_find_login_time_ms,
       sce.login_trigger_rg_logon_triggers_time_ms,
       sce.login_trigger_rg_exec_classifier_time_ms,
       sce.login_trigger_rg_session_recover_time_ms
INTO ##tips_connectivity_event
FROM shredded_connectivity_event AS sce
LEFT JOIN sys.messages AS m
ON sce.sni_consumer_error = m.message_id
   AND
   m.language_id = 1033
WHERE sce.remote_host <> '<named pipe>' -- ignore SQL DB internal connections
      AND
      (
      (
      sce.record_type = 'Error'
      AND
      NOT (sce.sni_consumer_error = 18456 AND sce.state = 123) -- SSMS noise
      )
      OR
      (
      sce.record_type = 'LoginTimers'
      AND
      sce.login_total_time_ms > @NotableNetworkEventsSlowLoginThresholdMs
      )
      OR
      (
      sce.record_type = 'ConnectionClose'
      AND
      (sce.physical_connection_is_killed = 1 OR sce.disconnect_due_to_read_error = 1 OR sce.network_error_found_in_input_stream = 1 OR sce.error_found_before_login = 1 OR sce.session_is_killed = 1)
      )
      )
;

IF @@ROWCOUNT > 0
BEGIN
    INSERT INTO @DetectedTip (tip_id, details)
    SELECT 1380 AS tip_id,
           CONCAT(
                 @NbspCRLF,
                 'In the last ', FORMAT(@NotableNetworkEventsIntervalMinutes, '#,0'),
                 ' minutes, notable network connectivity events have occurred. For details, execute this query in the same database:', @CRLF,
                 'SELECT event_age, * FROM ##tips_connectivity_event ORDER BY event_time DESC;',
                 @CRLF
                 ) AS details;

    ALTER TABLE ##tips_connectivity_event
    ADD event_age AS CONCAT(
                           DATEDIFF(second, event_time, CURRENT_TIMESTAMP) / 3600, ' h, ',
                           (DATEDIFF(second, event_time, CURRENT_TIMESTAMP) % 3600) / 60, ' m, ',
                           DATEDIFF(second, event_time, CURRENT_TIMESTAMP) % 60, ' s'
                           );
END;

END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 1222
        INSERT INTO @SkippedTip (tip_id)
        VALUES (1380);
    ELSE
        THROW;
END CATCH;

END;

-- Significant recent blocking
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1420) AND execute_indicator = 1)

WITH
blocking_snapshot AS
(
SELECT snapshot_time,
       duration_ms,
       blocked_task_count,
       delta_lock_wait_count,
       delta_lock_wait_time_ms,
       IIF(delta_lock_wait_time_ms > @LockBlockingTimeThresholdRatio * duration_ms OR blocked_task_count >= @LockBlockingBlockedTaskThreshold, 1, 0) AS blocking_indicator
FROM sys.dm_resource_governor_workload_groups_history_ex
WHERE @EngineEdition = 5
      AND
      name like 'UserPrimaryGroup.DB%'
      AND
      TRY_CAST(RIGHT(name, LEN(name) - LEN('UserPrimaryGroup.DB') - 2) AS int) = DB_ID()
),
pre_packed_blocking_snapshot AS
(
SELECT snapshot_time,
       duration_ms,
       blocked_task_count,
       delta_lock_wait_count,
       delta_lock_wait_time_ms,
       blocking_indicator,
       ROW_NUMBER() OVER (ORDER BY snapshot_time)
       -
       SUM(blocking_indicator) OVER (ORDER BY snapshot_time ROWS UNBOUNDED PRECEDING)
       AS grouping_helper
FROM blocking_snapshot
),
packed_blocking_snapshot AS
(
SELECT MIN(snapshot_time) AS min_snapshot_time,
       MAX(snapshot_time) AS max_snapshot_time,
       AVG(duration_ms) AS avg_snapshot_interval_duration_ms,
       MIN(blocked_task_count) AS min_blocked_task_count,
       MAX(blocked_task_count) AS max_blocked_task_count,
       SUM(delta_lock_wait_count) AS total_lock_waits,
       SUM(delta_lock_wait_time_ms) AS total_lock_wait_time_milliseconds
FROM pre_packed_blocking_snapshot
WHERE blocking_indicator = 1
GROUP BY grouping_helper
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1420 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'Significant lock blocking has occurred during the following time intervals (UTC):',
             @CRLF, @CRLF,
             STRING_AGG(
                       CAST(CONCAT(
                                  'Interval start time: ', FORMAT(DATEADD(millisecond, -avg_snapshot_interval_duration_ms, min_snapshot_time), 's'),
                                  ', end time: ', FORMAT(max_snapshot_time, 's'),
                                  ', duration: ', DATEADD(second, DATEDIFF(second, DATEADD(millisecond, -avg_snapshot_interval_duration_ms, min_snapshot_time), max_snapshot_time), CAST('00:00:00' AS time(0))),
                                  ', total lock wait time: ', DATEADD(millisecond, total_lock_wait_time_milliseconds, CAST('00:00:00' AS time(3))),
                                  ', minimum observed blocked tasks: ', FORMAT(min_blocked_task_count, '#,0'),
                                  ', maximum observed blocked tasks: ', FORMAT(max_blocked_task_count, '#,0'),
                                  ', total lock waits: ', FORMAT(total_lock_waits, '#,0')
                                  ) AS nvarchar(max)), @CRLF
                       )
                       WITHIN GROUP (ORDER BY min_snapshot_time DESC),
             @CRLF
             )
       AS details
FROM packed_blocking_snapshot
HAVING COUNT(1) > 0
;

-- High query optimizations
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1430) AND execute_indicator = 1)

WITH
high_optimizations_snapshot AS
(
SELECT snapshot_time,
       duration_ms,
       delta_request_count,
       delta_query_optimizations,
       IIF(delta_query_optimizations > @QueryOptimizationRequestThresholdRatio * delta_request_count AND delta_request_count >= @QueryOptimizationRequestCountThreshold, 1, 0) AS high_optimizations_indicator
FROM sys.dm_resource_governor_workload_groups_history_ex
WHERE @EngineEdition = 5
      AND
      name like 'UserPrimaryGroup.DB%'
      AND
      TRY_CAST(RIGHT(name, LEN(name) - LEN('UserPrimaryGroup.DB') - 2) AS int) = DB_ID()
),
pre_packed_high_optimizations_snapshot AS
(
SELECT snapshot_time,
       duration_ms,
       delta_request_count,
       delta_query_optimizations,
       high_optimizations_indicator,
       ROW_NUMBER() OVER (ORDER BY snapshot_time)
       -
       SUM(high_optimizations_indicator) OVER (ORDER BY snapshot_time ROWS UNBOUNDED PRECEDING)
       AS grouping_helper
FROM high_optimizations_snapshot
),
packed_high_optimization_snapshot AS
(
SELECT MIN(snapshot_time) AS min_snapshot_time,
       MAX(snapshot_time) AS max_snapshot_time,
       AVG(duration_ms) AS avg_snapshot_interval_duration_ms,
       SUM(delta_request_count) AS total_requests,
       SUM(delta_query_optimizations) AS total_optimizations
FROM pre_packed_high_optimizations_snapshot
WHERE high_optimizations_indicator = 1
GROUP BY grouping_helper
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1430 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'Time intervals with a high number of query optimizations (UTC):',
             @CRLF, @CRLF,
             STRING_AGG(
                       CAST(CONCAT(
                                  'Interval start time: ', FORMAT(DATEADD(millisecond, -avg_snapshot_interval_duration_ms, min_snapshot_time), 's'),
                                  ', end time: ', FORMAT(max_snapshot_time, 's'),
                                  ', duration: ', DATEADD(second, DATEDIFF(second, DATEADD(millisecond, -avg_snapshot_interval_duration_ms, min_snapshot_time), max_snapshot_time), CAST('00:00:00' AS time(0))),
                                  ', total requests: ', FORMAT(total_requests, '#,0'),
                                  ', total optimizations: ', FORMAT(total_optimizations, '#,0'),
                                  ', query optimization rate: ', FORMAT(LEAST(total_optimizations * 1.0 / total_requests, 1), 'P')
                                  ) AS nvarchar(max)), @CRLF
                       )
                       WITHIN GROUP (ORDER BY min_snapshot_time DESC),
             @CRLF
             )
       AS details
FROM packed_high_optimization_snapshot
HAVING COUNT(1) > 0
;

-- Local storage quota
IF EXISTS (SELECT 1 FROM @TipDefinition WHERE tip_id IN (1450) AND execute_indicator = 1)

WITH
local_storage AS
(
SELECT database_id,
       DB_NAME(database_id) AS database_name,
       SUM(IIF(file_id <> 2, size_on_disk_bytes, 0)) / 1024. / 1024 AS data_size_on_disk_mb,
       SUM(IIF(file_id = 2, size_on_disk_bytes, 0)) / 1024. / 1024 AS log_size_on_disk_mb
FROM sys.dm_io_virtual_file_stats(default, default)
GROUP BY database_id
),
local_storage_agg AS
(
SELECT STRING_AGG(
                 CAST(CONCAT(
                            'database (id: ', database_id,
                            ', name: ' + QUOTENAME(database_name), -- database name is only available for current database and system databases, include for usability if available
                            '), DATA: ', FORMAT(data_size_on_disk_mb, '#,0.00'),
                            ', LOG: ', FORMAT(log_size_on_disk_mb, '#,0.00')
                            ) AS nvarchar(max)), @CRLF
                 )
                 WITHIN GROUP (ORDER BY IIF(database_name IS NULL, 1, 0), database_id)
                 AS storage_summary
FROM local_storage
),
local_storage_quota AS
(
SELECT rg.user_data_directory_space_quota_mb,
       rg.user_data_directory_space_usage_mb,
       rg.user_data_directory_space_usage_mb * 1. / rg.user_data_directory_space_quota_mb AS quota_usage,
       lsa.storage_summary
FROM local_storage_agg AS lsa
CROSS JOIN sys.dm_user_db_resource_governance AS rg
WHERE rg.database_id = DB_ID()
      AND
      DATABASEPROPERTYEX(DB_NAME(), 'Edition') IN ('Premium','BusinessCritical') -- not relevant for remote storage SLOs
)
INSERT INTO @DetectedTip (tip_id, details)
SELECT 1450 AS tip_id,
       CONCAT(
             @NbspCRLF,
             'Maximum local storage (MB): ', FORMAT(user_data_directory_space_quota_mb, '#,0.00'), @CRLF,
             'Allocated local storage (MB): ', FORMAT(user_data_directory_space_usage_mb, '#,0.00'), @CRLF,
             'Local storage usage (%): ', FORMAT(quota_usage, 'P'),
             @CRLF, @CRLF,
             'Allocated local storage per database (MB):', @CRLF,
             storage_summary, @CRLF
             )
       AS details
FROM local_storage_quota
WHERE quota_usage > @MinLocalStorageQuotaUsageRatio;

END; -- end tips requiring VIEW SERVER STATE

-- Return detected tips

IF @JSONOutput = 0
    SELECT td.tip_id,
           td.tip_name AS description,
           td.confidence_percent,
           td.tip_url AS additional_info_url,
           d.details
    FROM @TipDefinition AS td
    LEFT JOIN @DetectedTip AS dt
    ON dt.tip_id = td.tip_id
    OUTER APPLY (
                SELECT dt.details AS [processing-instruction(_)]
                WHERE dt.details IS NOT NULL
                FOR XML PATH (''), TYPE
                ) d (details)
    WHERE dt.tip_id IS NOT NULL
          OR
          @ReturnAllTips = 1
    ORDER BY description;
ELSE IF @JSONOutput = 1
    WITH tips AS -- flatten for JSON output
    (
    SELECT td.tip_id,
           td.tip_name AS description,
           td.confidence_percent,
           td.tip_url AS additional_info_url,
           REPLACE(REPLACE(dt.details, CHAR(13), ''), NCHAR(160), '') AS details -- strip unnecessary formatting
    FROM @TipDefinition AS td
    LEFT JOIN @DetectedTip AS dt
    ON dt.tip_id = td.tip_id
    WHERE dt.tip_id IS NOT NULL
          OR
          @ReturnAllTips = 1
    )
    SELECT *
    FROM tips
    ORDER BY description
    FOR JSON AUTO;

-- Output skipped tips, if any
IF @ViewServerStateIndicator = 0
   OR
   EXISTS (SELECT 1 FROM @TipDefinition WHERE execute_indicator = 0)
   OR
   EXISTS (SELECT 1 FROM @SkippedTip)
BEGIN
    WITH tip AS
    (
    SELECT td.tip_id,
           td.tip_name,
           CASE WHEN @ViewServerStateIndicator = 0 AND td.required_permission = 'VIEW SERVER STATE' THEN 'insufficient permissions'
                WHEN td.execute_indicator = 0 THEN 'user-specified exclusions'
                WHEN st.tip_id IS NOT NULL THEN st.reason
                ELSE NULL
           END
           AS skipped_reason
    FROM @TipDefinition AS td
    LEFT JOIN @SkippedTip AS st
    ON td.tip_id = st.tip_id
    ),
    skipped_tip AS
    (
    SELECT CONCAT(
                 COUNT(1),
                 ' tip(s) were skipped because of ',
                 skipped_reason
                 ) AS warning,
           CASE skipped_reason WHEN 'insufficient permissions' THEN 'https://aka.ms/sqldbtipswiki#permissions'
                               WHEN 'user-specified exclusions' THEN 'https://aka.ms/sqldbtipswiki#tip-exclusions'
                               WHEN 'lock timeout' THEN 'https://aka.ms/sqldbtipswiki#how-it-works'
           END
           AS additional_info_url,
           CONCAT(
                 @NbspCRLF,
                 STRING_AGG(
                           CONCAT(
                                 'tip_id: ', tip_id,
                                 ', ', tip_name
                                 ),
                           @CRLF
                           )
                           WITHIN GROUP (ORDER BY tip_name),
                 @CRLF
                 )
           AS skipped_tips
    FROM tip
    WHERE skipped_reason IS NOT NULL
    GROUP BY skipped_reason
    HAVING COUNT(1) > 0
    )
    SELECT st.warning,
           st.additional_info_url,
           tl.skipped_tips
    FROM skipped_tip AS st
    OUTER APPLY (
                SELECT st.skipped_tips AS [processing-instruction(_)]
                WHERE st.skipped_tips IS NOT NULL
                FOR XML PATH (''), TYPE
                ) tl (skipped_tips)
END;

PRINT CONCAT(
            'Execution start time: ', @ExecStartTime,
            ', duration: ', FORMAT(DATEDIFF(second, @ExecStartTime, SYSDATETIMEOFFSET()), '#,0'),
            ' seconds'
            );

END TRY
BEGIN CATCH
    SET LOCK_TIMEOUT -1; -- revert to default

    THROW;
END CATCH;