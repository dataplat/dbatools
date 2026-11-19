#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Lists the slowest stored procedures and statements. Port of
/// public/Get-DbaQueryExecutionTime.ps1 (W1-094). The begin block builds $sql with the
/// bound-0-omits-clause quirks (an explicit -MinExecs 0 / -MinExecMs 0 / -MaxResultsPerDb 0
/// drops its clause) INCLUDING the AvgExecs_ms COLUMN TYPO branch (-MinExecMs without
/// -MinExecs emits an invalid column and every database faults into Stop-Function). The
/// explicit-Position pair (MinExecMs 3, ExcludeSystem 4) kills implicit positional
/// binding for every other parameter (surface-pinned). The per-record all-zero double
/// warning fires BEFORE the instance loop. Each instance rides one VERBATIM hop: the
/// $server.Databases walk with the -In/-NotIn/IsSystemObject filters, the per-db
/// verbose/IsAccessible-warning pair with its contained continue, and the
/// ExecuteWithResults row projection + Select-DefaultView under Stop-Function -Continue
/// (contained; -FunctionName per the W1-090 law). EE throws propagate uncaught. Surface
/// pinned by migration/baselines/Get-DbaQueryExecutionTime.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaQueryExecutionTime")]
public sealed class GetDbaQueryExecutionTimeCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to include.</summary>
    [Parameter]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>TOP limit per database (0 drops the clause).</summary>
    [Parameter]
    public int MaxResultsPerDb { get; set; } = 100;

    /// <summary>Minimum execution count (0 drops the clause).</summary>
    [Parameter]
    public int MinExecs { get; set; } = 100;

    /// <summary>Minimum average execution ms (0 drops the clause).</summary>
    [Parameter(Position = 3)]
    public int MinExecMs { get; set; } = 500;

    /// <summary>Excludes system databases.</summary>
    [Parameter(Position = 4)]
    [Alias("ExcludeSystemDatabases")]
    public SwitchParameter ExcludeSystem { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private string _sql = "";

    protected override void BeginProcessing()
    {
        // PS: the begin-block $sql build - conditional appends keyed on int truthiness
        // (an explicit 0 drops the clause), int-to-string invariant concatenation.
        StringBuilder sql = new StringBuilder();
        sql.Append(@";WITH StatsCTE AS
            (
                SELECT
                    DB_NAME() AS DatabaseName,
                    (total_worker_time / execution_count) / 1000 AS AvgExec_ms ,
                    execution_count ,
                    max_worker_time / 1000 AS MaxExec_ms ,
                    OBJECT_NAME(object_id) AS ProcName,
                    object_id,
                    type_desc,
                    cached_time,
                    last_execution_time,
                    total_worker_time / 1000 AS total_worker_time_ms,
                    total_elapsed_time / 1000 AS total_elapsed_time_ms,
                    OBJECT_NAME(object_id) AS SQLText,
                    OBJECT_NAME(object_id) AS full_statement_text
                FROM    sys.dm_exec_procedure_stats
                WHERE   database_id = DB_ID()");

        if (MinExecs != 0) sql.Append("\n AND execution_count >= " + MinExecs.ToString(CultureInfo.InvariantCulture));
        if (MinExecMs != 0) sql.Append("\n AND (total_worker_time / execution_count) / 1000 >= " + MinExecMs.ToString(CultureInfo.InvariantCulture));

        sql.Append(@"
 UNION
            SELECT
                DB_NAME() AS DatabaseName,
                ( qs.total_worker_time / qs.execution_count ) / 1000 AS AvgExec_ms ,
                qs.execution_count ,
                qs.max_worker_time / 1000 AS MaxExec_ms ,
                OBJECT_NAME(st.objectid) AS ProcName,
                   st.objectid AS [object_id],
                   'STATEMENT' AS type_desc,
                   '1901-01-01 00:00:00' AS cached_time,
                    qs.last_execution_time,
                    qs.total_worker_time / 1000 AS total_worker_time_ms,
                    qs.total_elapsed_time / 1000 AS total_elapsed_time_ms,
                    SUBSTRING(st.text, (qs.statement_start_offset/2)+1, 50) + '...' AS SQLText,
                    SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
                        ((CASE qs.statement_end_offset
                          WHEN -1 THEN DATALENGTH(st.text)
                         ELSE qs.statement_end_offset
                         END - qs.statement_start_offset)/2) + 1) AS full_statement_text
            FROM    sys.dm_exec_query_stats qs
            CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) AS pa
            CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
            WHERE st.dbid = DB_ID() OR (pa.attribute = 'dbid' AND pa.value = DB_ID())");

        if (MinExecs != 0) sql.Append("\n AND execution_count >= " + MinExecs.ToString(CultureInfo.InvariantCulture));
        if (MinExecMs != 0) sql.Append("\n AND (total_worker_time / execution_count) / 1000 >= " + MinExecMs.ToString(CultureInfo.InvariantCulture));

        if (MaxResultsPerDb != 0)
        {
            sql.Append(")\n SELECT TOP " + MaxResultsPerDb.ToString(CultureInfo.InvariantCulture));
        }
        else
        {
            sql.Append(@")
                        SELECT ");
        }

        sql.Append(@"
     DatabaseName,
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
                    FROM StatsCTE ");

        if (MinExecs != 0 || MinExecMs != 0)
        {
            sql.Append("\n WHERE \n");

            if (MinExecs != 0)
            {
                sql.Append(" execution_count >= " + MinExecs.ToString(CultureInfo.InvariantCulture));
            }

            if (MinExecMs > 0 && MinExecs != 0)
            {
                sql.Append("\n AND AvgExec_ms >= " + MinExecMs.ToString(CultureInfo.InvariantCulture));
            }
            else if (MinExecMs != 0)
            {
                // PS: the AvgExecs_ms COLUMN TYPO branch - preserved verbatim.
                sql.Append("\n AvgExecs_ms >= " + MinExecMs.ToString(CultureInfo.InvariantCulture));
            }
        }

        sql.Append("\n ORDER BY AvgExec_ms DESC");
        _sql = sql.ToString();
    }

    protected override void ProcessRecord()
    {
        // PS: the all-zero double warning fires per RECORD, before the instance loop.
        if (MaxResultsPerDb == 0 && MinExecs == 0 && MinExecMs == 0)
        {
            WriteMessage(MessageLevel.Warning, "Results may take time, depending on system resources and size of buffer cache.");
            WriteMessage(MessageLevel.Warning, "Consider limiting results using -MaxResultsPerDb, -MinExecs and -MinExecMs parameters.");
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Hashtable connectParams = new Hashtable();
            connectParams["SqlInstance"] = instance;
            connectParams["SqlCredential"] = SqlCredential;
            connectParams["MinimumVersion"] = 10;
            NestedConnect.Outcome connection = NestedConnect.Connect(this, connectParams);
            if (!connection.Ok)
            {
                StopFunction("Failure", target: instance, errorRecord: connection.Failure, category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }
            Server server = connection.Server!;

            NestedCommand.InvokeScopedStreaming(this, item => WriteObject(item), InstanceProjectionScript,
                server, instance, _sql, Database, ExcludeDatabase, ExcludeSystem.ToBool(), EnableException.ToBool(), BoundVerbose(), BoundDebug());
        }
    }

    /// <summary>A bound -Debug carrier for the hop scopes (W1-044 convention).</summary>
    private object? BoundDebug()
    {
        object? debug;
        if (MyInvocation.BoundParameters.TryGetValue("Debug", out debug))
            return LanguagePrimitives.IsTrue(debug);
        return null;
    }

    /// <summary>A bound -Verbose carrier for the hop scopes (W1-044 convention).</summary>
    private object? BoundVerbose()
    {
        object? verbose;
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out verbose))
            return LanguagePrimitives.IsTrue(verbose);
        return null;
    }

    // PS: the per-instance process body VERBATIM (the Databases walk and filters, the
    // per-db verbose/IsAccessible pair with its contained continue, and the
    // ExecuteWithResults projection under Stop-Function -Continue).
    private const string InstanceProjectionScript = """
param($server, $instance, $sql, $Database, $ExcludeDatabase, $ExcludeSystem, $EnableException, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($server, $instance, $sql, $Database, $ExcludeDatabase, $ExcludeSystem, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
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
            Stop-Function -Message "Could not process $db on $instance" -Target $db -ErrorRecord $_ -Continue -FunctionName Get-DbaQueryExecutionTime
        }
    }
} $server $instance $sql $Database $ExcludeDatabase $ExcludeSystem $EnableException $__boundVerbose $__boundDebug 3>&1
""";
}
