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
/// Reports estimated completion for long-running requests. Port of
/// public/Get-DbaEstimatedCompletionTime.ps1 (W1-075). QUIRK KEPT: the begin-block $sql
/// is MUTATED inside the instance loop - the -Database/-ExcludeDatabase AND clauses
/// COMPOUND across instances and pipeline records (visible in the Debug message);
/// the VALUE-truthy filter gates join names with "','"; the Query rides the hop in the
/// foreach expression (a fault surfaces statement-conditionally and the instance loop
/// continues); rows project raw reads and pipe through Select-DefaultView
/// -ExcludeProperty Text. Surface pinned by
/// migration/baselines/Get-DbaEstimatedCompletionTime.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaEstimatedCompletionTime")]
public sealed class GetDbaEstimatedCompletionTimeCommand : DbaInstanceCmdlet
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

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private const string BaseSql = @"SELECT
                DB_NAME(r.database_id) AS [Database],
                USER_NAME(r.user_id) AS [Login],
                Command,
                start_time AS StartTime,
                percent_complete AS PercentComplete,

                  RIGHT('00000' + CAST(((DATEDIFF(s,start_time,GETDATE()))/3600) AS VARCHAR),
                                CASE
                                    WHEN LEN(((DATEDIFF(s,start_time,GETDATE()))/3600)) < 2 THEN 2
                                    ELSE LEN(((DATEDIFF(s,start_time,GETDATE()))/3600))
                                 END)  + ':'
                + RIGHT('00' + CAST((DATEDIFF(s,start_time,GETDATE())%3600)/60 AS VARCHAR), 2) + ':'
                + RIGHT('00' + CAST((DATEDIFF(s,start_time,GETDATE())%60) AS VARCHAR), 2) AS RunningTime,

                  RIGHT('00000' + CAST((estimated_completion_time/3600000) AS VARCHAR),
                        CASE
                                    WHEN LEN((estimated_completion_time/3600000)) < 2 THEN 2
                                    ELSE LEN((estimated_completion_time/3600000))
                         END)  + ':'
                + RIGHT('00' + CAST((estimated_completion_time %3600000)/60000 AS VARCHAR), 2) + ':'
                + RIGHT('00' + CAST((estimated_completion_time %60000)/1000 AS VARCHAR), 2) AS EstimatedTimeToGo,
                DATEADD(SECOND,estimated_completion_time/1000, GETDATE()) AS EstimatedCompletionTime,
                s.Text
             FROM sys.dm_exec_requests r
            CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) s
            WHERE r.estimated_completion_time > 0";

    // PS: the begin-block $sql persists and the loop's appends COMPOUND across
    // instances and pipeline records.
    private string _sql = "";

    protected override void BeginProcessing()
    {
        _sql = BaseSql;
    }

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Hashtable connectParams = new Hashtable();
            connectParams["SqlInstance"] = instance;
            connectParams["SqlCredential"] = SqlCredential;
            NestedConnect.Outcome connection = NestedConnect.Connect(this, connectParams);
            if (!connection.Ok)
            {
                StopFunction("Failure", target: instance, errorRecord: connection.Failure, category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }
            Server server = connection.Server!;

            if (PsTruthy(Database))
            {
                string includeDatabases = PsJoin(Database!, "','");
                _sql = _sql + " AND DB_NAME(r.database_id) in ('" + includeDatabases + "')";
            }

            if (PsTruthy(ExcludeDatabase))
            {
                string excludeDatabases = PsJoin(ExcludeDatabase!, "','");
                _sql = _sql + " AND DB_NAME(r.database_id) not in ('" + excludeDatabases + "')";
            }

            WriteMessage(MessageLevel.Debug, _sql);
            object? results = null;
            try
            {
                results = PipelineValue(NestedCommand.InvokeScoped(this, ServerQueryScript, server, _sql));
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (RuntimeException ex)
            {
                StatementFault.Surface(this, ex, "Get-DbaEstimatedCompletionTime");
                continue;
            }
            foreach (object? row in EnumerateValue(results))
            {
                PSObject result = new PSObject();
                result.Properties.Add(new PSNoteProperty("ComputerName", SmoServerExtensions.GetComputerName(server)));
                result.Properties.Add(new PSNoteProperty("InstanceName", server.ServiceName));
                result.Properties.Add(new PSNoteProperty("SqlInstance", SmoServerExtensions.GetDomainInstanceName(server)));
                result.Properties.Add(new PSNoteProperty("Database", DotAccess(row, "Database")));
                result.Properties.Add(new PSNoteProperty("Login", DotAccess(row, "Login")));
                result.Properties.Add(new PSNoteProperty("Command", DotAccess(row, "Command")));
                result.Properties.Add(new PSNoteProperty("PercentComplete", DotAccess(row, "PercentComplete")));
                result.Properties.Add(new PSNoteProperty("StartTime", DotAccess(row, "StartTime")));
                result.Properties.Add(new PSNoteProperty("RunningTime", DotAccess(row, "RunningTime")));
                result.Properties.Add(new PSNoteProperty("EstimatedTimeToGo", DotAccess(row, "EstimatedTimeToGo")));
                result.Properties.Add(new PSNoteProperty("EstimatedCompletionTime", DotAccess(row, "EstimatedCompletionTime")));
                result.Properties.Add(new PSNoteProperty("Text", DotAccess(row, "Text")));

                try
                {
                    foreach (PSObject? shaped in NestedCommand.InvokeScoped(this, SelectDefaultViewScript, result))
                        WriteObject(shaped);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (RuntimeException ex)
                {
                    StatementFault.Surface(this, ex, "Get-DbaEstimatedCompletionTime");
                }
            }
        }
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

    /// <summary>The PS dot operator (raw DataRow column reads).</summary>
    private static object? DotAccess(object? item, string name)
    {
        if (item is null)
            return null;
        PSObject wrapped = PSObject.AsPSObject(item);
        PSPropertyInfo? direct = wrapped.Properties[name];
        if (direct is null)
            return null;
        object? value;
        try { value = direct.Value; }
        catch { return null; }
        if (value is PSObject psValue && psValue.BaseObject is not PSCustomObject)
            return psValue.BaseObject;
        return value;
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

    private const string SelectDefaultViewScript = """
param($__row)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__row)
    Select-DefaultView -InputObject $__row -ExcludeProperty Text
} $__row 3>&1
""";
}
