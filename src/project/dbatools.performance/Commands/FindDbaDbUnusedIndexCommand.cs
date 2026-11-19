#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;
// the sibling namespace Dataplat.Dbatools.Database shadows Smo.Database inside
// Dataplat.Dbatools.Commands (the W1-020 namespace trap) - alias the SMO type
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Finds unused indexes via sys.dm_db_index_usage_stats. Port of
/// public/Find-DbaDbUnusedIndex.ps1 (W1-055). Quirks preserved:
/// - the empty-input warning's `continue` has NO enclosing loop: it continues the CALLER's
///   loop / kills the pipeline (CallerFlow.Continue - the W1-026 class);
/// - the accessibility pre-check indexes the collection with the DATABASE OBJECT, which
///   string-converts to "[name]" and never matches - the check is DEAD and offline
///   databases fall through to the query catch (preserved verbatim);
/// - $Seeks/$Scans/$Lookups interpolate into the SQL at BEGIN; the 2008+ compression
///   columns swap in via ordinal Replace;
/// - DateTime interpolations render through LanguagePrimitives (invariant, W1-006 fact);
/// - the query catch's Stop-Function has no -Continue (loop proceeds unguarded).
/// The Database.Query ETS statement rides an engine hop under EngineTryScope; the
/// Get-DbaDatabase fetch rides NestedCommand with += append semantics.
/// Surface pinned by migration/baselines/Find-DbaDbUnusedIndex.json.
/// </summary>
[Cmdlet(VerbsCommon.Find, "DbaDbUnusedIndex")]
public sealed class FindDbaDbUnusedIndexCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Skips the uptime gate.</summary>
    [Parameter]
    public SwitchParameter IgnoreUptime { get; set; }

    /// <summary>user_seeks threshold.</summary>
    [Parameter(Position = 4)]
    [ValidateRange(1, 1000000)]
    public int Seeks { get; set; } = 1;

    /// <summary>user_scans threshold.</summary>
    [Parameter(Position = 5)]
    [ValidateRange(1, 1000000)]
    public int Scans { get; set; } = 1;

    /// <summary>user_lookups threshold.</summary>
    [Parameter(Position = 6)]
    [ValidateRange(1, 1000000)]
    public int Lookups { get; set; } = 1;

    /// <summary>Piped SMO databases from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 7)]
    public SmoDatabase[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private string _sql = "";

    protected override void BeginProcessing()
    {
        // PS: the begin-block template interpolates $Seeks/$Scans/$Lookups.
        _sql = SqlPart1 + Seeks.ToString(CultureInfo.InvariantCulture)
             + SqlPart2 + Scans.ToString(CultureInfo.InvariantCulture)
             + SqlPart3 + Lookups.ToString(CultureInfo.InvariantCulture)
             + SqlPart4;
    }

    protected override void ProcessRecord()
    {
        // PS: if ($SqlInstance) { $InputObject += Get-DbaDatabase ... }
        if (PsOps.IsTrue(SqlInstance))
        {
            Hashtable fetchParams = new Hashtable();
            fetchParams["SqlInstance"] = SqlInstance;
            fetchParams["SqlCredential"] = SqlCredential;
            fetchParams["Database"] = Database;
            fetchParams["ExcludeDatabase"] = ExcludeDatabase;
            PropagateBoundPreference(fetchParams);
            try
            {
                Collection<PSObject> fetched = NestedCommand.Invoke(this, "Get-DbaDatabase", fetchParams);
                InputObject = AppendDatabases(InputObject, fetched);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (RuntimeException ex)
            {
                StatementFault.Surface(this, ex, "Find-DbaDbUnusedIndex");
            }
        }

        // PS: if ($null -eq $InputObject -or $InputObject.Count -eq 0) { warning; continue }
        // - the continue has NO enclosing loop: caller-loop flow control (W1-026 class).
        if (InputObject is null || InputObject.Length == 0)
        {
            WriteMessage(MessageLevel.Warning, "Database [" + PsText(Database) + "] was not found on [" + PsText(SqlInstance) + "].");
            CallerFlow.Continue(this);
            return;
        }

        foreach (SmoDatabase? db in InputObject)
        {
            if (db is null || db.Parent is null)
            {
                // PS walk for a null element OR a Parent-less Database (codex r1 F1 +
                // r2): the accessibility statement indexes a null array (record,
                // statement continues), then $null.VersionMajor -lt 9 is TRUE (null
                // compares less), so the version Stop-Function fires with -Continue.
                StatementFault.Surface(this, new ErrorRecord(new RuntimeException("Cannot index into a null array."), "NullArray", ErrorCategory.InvalidOperation, null));
                StopFunction("This function does not support versions lower than SQL Server 2005 (v9).", continueLoop: true);
                continue;
            }

            // PS: $db.Parent.Databases[$db] - the object index string-converts to "[name]"
            // and never matches: the accessibility check is DEAD (preserved).
            SmoDatabase? bracketLookup = db.Parent.Databases[PsText(db)];
            if (bracketLookup is not null && !bracketLookup.IsAccessible)
            {
                WriteMessage(MessageLevel.Warning, "Database [" + PsText(db) + "] is not accessible.");
                continue;
            }

            Server server = db.Parent;
            string instance = server.Name;

            if (server.VersionMajor < 9)
            {
                StopFunction("This function does not support versions lower than SQL Server 2005 (v9).", continueLoop: true);
                continue;
            }

            // PS: tempdb CreateDate -> New-TimeSpan days
            DateTime lastRestart = server.Databases["tempdb"].CreateDate;
            int diffDays = (DateTime.Now - lastRestart).Days;

            if (diffDays <= 6)
            {
                if (IgnoreUptime.ToBool())
                {
                    WriteMessage(MessageLevel.Verbose, "The SQL Service was restarted on " + PsText(lastRestart) + ", which is not long enough for a solid evaluation.");
                }
                else
                {
                    StopFunction("The SQL Service on " + instance + " was restarted on " + PsText(lastRestart) + ", which is not long enough for a solid evaluation.", continueLoop: true);
                    continue;
                }
            }

            if ((server.VersionMajor == 11 && server.BuildNumber < 6537) || (server.VersionMajor == 12 && server.BuildNumber < 5000))
            {
                StopFunction("This SQL version has a known issue. Rebuilding an index clears any existing row entry from sys.dm_db_index_usage_stats for that index.\r\nPlease refer to connect item: https://support.microsoft.com/en-us/help/3160407/fix-sys-dm-db-index-usage-stats-missing-information-after-index-rebuil", continueLoop: true);
                continue;
            }

            if (diffDays <= 33)
            {
                WriteMessage(MessageLevel.Verbose, "The SQL Service on " + instance + " was restarted on " + PsText(lastRestart) + ", which may not be long enough for a solid evaluation.");
            }

            string sqlToRun = _sql;
            if (server.VersionMajor > 9)
            {
                sqlToRun = sqlToRun.Replace("--REPLACEPARAMCTE", ", p.data_compression_desc").Replace("--REPLACEPARAMSELECT", ", indexSpace.data_compression_desc AS CompressionDescription");
            }

            try
            {
                using EngineTryScope tryScope = EngineTryScope.Enter(this);
                foreach (PSObject? item in NestedCommand.InvokeScoped(this, DatabaseQueryScript, db, sqlToRun))
                    WriteObject(item);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                // PS: Stop-Function -Category InvalidOperation -ErrorRecord $_ -Target $db
                // (no -Continue: the loop proceeds unguarded).
                StopFunction("Issue gathering indexes", target: db, errorRecord: ToCaughtRecord(ex), category: ErrorCategory.InvalidOperation, continueLoop: true);
                continue;
            }
        }
    }

    /// <summary>PS: $InputObject += &lt;dbs&gt; on the [Smo.Database[]]-typed parameter
    /// (empty output NO-OP; elements re-cast on assignment).</summary>
    private SmoDatabase[]? AppendDatabases(SmoDatabase[]? current, Collection<PSObject> fetched)
    {
        if (fetched.Count == 0)
            return current;
        // PS: the typed-array += conversion is ATOMIC - the first invalid item faults the
        // whole assignment and $InputObject keeps its previous value (codex r1 F2).
        List<SmoDatabase> combined = new List<SmoDatabase>();
        if (current is not null)
            combined.AddRange(current);
        try
        {
            foreach (PSObject item in fetched)
                combined.Add((SmoDatabase)LanguagePrimitives.ConvertTo(item, typeof(SmoDatabase), CultureInfo.InvariantCulture));
        }
        catch (PSInvalidCastException ex)
        {
            StatementFault.Surface(this, ex, "Find-DbaDbUnusedIndex");
            return current;
        }
        return combined.ToArray();
    }

    /// <summary>PS string interpolation via LanguagePrimitives (invariant; arrays $OFS-join,
    /// the W1-004 alignment).</summary>
    private static string PsText(object? value)
    {
        if (value is null)
            return "";
        return (string)LanguagePrimitives.ConvertTo(value, typeof(string), CultureInfo.InvariantCulture);
    }

    /// <summary>PS preference inheritance for nested calls (W1-021 class).</summary>
    private void PropagateBoundPreference(Hashtable parameters)
    {
        object? verbose;
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out verbose))
            parameters["Verbose"] = verbose;
        object? errorAction;
        if (MyInvocation.BoundParameters.TryGetValue("ErrorAction", out errorAction))
            parameters["ErrorAction"] = errorAction;
    }

    /// <summary>PS: catch { $_ } with the flattened-record rebuild (W1-009 class).</summary>
    private static ErrorRecord ToCaughtRecord(Exception ex)
    {
        ErrorRecord? inner = (ex as IContainsErrorRecord)?.ErrorRecord;
        if (inner is not null && inner.Exception is not ParentContainsErrorRecordException)
            return inner;
        if (inner is not null)
            return new ErrorRecord(ex, FirstErrorIdComponent(inner.FullyQualifiedErrorId), inner.CategoryInfo.Category, inner.TargetObject);
        return new ErrorRecord(ex, "Find-DbaDbUnusedIndex", ErrorCategory.NotSpecified, null);
    }

    private static string FirstErrorIdComponent(string? fullyQualifiedErrorId)
    {
        if (string.IsNullOrEmpty(fullyQualifiedErrorId))
            return "Find-DbaDbUnusedIndex";
        int comma = fullyQualifiedErrorId!.IndexOf(',');
        return comma < 0 ? fullyQualifiedErrorId : fullyQualifiedErrorId.Substring(0, comma);
    }

    // PS: $db.Query($sqlToRun) - the statement runs on the engine (ETS dispatch, real-$null
    // emission, silent inner bookkeeping - the W1-046 seam).
    private const string DatabaseQueryScript = """
param($db, $query)
$db.Query($query)
""";

    private const string SqlPart1 = """

        ;WITH
            CTE_IndexSpace
        AS
        (
            SELECT
                s.object_id                         AS object_id
            ,   s.index_id                          AS index_id
            ,   SUM(s.used_page_count) * 8 / 1024.0 AS IndexSizeMB
            ,   SUM(p.[rows])                       AS [RowCount]
            --REPLACEPARAMCTE
            FROM
                sys.dm_db_partition_stats AS s
            INNER JOIN
                sys.partitions p WITH (NOLOCK)
                    ON s.[partition_id] = p.[partition_id]
                    AND s.[object_id] = p.[object_id]
                    AND s.index_id = p.index_id
            WHERE
                s.index_id > 0 -- Exclude HEAPS
                AND OBJECT_SCHEMA_NAME(s.[object_id]) <> 'sys'
            GROUP BY
                s.[object_id]
            ,   s.index_id
            --REPLACEPARAMCTE
        )
        SELECT  SERVERPROPERTY('MachineName') AS ComputerName,
        ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
        SERVERPROPERTY('ServerName') AS SqlInstance, DB_NAME(d.database_id) AS 'Database'
        ,d.database_id AS DatabaseId
        ,s.name AS 'Schema'
        ,t.name AS 'Table'
        ,i.object_id AS ObjectId
        ,i.name AS 'IndexName'
        ,i.index_id AS 'IndexId'
        ,i.type_desc AS 'TypeDesc'
        ,user_seeks AS 'UserSeeks'
        ,user_scans AS 'UserScans'
        ,user_lookups  AS 'UserLookups'
        ,user_updates  AS 'UserUpdates'
        ,last_user_seek  AS 'LastUserSeek'
        ,last_user_scan  AS 'LastUserScan'
        ,last_user_lookup  AS 'LastUserLookup'
        ,last_user_update  AS 'LastUserUpdate'
        ,system_seeks  AS 'SystemSeeks'
        ,system_scans  AS 'SystemScans'
        ,system_lookups  AS 'SystemLookup'
        ,system_updates  AS 'SystemUpdates'
        ,last_system_seek  AS 'LastSystemSeek'
        ,last_system_scan  AS 'LastSystemScan'
        ,last_system_lookup  AS 'LastSystemLookup'
        ,last_system_update AS 'LastSystemUpdate'
        ,COALESCE(indexSpace.IndexSizeMB, 0) AS 'IndexSizeMB'
        ,COALESCE(indexSpace.[RowCount], 0) AS 'RowCount'
        --REPLACEPARAMSELECT
        FROM sys.tables t
        JOIN sys.schemas s
            ON t.schema_id = s.schema_id
        JOIN sys.indexes i
            ON i.object_id = t.object_id
        JOIN sys.databases d
            ON d.name = DB_NAME()
        LEFT OUTER JOIN sys.dm_db_index_usage_stats iu
            ON iu.object_id = i.object_id
                AND iu.index_id = i.index_id
                AND iu.database_id = d.database_id
        JOIN CTE_IndexSpace indexSpace
            ON indexSpace.index_id = i.index_id
                AND indexSpace.object_id = i.object_id
        WHERE
            OBJECTPROPERTY(i.[object_id], 'IsMSShipped') = 0
            AND user_seeks < 
""";

    private const string SqlPart2 = """

            AND user_scans < 
""";

    private const string SqlPart3 = """

            AND user_lookups < 
""";

    private const string SqlPart4 = """

            AND i.type_desc NOT IN ('HEAP', 'CLUSTERED COLUMNSTORE')
""";

}
