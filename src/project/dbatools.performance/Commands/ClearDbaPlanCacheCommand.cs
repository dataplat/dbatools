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

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Clears the SQL Plans system cache when its size crosses the threshold. Port of
/// public/Clear-DbaPlanCache.ps1 (W1-047). The Get-DbaPlanCache fetch rides NestedCommand
/// (hybrid resolution + PSDPV shield, W1-021 preference propagation) and appends with the
/// PS += semantics (empty output = NO-OP, W1-044 lab fact); DBCC FREESYSTEMCACHE rides the
/// REAL Server.Query ETS ScriptMethod OUTSIDE any try - a fault there is
/// statement-terminating and follows the engine's conditional record-vs-unwind rule
/// (StatementFault), after which the function still emits the "Plan cache cleared" result
/// object (next-statement semantics, quirk preserved). The below-threshold branch keeps the
/// Status/verbose text's TRAILING SPACE verbatim. Connect failure maps to Stop-Function
/// -Category ConnectionError -Continue; the connect target/argument is the RESULT object's
/// SqlInstance property, cast at bind time inside the try like the function.
/// Surface pinned by migration/baselines/Clear-DbaPlanCache.json.
/// </summary>
[Cmdlet(VerbsCommon.Clear, "DbaPlanCache", SupportsShouldProcess = true)]
public sealed class ClearDbaPlanCacheCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Memory used threshold in MB.</summary>
    [Parameter(Position = 2)]
    public int Threshold { get; set; } = 100;

    /// <summary>Enables piping from Get-DbaPlanCache.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public object[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        // PS: foreach ($instance in $SqlInstance) { $InputObject += Get-DbaPlanCache ... }
        if (SqlInstance is not null)
        {
            foreach (DbaInstanceParameter instance in SqlInstance)
            {
                Hashtable fetchParams = new Hashtable();
                fetchParams["SqlInstance"] = instance;
                fetchParams["SqlCredential"] = SqlCredential;
                PropagateBoundPreference(fetchParams);
                try
                {
                    Collection<PSObject> fetched = NestedCommand.Invoke(this, "Get-DbaPlanCache", fetchParams);
                    InputObject = AppendPipelineOutput(InputObject, fetched);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (RuntimeException ex)
                {
                    // PS: a fetch-statement fault surfaces and the loop moves on.
                    StatementFault.Surface(this, ex, "Clear-DbaPlanCache");
                }
            }
        }

        if (InputObject is null)
            return;

        foreach (object? result in InputObject)
        {
            // PS: if ($result.MB -ge $Threshold)
            if (PsOps.Compare(DotAccess(result, "MB"), Threshold) >= 0)
            {
                if (ShouldProcess(PsText(DotAccess(result, "SqlInstance")), "Cleared SQL Plans plan cache"))
                {
                    // PS: try { $server = Connect-DbaInstance -SqlInstance $result.SqlInstance ... }
                    //     catch { Stop-Function -Message "Failure" -Category ConnectionError
                    //             -ErrorRecord $_ -Target $result.SqlInstance -Continue }
                    object? connectTarget = DotAccess(result, "SqlInstance");
                    Hashtable connectParams = new Hashtable();
                    connectParams["SqlInstance"] = connectTarget;
                    connectParams["SqlCredential"] = SqlCredential;
                    NestedConnect.Outcome connection = NestedConnect.Connect(this, connectParams);
                    if (!connection.Ok)
                    {
                        StopFunction("Failure", target: connectTarget, errorRecord: connection.Failure, category: ErrorCategory.ConnectionError, continueLoop: true);
                        continue;
                    }

                    // PS: $server.Query("DBCC FREESYSTEMCACHE('SQL Plans')") - OUTSIDE any
                    // try; a fault is statement-terminating (conditional record-vs-unwind)
                    // and the result object below still emits on the record path.
                    try
                    {
                        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ServerQueryScript, connection.ServerValue, "DBCC FREESYSTEMCACHE('SQL Plans')"))
                            WriteObject(item);
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception ex)
                    {
                        StatementFault.Surface(this, ex, "Clear-DbaPlanCache");
                    }

                    PSObject cleared = new PSObject();
                    cleared.Properties.Add(new PSNoteProperty("ComputerName", DotAccess(result, "ComputerName")));
                    cleared.Properties.Add(new PSNoteProperty("InstanceName", DotAccess(result, "InstanceName")));
                    cleared.Properties.Add(new PSNoteProperty("SqlInstance", DotAccess(result, "SqlInstance")));
                    cleared.Properties.Add(new PSNoteProperty("Size", DotAccess(result, "Size")));
                    cleared.Properties.Add(new PSNoteProperty("Status", "Plan cache cleared"));
                    WriteObject(cleared);
                }
            }
            else
            {
                // PS: ShouldProcess("Results $($result.Size) below threshold") - the Status
                // and verbose texts carry a TRAILING SPACE verbatim.
                if (ShouldProcess(PsText(DotAccess(result, "SqlInstance")), "Results " + PsText(DotAccess(result, "Size")) + " below threshold"))
                {
                    PSObject below = new PSObject();
                    below.Properties.Add(new PSNoteProperty("ComputerName", DotAccess(result, "ComputerName")));
                    below.Properties.Add(new PSNoteProperty("InstanceName", DotAccess(result, "InstanceName")));
                    below.Properties.Add(new PSNoteProperty("SqlInstance", DotAccess(result, "SqlInstance")));
                    below.Properties.Add(new PSNoteProperty("Size", DotAccess(result, "Size")));
                    below.Properties.Add(new PSNoteProperty("Status", "Plan cache size below threshold (" + Threshold.ToString(CultureInfo.InvariantCulture) + ") "));
                    WriteObject(below);
                    WriteMessage(MessageLevel.Verbose, "Plan cache size below threshold (" + Threshold.ToString(CultureInfo.InvariantCulture) + ") ");
                }
            }
        }
    }

    // PS: $server.Query($query) - the statement runs on the engine so the ETS
    // ScriptMethod, its silent inner bookkeeping, and real-$null output are the
    // function's own mechanics.
    private const string ServerQueryScript = """
param($server, $query)
$server.Query($query)
""";

    /// <summary>PS: $InputObject += &lt;command output&gt; on the [object[]]-typed parameter.
    /// Empty output is a NO-OP, one item appends the scalar, several concatenate
    /// (lab-probed, W1-044).</summary>
    private static object[]? AppendPipelineOutput(object[]? current, Collection<PSObject> fetched)
    {
        if (fetched.Count == 0)
            return current;
        int currentLength = current?.Length ?? 0;
        object[] combined = new object[currentLength + fetched.Count];
        if (current is not null)
            Array.Copy(current, combined, currentLength);
        for (int index = 0; index < fetched.Count; index++)
            combined[currentLength + index] = fetched[index];
        return combined;
    }

    /// <summary>The PS dot operator with member-enumeration semantics (the W1-044 DotAccess
    /// shape: null elements skipped, property-bag misses contribute null, single value
    /// projects the scalar, empty projects null).</summary>
    private static object? DotAccess(object? item, string name)
    {
        if (item is null)
            return null;
        PSObject wrapped = PSObject.AsPSObject(item);
        PSPropertyInfo? direct = wrapped.Properties[name];
        if (direct is not null)
        {
            object? value;
            try { value = direct.Value; }
            catch { return null; }
            return UnwrapTransit(value);
        }
        object? baseValue = wrapped.BaseObject;
        if (baseValue is not string && LanguagePrimitives.GetEnumerable(baseValue) is IEnumerable elements)
        {
            List<object?> collected = new List<object?>();
            foreach (object? element in elements)
            {
                if (element is null)
                    continue;
                PSObject wrappedElement = PSObject.AsPSObject(element);
                PSPropertyInfo? property = wrappedElement.Properties[name];
                if (property is not null)
                {
                    try { collected.Add(UnwrapTransit(property.Value)); }
                    catch { collected.Add(null); }
                }
                else if (wrappedElement.BaseObject is PSCustomObject)
                {
                    collected.Add(null);
                }
            }
            if (collected.Count == 0)
                return null;
            if (collected.Count == 1)
                return collected[0];
            return collected.ToArray();
        }
        return null;
    }

    /// <summary>Unwraps the pipeline-transit PSObject wrapper except pure property bags
    /// (W1-030 class).</summary>
    private static object? UnwrapTransit(object? value)
    {
        if (value is PSObject psValue && psValue.BaseObject is not PSCustomObject)
            return psValue.BaseObject;
        return value;
    }

    /// <summary>PS string interpolation of a value; arrays space-join.</summary>
    private static string PsText(object? value)
    {
        if (value is null)
            return "";
        return PSObject.AsPSObject(value).ToString();
    }

    /// <summary>PS preference inheritance for nested calls (the W1-021 class).</summary>
    private void PropagateBoundPreference(Hashtable parameters)
    {
        object? verbose;
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out verbose))
            parameters["Verbose"] = verbose;
        object? errorAction;
        if (MyInvocation.BoundParameters.TryGetValue("ErrorAction", out errorAction))
            parameters["ErrorAction"] = errorAction;
    }
}
