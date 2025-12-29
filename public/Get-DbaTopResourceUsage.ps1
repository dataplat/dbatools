function Get-DbaTopResourceUsage {
    <#
    .SYNOPSIS
        Identifies the most resource-intensive cached queries from sys.dm_exec_query_stats for performance troubleshooting

    .DESCRIPTION
        Analyzes cached query performance by examining sys.dm_exec_query_stats to find your worst-performing queries across four key metrics: total duration, execution frequency, IO operations, and CPU time. Each metric returns the top consumers (default 20) grouped by query hash, so you can quickly spot patterns in problematic queries that are dragging down server performance.

        When your SQL Server is running slowly, this command helps you skip the guesswork and zero in on the specific queries consuming the most resources. Instead of manually writing complex DMV queries, you get formatted results showing query text, execution plans, database context, and performance metrics in one output.

        You can focus on specific databases, exclude system objects like replication procedures, or analyze just one metric type (like Duration) when investigating particular performance issues. The results include actual query text and execution plans, so you can immediately start optimizing the problematic SQL.

        This command is based off of queries provided by Michael J. Swart at http://michaeljswart.com/go/Top20

        Per Michael: "I've posted queries like this before, and others have written many other versions of this query. All these queries are based on sys.dm_exec_query_stats."

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to analyze for resource-intensive queries. Accepts multiple database names.
        Use this when troubleshooting performance issues in specific databases rather than analyzing server-wide query performance.

    .PARAMETER ExcludeDatabase
        Specifies databases to skip when analyzing query performance across the SQL Server instance.
        Use this to exclude test databases, archived databases, or other databases that aren't relevant to your performance investigation.

    .PARAMETER ExcludeSystem
        Excludes system objects like replication procedures (sp_MS% objects) from the query analysis results.
        Use this when you want to focus on application queries rather than system maintenance operations that may consume resources.

    .PARAMETER Type
        Specifies which resource usage metrics to analyze: Duration, Frequency, IO, CPU, or All (default).
        Use specific types when investigating particular performance symptoms - Duration for slow queries, Frequency for high-activity queries, IO for disk bottlenecks, or CPU for processor-intensive operations.

    .PARAMETER Limit
        Controls how many top resource-consuming query hashes to return for each metric type (default is 20).
        Increase this value when you need to analyze more queries, or decrease it to focus on only the most problematic queries during initial performance triage.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Returns one result set per cached query grouped by query hash matching the specified resource metric criteria. When -Type All (default) is specified, up to 80 result objects are returned (20 per metric type × 4 metric types).

        Duration metric results (when -Type includes "Duration"):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name
        - Database: The database context where the query executed
        - ObjectName: The stored procedure or object name containing the query (or '<none>' for ad-hoc queries)
        - QueryHash: The binary hash identifier for the query
        - TotalElapsedTimeMs: Total elapsed time in milliseconds for this cached query execution plan
        - ExecutionCount: Total number of times this query execution plan was executed
        - AverageDurationMs: Average elapsed time per execution in milliseconds
        - QueryTotalElapsedTimeMs: Total elapsed time for all occurrences of this query hash
        - QueryText: The actual SQL statement text being executed

        Frequency metric results (when -Type includes "Frequency"):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name
        - Database: The database context where the query executed
        - ObjectName: The stored procedure or object name containing the query (or '<none>' for ad-hoc queries)
        - QueryHash: The binary hash identifier for the query
        - ExecutionCount: Number of times this query execution plan was executed
        - QueryTotalExecutions: Total execution count for all occurrences of this query hash
        - QueryText: The actual SQL statement text being executed

        IO metric results (when -Type includes "IO"):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name
        - Database: The database context where the query executed
        - ObjectName: The stored procedure or object name containing the query (or '<none>' for ad-hoc queries)
        - QueryHash: The binary hash identifier for the query
        - TotalIO: Total logical reads and writes (sum of logical read and write operations)
        - ExecutionCount: Number of times this query execution plan was executed
        - AverageIO: Average IO operations per execution
        - QueryTotalIO: Total IO operations for all occurrences of this query hash
        - QueryText: The actual SQL statement text being executed

        CPU metric results (when -Type includes "CPU"):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name
        - Database: The database context where the query executed
        - ObjectName: The stored procedure or object name containing the query (or '<none>' for ad-hoc queries)
        - QueryHash: The binary hash identifier for the query
        - CpuTime: Total worker time in microseconds (CPU time consumed)
        - ExecutionCount: Number of times this query execution plan was executed
        - AverageCpuMs: Average CPU time per execution in milliseconds
        - QueryTotalCpu: Total CPU time for all occurrences of this query hash
        - QueryText: The actual SQL statement text being executed

        Additional property available with Select-Object *:
        - QueryPlan: The actual execution plan XML (excluded from default display via Select-DefaultView)

        The -ExcludeSystem parameter filters out system replication procedures (sp_MS%) from all result sets. The -Database and -ExcludeDatabase parameters filter results to specific databases before aggregation.

    .NOTES
        Tags: Diagnostic, Performance, Query
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaTopResourceUsage

    .EXAMPLE
        PS C:\> Get-DbaTopResourceUsage -SqlInstance sql2008, sql2012

        Return the 80 (20 x 4 types) top usage results by duration, frequency, IO, and CPU servers for servers sql2008 and sql2012

    .EXAMPLE
        PS C:\> Get-DbaTopResourceUsage -SqlInstance sql2008 -Type Duration, Frequency -Database TestDB

        Return the highest usage by duration (top 20) and frequency (top 20) for the TestDB on sql2008

    .EXAMPLE
        PS C:\> Get-DbaTopResourceUsage -SqlInstance sql2016 -Limit 30

        Return the highest usage by duration (top 30) and frequency (top 30) for the TestDB on sql2016

    .EXAMPLE
        PS C:\> Get-DbaTopResourceUsage -SqlInstance sql2008, sql2012 -ExcludeSystem

        Return the 80 (20 x 4 types) top usage results by duration, frequency, IO, and CPU servers for servers sql2008 and sql2012 without any System Objects

    .EXAMPLE
        PS C:\> Get-DbaTopResourceUsage -SqlInstance sql2016| Select-Object *

        Return all the columns plus the QueryPlan column

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [ValidateSet("All", "Duration", "Frequency", "IO", "CPU")]
        [string[]]$Type = "All",
        [int]$Limit = 20,
        [switch]$EnableException,
        [switch]$ExcludeSystem
    )

    begin {

        $instancecolumns = " SERVERPROPERTY('MachineName') AS ComputerName,
        ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
        SERVERPROPERTY('ServerName') AS SqlInstance, "

        if ($database) {
            $wheredb = " AND COALESCE(DB_NAME(st.dbid), DB_NAME(CAST(pa.value AS INT)), 'Resource') IN ('$($database -join '', '')')"
        }

        if ($ExcludeDatabase) {
            $wherenotdb = " AND COALESCE(DB_NAME(st.dbid), DB_NAME(CAST(pa.value AS INT)), 'Resource') NOT IN ('$($excludedatabase -join '', '')')"
        }

        if ($ExcludeSystem) {
            $whereexcludesystem = " AND COALESCE(OBJECT_NAME(st.objectid, st.dbid), '<none>') NOT LIKE 'sp_MS%' "
        }
        $duration = ";WITH long_queries AS
                        (
                            SELECT TOP $Limit
                                query_hash,
                                SUM(total_elapsed_time) elapsed_time
                            FROM sys.dm_exec_query_stats
                            WHERE query_hash <> 0x0
                            GROUP BY query_hash
                            ORDER BY SUM(total_elapsed_time) DESC
                        )
                        SELECT $instancecolumns
                            COALESCE(DB_NAME(st.dbid), DB_NAME(CAST(pa.value AS INT)), 'Resource') AS [Database],
                            COALESCE(OBJECT_NAME(st.objectid, st.dbid), '<none>') AS ObjectName,
                            qs.query_hash AS QueryHash,
                            qs.total_elapsed_time / 1000 AS TotalElapsedTimeMs,
                            qs.execution_count AS ExecutionCount,
                            CAST((total_elapsed_time / 1000) / (execution_count + 0.0) AS money) AS AverageDurationMs,
                            lq.elapsed_time / 1000 AS QueryTotalElapsedTimeMs,
                            SUBSTRING(st.TEXT,(qs.statement_start_offset + 2) / 2,
                                (CASE
                                    WHEN qs.statement_end_offset = -1  THEN LEN(CONVERT(NVARCHAR(MAX),st.text)) * 2
                                    ELSE qs.statement_end_offset
                                    END - qs.statement_start_offset) / 2) AS QueryText,
                            qp.query_plan AS QueryPlan
                        FROM sys.dm_exec_query_stats qs
                        JOIN long_queries lq
                            ON lq.query_hash = qs.query_hash
                        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
                        CROSS APPLY sys.dm_exec_query_plan (qs.plan_handle) qp
                        OUTER APPLY sys.dm_exec_plan_attributes(qs.plan_handle) pa
                        WHERE pa.attribute = 'dbid' $wheredb $wherenotdb $whereexcludesystem
                        ORDER BY lq.elapsed_time DESC,
                            lq.query_hash,
                            qs.total_elapsed_time DESC
                        OPTION (RECOMPILE)"

        $frequency = ";WITH frequent_queries AS
                        (
                            SELECT TOP $Limit
                                query_hash,
                                SUM(execution_count) executions
                            FROM sys.dm_exec_query_stats
                            WHERE query_hash <> 0x0
                            GROUP BY query_hash
                            ORDER BY SUM(execution_count) DESC
                        )
                        SELECT $instancecolumns
                            COALESCE(DB_NAME(st.dbid), DB_NAME(CAST(pa.value AS INT)), 'Resource') AS [Database],
                            COALESCE(OBJECT_NAME(st.objectid, st.dbid), '<none>') AS ObjectName,
                            qs.query_hash AS QueryHash,
                            qs.execution_count AS ExecutionCount,
                            executions AS QueryTotalExecutions,
                            SUBSTRING(st.TEXT,(qs.statement_start_offset + 2) / 2,
                                (CASE
                                    WHEN qs.statement_end_offset = -1  THEN LEN(CONVERT(NVARCHAR(MAX),st.text)) * 2
                                    ELSE qs.statement_end_offset
                                    END - qs.statement_start_offset) / 2) AS QueryText,
                            qp.query_plan AS QueryPlan
                        FROM sys.dm_exec_query_stats qs
                        JOIN frequent_queries fq
                            ON fq.query_hash = qs.query_hash
                        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
                        CROSS APPLY sys.dm_exec_query_plan (qs.plan_handle) qp
                        OUTER APPLY sys.dm_exec_plan_attributes(qs.plan_handle) pa
                        WHERE pa.attribute = 'dbid'  $wheredb $wherenotdb $whereexcludesystem
                        ORDER BY fq.executions DESC,
                            fq.query_hash,
                            qs.execution_count DESC
                        OPTION (RECOMPILE)"

        $io = ";WITH high_io_queries AS
                (
                    SELECT TOP $Limit
                        query_hash,
                        SUM(total_logical_reads + total_logical_writes) io
                    FROM sys.dm_exec_query_stats
                    WHERE query_hash <> 0x0
                    GROUP BY query_hash
                    ORDER BY SUM(total_logical_reads + total_logical_writes) DESC
                )
                SELECT $instancecolumns
                    COALESCE(DB_NAME(st.dbid), DB_NAME(CAST(pa.value AS INT)), 'Resource') AS [Database],
                    COALESCE(OBJECT_NAME(st.objectid, st.dbid), '<none>') AS ObjectName,
                    qs.query_hash AS QueryHash,
                    qs.total_logical_reads + total_logical_writes AS TotalIO,
                    qs.execution_count AS ExecutionCount,
                    CAST((total_logical_reads + total_logical_writes) / (execution_count + 0.0) AS money) AS AverageIO,
                    io AS QueryTotalIO,
                    SUBSTRING(st.TEXT,(qs.statement_start_offset + 2) / 2,
                        (CASE
                            WHEN qs.statement_end_offset = -1  THEN LEN(CONVERT(NVARCHAR(MAX),st.text)) * 2
                            ELSE qs.statement_end_offset
                            END - qs.statement_start_offset) / 2) AS QueryText,
                    qp.query_plan AS QueryPlan
                FROM sys.dm_exec_query_stats qs
                JOIN high_io_queries fq
                    ON fq.query_hash = qs.query_hash
                CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
                CROSS APPLY sys.dm_exec_query_plan (qs.plan_handle) qp
                OUTER APPLY sys.dm_exec_plan_attributes(qs.plan_handle) pa
                WHERE pa.attribute = 'dbid' $wheredb $wherenotdb $whereexcludesystem
                ORDER BY fq.io DESC,
                    fq.query_hash,
                    qs.total_logical_reads + total_logical_writes DESC
                OPTION (RECOMPILE)"

        $cpu = ";WITH high_cpu_queries AS
                (
                    SELECT TOP $Limit
                        query_hash,
                        SUM(total_worker_time) cpuTime
                    FROM sys.dm_exec_query_stats
                    WHERE query_hash <> 0x0
                    GROUP BY query_hash
                    ORDER BY SUM(total_worker_time) DESC
                )
                SELECT $instancecolumns
                    COALESCE(DB_NAME(st.dbid), DB_NAME(CAST(pa.value AS INT)), 'Resource') AS [Database],
                    COALESCE(OBJECT_NAME(st.objectid, st.dbid), '<none>') AS ObjectName,
                    qs.query_hash AS QueryHash,
                    qs.total_worker_time AS CpuTime,
                    qs.execution_count AS ExecutionCount,
                    CAST(total_worker_time / (execution_count + 0.0) AS money) AS AverageCpuMs,
                    cpuTime AS QueryTotalCpu,
                    SUBSTRING(st.TEXT,(qs.statement_start_offset + 2) / 2,
                        (CASE
                            WHEN qs.statement_end_offset = -1  THEN LEN(CONVERT(NVARCHAR(MAX),st.text)) * 2
                            ELSE qs.statement_end_offset
                            END - qs.statement_start_offset) / 2) AS QueryText,
                    qp.query_plan AS QueryPlan
                FROM sys.dm_exec_query_stats qs
                JOIN high_cpu_queries hcq
                    ON hcq.query_hash = qs.query_hash
                CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
                CROSS APPLY sys.dm_exec_query_plan (qs.plan_handle) qp
                OUTER APPLY sys.dm_exec_plan_attributes(qs.plan_handle) pa
                WHERE pa.attribute = 'dbid' $wheredb $wherenotdb $whereexcludesystem
                ORDER BY hcq.cpuTime DESC,
                    hcq.query_hash,
                    qs.total_worker_time DESC
                OPTION (RECOMPILE)"
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Type -in "All", "Duration") {
                try {
                    Write-Message -Level Debug -Message "Executing SQL: $duration"
                    $server.Query($duration) | Select-DefaultView -ExcludeProperty QueryPlan
                } catch {
                    Stop-Function -Message "Failure executing query for duration." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($Type -in "All", "Frequency") {
                try {
                    Write-Message -Level Debug -Message "Executing SQL: $frequency"
                    $server.Query($frequency) | Select-DefaultView -ExcludeProperty QueryPlan
                } catch {
                    Stop-Function -Message "Failure executing query for frequency." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($Type -in "All", "IO") {
                try {
                    Write-Message -Level Debug -Message "Executing SQL: $io"
                    $server.Query($io) | Select-DefaultView -ExcludeProperty QueryPlan
                } catch {
                    Stop-Function -Message "Failure executing query for IO." -ErrorRecord $_ -Target $server -Continue
                }
            }

            if ($Type -in "All", "CPU") {
                try {
                    Write-Message -Level Debug -Message "Executing SQL: $cpu"
                    $server.Query($cpu) | Select-DefaultView -ExcludeProperty QueryPlan
                } catch {
                    Stop-Function -Message "Failure executing query for CPU." -ErrorRecord $_ -Target $server -Continue
                }
            }
        }
    }
}