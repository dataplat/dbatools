#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

// Structural partial split out of InvokeDbaQueryCommand.Async.cs (400-line limit): the nested
// dbatools-command / path-resolution / file-download helpers. No behavior change — the methods
// are moved verbatim.
public sealed partial class InvokeDbaQueryCommand
{
    /// <summary>PS: "$(Get-DbatoolsPath -Name temp)" via the real command.</summary>
    private string GetDbatoolsTempPath()
    {
        Hashtable pathParams = new();
        pathParams["Name"] = "temp";
        Collection<PSObject> result = NestedCommand.Invoke(this, "Get-DbatoolsPath", pathParams);
        return PsText(ShapePipelineValue(result));
    }

    /// <summary>
    /// PS http-file branch: Invoke-TlsWebRequest (a PRIVATE module function, so it runs in
    /// the dbatools module scope) with the default-proxy-credentials retry; returns the
    /// failure record of the RETRY (the outer catch's $_) or null on success.
    /// </summary>
    private ErrorRecord? DownloadSqlFile(string uri, string outFile)
    {
        Hashtable requestParams = new();
        requestParams["Uri"] = uri;
        requestParams["OutFile"] = outFile;
        requestParams["ErrorAction"] = "Stop";
        try
        {
            try
            {
                ModuleScopedInvoke("Invoke-TlsWebRequest", requestParams);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch
            {
                // PS: (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                // (mutates the shared default proxy, then retries)
#pragma warning disable SYSLIB0014
                System.Net.WebClient webClient = new();
#pragma warning restore SYSLIB0014
                // A null default proxy faults the assignment exactly like the PS statement
                // would; the outer catch owns it.
                webClient.Proxy!.Credentials = System.Net.CredentialCache.DefaultNetworkCredentials;
                ModuleScopedInvoke("Invoke-TlsWebRequest", requestParams);
            }
            return null;
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            return RecordFrom(ex);
        }
    }

    /// <summary>Runs a PRIVATE dbatools function in the module scope (W5-027 pattern).</summary>
    private Collection<PSObject> ModuleScopedInvoke(string commandName, Hashtable parameters)
    {
        NestedCommand.RequireDbatoolsScriptModule(this);
        ScriptBlock script = ScriptBlock.Create(
            "param($__cmd, $__params) & (Get-Module dbatools | Where-Object ModuleType -eq \"Script\" | Select-Object -First 1) { param($c, $p) & $c @p } $__cmd $__params");
        return InvokeCommand.InvokeScript(true, script, null, commandName, parameters);
    }

    /// <summary>PS: Resolve-Path $item | Select-Object -ExpandProperty Path | Get-Item -ErrorAction Stop.</summary>
    private List<PSObject> ResolvePathItems(string item)
    {
        Hashtable resolveParams = new();
        resolveParams["Path"] = item;
        Collection<PSObject> resolved = NestedCommand.Invoke(this, "Resolve-Path", resolveParams);
        List<string> pathTexts = new();
        foreach (PSObject pathInfo in resolved)
            pathTexts.Add(PsText(PsProperty.Get(pathInfo, "Path")));
        List<PSObject> items = new();
        if (pathTexts.Count == 0)
            return items;
        Hashtable getItemParams = new();
        getItemParams["Path"] = pathTexts.ToArray();
        getItemParams["ErrorAction"] = "Stop";
        foreach (PSObject fileItem in NestedCommand.Invoke(this, "Get-Item", getItemParams))
            items.Add(fileItem);
        return items;
    }

    /// <summary>PS: $(Resolve-Path -LiteralPath $item).ProviderPath (interpolated downstream,
    /// so a resolution failure yields an empty string).</summary>
    private string GetLiteralProviderPath(string item)
    {
        Hashtable resolveParams = new();
        resolveParams["LiteralPath"] = item;
        Collection<PSObject> resolved = NestedCommand.Invoke(this, "Resolve-Path", resolveParams);
        object? providerPath = resolved.Count > 0 ? PsProperty.Get(resolved[0], "ProviderPath") : null;
        return PsText(providerPath);
    }

    /// <summary>
    /// Runs a nested command with PS-bubbling warning parity (same pattern as
    /// ImportDbaCsvCommand.ConnectViaCommand / ImportDbatoolsConfigCommand — third private
    /// copy; shared-promotion is an owner hand-back): the script-side catch returns the
    /// outcome as data so warnings written before a terminating failure still reach this
    /// cmdlet, which re-emits them display-suppressed for -WarningVariable capture.
    /// </summary>
    private Collection<PSObject> InvokeNestedPreservingWarnings(string commandName, Hashtable parameters, object? pipelineInput, out ErrorRecord? failure)
    {
        // PS: a bound -WarningAction on the outer command sets the preference the nested
        // call inherits (display suppression; -WarningVariable still captures).
        ScriptBlock script;
        if (pipelineInput is null)
        {
            script = ScriptBlock.Create(
                "param($__params, $__wp) if ($null -ne $__wp) { $WarningPreference = $__wp } try { $__r = & " + commandName + " @__params -WarningVariable __nestedWarnings; @{ ok = $true; result = $__r; warnings = $__nestedWarnings } } catch { @{ ok = $false; record = $_; warnings = $__nestedWarnings } }");
        }
        else
        {
            script = ScriptBlock.Create(
                "param($__params, $__wp, $__input) if ($null -ne $__wp) { $WarningPreference = $__wp } try { $__r = $__input | & " + commandName + " @__params -WarningVariable __nestedWarnings; @{ ok = $true; result = $__r; warnings = $__nestedWarnings } } catch { @{ ok = $false; record = $_; warnings = $__nestedWarnings } }");
        }
        object? boundWarningAction;
        MyInvocation.BoundParameters.TryGetValue("WarningAction", out boundWarningAction);

        Collection<PSObject> raw;
        // Empty-table shield: module-internal calls never saw caller-local OR global
        // defaults (lab-proven via the PassThru-injection probe).
        object? effectiveDefaults = SessionState.PSVariable.GetValue("PSDefaultParameterValues");
        bool shielded = effectiveDefaults is not null;
        if (shielded)
            SessionState.PSVariable.Set("PSDefaultParameterValues", new DefaultParameterDictionary());
        try
        {
            raw = pipelineInput is null
                ? InvokeCommand.InvokeScript(true, script, null, parameters, boundWarningAction)
                : InvokeCommand.InvokeScript(true, script, null, parameters, boundWarningAction, pipelineInput);
        }
        finally
        {
            if (shielded)
                SessionState.PSVariable.Set("PSDefaultParameterValues", effectiveDefaults);
        }

        Hashtable outcome = (Hashtable)raw[0].BaseObject;

        object? warnings = outcome["warnings"];
        if (warnings is not null)
        {
            IEnumerable? enumerable = LanguagePrimitives.GetEnumerable(warnings);
            if (enumerable is not null)
            {
                foreach (object? warningItem in enumerable)
                {
                    object? unwrapped = warningItem is PSObject wrappedWarning ? wrappedWarning.BaseObject : warningItem;
                    string text = unwrapped is WarningRecord warningRecord ? warningRecord.Message : PsText(unwrapped);
                    object? oldPreference = SessionState.PSVariable.GetValue("WarningPreference");
                    try
                    {
                        SessionState.PSVariable.Set("WarningPreference", ActionPreference.SilentlyContinue);
                        WriteWarning(text);
                    }
                    finally
                    {
                        SessionState.PSVariable.Set("WarningPreference", oldPreference);
                    }
                }
            }
        }

        if (!LanguagePrimitives.IsTrue(outcome["ok"]))
        {
            object? record = outcome["record"];
            if (record is PSObject wrappedRecord)
                record = wrappedRecord.BaseObject;
            failure = (ErrorRecord)record!;
            return new Collection<PSObject>();
        }

        failure = null;
        Collection<PSObject> results = new();
        object? resultValue = outcome["result"];
        if (resultValue is not null)
        {
            IEnumerable? resultEnumerable = LanguagePrimitives.GetEnumerable(resultValue);
            if (resultEnumerable is null)
            {
                results.Add(PSObject.AsPSObject(resultValue));
            }
            else
            {
                foreach (object? element in resultEnumerable)
                {
                    if (element is not null)
                        results.Add(PSObject.AsPSObject(element));
                }
            }
        }
        return results;
    }

    /// <summary>PS string interpolation of an arbitrary token.</summary>
    private static string PsText(object? value)
    {
        if (value is null)
            return "";
        return PSObject.AsPSObject(value).ToString();
    }

    /// <summary>The catch-block $_ equivalent for a .NET-thrown exception. A REAL nested
    /// record rides through; a hand-constructed RuntimeException's lazily-created record
    /// wraps itself in ParentContainsErrorRecordException and DROPS the inner-exception
    /// chain (observed: the r2 F2 MethodInvocationException wrapper leaked into the
    /// warning because the deepest-message walk lost the SqlException), so those build a
    /// fresh record from the exception itself.</summary>
    private static ErrorRecord RecordFrom(Exception ex)
    {
        if (ex is RuntimeException runtime && runtime.ErrorRecord is not null &&
            runtime.ErrorRecord.Exception is not ParentContainsErrorRecordException)
        {
            return runtime.ErrorRecord;
        }
        return new ErrorRecord(ex, "Invoke-DbaQuery", ErrorCategory.NotSpecified, null);
    }

    /// <summary>PS pipeline-assignment shaping of a nested result (null/single/array).</summary>
    internal static object? ShapePipelineValue(Collection<PSObject> raw)
    {
        if (raw.Count == 0)
            return null;
        if (raw.Count == 1)
            return raw[0];
        object[] shaped = new object[raw.Count];
        for (int i = 0; i < raw.Count; i++)
            shaped[i] = raw[i];
        return shaped;
    }
}
