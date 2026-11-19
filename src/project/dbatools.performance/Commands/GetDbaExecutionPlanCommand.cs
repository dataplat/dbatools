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
/// Reads cached execution plans. Port of public/Get-DbaExecutionPlan.ps1 (W1-076). The
/// WHOLE instance body sits inside the function's OUTER try - an EE connect failure's
/// throw is caught there and escalates to the "Query Failure Failure" Stop-Function
/// (non-EE takes the direct -Continue); the WHERE assembly keeps the quirks ($where is
/// UNDEFINED when no filter is bound and its .length read walks the module scope - the
/// W1-051 law; the joined clauses append after the double space; the Since* verbose
/// lines keep the "exectuion" TYPO; datetimes format invariant yyyy-MM-ddTHH:mm:ss);
/// -Force emits the RAW query rows while the default path projects each row through the
/// VERBATIM PS body in a module hop (XML-adapter walks, byte[] hex folds, the
/// PSCustomObject and its Select-DefaultView) so a row fault aborts the instance into
/// the outer catch exactly like PS. Surface pinned by
/// migration/baselines/Get-DbaExecutionPlan.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaExecutionPlan")]
public sealed class GetDbaExecutionPlanCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The databases to include.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>The databases to skip.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Only plans created at or after this time.</summary>
    [Parameter(Position = 4)]
    [PsDateTimeCast]
    public DateTime SinceCreation { get; set; }

    /// <summary>Only plans last executed at or after this time.</summary>
    [Parameter(Position = 5)]
    [PsDateTimeCast]
    public DateTime SinceLastExecution { get; set; }

    /// <summary>Exclude rows whose single-statement plan is NULL.</summary>
    [Parameter]
    public SwitchParameter ExcludeEmptyQueryPlan { get; set; }

    /// <summary>Return the raw DMV rows with every column.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private const string From = @" FROM sys.dm_exec_query_stats deqs
                        CROSS APPLY sys.dm_exec_text_query_plan(deqs.plan_handle,
                            deqs.statement_start_offset,
                            deqs.statement_end_offset) AS detqp
                        CROSS APPLY sys.dm_exec_query_plan(deqs.plan_handle) AS deqp
                        CROSS APPLY sys.dm_exec_sql_text(deqs.plan_handle) AS execText";

    private const string DefaultSelect = @"SELECT DB_NAME(deqp.dbid) AS DatabaseName, OBJECT_NAME(deqp.objectid) AS ObjectName,
                    detqp.query_plan AS SingleStatementPlan,
                    deqp.query_plan AS BatchQueryPlan,
                    ROW_NUMBER() OVER ( ORDER BY Statement_Start_offset ) AS QueryPosition,
                    sql_handle AS SqlHandle,
                    plan_handle AS PlanHandle,
                    creation_time AS CreationTime,
                    last_execution_time AS LastExecutionTime";

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            try
            {
                Hashtable connectParams = new Hashtable();
                connectParams["SqlInstance"] = instance;
                connectParams["SqlCredential"] = SqlCredential;
                connectParams["MinimumVersion"] = 9;
                NestedConnect.Outcome connection = NestedConnect.Connect(this, connectParams);
                if (!connection.Ok)
                {
                    // PS: the inner catch's Stop-Function - non-EE continues directly;
                    // under EE its throw is CAUGHT by the fn's outer catch, which bags
                    // the record in $error before the "Query Failure Failure" rethrow
                    // (the rethrown record renders identically) - model the bagging.
                    if (EnableException.ToBool() && connection.Failure is not null)
                    {
                        string innerMessage = MessageService.GetErrorMessage(connection.Failure);
                        ErrorCategory innerCategory = connection.Failure.CategoryInfo.Category != ErrorCategory.NotSpecified ? connection.Failure.CategoryInfo.Category : ErrorCategory.ConnectionError;
                        InsertCaughtRecord(new ErrorRecord(new Exception(innerMessage, connection.Failure.Exception), "dbatools_Get-DbaExecutionPlan", innerCategory, instance));
                    }
                    StopFunction("Failure", target: instance, errorRecord: connection.Failure, category: ErrorCategory.ConnectionError, continueLoop: true);
                    continue;
                }
                Server server = connection.Server!;

                string select = Force.IsPresent ? "SELECT * " : DefaultSelect;

                bool anyFilter = PsTruthy(ExcludeDatabase) || PsTruthy(Database) || TestBound("SinceCreation") || TestBound("SinceLastExecution") || ExcludeEmptyQueryPlan.IsPresent;
                // PS: $where stays UNDEFINED without filters - the .length read and the
                // final interpolation walk the module scope (the W1-051 law).
                object? whereValue = anyFilter ? " WHERE " : PipelineValue(NestedCommand.InvokeScoped(this, ModuleVariableScript, "where"));

                List<string> whereArray = new List<string>();

                if (PsTruthy(Database))
                {
                    string dbList = PsJoin(Database!, "','");
                    whereArray.Add(" DB_NAME(deqp.dbid) in ('" + dbList + "') ");
                }

                if (TestBound("SinceCreation"))
                {
                    WriteMessage(MessageLevel.Verbose, "Adding creation time");
                    whereArray.Add(" creation_time >= CONVERT(DATETIME,'" + SinceCreation.ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture) + "',126) ");
                }

                if (TestBound("SinceLastExecution"))
                {
                    WriteMessage(MessageLevel.Verbose, "Adding last exectuion time");
                    whereArray.Add(" last_execution_time >= CONVERT(DATETIME,'" + SinceLastExecution.ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture) + "',126) ");
                }

                if (PsTruthy(ExcludeDatabase))
                {
                    string dbList = PsJoin(ExcludeDatabase!, "','");
                    whereArray.Add(" DB_NAME(deqp.dbid) not in ('" + dbList + "') ");
                }

                if (ExcludeEmptyQueryPlan.IsPresent)
                {
                    whereArray.Add(" detqp.query_plan IS NOT NULL");
                }

                string whereText = PsText(whereValue);
                if (whereText.Length > 0)
                {
                    whereText = whereText + " " + string.Join(" AND ", whereArray);
                }

                string sql = select + " " + From + " " + whereText;
                WriteMessage(MessageLevel.Debug, sql);

                if (Force.IsPresent)
                {
                    foreach (PSObject? row in NestedCommand.InvokeScoped(this, ServerQueryScript, server, sql))
                        WriteObject(row);
                }
                else
                {
                    object? results = PipelineValue(NestedCommand.InvokeScoped(this, ServerQueryScript, server, sql));
                    foreach (object? row in EnumerateValue(results))
                    {
                        foreach (PSObject? shaped in NestedCommand.InvokeScoped(this, RowProjectionScript, row, server))
                            WriteObject(shaped);
                    }
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction("Query Failure Failure", target: instance, errorRecord: StatementFault.Record(ex, "Get-DbaExecutionPlan"), continueLoop: true);
                continue;
            }
        }
    }

    /// <summary>The PS catch bookkeeping: a caught terminating record lands in $error.</summary>
    private void InsertCaughtRecord(ErrorRecord record)
    {
        if (SessionState.PSVariable.GetValue("global:Error") is ArrayList errorList)
            errorList.Insert(0, record);
    }

    /// <summary>PS -join: elements convert with the CURRENT-culture ToString (unlike
    /// interpolation's invariant conversion - lab-probed both editions: fr-FR joins
    /// [decimal]1.5 as "1,5").</summary>
    private static string PsJoin(object[] values, string separator)
    {
        List<string> parts = new List<string>();
        foreach (object? value in values)
        {
            object? unwrapped = value is PSObject pso ? pso.BaseObject : value;
            if (unwrapped is null)
                parts.Add("");
            else if (unwrapped is IConvertible convertible)
                parts.Add(convertible.ToString(CultureInfo.CurrentCulture));
            else
                parts.Add(unwrapped.ToString() ?? "");
        }
        return string.Join(separator, parts);
    }

    /// <summary>PS array truthiness: empty = false, one element = its truthiness,
    /// two or more = true.</summary>
    private static bool PsTruthy(object[]? values)
    {
        if (values is null || values.Length == 0)
            return false;
        if (values.Length == 1)
            return LanguagePrimitives.IsTrue(values[0]);
        return true;
    }

    /// <summary>PS pipeline-assignment collapse: none = null, one = the item, many = array.</summary>
    private static object? PipelineValue(Collection<PSObject> results)
    {
        if (results.Count == 0)
            return null;
        if (results.Count == 1)
            return results[0];
        object?[] array = new object?[results.Count];
        for (int n = 0; n < results.Count; n++)
            array[n] = results[n];
        return array;
    }

    /// <summary>PS foreach over a value: null iterates zero times, an array yields
    /// elements (nulls included), a scalar yields itself.</summary>
    private static IEnumerable<object?> EnumerateValue(object? value)
    {
        if (value is null)
            yield break;
        if (value is object?[] array)
        {
            foreach (object? element in array)
                yield return element;
            yield break;
        }
        yield return value;
    }

    /// <summary>PS string interpolation via LanguagePrimitives (invariant).</summary>
    private static string PsText(object? value)
    {
        if (value is null)
            return "";
        return (string)LanguagePrimitives.ConvertTo(value, typeof(string), CultureInfo.InvariantCulture);
    }

    // PS: $server.Query($query) on the engine (the W1-046 seam).
    private const string ServerQueryScript = """
param($server, $query)
$server.Query($query)
""";

    // PS: the per-row projection VERBATIM (XML-adapter walks, byte[] hex folds and the
    // Select-DefaultView) - a fault propagates to the caller's outer catch like PS.
    private const string RowProjectionScript = """
param($row, $server)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($row, $server)
    $simple = ([xml]$row.SingleStatementPlan).ShowPlanXML.BatchSequence.Batch.Statements.StmtSimple
    $sqlHandle = "0x"; $row.sqlhandle | ForEach-Object { $sqlHandle += ("{0:X}" -f $_).PadLeft(2, "0") }
    $planHandle = "0x"; $row.planhandle | ForEach-Object { $planHandle += ("{0:X}" -f $_).PadLeft(2, "0") }
    $planWarnings = $simple.QueryPlan.Warnings.PlanAffectingConvert;

    [PSCustomObject]@{
        ComputerName                      = $server.ComputerName
        InstanceName                      = $server.ServiceName
        SqlInstance                       = $server.DomainInstanceName
        DatabaseName                      = $row.DatabaseName
        ObjectName                        = $row.ObjectName
        QueryPosition                     = $row.QueryPosition
        SqlHandle                         = $sqlHandle
        PlanHandle                        = $planHandle
        CreationTime                      = $row.CreationTime
        LastExecutionTime                 = $row.LastExecutionTime
        StatementCondition                = ([xml]$row.SingleStatementPlan).ShowPlanXML.BatchSequence.Batch.Statements.StmtCond
        StatementSimple                   = $simple
        StatementId                       = $simple.StatementId
        StatementCompId                   = $simple.StatementCompId
        StatementType                     = $simple.StatementType
        RetrievedFromCache                = $simple.RetrievedFromCache
        StatementSubTreeCost              = $simple.StatementSubTreeCost
        StatementEstRows                  = $simple.StatementEstRows
        SecurityPolicyApplied             = $simple.SecurityPolicyApplied
        StatementOptmLevel                = $simple.StatementOptmLevel
        QueryHash                         = $simple.QueryHash
        QueryPlanHash                     = $simple.QueryPlanHash
        StatementOptmEarlyAbortReason     = $simple.StatementOptmEarlyAbortReason
        CardinalityEstimationModelVersion = $simple.CardinalityEstimationModelVersion

        ParameterizedText                 = $simple.ParameterizedText
        StatementSetOptions               = $simple.StatementSetOptions
        QueryPlan                         = $simple.QueryPlan
        BatchConditionXml                 = ([xml]$row.BatchQueryPlan).ShowPlanXML.BatchSequence.Batch.Statements.StmtCond
        BatchSimpleXml                    = ([xml]$row.BatchQueryPlan).ShowPlanXML.BatchSequence.Batch.Statements.StmtSimple
        BatchQueryPlanRaw                 = [xml]$row.BatchQueryPlan
        SingleStatementPlanRaw            = [xml]$row.SingleStatementPlan
        PlanWarnings                      = $planWarnings
    } | Select-DefaultView -ExcludeProperty BatchQueryPlan, SingleStatementPlan, BatchConditionXmlRaw, BatchQueryPlanRaw, SingleStatementPlanRaw, PlanWarnings
} $row $server 3>&1
""";

    // PS: the undefined fn-variable read resolves module -> global (the W1-051 law).
    private const string ModuleVariableScript = """
param($__name)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__name)
    $ExecutionContext.SessionState.PSVariable.GetValue($__name)
} $__name 3>&1
""";
}
