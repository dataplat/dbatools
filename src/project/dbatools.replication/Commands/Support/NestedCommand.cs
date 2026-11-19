#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Reflection;
using System.Runtime.ExceptionServices;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Invokes other dbatools PUBLIC commands from inside a ported cmdlet through the caller's
/// own runspace, exactly the way the retired PS function invoked them: by command name, with
/// a splatted parameter table (null-valued keys BIND, matching PS splat semantics), streams
/// flowing through to the user. During the hybrid period the name resolves to whichever
/// implementation is live (PS function or flipped cmdlet) — byte-parity either way, and the
/// kill-switch keeps working. Pattern precedent: RemoteExecutionService (Wave 5) drives
/// engine cmdlets through nested pipelines.
/// Command names are FIXED LITERALS at every call site; no user input reaches the script text.
/// </summary>
internal static partial class NestedCommand
{
    /// <summary>
    /// Replicates the module scope boundary the retired PS functions had around their
    /// internal calls: a PS function's nested *-Dba* invocations resolved
    /// $PSDefaultParameterValues through the dbatools module scope chain (module -> global),
    /// so a caller-LOCAL dictionary — like the test suite's file-scoped
    /// '*-Dba*:WarningVariable' = 'WarnVar' default — never applied to them. InvokeScript
    /// from a cmdlet chains to the caller's scope instead, so without this shield every
    /// nested *-Dba* command re-binds such a default and re-initializes the very variable
    /// the OUTER command is capturing warnings into, wiping it (lab-proven: outer-only
    /// pattern captures fine, nested-only pattern clobbers even an explicit outer
    /// -WarningVariable of the same name). Swaps the effective value for the global one for
    /// the duration of the nested invocation and restores it afterwards; no-op when
    /// effective and global already match (no caller-local dictionary — the common case).
    /// </summary>
    internal static IDisposable? ShieldDefaultParameterValues(PSCmdlet host)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        object? effective = host.SessionState.PSVariable.GetValue("PSDefaultParameterValues");
        if (effective is null)
            return null;
        // Module-internal calls resolve $PSDefaultParameterValues from the MODULE's session
        // state, where none is defined - neither caller-LOCAL nor GLOBAL defaults ever
        // reached the retired functions' nested calls (lab-proven: a global
        // Set-DbatoolsConfig:PassThru default injects into an InvokeScript-invoked nested
        // call but NOT into the function's own). The faithful shield is an EMPTY table.
        host.SessionState.PSVariable.Set("PSDefaultParameterValues", new System.Management.Automation.DefaultParameterDictionary());
        return new DefaultParameterRestore(host, effective);
    }

    private sealed class DefaultParameterRestore : IDisposable
    {
        private readonly PSCmdlet _host;
        private readonly object _saved;

        internal DefaultParameterRestore(PSCmdlet host, object saved)
        {
            _host = host;
            _saved = saved;
        }

        public void Dispose()
        {
            _host.SessionState.PSVariable.Set("PSDefaultParameterValues", _saved);
        }
    }

    /// <summary>
    /// Buffered invocation — for PS call sites that assigned the output to a variable or
    /// discarded it ($x = Get-DbaBackupInformation ... / $null = ... | Test-DbaBackupInformation).
    /// Nested warnings merge back (3&gt;&amp;1) and re-emit through the HOST cmdlet's own
    /// warning stream: in PS the inner function's warnings bubbled through the outer
    /// function's runtime, so the caller's -WarningVariable captured them alongside the
    /// outer command's own warnings ("Database X exists, so WithReplace must be specified"
    /// arrives next to "unable to be restored"). InvokeScript-invoked cmdlets bypass the
    /// host runtime, so without the merge those records never reach the caller's variable.
    /// </summary>
    internal static Collection<PSObject> Invoke(PSCmdlet host, string commandName, IDictionary parameters, object? pipelineInput = null)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        using (ShieldDefaultParameterValues(host))
        using (PropagateActionPreferences(host))
        {
            using ErrorVariableBridge bridge = new ErrorVariableBridge(host);
            Collection<PSObject> raw;
            if (pipelineInput is null)
            {
                ScriptBlock script = ScriptBlock.Create("param($__parameters) & " + commandName + " @__parameters 3>&1");
                raw = host.InvokeCommand.InvokeScript(false, script, null, parameters);
            }
            else
            {
                ScriptBlock piped = ScriptBlock.Create("param($__parameters, $__input) $__input | & " + commandName + " @__parameters 3>&1");
                raw = host.InvokeCommand.InvokeScript(false, piped, null, parameters, pipelineInput);
            }

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

    /// <summary>
    /// Runs a script — typically a module-scoped `&amp; (Get-Module dbatools) { ... }` hop
    /// that reaches PRIVATE functions — with the empty-table PSDPV shield, re-emitting
    /// 3&gt;&amp;1-merged WarningRecords through the host cmdlet's warning stream (caller
    /// -WarningVariable parity, matching how a function-internal call's warnings bubbled)
    /// and returning the remaining output. Engine flow control (a Stop-Function-style
    /// helper's continue/break — PS try/catch cannot intercept those and neither does
    /// this) and terminating errors propagate to the caller, but NOTHING THIS INVOCATION
    /// ALREADY PRODUCED SURVIVES THAT UNWIND: InvokeScript hands back its Collection only on
    /// normal completion, so a guard that warns and then unwinds loses its warning and the
    /// caller's statement dies with no diagnostic at all. Measured both editions, A/B'd
    /// against the same command running as its retired function. A guard at hop TOP LEVEL
    /// (outside any loop) is the shape that hits this; inside a loop the continue binds to
    /// that loop and never reaches the boundary. Contrast InvokeScopedStreaming, which keeps
    /// the warning and loses the flow control instead.
    /// The script is wrapped in an `&amp; {{ ... }} @args` block: InvokeScript's
    /// useLocalScope:false DOT-SOURCES the text, so a bare script's param() would BIND IN
    /// THE CALLER'S SCOPE and die "Cannot overwrite variable X because the variable has
    /// been optimized" whenever the calling function/scriptblock has an optimized local of
    /// the same name (lab-proven: Set-DbatoolsPath's $Name/$Scope vs the Register hop's
    /// params). The wrapper block creates a real scope for the param binding while dynamic
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
            // object[]-unpacking (W5-016), then splats positionally into the real scope.
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

    /// <summary>
    /// Streaming invocation over a steppable pipeline — for PS call sites that piped input to
    /// the command at top level, where output must reach the user's pipeline as it is
    /// produced (restore progress objects), not after the command completes.
    /// </summary>
    internal static void InvokeStreamed(PSCmdlet host, string commandName, IDictionary parameters, IEnumerable pipelineInput)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        using (ShieldDefaultParameterValues(host))
        using (PropagateActionPreferences(host))
        {
            using ErrorVariableBridge bridge = new ErrorVariableBridge(host);
            ScriptBlock script = ScriptBlock.Create("param($__parameters) & " + commandName + " @__parameters 3>&1");
            SteppablePipeline pipeline = script.GetSteppablePipeline(CommandOrigin.Internal, new object[] { parameters });
            bool stopped = false;
            try
            {
                pipeline.Begin(true);
                foreach (object? item in pipelineInput)
                {
                    foreach (object output in pipeline.Process(item))
                        ForwardStreamedItem(host, output, bridge.HopEraBaselineHead);
                }
                foreach (object output in pipeline.End())
                    ForwardStreamedItem(host, output, bridge.HopEraBaselineHead);
            }
            catch
            {
                stopped = true;
                try { pipeline.Dispose(); }
                catch { /* the failed pipeline may already be dead; the original error wins */ }
                throw;
            }
            finally
            {
                if (!stopped)
                    pipeline.Dispose();
            }
        }
    }

    /// <summary>
    /// Streamed counterpart of the buffered warning re-emit: merged-back warning records
    /// route through the host's warning stream as they arrive, everything else stays
    /// pipeline output.
    ///
    /// Because they arrive as produced, a warning survives an unwind here that the buffered
    /// path would have discarded - but the unwind itself does NOT reach the caller. The hop
    /// runs in a nested pipeline, so an engine continue/break with no enclosing loop inside
    /// the hop has nowhere to propagate and is absorbed at that boundary: the caller's
    /// post-statement runs where the retired function skipped it. Measured both editions,
    /// A/B'd against the same command running as its retired function. The two invoke shapes
    /// therefore diverge from the function world in opposite directions, and neither is a
    /// superset of the other.
    /// </summary>
    private static void ForwardStreamedItem(PSCmdlet host, object? item, object? hopEraBaselineHead)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        object? unwrapped = item is PSObject psObject ? psObject.BaseObject : item;
        if (unwrapped is WarningRecord warning)
            host.WriteWarning(warning.Message);
        else if (unwrapped is ErrorRecord nonTerminating)
        {
            // Same channel correction as the item-form branches above.
            RemoveHopEraDuplicateError(host, nonTerminating, hopEraBaselineHead);
            host.WriteError(PreserveErrorIdentity(nonTerminating));
        }
        else
            host.WriteObject(item);
    }

    // DEF-001 remedy, copied BYTE-IDENTICAL from dbatools.agent/Commands/NestedCommand.cs@3acfd56
    // (the canonical fixed copy-source) per the fleet-fix directive. Streams hop output to the host
    // as produced instead of buffering, with the W2-030 pipeline-stop guard.
    internal static void InvokeScopedStreaming(
        PSCmdlet host,
        Action<PSObject> onOutput,
        string scriptText,
        params object?[] scriptArgs)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        using (ShieldDefaultParameterValues(host))
        using (PropagateActionPreferences(host))
        {
            using ErrorVariableBridge bridge = new ErrorVariableBridge(host);
            Hashtable termination = new Hashtable { ["ErrorRecord"] = null };
            string terminationMarker = "__dbatoolsNestedTermination_" + Guid.NewGuid().ToString("N");
            using InterruptBeacon interruptBeacon = new InterruptBeacon(host);
            string __seedToken = Guid.NewGuid().ToString("N");
            string wrapper =
                "param($__nestedCommandArguments, $__nestedTermination, $__nestedTerminationMarker, $__nestedInterruptBeacon)\n" + ModuleRootSeedProlog(host, scriptText, __seedToken) + InterruptBeaconSeedProlog(__seedToken) + "try { & {\n" + scriptText +
                "\n} @__nestedCommandArguments 6>&1 5>&1 4>&1 3>&1 2>&1 } catch { " +
                "$__nestedTermination.ErrorRecord = $PSItem; " +
                "Write-Output $__nestedTerminationMarker }" + InterruptBeaconSeedEpilog(__seedToken) + ModuleRootSeedEpilog(__seedToken);

            ErrorRecord? terminatingError = null;
            // Pipeline-stop parity (DEF-001 tail, W2-030): a downstream early stop -
            // e.g. `<cmdlet> | Select-Object -First N` - makes the host's WriteObject throw
            // PipelineStoppedException the instant it has enough. Escaping that from the
            // DataAdded handler killed the child process outright (function world survives).
            // Catch it, BeginStop the nested pipeline (non-blocking - a blocking Stop() from
            // inside the pipeline's own output handler deadlocks) so upstream side effects
            // halt exactly like the function world, then re-throw to the host after Invoke.
            bool downstreamStopped = false;
            using PowerShell nested = PowerShell.Create(RunspaceMode.CurrentRunspace);
            using PSDataCollection<PSObject> output = new PSDataCollection<PSObject>();
            output.DataAdded += (_, eventArgs) =>
            {
                if (downstreamStopped)
                {
                    return;
                }
                PSObject item = output[eventArgs.Index];
                try
                {
                    if (string.Equals(item?.BaseObject as string, terminationMarker, StringComparison.Ordinal))
                    {
                        terminatingError = termination["ErrorRecord"] as ErrorRecord ??
                            throw new InvalidOperationException("Nested command terminated without an ErrorRecord.");
                    }
                    else if (item?.BaseObject is WarningRecord warning)
                    {
                        host.WriteWarning(warning.Message);
                    }
                    else if (item?.BaseObject is VerboseRecord verbose)
                    {
                        host.WriteVerbose(verbose.Message);
                    }
                    else if (item?.BaseObject is DebugRecord debug)
                    {
                        host.WriteDebug(debug.Message);
                    }
                    else if (IsInformationStreamRecord(item?.BaseObject))
                    {
                        RelayInformationStreamRecord(host, item!.BaseObject);
                    }
                    else if (item?.BaseObject is ErrorRecord nonTerminating)
                    {
                        // Same channel correction as the item-form branches above.
                        host.WriteError(PreserveErrorIdentity(nonTerminating));
                    }
                    else
                    {
                        onOutput(item!);
                    }
                }
                catch (PipelineStoppedException)
                {
                    downstreamStopped = true;
                    try
                    {
                        nested.BeginStop(null, null);
                    }
                    catch (PSInvalidOperationException)
                    {
                        // The pipeline may already be past the stoppable state; the re-throw below still unwinds the host.
                    }
                }
            };

            nested.AddScript(wrapper, useLocalScope: false)
                .AddArgument(scriptArgs)
                .AddArgument(termination)
                .AddArgument(terminationMarker)
                .AddArgument(interruptBeacon.State);
            try
            {
                nested.Invoke<PSObject>(null, output, null);
            }
            catch (PipelineStoppedException)
            {
                downstreamStopped = true;
            }

            if (downstreamStopped)
            {
                // Honor the downstream stop on the HOST pipeline - unwinds ProcessRecord
                // exactly like the function world's StopUpstreamCommands.
                throw new PipelineStoppedException();
            }

            if (terminatingError is not null)
            {
                bridge.Complete(terminatingError);
                RemoveCapturedErrorBookkeeping(host, terminatingError);
                host.InvokeCommand.InvokeScript(
                    false,
                    ScriptBlock.Create("param($__record) throw $__record"),
                    null,
                    new object?[] { terminatingError });
                throw new InvalidOperationException("Nested terminating ErrorRecord unexpectedly returned.");
            }
        }
    }

    // The information stream is probed by type NAME and relayed by reflection, never by a
    // typed reference. System.Management.Automation.InformationRecord and Cmdlet.WriteInformation
    // both arrived in PowerShell 5.0 and are absent from the System.Management.Automation 3.0.0.0
    // surface this net472 assembly is compiled against. A typed reference would sit inside the
    // DataAdded handler above, and the CLR jits a method body whole: on a Windows PowerShell 3.0
    // or 4.0 host the FIRST output record of ANY hopped command would fail to jit the handler and
    // throw, whether or not an information record ever appeared. Probing by name keeps every
    // token in this file resolvable on the floor while preserving the PS 5+ relay exactly.
    private static bool IsInformationStreamRecord(object? value)
    {
        for (Type? candidate = value?.GetType(); candidate is not null; candidate = candidate.BaseType)
        {
            if (string.Equals(candidate.FullName, "System.Management.Automation.InformationRecord", StringComparison.Ordinal))
                return true;
        }

        return false;
    }

    private static void RelayInformationStreamRecord(PSCmdlet host, object record)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        MethodInfo? writeInformation = typeof(Cmdlet).GetMethod(
            "WriteInformation",
            new Type[] { typeof(object), typeof(string[]) });
        if (writeInformation is null)
        {
            // No information stream on this engine, so the nested pipeline cannot have merged a
            // record into 6>&1 in the first place. Drop it rather than fail the whole relay.
            return;
        }

        Type recordType = record.GetType();
        object? messageData = recordType.GetProperty("MessageData")?.GetValue(record, null);
        List<string> tags = new List<string>();
        if (recordType.GetProperty("Tags")?.GetValue(record, null) is IEnumerable rawTags)
        {
            foreach (object? tag in rawTags)
            {
                if (tag is string text)
                    tags.Add(text);
            }
        }

        try
        {
            writeInformation.Invoke(host, new object?[] { messageData, tags.ToArray() });
        }
        catch (TargetInvocationException invocation) when (invocation.InnerException is not null)
        {
            // Reflection wraps whatever the real call throws. The caller's stop guard matches
            // PipelineStoppedException by type, so the original has to come back out unwrapped.
            ExceptionDispatchInfo.Capture(invocation.InnerException).Throw();
        }
    }

    private static void RemoveCapturedErrorBookkeeping(PSCmdlet host, ErrorRecord record)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        // ThrowTerminatingError will add the final outer record; de-dup is best effort only.
        // The match rule is shared with every hop cmdlet's RemoveHopErrorBookkeeping.
        RemoveDuplicateError(host, record);
    }
}
