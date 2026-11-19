#nullable enable

using System;
using System.Collections;
using System.Collections.ObjectModel;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// The buffered whole-body hop entry point plus the $error-dedup and bound-common-parameter
/// helpers a hop needs. This satellite standardized on RemoteExecutionService + NestedCommand.Invoke
/// for its OS/WMI/cert commands, so these lived only in the SQL-touching satellites; a command whose
/// unit tests mock a private helper (Invoke-Command2) and a nested cmdlet with -ModuleName dbatools
/// needs the body to run in the real module scope, which is what InvokeScoped provides.
///
/// InvokeScoped and the helpers are copied verbatim from the canonical dbatools.core copy (the
/// internal class is per-assembly, so each satellite keeps its own). They reuse this satellite's
/// existing ShieldDefaultParameterValues, PropagateActionPreferences, ErrorVariableBridge,
/// InterruptBeacon, ModuleRootSeed* and PreserveErrorIdentity; the existing NestedCommand.Invoke /
/// InvokeStreamed callers do not reference these members, so adding them changes no shipped behavior.
/// The streaming counterpart lives in NestedCommand.HopScopedStreaming.cs (this file kept under the
/// 400-line limit).
/// </summary>
internal static partial class NestedCommand
{
    /// <summary>
    /// Runs a script - typically a module-scoped `&amp; (Get-Module dbatools) { ... }` hop
    /// that reaches PRIVATE functions - with the empty-table PSDPV shield, re-emitting
    /// 3&gt;&amp;1-merged WarningRecords through the host cmdlet's warning stream (caller
    /// -WarningVariable parity, matching how a function-internal call's warnings bubbled)
    /// and returning the remaining output. Engine flow control (a Stop-Function-style
    /// helper's continue/break - PS try/catch cannot intercept those and neither does
    /// this) and terminating errors propagate to the caller, but NOTHING THIS INVOCATION
    /// ALREADY PRODUCED SURVIVES THAT UNWIND: InvokeScript hands back its Collection only on
    /// normal completion, so a guard that warns and then unwinds loses its warning and the
    /// caller's statement dies with no diagnostic at all. A guard at hop TOP LEVEL
    /// (outside any loop) is the shape that hits this; inside a loop the continue binds to
    /// that loop and never reaches the boundary. Contrast InvokeScopedStreaming, which keeps
    /// the warning and loses the flow control instead.
    /// The script is wrapped in an `&amp; {{ ... }} @args` block: InvokeScript's
    /// useLocalScope:false DOT-SOURCES the text, so a bare script's param() would BIND IN
    /// THE CALLER'S SCOPE and die "Cannot overwrite variable X because the variable has
    /// been optimized" whenever the calling function/scriptblock has an optimized local of
    /// the same name. The wrapper block creates a real scope for the param binding while dynamic
    /// READS (preference variables) still resolve through the caller.
    /// </summary>
    internal static Collection<PSObject> InvokeScoped(PSCmdlet host, string scriptText, params object?[] scriptArgs)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        using (ShieldDefaultParameterValues(host))
        using (PropagateActionPreferences(host))
        {
            using ErrorVariableBridge bridge = new ErrorVariableBridge(host);
            // The carrier param is the ONLY name bound in the caller's scope; the args
            // array travels as a single element so null elements survive the InvokeScript
            // object[]-unpacking, then splats positionally into the real scope.
            using InterruptBeacon interruptBeacon = new InterruptBeacon(host);
            string __seedToken = Guid.NewGuid().ToString("N");
            ScriptBlock script = ScriptBlock.Create(
                "param($__nestedCommandArguments, $__nestedInterruptBeacon)\n" + ModuleRootSeedProlog(host, scriptText, __seedToken) + InterruptBeaconSeedProlog(__seedToken) + "& {\n" + scriptText + "\n} @__nestedCommandArguments" + InterruptBeaconSeedEpilog(__seedToken) + ModuleRootSeedEpilog(__seedToken));
            Collection<PSObject> raw = host.InvokeCommand.InvokeScript(false, script, null, new object?[] { scriptArgs, interruptBeacon.State });
            Collection<PSObject> output = new Collection<PSObject>();
            foreach (PSObject item in raw)
            {
                if (item?.BaseObject is WarningRecord warning)
                    host.WriteWarning(warning.Message);
                else if (item?.BaseObject is ErrorRecord nonTerminating)
                {
                    // Re-emit through the cmdlet's own error channel so -ErrorVariable capture
                    // and caller-side preference handling see them, as the function world does.
                    RemoveHopEraDuplicateError(host, nonTerminating, bridge.HopEraBaselineHead);
                    host.WriteError(PreserveErrorIdentity(nonTerminating));
                }
                else
                    output.Add(item!);
            }
            return output;
        }
    }

    // An InnerException chain longer than this is a cycle or a pathological wrap; a
    // bookkeeping helper must never be the thing that hangs the pipeline.
    private const int MaximumExceptionChainDepth = 32;

    /// <summary>
    /// Drops $error[0] when it is the hop's own copy of the supplied record. A hop runs its
    /// body in a nested pipeline with 2&gt;&amp;1 merged, so a non-terminating failure lands in
    /// the runspace's $error AND arrives at the host as an output item; re-emitting it with
    /// WriteError would push a second copy and leave the caller with one more record than the
    /// retired function produced. Best effort: a runspace that denies $error access keeps the
    /// duplicate rather than failing the command.
    /// </summary>
    /// <param name="host">The cmdlet whose session state owns $error</param>
    /// <param name="record">The record about to be re-emitted through the host's error stream</param>
    internal static void RemoveDuplicateError(PSCmdlet host, ErrorRecord record)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        if (host is null || record is null)
        {
            return;
        }

        try
        {
            if (host.SessionState.PSVariable.GetValue("Error") is not ArrayList errorList || errorList.Count == 0)
            {
                return;
            }
            if (errorList[0] is not ErrorRecord first)
            {
                return;
            }
            if (IsSameFailure(first, record))
            {
                errorList.RemoveAt(0);
            }
        }
        catch
        {
            // Best-effort bookkeeping only.
        }
    }

    /// <summary>
    /// Removes one matching record from the hop-era portion of $error. The boundary is the same
    /// pre-hop head used by ErrorVariableBridge; scanning past it could delete session history
    /// and make the bridge misclassify that history as hop output.
    /// </summary>
    internal static void RemoveHopEraDuplicateError(PSCmdlet host, ErrorRecord record, object? hopEraBaselineHead)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        if (host is null || record is null)
        {
            return;
        }

        try
        {
            if (host.SessionState.PSVariable.GetValue("Error") is not ArrayList errorList || errorList.Count == 0)
            {
                return;
            }

            int limit = HopEraLimit(errorList, hopEraBaselineHead);
            for (int i = 0; i < limit; i++)
            {
                if (errorList[i] is ErrorRecord candidate && IsSameFailure(candidate, record))
                {
                    errorList.RemoveAt(i);
                    return;
                }
            }
        }
        catch
        {
            // Best-effort bookkeeping only.
        }
    }

    private static int HopEraLimit(ArrayList errorList, object? hopEraBaselineHead)
    {
        if (hopEraBaselineHead is null)
        {
            return errorList.Count;
        }
        for (int i = 0; i < errorList.Count; i++)
        {
            if (ReferenceEquals(errorList[i], hopEraBaselineHead))
            {
                return i;
            }
        }
        return errorList.Count;
    }

    /// <summary>
    /// Whether the record sitting on top of $error is the hop's own copy of the record the host
    /// is about to re-emit. Every arm is anchored to OBJECT IDENTITY.
    ///
    /// The rule used to fall back to comparing exception message TEXT, and that arm could
    /// dequeue a completely unrelated record: two instances both failing with dbatools' bare
    /// "Failure" message is the everyday case, and nothing in a text comparison ties the
    /// candidate to the failure this hop produced. The hop's own duplicate then stayed in
    /// $error while somebody else's diagnostic disappeared from it.
    /// </summary>
    /// <param name="first">The record currently at $error[0]</param>
    /// <param name="record">The record the host is about to re-emit</param>
    /// <returns>True when they are the same failure</returns>
    internal static bool IsSameFailure(ErrorRecord? first, ErrorRecord? record)
    {
        if (first is null || record is null)
        {
            return false;
        }
        if (ReferenceEquals(first, record))
        {
            return true;
        }

        Exception? firstException = first.Exception;
        Exception? recordException = record.Exception;
        if (firstException is null || recordException is null)
        {
            return false;
        }
        if (ReferenceEquals(firstException, recordException))
        {
            return true;
        }

        // A re-wrapped record still carries the original exception OBJECT in its chain -
        // Stop-Function builds new Exception(message, record.Exception) - so walking the chain
        // recognizes the duplicate without ever comparing text.
        return ChainContains(firstException, recordException)
            || ChainContains(recordException, firstException);
    }

    private static bool ChainContains(Exception outer, Exception target)
    {
        Exception? current = outer.InnerException;
        for (int depth = 0; current is not null && depth < MaximumExceptionChainDepth; depth++)
        {
            if (ReferenceEquals(current, target))
            {
                return true;
            }
            current = current.InnerException;
        }
        return false;
    }

    /// <summary>
    /// The bound truthiness of a common parameter (-Verbose/-Debug) for forwarding into a hop
    /// body: true or false when the caller bound it, null when they did not, so the hop can tell
    /// "explicitly off" from "not specified" - a distinction a plain bool loses.
    /// </summary>
    /// <param name="host">The cmdlet whose invocation carries the bound parameters</param>
    /// <param name="name">The common parameter name</param>
    /// <returns>The bound value's truthiness, or null when unbound</returns>
    internal static object? BoundCommonParameter(PSCmdlet host, string name)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        if (host.MyInvocation.BoundParameters.TryGetValue(name, out object? value))
        {
            return LanguagePrimitives.IsTrue(value);
        }
        return null;
    }
}
