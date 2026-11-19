#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Lists the top resource-consuming queries by duration/frequency/IO/CPU. Port of
/// public/Get-DbaTopResourceUsage.ps1 (W1-101). Quirks preserved: the begin-block WHERE
/// fragments interpolate `$($list -join \'\', \'\')` - the join glue is EMPTY and the
/// trailing \'\' makes a 2-element array whose $OFS stringification appends a SPACE
/// (single-db filters survive only via SQL trailing-space padding; MULTI-value lists
/// concatenate into one nonsense literal and match NOTHING); unset fragments read
/// through the module/global scope (the undefined-variable law); the four
/// `$Type -in "All", "X"` gates compare each RHS against the ARRAY $Type coerced to its
/// $OFS join (MULTI-value -Type matches NO gate and emits NOTHING); each gated block
/// debug-logs its SQL and pipes $server.Query through Select-DefaultView
/// -ExcludeProperty QueryPlan; a block fault Stop-Functions with -Continue targeting the
/// INSTANCE loop (remaining blocks for that instance are SKIPPED). Surface pinned by
/// migration/baselines/Get-DbaTopResourceUsage.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaTopResourceUsage")]
public sealed class GetDbaTopResourceUsageCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to include.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>The resource dimension(s) to report.</summary>
    [Parameter(Position = 4)]
    [ValidateSet("All", "Duration", "Frequency", "IO", "CPU")]
    public string[] Type { get; set; } = new string[] { "All" };

    /// <summary>TOP limit per dimension.</summary>
    [Parameter(Position = 5)]
    public int Limit { get; set; } = 20;

    /// <summary>Excludes system replication procedures.</summary>
    [Parameter]
    public SwitchParameter ExcludeSystem { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private string _duration = "";
    private string _frequency = "";
    private string _io = "";
    private string _cpu = "";

    protected override void BeginProcessing()
    {
        // PS: the WHERE fragments - the empty-glue join plus the trailing \'\' array
        // element stringifies with a TRAILING SPACE; unset fragments read through the
        // module/global scope (the undefined-variable law).
        string wheredb = LanguagePrimitives.IsTrue(Database)
            ? " AND COALESCE(DB_NAME(st.dbid), DB_NAME(CAST(pa.value AS INT)), \'Resource\') IN (\'" + JoinListQuirk(Database) + "\')"
            : ModuleVariableText("wheredb");
        string wherenotdb = LanguagePrimitives.IsTrue(ExcludeDatabase)
            ? " AND COALESCE(DB_NAME(st.dbid), DB_NAME(CAST(pa.value AS INT)), \'Resource\') NOT IN (\'" + JoinListQuirk(ExcludeDatabase) + "\')"
            : ModuleVariableText("wherenotdb");
        string whereexcludesystem = ExcludeSystem.ToBool()
            ? " AND COALESCE(OBJECT_NAME(st.objectid, st.dbid), \'<none>\') NOT LIKE \'sp_MS%\' "
            : ModuleVariableText("whereexcludesystem");

        string limit = Limit.ToString(CultureInfo.InvariantCulture);
        _duration = string.Format(CultureInfo.InvariantCulture, DurationTemplate, InstanceColumns, limit, wheredb, wherenotdb, whereexcludesystem);
        _frequency = string.Format(CultureInfo.InvariantCulture, FrequencyTemplate, InstanceColumns, limit, wheredb, wherenotdb, whereexcludesystem);
        _io = string.Format(CultureInfo.InvariantCulture, IoTemplate, InstanceColumns, limit, wheredb, wherenotdb, whereexcludesystem);
        _cpu = string.Format(CultureInfo.InvariantCulture, CpuTemplate, InstanceColumns, limit, wheredb, wherenotdb, whereexcludesystem);
    }

    protected override void ProcessRecord()
    {
        // PS: "$Type -in ..." coerces the ARRAY LHS to its $OFS join per -eq compare.
        string typeText = TypeText();

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

            // PS: a block fault Stop-Functions with -Continue, which targets the
            // INSTANCE loop - the remaining blocks for this instance are skipped.
            if (GateMatches(typeText, "Duration") && !RunBlock(server, _duration, "duration"))
                continue;
            if (GateMatches(typeText, "Frequency") && !RunBlock(server, _frequency, "frequency"))
                continue;
            if (GateMatches(typeText, "IO") && !RunBlock(server, _io, "IO"))
                continue;
            if (GateMatches(typeText, "CPU") && !RunBlock(server, _cpu, "CPU"))
                continue;
        }
    }

    /// <summary>Runs one gated block; false = faulted (the caller continues the
    /// instance loop).</summary>
    private bool RunBlock(Server server, string sql, string label)
    {
        try
        {
            // PS: the Write-Message -Level Debug sits INSIDE the try - a
            // $DebugPreference = "Stop" fault follows the block-fault path.
            WriteMessage(MessageLevel.Debug, "Executing SQL: " + sql);
            foreach (PSObject? item in NestedCommand.InvokeScoped(this, QueryProjectionScript, server, sql))
                WriteObject(item);
            return true;
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (RuntimeException ex)
        {
            StopFunction("Failure executing query for " + label + ".", target: server, errorRecord: StatementFault.Record(ex, "Get-DbaTopResourceUsage"), continueLoop: true);
            return false;
        }
    }

    /// <summary>PS scalar coercion of the $Type array for the -in gates ($OFS join).</summary>
    private string TypeText()
    {
        if (Type.Length == 1)
            return Type[0];
        return string.Join(" ", Type);
    }

    /// <summary>One `$Type -in "All", "X"` gate (case-insensitive -eq).</summary>
    private static bool GateMatches(string typeText, string name)
    {
        return string.Equals(typeText, "All", StringComparison.OrdinalIgnoreCase)
            || string.Equals(typeText, name, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>PS: `$($list -join \'\', \'\')` - empty-glue join, then the trailing
    /// empty element stringifies via $OFS into a TRAILING SPACE.</summary>
    private static string JoinListQuirk(object[]? values)
    {
        List<string> texts = new List<string>();
        foreach (object? value in values ?? new object[0])
            texts.Add(PsJoinText(value));
        return string.Join("", texts) + " ";
    }

    /// <summary>PS -join element conversion (CURRENT culture, the W1-076 law).</summary>
    private static string PsJoinText(object? value)
    {
        if (value is null)
            return "";
        if (value is IConvertible convertible)
            return convertible.ToString(CultureInfo.CurrentCulture);
        return PSObject.AsPSObject(value).ToString();
    }

    /// <summary>The undefined-variable read: an unset begin-block fragment resolves
    /// module scope then global (the established law), read as interpolation text - an
    /// ARRAY value $OFS-joins per element (the hop enumerates it into N results).</summary>
    private string ModuleVariableText(string name)
    {
        Collection<PSObject> results = NestedCommand.InvokeScoped(this, ModuleVariableScript, name);
        if (results.Count == 0)
            return "";
        List<string> texts = new List<string>();
        foreach (PSObject? result in results)
        {
            if (result is null)
            {
                texts.Add("");
                continue;
            }
            texts.Add((string)LanguagePrimitives.ConvertTo(result, typeof(string), CultureInfo.InvariantCulture));
        }
        return string.Join(" ", texts);
    }

    private const string ModuleVariableScript = """
param($__name)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__name)
    $ExecutionContext.SessionState.PSVariable.GetValue($__name)
} $__name
""";

    // PS: $server.Query($q) | Select-DefaultView -ExcludeProperty QueryPlan VERBATIM
    // (the W1-046 seam piped through the module-scoped SDV).
    private const string QueryProjectionScript = """
param($server, $query)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($server, $query)
    $server.Query($query) | Select-DefaultView -ExcludeProperty QueryPlan
} $server $query 3>&1
""";

    private const string InstanceColumns = @" SERVERPROPERTY('MachineName') AS ComputerName,
        ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
        SERVERPROPERTY('ServerName') AS SqlInstance, ";

    private const string DurationTemplate = @";WITH long_queries AS
                        (
                            SELECT TOP {1}
                                query_hash,
                                SUM(total_elapsed_time) elapsed_time
                            FROM sys.dm_exec_query_stats
                            WHERE query_hash <> 0x0
                            GROUP BY query_hash
                            ORDER BY SUM(total_elapsed_time) DESC
                        )
                        SELECT {0}
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
                        WHERE pa.attribute = 'dbid' {2} {3} {4}
                        ORDER BY lq.elapsed_time DESC,
                            lq.query_hash,
                            qs.total_elapsed_time DESC
                        OPTION (RECOMPILE)";

    private const string FrequencyTemplate = @";WITH frequent_queries AS
                        (
                            SELECT TOP {1}
                                query_hash,
                                SUM(execution_count) executions
                            FROM sys.dm_exec_query_stats
                            WHERE query_hash <> 0x0
                            GROUP BY query_hash
                            ORDER BY SUM(execution_count) DESC
                        )
                        SELECT {0}
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
                        WHERE pa.attribute = 'dbid'  {2} {3} {4}
                        ORDER BY fq.executions DESC,
                            fq.query_hash,
                            qs.execution_count DESC
                        OPTION (RECOMPILE)";

    private const string IoTemplate = @";WITH high_io_queries AS
                (
                    SELECT TOP {1}
                        query_hash,
                        SUM(total_logical_reads + total_logical_writes) io
                    FROM sys.dm_exec_query_stats
                    WHERE query_hash <> 0x0
                    GROUP BY query_hash
                    ORDER BY SUM(total_logical_reads + total_logical_writes) DESC
                )
                SELECT {0}
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
                WHERE pa.attribute = 'dbid' {2} {3} {4}
                ORDER BY fq.io DESC,
                    fq.query_hash,
                    qs.total_logical_reads + total_logical_writes DESC
                OPTION (RECOMPILE)";

    private const string CpuTemplate = @";WITH high_cpu_queries AS
                (
                    SELECT TOP {1}
                        query_hash,
                        SUM(total_worker_time) cpuTime
                    FROM sys.dm_exec_query_stats
                    WHERE query_hash <> 0x0
                    GROUP BY query_hash
                    ORDER BY SUM(total_worker_time) DESC
                )
                SELECT {0}
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
                WHERE pa.attribute = 'dbid' {2} {3} {4}
                ORDER BY hcq.cpuTime DESC,
                    hcq.query_hash,
                    qs.total_worker_time DESC
                OPTION (RECOMPILE)";
}
