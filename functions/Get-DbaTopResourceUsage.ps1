function Get-DbaTopResourceUsage {
    <#
    .SYNOPSIS
        Returns the top 20 resource consumers for cached queries based on four different metrics: duration, frequency, IO, and CPU.

    .DESCRIPTION
        Returns the top 20 resource consumers for cached queries based on four different metrics: duration, frequency, IO, and CPU.

        This command is based off of queries provided by Michael J. Swart at http://michaeljswart.com/go/Top20

        Per Michael: "I've posted queries like this before, and others have written many other versions of this query. All these queries are based on sys.dm_exec_query_stats."

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER ExcludeSystem
        This will exclude system objects like replication procedures from being returned.

    .PARAMETER Type
        By default, all Types run but you can specify one or more of the following: Duration, Frequency, IO, or CPU

    .PARAMETER Limit
        By default, these query the Top 20 worst offenders (though more than 20 results can be returned if each of the top 20 have more than 1 subsequent result)

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Query, Performance
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
            $wheredb = " and coalesce(db_name(st.dbid), db_name(cast(pa.value AS INT)), 'Resource') in ('$($database -join '', '')')"
        }

        if ($ExcludeDatabase) {
            $wherenotdb = " and coalesce(db_name(st.dbid), db_name(cast(pa.value AS INT)), 'Resource') not in ('$($excludedatabase -join '', '')')"
        }

        if ($ExcludeSystem) {
            $whereexcludesystem = " AND coalesce(object_name(st.objectid, st.dbid), '<none>') NOT LIKE 'sp_MS%' "
        }
        $duration = ";with long_queries as
                        (
                            select top $Limit
                                query_hash,
                                sum(total_elapsed_time) elapsed_time
                            from sys.dm_exec_query_stats
                            where query_hash <> 0x0
                            group by query_hash
                            order by sum(total_elapsed_time) desc
                        )
                        select $instancecolumns
                            coalesce(db_name(st.dbid), db_name(cast(pa.value AS INT)), 'Resource') AS [Database],
                            coalesce(object_name(st.objectid, st.dbid), '<none>') as ObjectName,
                            qs.query_hash as QueryHash,
                            qs.total_elapsed_time / 1000 as TotalElapsedTimeMs,
                            qs.execution_count as ExecutionCount,
                            cast((total_elapsed_time / 1000) / (execution_count + 0.0) as money) as AverageDurationMs,
                            lq.elapsed_time / 1000 as QueryTotalElapsedTimeMs,
                            SUBSTRING(st.TEXT,(qs.statement_start_offset + 2) / 2,
                                (CASE
                                    WHEN qs.statement_end_offset = -1  THEN LEN(CONVERT(NVARCHAR(MAX),st.text)) * 2
                                    ELSE qs.statement_end_offset
                                    END - qs.statement_start_offset) / 2) as QueryText,
                            qp.query_plan as QueryPlan
                        from sys.dm_exec_query_stats qs
                        join long_queries lq
                            on lq.query_hash = qs.query_hash
                        cross apply sys.dm_exec_sql_text(qs.sql_handle) st
                        cross apply sys.dm_exec_query_plan (qs.plan_handle) qp
                        outer apply sys.dm_exec_plan_attributes(qs.plan_handle) pa
                        where pa.attribute = 'dbid' $wheredb $wherenotdb $whereexcludesystem
                        order by lq.elapsed_time desc,
                            lq.query_hash,
                            qs.total_elapsed_time desc
                        option (recompile)"

        $frequency = ";with frequent_queries as
                        (
                            select top $Limit
                                query_hash,
                                sum(execution_count) executions
                            from sys.dm_exec_query_stats
                            where query_hash <> 0x0
                            group by query_hash
                            order by sum(execution_count) desc
                        )
                        select $instancecolumns
                            coalesce(db_name(st.dbid), db_name(cast(pa.value AS INT)), 'Resource') AS [Database],
                            coalesce(object_name(st.objectid, st.dbid), '<none>') as ObjectName,
                            qs.query_hash as QueryHash,
                            qs.execution_count as ExecutionCount,
                            executions as QueryTotalExecutions,
                            SUBSTRING(st.TEXT,(qs.statement_start_offset + 2) / 2,
                                (CASE
                                    WHEN qs.statement_end_offset = -1  THEN LEN(CONVERT(NVARCHAR(MAX),st.text)) * 2
                                    ELSE qs.statement_end_offset
                                    END - qs.statement_start_offset) / 2) as QueryText,
                            qp.query_plan as QueryPlan
                        from sys.dm_exec_query_stats qs
                        join frequent_queries fq
                            on fq.query_hash = qs.query_hash
                        cross apply sys.dm_exec_sql_text(qs.sql_handle) st
                        cross apply sys.dm_exec_query_plan (qs.plan_handle) qp
                        outer apply sys.dm_exec_plan_attributes(qs.plan_handle) pa
                        where pa.attribute = 'dbid'  $wheredb $wherenotdb $whereexcludesystem
                        order by fq.executions desc,
                            fq.query_hash,
                            qs.execution_count desc
                        option (recompile)"

        $io = ";with high_io_queries as
                (
                    select top $Limit
                        query_hash,
                        sum(total_logical_reads + total_logical_writes) io
                    from sys.dm_exec_query_stats
                    where query_hash <> 0x0
                    group by query_hash
                    order by sum(total_logical_reads + total_logical_writes) desc
                )
                select $instancecolumns
                    coalesce(db_name(st.dbid), db_name(cast(pa.value AS INT)), 'Resource') AS [Database],
                    coalesce(object_name(st.objectid, st.dbid), '<none>') as ObjectName,
                    qs.query_hash as QueryHash,
                    qs.total_logical_reads + total_logical_writes as TotalIO,
                    qs.execution_count as ExecutionCount,
                    cast((total_logical_reads + total_logical_writes) / (execution_count + 0.0) as money) as AverageIO,
                    io as QueryTotalIO,
                    SUBSTRING(st.TEXT,(qs.statement_start_offset + 2) / 2,
                        (CASE
                            WHEN qs.statement_end_offset = -1  THEN LEN(CONVERT(NVARCHAR(MAX),st.text)) * 2
                            ELSE qs.statement_end_offset
                            END - qs.statement_start_offset) / 2) as QueryText,
                    qp.query_plan as QueryPlan
                from sys.dm_exec_query_stats qs
                join high_io_queries fq
                    on fq.query_hash = qs.query_hash
                cross apply sys.dm_exec_sql_text(qs.sql_handle) st
                cross apply sys.dm_exec_query_plan (qs.plan_handle) qp
                outer apply sys.dm_exec_plan_attributes(qs.plan_handle) pa
                where pa.attribute = 'dbid' $wheredb $wherenotdb $whereexcludesystem
                order by fq.io desc,
                    fq.query_hash,
                    qs.total_logical_reads + total_logical_writes desc
                option (recompile)"

        $cpu = ";with high_cpu_queries as
                (
                    select top $Limit
                        query_hash,
                        sum(total_worker_time) cpuTime
                    from sys.dm_exec_query_stats
                    where query_hash <> 0x0
                    group by query_hash
                    order by sum(total_worker_time) desc
                )
                select $instancecolumns
                    coalesce(db_name(st.dbid), db_name(cast(pa.value AS INT)), 'Resource') AS [Database],
                    coalesce(object_name(st.objectid, st.dbid), '<none>') as ObjectName,
                    qs.query_hash as QueryHash,
                    qs.total_worker_time as CpuTime,
                    qs.execution_count as ExecutionCount,
                    cast(total_worker_time / (execution_count + 0.0) as money) as AverageCpuMs,
                    cpuTime as QueryTotalCpu,
                    SUBSTRING(st.TEXT,(qs.statement_start_offset + 2) / 2,
                        (CASE
                            WHEN qs.statement_end_offset = -1  THEN LEN(CONVERT(NVARCHAR(MAX),st.text)) * 2
                            ELSE qs.statement_end_offset
                            END - qs.statement_start_offset) / 2) as QueryText,
                    qp.query_plan as QueryPlan
                from sys.dm_exec_query_stats qs
                join high_cpu_queries hcq
                    on hcq.query_hash = qs.query_hash
                cross apply sys.dm_exec_sql_text(qs.sql_handle) st
                cross apply sys.dm_exec_query_plan (qs.plan_handle) qp
                outer apply sys.dm_exec_plan_attributes(qs.plan_handle) pa
                where pa.attribute = 'dbid' $wheredb $wherenotdb $whereexcludesystem
                order by hcq.cpuTime desc,
                    hcq.query_hash,
                    qs.total_worker_time desc
                option (recompile)"
    }

    process {
        foreach ($instance in $SqlInstance) {

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            if ($server.ConnectionContext.StatementTimeout -ne 0) {
                $server.ConnectionContext.StatementTimeout = 0
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