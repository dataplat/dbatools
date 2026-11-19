#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports execution plans from the plan cache to .sqlplan files. Port of
/// public/Export-DbaExecutionPlan.ps1 (W1-050; TA-096 characterization first). The
/// begin-block Export-Plan helper runs VERBATIM as a module-scoped hop with THIS cmdlet
/// passed in as $Pscmdlet (its ShouldProcess calls hit the real runtime - WhatIf/Confirm
/// text exact) and $EnableException re-established for the nested Stop-Function dynamic
/// read; hop warnings merge back 3&gt;&amp;1. Function quirks preserved:
/// - Test-Bound -ParamterName Path (TYPO) returns FALSE unconditionally and silently
///   (lab-pinned both editions), so the whole process-block Path directory check is dead
///   code and is omitted;
/// - the piped branch runs Export-Plan for the FIRST element only (return-in-foreach) -
///   pipeline input still processes every item because each binds its own ProcessRecord;
/// - the query catch calls Stop-Function with the -ErroRecord TYPO VERBATIM through a hop:
///   whatever the engine does (binding fault vs tolerated -Continue) surfaces mechanically
///   (FlowControlException = loop continue; other RuntimeException = conditional statement
///   fault, after which the row loop reads a null $dataTable and emits nothing);
/// - $where stays undefined when no filter applies (null .Length reads false, no record)
///   and the composed SQL keeps the function's exact whitespace;
/// - connect rides NestedConnect (W1-046 seam: nested verbose under -Verbose,
///   stream-suppressed but variable-captured failure warning, MinimumVersion 9).
/// Ledger-class: FQEID command-identity suffix (W5-038 kin); a DBNull plan column faults
/// the [xml] cast statement-style and the row's Export-Plan call then sees the previous
/// row's object (function-scope staleness, modeled with a field).
/// Surface pinned by migration/baselines/Export-DbaExecutionPlan.json.
/// </summary>
[Cmdlet(VerbsData.Export, "DbaExecutionPlan", SupportsShouldProcess = true, DefaultParameterSetName = "Default")]
public sealed class ExportDbaExecutionPlanCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ParameterSetName = "NotPiped", Mandatory = true)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(ParameterSetName = "NotPiped")]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>The directory the .sqlplan files are written to.</summary>
    [Parameter(ParameterSetName = "Piped")]
    [Parameter(ParameterSetName = "NotPiped")]
    public string? Path { get; set; }

    /// <summary>Plans created after this time.</summary>
    [Parameter(ParameterSetName = "NotPiped")]
    [PsDateTimeCast]
    public DateTime SinceCreation { get; set; }

    /// <summary>Plans last executed after this time.</summary>
    [Parameter(ParameterSetName = "NotPiped")]
    [PsDateTimeCast]
    public DateTime SinceLastExecution { get; set; }

    /// <summary>Piped plan objects from Get-DbaExecutionPlan (or this command's output).</summary>
    [Parameter(ParameterSetName = "Piped", Mandatory = true, ValueFromPipeline = true)]
    public object[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // PS function-scope staleness: $object persists across rows within one invocation.
    private object? _rowObject;

    protected override void BeginProcessing()
    {
        // PS: [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport') -
        // bind-time default through the real (compiled) config reader.
        if (!TestBound("Path"))
        {
            Hashtable configParams = new Hashtable();
            configParams["FullName"] = "Path.DbatoolsExport";
            Collection<PSObject> configValue = NestedCommand.Invoke(this, "Get-DbatoolsConfigValue", configParams);
            object? raw = configValue.Count > 0 ? (object?)configValue[0] : null;
            Path = raw is null ? "" : (string)LanguagePrimitives.ConvertTo(raw, typeof(string), CultureInfo.InvariantCulture);
        }
    }

    protected override void ProcessRecord()
    {
        // PS: if ((Test-Bound -ParamterName Path) -and ...) { ... } - the TYPO'd
        // simple-function call returns FALSE unconditionally and silently (lab-pinned),
        // so the directory check is dead code.

        // PS: if ($InputObject) { foreach ($object in $InputObject) { Export-Plan $object; return } }
        if (PsOps.IsTrue(InputObject))
        {
            foreach (object? inputItem in InputObject!)
            {
                EmitPlan(inputItem);
                return;
            }
        }

        if (SqlInstance is null)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance -MinimumVersion 9 } catch { Stop-Function
            //     -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            Hashtable connectParams = new Hashtable();
            connectParams["SqlInstance"] = instance;
            connectParams["SqlCredential"] = SqlCredential;
            connectParams["MinimumVersion"] = 9;
            NestedConnect.Outcome connection = NestedConnect.Connect(this, connectParams);
            if (!connection.Ok)
            {
                StopFunction("Failure", target: instance, errorRecord: connection.Failure, category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }
            Server? server = connection.Server;

            // PS: $where only comes into existence when a filter applies; a null .Length
            // reads null (falsy) without a record.
            bool needWhere = PsOps.IsTrue(ExcludeDatabase) || PsOps.IsTrue(Database) || TestBound("SinceCreation") || TestBound("SinceLastExecution");
            string? where = needWhere ? " WHERE " : null;

            List<string> whereArray = new List<string>();

            // PS: if ($Database -gt 0) - the ARRAY -gt operator FILTERS; truthiness of the
            // filtered set decides (string elements compare against "0"). A non-comparable
            // element ABORTS the comparison (codex r1: NotIcomparable), statement-style.
            bool databaseClauseApplies = false;
            try
            {
                databaseClauseApplies = PsOps.IsTrue(GreaterThanFilter(Database, 0));
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception compareFault)
            {
                StatementFault.Surface(this, compareFault, "Export-DbaExecutionPlan");
            }
            if (databaseClauseApplies)
            {
                string dbList = JoinValues(Database!, "','");
                whereArray.Add(" DB_NAME(deqp.dbid) IN ('" + dbList + "') ");
            }

            if (TestBound("SinceCreation"))
            {
                WriteMessage(MessageLevel.Verbose, "Adding creation time");
                whereArray.Add(" creation_time >= CONVERT(DATETIME,'" + SinceCreation.ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture) + "',126) ");
            }

            if (TestBound("SinceLastExecution"))
            {
                WriteMessage(MessageLevel.Verbose, "Adding last execution time");
                whereArray.Add(" last_execution_time >= CONVERT(DATETIME,'" + SinceLastExecution.ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture) + "',126) ");
            }

            if (TestBound("ExcludeDatabase"))
            {
                string dbList = JoinValues(ExcludeDatabase ?? Array.Empty<object>(), "','");
                whereArray.Add(" DB_NAME(deqp.dbid) NOT IN ('" + dbList + "') ");
            }

            // PS: if (Test-Bound 'ExcludeEmptyQueryPlan') - the parameter does not exist,
            // so the clause never applies (always-false branch preserved as dead code).

            if (where is not null && where.Length > 0)
            {
                string joined = string.Join(" AND ", whereArray);
                where = where + " " + joined;
            }

            string sql = SelectText + " " + FromText + " " + (where ?? "");
            WriteMessage(MessageLevel.Debug, "SQL Statement: " + sql);

            DataTableCollection? tables = null;
            try
            {
                tables = server!.ConnectionContext.ExecuteWithResults(sql).Tables;
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                // PS: the catch itself bags the caught record ($error), a MethodInvocation
                // wrap around the SMO fault (W1-020 class); then Stop-Function runs with
                // the -ErroRecord TYPO VERBATIM through the hop - the engine's binding
                // fault surfaces statement-style (lab: NamedParameterNotFound record and
                // the row loop below reads a null $dataTable), and a tolerated -Continue
                // would escape as flow control.
                ErrorRecord caughtRecord = new ErrorRecord(
                    new RuntimeException("Exception calling \"ExecuteWithResults\" with \"1\" argument(s): \"" + ex.Message + "\"", ex),
                    ex.GetType().Name, ErrorCategory.NotSpecified, null);
                BagError(caughtRecord);
                try
                {
                    NestedCommand.InvokeScoped(this, StopFunctionTypoScript, caughtRecord, instance, EnableException.ToBool(), BoundVerbose(), BoundDebug());
                }
                catch (FlowControlException)
                {
                    continue;
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (RuntimeException hopFault)
                {
                    RemoveHopFaultBookkeeping(hopFault);
                    StatementFault.Surface(this, hopFault, "Export-DbaExecutionPlan");
                }
            }

            // PS: foreach ($row in ($dataTable.Rows)) - member enumeration over the Tables
            // collection; a null $dataTable enumerates nothing.
            if (tables is null)
                continue;
            foreach (DataTable table in tables)
            {
                foreach (DataRow row in table.Rows)
                {
                    string sqlHandleHex = ToHexHandle(row["SqlHandle"]);
                    string planHandleHex = ToHexHandle(row["PlanHandle"]);

                    try
                    {
                        PSObject rowObject = new PSObject();
                        rowObject.Properties.Add(new PSNoteProperty("ComputerName", SmoServerExtensions.GetComputerName(server!)));
                        rowObject.Properties.Add(new PSNoteProperty("InstanceName", server!.ServiceName));
                        rowObject.Properties.Add(new PSNoteProperty("SqlInstance", SmoServerExtensions.GetDomainInstanceName(server!)));
                        rowObject.Properties.Add(new PSNoteProperty("DatabaseName", row["DatabaseName"]));
                        rowObject.Properties.Add(new PSNoteProperty("SqlHandle", sqlHandleHex));
                        rowObject.Properties.Add(new PSNoteProperty("PlanHandle", planHandleHex));
                        rowObject.Properties.Add(new PSNoteProperty("SingleStatementPlan", row["SingleStatementPlan"]));
                        rowObject.Properties.Add(new PSNoteProperty("BatchQueryPlan", row["BatchQueryPlan"]));
                        rowObject.Properties.Add(new PSNoteProperty("QueryPosition", row["QueryPosition"]));
                        rowObject.Properties.Add(new PSNoteProperty("CreationTime", row["CreationTime"]));
                        rowObject.Properties.Add(new PSNoteProperty("LastExecutionTime", row["LastExecutionTime"]));
                        rowObject.Properties.Add(new PSNoteProperty("BatchQueryPlanRaw", LanguagePrimitives.ConvertTo(row["BatchQueryPlan"], typeof(System.Xml.XmlDocument), CultureInfo.InvariantCulture)));
                        rowObject.Properties.Add(new PSNoteProperty("SingleStatementPlanRaw", LanguagePrimitives.ConvertTo(row["SingleStatementPlan"], typeof(System.Xml.XmlDocument), CultureInfo.InvariantCulture)));
                        _rowObject = rowObject;
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception castFault)
                    {
                        // PS: a DBNull/garbage plan faults the [xml] cast inside the literal;
                        // $object keeps its previous value and Export-Plan still runs.
                        StatementFault.Surface(this, castFault, "Export-DbaExecutionPlan");
                    }

                    EmitPlan(_rowObject);
                }
            }
        }
    }

    /// <summary>PS: Export-Plan $object - the begin-block helper VERBATIM as a module hop;
    /// a top-level statement fault in it follows the conditional rule.</summary>
    private void EmitPlan(object? planObject)
    {
        try
        {
            NestedCommand.InvokeScopedStreaming(this, item => WriteObject(item), ExportPlanScript,
                    this, planObject, Path, EnableException.ToBool(), BoundVerbose(), BoundDebug());
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (RuntimeException ex)
        {
            StatementFault.Surface(this, ex, "Export-DbaExecutionPlan");
        }
    }

    /// <summary>PS: "0x" + per-byte {0:X} PadLeft(2,'0') over the handle column.</summary>
    private static string ToHexHandle(object? value)
    {
        StringBuilder builder = new StringBuilder("0x");
        if (value is byte[] bytes)
        {
            foreach (byte b in bytes)
                builder.Append(b.ToString("X", CultureInfo.InvariantCulture).PadLeft(2, '0'));
        }
        else if (value is not null && value is not DBNull && LanguagePrimitives.GetEnumerable(value) is IEnumerable items)
        {
            foreach (object? item in items)
                builder.Append(string.Format(CultureInfo.InvariantCulture, "{0:X}", item).PadLeft(2, '0'));
        }
        else if (value is not null && value is not DBNull)
        {
            builder.Append(string.Format(CultureInfo.InvariantCulture, "{0:X}", value).PadLeft(2, '0'));
        }
        return builder.ToString();
    }

    /// <summary>PS: $Database -gt 0 - the array comparison FILTERS elements (LHS-driven
    /// conversion); null elements never satisfy -gt.</summary>
    private static object? GreaterThanFilter(object[]? values, object comparand)
    {
        if (values is null)
            return null;
        List<object?> matched = new List<object?>();
        foreach (object? value in values)
        {
            // a non-comparable element throws and aborts the whole filter, like PS -gt
            if (PsOps.Compare(value, comparand) > 0)
                matched.Add(value);
        }
        return matched.ToArray();
    }

    /// <summary>PS: $values -join "','".</summary>
    private static string JoinValues(object[] values, string separator)
    {
        List<string> parts = new List<string>();
        foreach (object? value in values)
            parts.Add(value is null ? "" : PSObject.AsPSObject(value).ToString());
        return string.Join(separator, parts);
    }

    /// <summary>PS: a catch block bags the caught record in $error before its body runs.</summary>
    private void BagError(ErrorRecord record)
    {
        try
        {
            if (SessionState.PSVariable.GetValue("Error") is ArrayList errorList)
                errorList.Insert(0, record);
        }
        catch
        {
            // $error decoration is best-effort (constrained runspaces)
        }
    }

    /// <summary>The W1-044 compensation: the nested pipeline silently bags a hop fault on
    /// propagation; the visible surface below re-bags, so the duplicate is removed.</summary>
    private void RemoveHopFaultBookkeeping(Exception fault)
    {
        try
        {
            if (SessionState.PSVariable.GetValue("Error") is not ArrayList errorList || errorList.Count == 0)
                return;
            if (errorList[0] is not ErrorRecord first)
                return;
            Exception? recordException = (fault as IContainsErrorRecord)?.ErrorRecord?.Exception;
            bool sameFault = ReferenceEquals(first.Exception, fault) ||
                (recordException is not null && ReferenceEquals(first.Exception, recordException)) ||
                string.Equals(first.Exception?.Message, fault.Message, StringComparison.Ordinal);
            if (sameFault)
                errorList.RemoveAt(0);
        }
        catch
        {
            // best-effort, like BagError
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

    // PS: the $select/$from fragments VERBATIM (whitespace included).
    private const string SelectText = @"SELECT DB_NAME(deqp.dbid) AS DatabaseName, OBJECT_NAME(deqp.objectid) AS ObjectName,
                    detqp.query_plan AS SingleStatementPlan,
                    deqp.query_plan AS BatchQueryPlan,
                    ROW_NUMBER() OVER ( ORDER BY Statement_Start_offset ) AS QueryPosition,
                    sql_handle AS SqlHandle,
                    plan_handle AS PlanHandle,
                    creation_time AS CreationTime,
                    last_execution_time AS LastExecutionTime";

    private const string FromText = @" FROM sys.dm_exec_query_stats deqs
                        CROSS APPLY sys.dm_exec_text_query_plan(deqs.plan_handle,
                            deqs.statement_start_offset,
                            deqs.statement_end_offset) AS detqp
                        CROSS APPLY sys.dm_exec_query_plan(deqs.plan_handle) AS deqp
                        CROSS APPLY sys.dm_exec_sql_text(deqs.plan_handle) AS execText";

    // PS: the begin-block Export-Plan function body VERBATIM; $Pscmdlet IS this cmdlet, so
    // ShouldProcess/WhatIf/Confirm ride the real runtime; $EnableException feeds the nested
    // Stop-Function dynamic read; the internal -Continue targets the hop's own foreach.
    // The ShouldProcess carrier is named $__realCmdlet, NOT $Pscmdlet: that name would
    // shadow the automatic $PSCmdlet for every nested dynamic read, and Stop-Function /
    // Write-Message default their -Cmdlet to $PSCmdlet typed [PSScriptCmdlet] - a binary
    // cmdlet under that name poisons them (lab-caught: ConvertToFinalInvalidCastException
    // storm). The three ShouldProcess sites are the ONLY token change in the verbatim body.
    private const string ExportPlanScript = """
param($__realCmdlet, $object, $path, $EnableException, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__realCmdlet, $object, $path, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    function Export-Plan {
        param(
            [object]$object
        )
    $instanceName = $object.SqlInstance
    $dbName = $object.DatabaseName
    $queryPosition = $object.QueryPosition
    $sqlHandle = "0x"; $object.SqlHandle | ForEach-Object { $sqlHandle += ("{0:X}" -f $_).PadLeft(2, "0") }
    $sqlHandle = $sqlHandle.TrimStart('0x02000000').TrimEnd('0000000000000000000000000000000000000000')
    $shortName = "$instanceName-$dbName-$queryPosition-$sqlHandle"

    foreach ($queryPlan in $object.BatchQueryPlanRaw) {
        $fileName = "$path\$shortName-batch.sqlplan"

        try {
            if ($__realCmdlet.ShouldProcess("localhost", "Writing XML file to $fileName")) {
                $queryPlan.Save($fileName)
            }
        } catch {
            Stop-Function -Message "Skipped query plan for $fileName because it is null." -Target $fileName -ErrorRecord $_ -Continue
        }
    }

    foreach ($statementPlan in $object.SingleStatementPlanRaw) {
        $fileName = "$path\$shortName.sqlplan"

        try {
            if ($__realCmdlet.ShouldProcess("localhost", "Writing XML file to $fileName")) {
                $statementPlan.Save($fileName)
            }
        } catch {
            Stop-Function -Message "Skipped statement plan for $fileName because it is null." -Target $fileName -ErrorRecord $_ -Continue
        }
    }

    if ($__realCmdlet.ShouldProcess("console", "Showing output object")) {
        Add-Member -Force -InputObject $object -MemberType NoteProperty -Name OutputFile -Value $fileName
        Select-DefaultView -InputObject $object -Property ComputerName, InstanceName, SqlInstance, DatabaseName, SqlHandle, CreationTime, LastExecutionTime, OutputFile
    }
    }
    Export-Plan $object
} $__realCmdlet $object $path $EnableException $__boundVerbose $__boundDebug 3>&1
""";

    // PS: the query catch VERBATIM, -ErroRecord TYPO included.
    private const string StopFunctionTypoScript = """
param($__record, $instance, $EnableException, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__record, $instance, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    $_ = $__record
    Stop-Function -Message "Issue collecting execution plans" -Target $instance -ErroRecord $_ -Continue
} $__record $instance $EnableException $__boundVerbose $__boundDebug 3>&1
""";
}
