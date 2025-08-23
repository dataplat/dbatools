function Get-DbaQueryExecutionTime {
    <#
    .SYNOPSIS
        Retrieves stored procedures and SQL statements with the highest CPU execution times from SQL Server instances.

    .DESCRIPTION
        Analyzes SQL Server's query execution statistics to identify performance bottlenecks by examining CPU worker time data from dynamic management views. This function queries sys.dm_exec_procedure_stats for stored procedures and sys.dm_exec_query_stats for ad hoc statements, returning detailed execution metrics including average execution time, total executions, and maximum execution time.

        Use this when troubleshooting performance issues, identifying resource-intensive queries during peak hours, or conducting routine performance audits. The results help pinpoint which stored procedures or SQL statements are consuming the most CPU resources across your databases, so you don't have to manually query DMVs or run expensive profiler traces.

        By default, returns the top 100 results per database for queries executed at least 100 times with an average execution time of 500ms or higher. Results include the full SQL text for ad hoc statements and procedure names for stored procedures, along with execution statistics and timing data.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to analyze for query execution statistics. Accepts wildcards for pattern matching.
        Use this when troubleshooting performance issues in specific databases instead of scanning all databases on the instance.
        Helpful for focusing on production databases or isolating performance analysis to databases experiencing issues.

    .PARAMETER ExcludeDatabase
        Specifies databases to skip during the execution time analysis. Accepts wildcards for pattern matching.
        Use this to avoid processing databases that are known to be performing well or contain only static reference data.
        Common use case is excluding development or staging databases when analyzing production performance.

    .PARAMETER MaxResultsPerDb
        Limits the number of top execution time results returned per database. Defaults to 100 results.
        Specify a lower number for quick performance overviews or higher numbers for comprehensive analysis.
        Large values may impact query performance on busy systems with extensive plan cache data.

    .PARAMETER MinExecs
        Filters results to queries that have executed at least this many times. Defaults to 100 executions.
        Use this to focus on frequently-run queries that have consistent performance patterns rather than one-time queries.
        Higher values help identify truly problematic queries that impact system performance regularly.

    .PARAMETER MinExecMs
        Filters results to queries with an average execution time of at least this many milliseconds. Defaults to 500ms.
        Use this to focus on genuinely slow queries rather than fast queries that happen to consume CPU cycles.
        Lowering this value shows more queries but may include acceptable performance levels.

    .PARAMETER ExcludeSystem
        Skips analysis of system databases (master, model, msdb, tempdb).
        Use this when focusing performance analysis on user databases only, since system database queries are typically administrative.
        System database performance issues are usually infrastructure-related rather than application code problems.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Diagnostic, Performance, Query
        Author: Brandon Abshire, netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaQueryExecutionTime

    .EXAMPLE
        PS C:\> Get-DbaQueryExecutionTime -SqlInstance sql2008, sqlserver2012

        Return the top 100 slowest stored procedures or statements for servers sql2008 and sqlserver2012.

    .EXAMPLE
        PS C:\> Get-DbaQueryExecutionTime -SqlInstance sql2008 -Database TestDB

        Return the top 100 slowest stored procedures or statements on server sql2008 for only the TestDB database.

    .EXAMPLE
        PS C:\> Get-DbaQueryExecutionTime -SqlInstance sql2008 -Database TestDB -MaxResultsPerDb 100 -MinExecs 200 -MinExecMs 1000

        Return the top 100 slowest stored procedures or statements on server sql2008 for only the TestDB database, limiting results to queries with more than 200 total executions and an execution time over 1000ms or higher.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [int]$MaxResultsPerDb = 100,
        [int]$MinExecs = 100,
        [parameter(Position = 3)]
        [int]$MinExecMs = 500,
        [parameter(Position = 4)]
        [Alias("ExcludeSystemDatabases")]
        [switch]$ExcludeSystem,
        [switch]$EnableException
    )

    begin {
        $sql = ";With StatsCTE AS
            (
                SELECT
                    DB_NAME() as DatabaseName,
                    (total_worker_time / execution_count) / 1000 AS AvgExec_ms ,
                    execution_count ,
                    max_worker_time / 1000 AS MaxExec_ms ,
                    OBJECT_NAME(object_id) as ProcName,
                    object_id,
                    type_desc,
                    cached_time,
                    last_execution_time,
                    total_worker_time / 1000 as total_worker_time_ms,
                    total_elapsed_time / 1000 as total_elapsed_time_ms,
                    OBJECT_NAME(object_id) as SQLText,
                    OBJECT_NAME(object_id) as full_statement_text
                FROM    sys.dm_exec_procedure_stats
                WHERE   database_id = DB_ID()"

        if ($MinExecs) { $sql += "`n AND execution_count >= " + $MinExecs }
        if ($MinExecMs) { $sql += "`n AND (total_worker_time / execution_count) / 1000 >= " + $MinExecMs }

        $sql += "`n UNION
            SELECT
                DB_NAME() as DatabaseName,
                ( qs.total_worker_time / qs.execution_count ) / 1000 AS AvgExec_ms ,
                qs.execution_count ,
                qs.max_worker_time / 1000 AS MaxExec_ms ,
                OBJECT_NAME(st.objectid) as ProcName,
                   st.objectid as [object_id],
                   'STATEMENT' as type_desc,
                   '1901-01-01 00:00:00' as cached_time,
                    qs.last_execution_time,
                    qs.total_worker_time / 1000 as total_worker_time_ms,
                    qs.total_elapsed_time / 1000 as total_elapsed_time_ms,
                    SUBSTRING(st.text, (qs.statement_start_offset/2)+1, 50) + '...' AS SQLText,
                    SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
                        ((CASE qs.statement_end_offset
                          WHEN -1 THEN DATALENGTH(st.text)
                         ELSE qs.statement_end_offset
                         END - qs.statement_start_offset)/2) + 1) AS full_statement_text
            FROM    sys.dm_exec_query_stats qs
            CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) as pa
            CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) as st
            WHERE st.dbid = DB_ID() OR (pa.attribute = 'dbid' and pa.value = DB_ID())"

        if ($MinExecs) { $sql += "`n AND execution_count >= " + $MinExecs }
        if ($MinExecMs) { $sql += "`n AND (total_worker_time / execution_count) / 1000 >= " + $MinExecMs }

        if ($MaxResultsPerDb) { $sql += ")`n SELECT TOP " + $MaxResultsPerDb }
        else {
            $sql += ")
                        SELECT "
        }

        $sql += "`n     DatabaseName,
                        AvgExec_ms,
                        execution_count,
                        MaxExec_ms,
                        ProcName,
                        object_id,
                        type_desc,
                        cached_time,
                        last_execution_time,
                        total_worker_time_ms,
                        total_elapsed_time_ms,
                        SQLText,
                        full_statement_text
                    FROM StatsCTE "

        if ($MinExecs -or $MinExecMs) {
            $sql += "`n WHERE `n"

            if ($MinExecs) {
                $sql += " execution_count >= " + $MinExecs
            }

            if ($MinExecMs -gt 0 -and $MinExecs) {
                $sql += "`n AND AvgExec_ms >= " + $MinExecMs
            } elseif ($MinExecMs) {
                $sql += "`n AvgExecs_ms >= " + $MinExecMs
            }
        }

        $sql += "`n ORDER BY AvgExec_ms DESC"
    }
    process {
        if (!$MaxResultsPerDb -and !$MinExecs -and !$MinExecMs) {
            Write-Message -Level Warning -Message "Results may take time, depending on system resources and size of buffer cache."
            Write-Message -Level Warning -Message "Consider limiting results using -MaxResultsPerDb, -MinExecs and -MinExecMs parameters."
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $dbs = $server.Databases
            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeSystem) {
                $dbs = $dbs | Where-Object { $_.IsSystemObject -eq $false }
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $db on $instance"

                if ($db.IsAccessible -eq $false) {
                    Write-Message -Level Warning -Message "The database $db is not accessible. Skipping database."
                    continue
                }

                try {
                    foreach ($row in $db.ExecuteWithResults($sql).Tables.Rows) {
                        [PSCustomObject]@{
                            ComputerName       = $server.ComputerName
                            InstanceName       = $server.ServiceName
                            SqlInstance        = $server.DomainInstanceName
                            Database           = $row.DatabaseName
                            ProcName           = $row.ProcName
                            ObjectID           = $row.object_id
                            TypeDesc           = $row.type_desc
                            Executions         = $row.Execution_Count
                            AvgExecMs          = $row.AvgExec_ms
                            MaxExecMs          = $row.MaxExec_ms
                            CachedTime         = $row.cached_time
                            LastExecTime       = $row.last_execution_time
                            TotalWorkerTimeMs  = $row.total_worker_time_ms
                            TotalElapsedTimeMs = $row.total_elapsed_time_ms
                            SQLText            = $row.SQLText
                            FullStatementText  = $row.full_statement_text
                        } | Select-DefaultView -ExcludeProperty FullStatementText
                    }
                } catch {
                    Stop-Function -Message "Could not process $db on $instance" -Target $db -ErrorRecord $_ -Continue
                }
            }
        }
    }
}