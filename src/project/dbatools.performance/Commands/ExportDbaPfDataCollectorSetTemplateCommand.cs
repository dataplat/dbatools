#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports Data Collector Set templates to XML files. Port of
/// public/Export-DbaPfDataCollectorSetTemplate.ps1 (W1-051; W1-044 sibling shape).
/// Set-Content/Get-ChildItem ride the engine via NestedCommand (per-edition Unicode
/// encoding, provider errors, ambient -WhatIf reach); the private helpers
/// (Test-ExportDirectory, Remove-InvalidFileNameChars) run module-scoped with
/// $EnableException re-established. Function quirks preserved:
/// - $FilePath persists once computed, so every LATER set overwrites the FIRST file
///   (function-scope staleness - the parameter property carries it);
/// - the verbose line interpolates the UNDEFINED $filename ("Wrote X to .") and a stale
///   or never-computed $csname when -FilePath was bound;
/// - the begin-block Test-ExportDirectory Stop-Function arms its interrupt in the WRONG
///   scope (Scope 1 = the helper itself), so the process guard NEVER fires from that path
///   (lab-verifiable latent bug) - the port re-emits the warning and proceeds identically,
///   while its OWN type-check StopFunction arms Interrupted for later pipeline items
///   exactly like the function's in-process Stop-Function;
/// - the type check reads the PER-OBJECT DataCollectorSetObject (not the W1-044 aggregate).
/// Statement faults follow the conditional record-vs-unwind rule (StatementFault seam).
/// Surface pinned by migration/baselines/Export-DbaPfDataCollectorSetTemplate.json.
/// </summary>
[Cmdlet(VerbsData.Export, "DbaPfDataCollectorSetTemplate")]
public sealed partial class ExportDbaPfDataCollectorSetTemplateCommand : DbaBaseCmdlet
{
    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; }

    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    [Parameter(Position = 2)]
    [Alias("DataCollectorSet")]
    public string[]? CollectorSet { get; set; }

    [Parameter(Position = 3)]
    public string? Path { get; set; }

    [Parameter(Position = 4)]
    [Alias("OutFile", "FileName")]
    public string? FilePath { get; set; }

    [Parameter(ValueFromPipeline = true, Position = 5)]
    public object[]? InputObject { get; set; }

    // PS function-scope staleness: $csname persists across objects/items; until the
    // computing branch runs, the interpolation reads it DYNAMICALLY (module scope, then
    // global) like any undefined function variable (codex r1 / the W1-044 $counters class).
    private object? _csname;
    private bool _csnameAssigned;

    protected override void BeginProcessing()
    {
        // PS: [DbaInstance[]]$ComputerName = $env:COMPUTERNAME (bind-time cast).
        if (!TestBound("ComputerName"))
        {
            string? localName = Environment.GetEnvironmentVariable("COMPUTERNAME");
            if (localName is not null)
                ComputerName = (DbaInstanceParameter[])LanguagePrimitives.ConvertTo(localName, typeof(DbaInstanceParameter[]), CultureInfo.InvariantCulture);
        }

        // PS: [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport').
        if (!TestBound("Path"))
        {
            Hashtable configParams = new Hashtable();
            configParams["FullName"] = "Path.DbatoolsExport";
            Collection<PSObject> configValue = NestedCommand.Invoke(this, "Get-DbatoolsConfigValue", configParams);
            object? raw = configValue.Count > 0 ? (object?)configValue[0] : null;
            Path = raw is null ? "" : (string)LanguagePrimitives.ConvertTo(raw, typeof(string), CultureInfo.InvariantCulture);
        }

        // PS: $null = Test-ExportDirectory -Path $Path - the helper's Stop-Function warning
        // re-emits; its interrupt lands in the WRONG scope in the function world, so no
        // interrupt is armed here either (quirk preserved). EE throws propagate.
        NestedCommand.InvokeScoped(this, TestExportDirectoryScript, Path, EnableException.ToBool(), BoundVerbose(), BoundDebug());
    }

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return } - armed only by the in-process
        // type-check Stop-Function below (the begin-block path never arms it).
        if (Interrupted)
            return;

        // PS: if ($InputObject.Credential -and (Test-Bound -ParameterName Credential -Not))
        object? inputCredential = DotAccess(InputObject, "Credential");
        if (PsOps.IsTrue(inputCredential) && !TestBound("Credential"))
        {
            try
            {
                Credential = (PSCredential?)LanguagePrimitives.ConvertTo(inputCredential, typeof(PSCredential), CultureInfo.InvariantCulture);
            }
            catch (PSInvalidCastException ex)
            {
                StatementFault.Surface(this, ex, "Export-DbaPfDataCollectorSetTemplate");
            }
        }

        // PS: if (-not $InputObject -or ($InputObject -and (Test-Bound -ParameterName ComputerName)))
        if (!PsOps.IsTrue(InputObject) || (PsOps.IsTrue(InputObject) && TestBound("ComputerName")))
        {
            if (ComputerName is not null)
            {
                foreach (DbaInstanceParameter? computerItem in ComputerName)
                {
                    Hashtable fetchParams = new Hashtable();
                    fetchParams["ComputerName"] = computerItem;
                    fetchParams["Credential"] = Credential;
                    fetchParams["CollectorSet"] = CollectorSet;
                    PropagateBoundPreference(fetchParams);
                    try
                    {
                        Collection<PSObject> fetched = NestedCommand.Invoke(this, "Get-DbaPfDataCollectorSet", fetchParams);
                        InputObject = AppendPipelineOutput(InputObject, fetched);
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (RuntimeException ex)
                    {
                        StatementFault.Surface(this, ex, "Export-DbaPfDataCollectorSetTemplate");
                    }
                }
            }
        }

        if (InputObject is null)
            return;

        foreach (object? setObject in InputObject)
        {
            // PS: if (-not $object.DataCollectorSetObject) { Stop-Function ...; return }
            if (!PsOps.IsTrue(DotAccess(setObject, "DataCollectorSetObject")))
            {
                StopFunction("InputObject is not of the right type. Please use Get-DbaPfDataCollectorSet.");
                return;
            }

            // PS: if (-not $FilePath) { $csname = Remove-InvalidFileNameChars -Name $object.Name;
            //     $FilePath = "$Path\$csname.xml" } - $FilePath persists, later sets overwrite.
            if (!PsOps.IsTrue(FilePath))
            {
                try
                {
                    Collection<PSObject> cleaned = NestedCommand.InvokeScoped(this, RemoveInvalidFileNameCharsScript, DotAccess(setObject, "Name"), EnableException.ToBool(), BoundVerbose(), BoundDebug());
                    _csname = cleaned.Count > 0 ? (object?)cleaned[cleaned.Count - 1] : null;
                    _csnameAssigned = true;
                    FilePath = PsText(Path) + "\\" + PsText(_csname) + ".xml";
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (RuntimeException ex)
                {
                    StatementFault.Surface(this, ex, "Export-DbaPfDataCollectorSetTemplate");
                }
            }

            // PS: Write-Message -Level Verbose -Message "Wrote $csname to $filename." -
            // $filename is UNDEFINED (typo) and $csname may be too: both resolve through
            // the dynamic scope chain (module, then global) when no local exists.
            object? csnameValue = _csnameAssigned ? _csname : GetModuleScopeVariable("csname");
            WriteMessage(MessageLevel.Verbose, "Wrote " + PsText(csnameValue) + " to " + PsText(GetModuleScopeVariable("filename")) + ".");

            // PS: Set-Content -Path $FilePath -Value $object.Xml -Encoding Unicode (engine
            // cmdlet: per-edition encoding). Bound -Verbose is NOT propagated: binding it
            // on a provider cmdlet adds ShouldProcess "Performing the operation" verbose
            // the ambient function world never shows (lab split); non-terminating provider
            // errors merge back 2>&1 and re-emit with the silent-bag compensation (W1-045).
            Hashtable contentParams = new Hashtable();
            contentParams["Path"] = FilePath;
            contentParams["Value"] = DotAccess(setObject, "Xml");
            contentParams["Encoding"] = "Unicode";
            PropagateBoundErrorAction(contentParams);
            RunProviderStatement(SetContentScript, contentParams);

            // PS: Get-ChildItem -Path $FilePath (the output objects)
            Hashtable childParams = new Hashtable();
            childParams["Path"] = FilePath;
            PropagateBoundErrorAction(childParams);
            RunProviderStatement(GetChildItemScript, childParams);
        }
    }

    /// <summary>PS: $InputObject += &lt;command output&gt; (empty = NO-OP, W1-044 fact).</summary>
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

    /// <summary>The PS dot operator with member-enumeration semantics (W1-044 shape).</summary>
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

    /// <summary>Unwraps the pipeline-transit PSObject wrapper except property bags.</summary>
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

    /// <summary>Runs an engine provider statement hop: output streams, merged-back
    /// non-terminating errors re-emit through this cmdlet's error stream (removing the
    /// silent $error duplicate the nested pipeline bagged - the W1-045 seam), and
    /// terminating faults surface statement-style.</summary>
    private void RunProviderStatement(string script, Hashtable parameters)
    {
        try
        {
            foreach (PSObject? item in NestedCommand.InvokeScoped(this, script, parameters))
            {
                if (item?.BaseObject is ErrorRecord nestedError)
                {
                    NestedCommand.RemoveDuplicateError(this, nestedError);
                    WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                }
                else
                {
                    WriteObject(item);
                }
            }
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (RuntimeException ex)
        {
            StatementFault.Surface(this, ex, "Export-DbaPfDataCollectorSetTemplate");
        }
    }

    /// <summary>Bound -ErrorAction reaches nested calls in the function world; bound
    /// -Verbose deliberately does NOT ride provider cmdlets (see RunProviderStatement).</summary>
    private void PropagateBoundErrorAction(Hashtable parameters)
    {
        object? errorAction;
        if (MyInvocation.BoundParameters.TryGetValue("ErrorAction", out errorAction))
            parameters["ErrorAction"] = errorAction;
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

    /// <summary>PS: an undefined function variable resolves through the dynamic scope
    /// chain - module scope, then global (the W1-007/W1-044 technique).</summary>
    private object? GetModuleScopeVariable(string variableName)
    {
        Hashtable getModuleParams = new Hashtable();
        getModuleParams["Name"] = "dbatools";
        foreach (PSObject wrapped in NestedCommand.Invoke(this, "Get-Module", getModuleParams))
        {
            if (wrapped?.BaseObject is PSModuleInfo module && module.ModuleType == ModuleType.Script)
                return module.SessionState.PSVariable.GetValue(variableName);
        }
        return null;
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
}
