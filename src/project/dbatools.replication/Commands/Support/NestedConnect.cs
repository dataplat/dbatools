#nullable enable

using System.Collections;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// PS: $server = Connect-DbaInstance -SqlInstance ... inside a function try/catch. The REAL
/// command runs nested (local scope, PSDefaultParameterValues shielded to an empty table,
/// explicit -WarningVariable) so a connect failure surfaces its display-suppressed warning
/// to the caller's -WarningVariable exactly like the function's nested call did (the W1-018
/// Import-DbaCsv shape), the nested compiled cmdlet's VERBOSE lines flow when the caller
/// bound -Verbose (forwarded as a local $VerbosePreference, the W1-046 lab split), and the
/// caught record keeps the engine's own $error bookkeeping (bagged once on propagation).
/// </summary>
internal static class NestedConnect
{
    internal sealed class Outcome
    {
        internal bool Ok;
        internal object? ServerValue;
        internal object? RawServerValue;
        internal ErrorRecord? Failure;

        /// <summary>The SMO server, when the nested call produced one.</summary>
        internal Server? Server
        {
            get { return ServerValue as Server; }
        }
    }

    private const string ConnectScript =
        "param($__connectParams, $__wp, $__vp, $__dp) " +
        "if ($null -ne $__wp) { $WarningPreference = $__wp } " +
        "if ($null -ne $__vp) { $VerbosePreference = $__vp } " +
        "if ($null -ne $__dp) { $DebugPreference = $__dp } " +
        "try { $__server = Connect-DbaInstance @__connectParams -WarningVariable __nestedWarnings; @{ ok = $true; server = $__server; warnings = $__nestedWarnings } } " +
        "catch { @{ ok = $false; record = $_; warnings = $__nestedWarnings } }";

    /// <summary>Runs the real Connect-DbaInstance with the given splat.</summary>
    internal static Outcome Connect(PSCmdlet host, Hashtable connectParams)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        object? boundWarningAction;
        host.MyInvocation.BoundParameters.TryGetValue("WarningAction", out boundWarningAction);
        object? boundVerbose = null;
        object? verboseValue;
        if (host.MyInvocation.BoundParameters.TryGetValue("Verbose", out verboseValue))
            boundVerbose = LanguagePrimitives.IsTrue(verboseValue) ? "Continue" : "SilentlyContinue";
        // Debug rides the same seam (the class the 41-hop carrier fix closed at hop level;
        // without this the nested Connect-DbaInstance's debug records stay suppressed).
        object? boundDebug = null;
        object? debugValue;
        if (host.MyInvocation.BoundParameters.TryGetValue("Debug", out debugValue))
            boundDebug = LanguagePrimitives.IsTrue(debugValue) ? "Continue" : "SilentlyContinue";

        ScriptBlock script = ScriptBlock.Create(ConnectScript);

        Collection<PSObject> results;
        // Empty-table shield: module-internal calls never saw caller-local OR global
        // defaults (the W1-019 lab fact).
        object? effectiveDefaults = host.SessionState.PSVariable.GetValue("PSDefaultParameterValues");
        bool shielded = effectiveDefaults is not null;
        if (shielded)
            host.SessionState.PSVariable.Set("PSDefaultParameterValues", new DefaultParameterDictionary());
        try
        {
            results = host.InvokeCommand.InvokeScript(true, script, null, connectParams, boundWarningAction, boundVerbose, boundDebug);
        }
        finally
        {
            if (shielded)
                host.SessionState.PSVariable.Set("PSDefaultParameterValues", effectiveDefaults);
        }

        Hashtable outcomeTable = (Hashtable)results[0].BaseObject;

        // The nested warnings already displayed (or were suppressed) inside the nested
        // runtime; the re-emit only restores caller -WarningVariable capture, so it always
        // writes display-suppressed (the MessageService WarningPreference-swap trick).
        object? warnings = outcomeTable["warnings"];
        if (warnings is not null && LanguagePrimitives.GetEnumerable(warnings) is IEnumerable warningItems)
        {
            foreach (object? warningItem in warningItems)
            {
                object? unwrapped = warningItem is PSObject wrappedWarning ? wrappedWarning.BaseObject : warningItem;
                string text = unwrapped is WarningRecord warningRecord ? warningRecord.Message : (unwrapped is null ? "" : PSObject.AsPSObject(unwrapped).ToString());
                object? oldPreference = host.SessionState.PSVariable.GetValue("WarningPreference");
                try
                {
                    host.SessionState.PSVariable.Set("WarningPreference", ActionPreference.SilentlyContinue);
                    host.WriteWarning(text);
                }
                finally
                {
                    host.SessionState.PSVariable.Set("WarningPreference", oldPreference);
                }
            }
        }

        Outcome outcome = new Outcome();
        outcome.Ok = LanguagePrimitives.IsTrue(outcomeTable["ok"]);
        if (outcome.Ok)
        {
            object? serverValue = outcomeTable["server"];
            // The PSObject wrapper carries instance ETS decorations (mock-driven test
            // servers Add-Member ScriptMethods) - keep it for hops that need the
            // fn-world dispatch (the W1-105 law).
            outcome.RawServerValue = serverValue;
            if (serverValue is PSObject wrappedServer)
                serverValue = wrappedServer.BaseObject;
            outcome.ServerValue = serverValue;
        }
        else
        {
            object? record = outcomeTable["record"];
            if (record is PSObject wrappedRecord)
                record = wrappedRecord.BaseObject;
            outcome.Failure = record as ErrorRecord;
        }
        return outcome;
    }
}
