#nullable enable

using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Text.RegularExpressions;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Returns detailed records of dbatools-tagged errors from the session's global error
/// collection. Port of public/Get-DbatoolsError.ps1: $global:error read live off the
/// SessionState (the W1-007 technique), the Where-Object FullyQualifiedErrorId -match
/// dbatools filter modeled natively (PS -match: string conversion + case-insensitive regex),
/// and the Select-Object -First/-Last/-Skip nine-property projection riding the REAL engine
/// cmdlet through NestedCommand so First-0/Last-0 interplay and Selected.* typenames are the
/// engine's own. Test-Bound -Not First, Last, Skip, All (none-bound) defaults First to 1;
/// -All widens First to the whole collection. Surface pinned by
/// migration/baselines/Get-DbatoolsError.json (First pos0, Last pos1, Skip pos2).
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbatoolsError")]
[OutputType(typeof(PSObject))]
public sealed class GetDbatoolsErrorCommand : DbaBaseCmdlet
{
    /// <summary>Returns the newest n dbatools errors.</summary>
    [Parameter(Position = 0)]
    [PsIntCast]
    public int First { get; set; }

    /// <summary>Returns the oldest n dbatools errors.</summary>
    [Parameter(Position = 1)]
    [PsIntCast]
    public int Last { get; set; }

    /// <summary>Skips the newest n dbatools errors.</summary>
    [Parameter(Position = 2)]
    [PsIntCast]
    public int Skip { get; set; }

    /// <summary>Returns every dbatools error in the collection.</summary>
    [Parameter]
    public SwitchParameter All { get; set; }

    /// <summary>Retains internal exception state without exposing a parameter absent from the pinned function.</summary>
    public override SwitchParameter EnableException
    {
        get => base.EnableException;
        set => base.EnableException = value;
    }

    // PS: Select-Object ... -Property <this list, in this order>
    private static readonly string[] ProjectedProperties =
    {
        "CategoryInfo", "ErrorDetails", "Exception", "FullyQualifiedErrorId",
        "InvocationInfo", "PipelineIterationInfo", "PSMessageDetails", "ScriptStackTrace",
        "TargetObject"
    };

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // PS: if (Test-Bound -Not First, Last, Skip, All) { $First = 1 } - none bound
        if (!(TestBound("First") || TestBound("Last") || TestBound("Skip") || TestBound("All")))
        {
            First = 1;
        }

        // PS: $global:error - the session's live error collection
        object? errorCollection = SessionState.PSVariable.GetValue("global:Error");

        if (All.IsPresent)
        {
            // PS: $First = $global:error.Count
            First = errorCollection is ICollection collection ? collection.Count : 0;
        }

        // PS: $global:error | Where-Object FullyQualifiedErrorId -match dbatools - PS -match
        // converts the property value to string (null/missing -> "") and matches the regex
        // case-insensitively.
        List<object> filtered = new List<object>();
        if (errorCollection is not null && LanguagePrimitives.GetEnumerable(errorCollection) is IEnumerable errors)
        {
            foreach (object? record in errors)
            {
                if (record is null)
                {
                    continue;
                }
                PSPropertyInfo? property = PSObject.AsPSObject(record).Properties["FullyQualifiedErrorId"];
                object? value = null;
                if (property is not null)
                {
                    try
                    {
                        value = property.Value;
                    }
                    catch
                    {
                        value = null;
                    }
                }
                string text = value is null ? string.Empty : (LanguagePrimitives.ConvertTo<string>(value) ?? string.Empty);
                if (Regex.IsMatch(text, "dbatools", RegexOptions.IgnoreCase))
                {
                    filtered.Add(record);
                }
            }
        }

        // PS: ... | Select-Object -First $First -Last $Last -Skip $Skip -Property <list> -
        // always passes all three values (unbound ints stay 0) so the engine's own
        // First/Last/Skip interplay applies.
        Hashtable splatSelect = new();
        splatSelect["First"] = First;
        splatSelect["Last"] = Last;
        splatSelect["Skip"] = Skip;
        splatSelect["Property"] = ProjectedProperties;
        Collection<PSObject> output = NestedCommand.Invoke(this, "Select-Object", splatSelect, pipelineInput: filtered);
        foreach (PSObject item in output)
        {
            WriteObject(item);
        }
    }
}
