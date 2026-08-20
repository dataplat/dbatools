function Find-DbaDbQueryStoreRegression {
    <#
    .SYNOPSIS
        Detects query performance regressions from Query Store runtime statistics using an
        execution-weighted baseline.

    .DESCRIPTION
        Reads sys.query_store_runtime_stats and flags queries whose recent performance has
        regressed against a historical baseline.

        Rather than a naive average-vs-average comparison, each plan's historical duration is
        weighted by execution count, and low-frequency / low-total-impact queries are filtered
        out, so genuine regressions surface instead of noise from a handful of slow one-off
        executions.

        This command is read-only: it queries Query Store and returns objects. It does not force
        plans, clear the store, or change any configuration.

        Query Store must be enabled on the target database(s) (SQL Server 2016+).

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell
        credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and
        Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. If unspecified, all Query Store-enabled user databases are
        processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude.

    .PARAMETER BaselineStartDaysAgo
        Start of the historical baseline window, in days before now. Default: 7.

    .PARAMETER BaselineEndDaysAgo
        End of the historical baseline window, in days before now. Default: 1. The baseline
        window is therefore BaselineStartDaysAgo..BaselineEndDaysAgo, and the current window is
        BaselineEndDaysAgo..now.

    .PARAMETER SlowdownThreshold
        Minimum ratio of current duration to baseline duration for a query to be flagged.
        Default: 1.5 (50% slower).

    .PARAMETER MinExecutionCount
        Minimum executions in the current window for a query to be considered. Default: 20.

    .PARAMETER MinTotalDurationMs
        Minimum total current duration in milliseconds (summed across executions) for a query to
        be considered. Filters queries that are individually slow but negligible to the overall
        workload. Default: 100.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a
        friendly warning message. This avoids overwhelming you with "sea of red" exceptions, but
        is inconvenient because it basically disables advanced scripting.

        Using this switch turns this "nice by default" feature off and enables you to catch
        exceptions with your own try/catch.

    .NOTES
        Tags: QueryStore, Performance, Diagnostic
        Author: Deepesh Dhake

        Website: https://dbatools.io
        Copyright: (c) 2026 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaDbQueryStoreRegression

    .EXAMPLE
        PS C:\> Find-DbaDbQueryStoreRegression -SqlInstance sql2017 -Database AdventureWorks

        Finds queries in AdventureWorks that ran at least 50% slower in the last day versus the
        prior 7-to-1-day baseline, considering only queries executed 20 or more times.

    .EXAMPLE
        PS C:\> Find-DbaDbQueryStoreRegression -SqlInstance sql2017 -Database Sales -SlowdownThreshold 2.0 -MinExecutionCount 50

        Only flags queries in Sales that at least doubled in duration and ran 50 or more times.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2017 | Find-DbaDbQueryStoreRegression | Sort-Object SlowdownFactor -Descending

        Pipes databases in and returns all regressions across the instance, worst first.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [int]$BaselineStartDaysAgo = 7,
        [int]$BaselineEndDaysAgo = 1,
        [double]$SlowdownThreshold = 1.5,
        [int]$MinExecutionCount = 20,
        [long]$MinTotalDurationMs = 100,
        [switch]$EnableException
    )

    begin {
        if ($BaselineEndDaysAgo -ge $BaselineStartDaysAgo) {
            Stop-Function -Message "BaselineEndDaysAgo ($BaselineEndDaysAgo) must be smaller than BaselineStartDaysAgo ($BaselineStartDaysAgo). The baseline is the older window."
            return
        }

        $minTotalDurationUs = $MinTotalDurationMs * 1000

        # Regression is measured at the QUERY level: each query's executions are aggregated
        # across ALL its plans within a window (weighted by execution count). This catches
        # plan-flip regressions - the common case where a query degrades because the optimizer
        # switched to a worse plan - which a plan-level comparison would miss.
        $sql = "
DECLARE @BaselineStart datetimeoffset = DATEADD(day, -$BaselineStartDaysAgo, SYSDATETIMEOFFSET());
DECLARE @BaselineEnd   datetimeoffset = DATEADD(day, -$BaselineEndDaysAgo,   SYSDATETIMEOFFSET());
DECLARE @CurrentStart  datetimeoffset = @BaselineEnd;

WITH baseline AS (
    SELECT q.query_id,
        SUM(rs.avg_duration * rs.count_executions) * 1.0 / NULLIF(SUM(rs.count_executions), 0) AS baseline_duration,
        SUM(rs.count_executions) AS baseline_exec_count,
        COUNT(DISTINCT p.plan_id) AS baseline_plan_count
    FROM sys.query_store_runtime_stats rs
    JOIN sys.query_store_plan  p ON rs.plan_id = p.plan_id
    JOIN sys.query_store_query q ON p.query_id = q.query_id
    WHERE rs.last_execution_time >= @BaselineStart AND rs.last_execution_time < @BaselineEnd
    GROUP BY q.query_id
),
current_perf AS (
    SELECT q.query_id,
        SUM(rs.avg_duration * rs.count_executions) * 1.0 / NULLIF(SUM(rs.count_executions), 0) AS current_duration,
        SUM(rs.count_executions) AS current_exec_count,
        SUM(rs.avg_duration * rs.count_executions) AS current_total_duration,
        COUNT(DISTINCT p.plan_id) AS current_plan_count
    FROM sys.query_store_runtime_stats rs
    JOIN sys.query_store_plan  p ON rs.plan_id = p.plan_id
    JOIN sys.query_store_query q ON p.query_id = q.query_id
    WHERE rs.last_execution_time >= @CurrentStart
    GROUP BY q.query_id
)
SELECT
    c.query_id AS QueryId,
    CAST(b.baseline_duration / 1000.0 AS DECIMAL(18,2)) AS BaselineDurationMs,
    CAST(c.current_duration  / 1000.0 AS DECIMAL(18,2)) AS CurrentDurationMs,
    CAST(c.current_duration * 1.0 / NULLIF(b.baseline_duration, 0) AS DECIMAL(10,2)) AS SlowdownFactor,
    b.baseline_exec_count AS BaselineExecCount,
    c.current_exec_count  AS CurrentExecCount,
    CASE WHEN c.current_plan_count > b.baseline_plan_count OR c.current_plan_count > 1
         THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END AS PlanChanged
FROM current_perf c
JOIN baseline b ON c.query_id = b.query_id
WHERE c.current_duration > b.baseline_duration * $SlowdownThreshold
  AND c.current_exec_count > $MinExecutionCount
  AND c.current_total_duration > $minTotalDurationUs
ORDER BY SlowdownFactor DESC;"
    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 13
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $dbs = Get-DbaDatabase -SqlInstance $server -Database $Database -ExcludeDatabase $ExcludeDatabase -ExcludeSystem

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $($db.Name) on $instance"

                if ($db.QueryStoreOptions.ActualState -eq 'Off') {
                    Write-Message -Level Warning -Message "Query Store is not enabled on $($db.Name) on $instance, skipping"
                    continue
                }

                try {
                    $results = $db.Query($sql)
                } catch {
                    Stop-Function -Message "Failure executing Query Store analysis against $($db.Name) on $instance" -ErrorRecord $_ -Target $db -Continue
                }

                foreach ($row in $results) {
                    [PSCustomObject]@{
                        ComputerName      = $server.ComputerName
                        InstanceName      = $server.ServiceName
                        SqlInstance       = $server.DomainInstanceName
                        Database          = $db.Name
                        QueryId           = $row.QueryId
                        BaselineDurationMs = $row.BaselineDurationMs
                        CurrentDurationMs  = $row.CurrentDurationMs
                        SlowdownFactor     = $row.SlowdownFactor
                        PlanChanged        = [bool]$row.PlanChanged
                        BaselineExecCount  = $row.BaselineExecCount
                        CurrentExecCount   = $row.CurrentExecCount
                    } | Select-DefaultView -Property SqlInstance, Database, QueryId, BaselineDurationMs, CurrentDurationMs, SlowdownFactor, PlanChanged, CurrentExecCount
                }
            }
        }
    }
}
