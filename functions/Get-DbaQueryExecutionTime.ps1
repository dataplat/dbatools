function Get-DbaQueryExecutionTime {
    <#
    .SYNOPSIS
        Displays Stored Procedures and Ad hoc queries with the highest execution times.  Works on SQL Server 2008 and above.

    .DESCRIPTION
        Quickly find slow query executions within a database.  Results will include stored procedures and individual SQL statements.

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

    .PARAMETER MaxResultsPerDb
        Allows you to limit the number of results returned, as many systems can have very large amounts of query plans.  Default value is 100 results.

    .PARAMETER MinExecs
        Allows you to limit the scope to queries that have been executed a minimum number of time. Default value is 100 executions.

    .PARAMETER MinExecMs
        Allows you to limit the scope to queries with a specified average execution time.  Default value is 500 (ms).

    .PARAMETER ExcludeSystem
        Allows you to suppress output on system databases

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Query, Performance
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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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