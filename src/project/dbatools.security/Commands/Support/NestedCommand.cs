#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Runtime.ExceptionServices;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Invokes dbatools PowerShell commands and module-scoped script bodies from inside a compiled
/// cmdlet, reproducing the scope and stream behavior a PowerShell function had around its own
/// internal calls.
/// </summary>
/// <remarks>
/// Commands are named by fixed literals at every call site; no caller input reaches the script
/// text. Name resolution picks up whichever implementation is live, so a command that exists as
/// either a script function or a compiled cmdlet behaves identically through this entry point.
/// </remarks>
internal static partial class NestedCommand
{
    /// <summary>
    /// Replaces the effective $PSDefaultParameterValues with an empty table for the duration of a
    /// nested invocation, returning a handle that restores the original on disposal.
    /// </summary>
    /// <param name="host">The cmdlet whose session state supplies the variable.</param>
    /// <returns>A disposable that restores the caller's table, or null when none is defined.</returns>
    /// <remarks>
    /// A PowerShell function's nested command calls resolved $PSDefaultParameterValues through the
    /// module scope chain, where none is defined - so neither a caller-local nor a global default
    /// ever reached them. Invoking a script from a cmdlet chains to the CALLER's scope instead, so
    /// without this shield a caller-local default such as '*-Dba*:WarningVariable' would re-bind on
    /// every nested call and re-initialize the very variable the outer command is capturing into,
    /// discarding it. An empty table, not the global one, is the faithful reproduction.
    /// </remarks>
    internal static IDisposable? ShieldDefaultParameterValues(PSCmdlet host)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        object? effective = host.SessionState.PSVariable.GetValue("PSDefaultParameterValues");
        if (effective is null)
            return null;
        host.SessionState.PSVariable.Set("PSDefaultParameterValues", new System.Management.Automation.DefaultParameterDictionary());
        return new DefaultParameterRestore(host, effective);
    }

    /// <summary>Restores a saved $PSDefaultParameterValues table when disposed.</summary>
    private sealed class DefaultParameterRestore : IDisposable
    {
        private readonly PSCmdlet _host;
        private readonly object _saved;

        /// <summary>Captures the table to restore.</summary>
        /// <param name="host">The cmdlet whose session state holds the variable.</param>
        /// <param name="saved">The table to put back on disposal.</param>
        internal DefaultParameterRestore(PSCmdlet host, object saved)
        {
            _host = host;
            _saved = saved;
        }

        /// <summary>Puts the caller's original table back.</summary>
        public void Dispose()
        {
            _host.SessionState.PSVariable.Set("PSDefaultParameterValues", _saved);
        }
    }

    /// <summary>
    /// Invokes a named command and returns its output once the command has completed.
    /// </summary>
    /// <param name="host">The calling cmdlet.</param>
    /// <param name="commandName">A fixed literal command name.</param>
    /// <param name="parameters">Parameters to splat; null-valued keys bind, matching splat semantics.</param>
    /// <param name="pipelineInput">Optional input to pipe into the command.</param>
    /// <returns>The command's output with warning records removed.</returns>
    /// <remarks>
    /// For call sites that assigned the output to a variable or discarded it, where nothing depends
    /// on output arriving before the command finishes. Warnings are merged back and re-emitted
    /// through the HOST cmdlet's warning stream: an inner function's warnings bubbled through the
    /// outer function's runtime, so a caller's -WarningVariable captured them alongside the outer
    /// command's own. A script invoked from a cmdlet bypasses the host runtime, so without this
    /// merge those records would never reach the caller's variable.
    /// </remarks>
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
    /// Runs a script - typically a module-scoped hop that reaches private functions - and returns
    /// its output once the script has completed.
    /// </summary>
    /// <param name="host">The calling cmdlet.</param>
    /// <param name="scriptText">The script to run.</param>
    /// <param name="scriptArgs">Arguments splatted positionally into the script.</param>
    /// <returns>The script's output with warning records removed.</returns>
    /// <remarks>
    /// Merged warning records re-emit through the host's warning stream for -WarningVariable
    /// parity. Engine flow control raised by a helper (a continue or break that PowerShell
    /// try/catch cannot intercept) and terminating errors propagate to the caller, but nothing
    /// this invocation already produced survives that unwind: InvokeScript hands back its
    /// Collection only on normal completion, so a guard that warns and then unwinds loses its
    /// warning and the caller's statement dies with no diagnostic at all. Measured both
    /// editions, A/B'd against the same command running as its retired function. A guard at hop
    /// top level (outside any loop) is the shape that hits this; inside a loop the continue
    /// binds to that loop and never reaches the boundary. Contrast InvokeScopedStreaming, which
    /// keeps the warning and loses the flow control instead.
    /// The script is wrapped in an "&amp; { ... } @args" block because the invocation dot-sources
    /// the text: a bare script's param() would bind IN THE CALLER'S SCOPE and fail with "Cannot
    /// overwrite variable X because the variable has been optimized" whenever the calling function
    /// has an optimized local of the same name. The wrapper block creates a real scope for the
    /// param binding while dynamic reads such as preference variables still resolve through the
    /// caller. The argument array travels as a SINGLE element so that null elements survive the
    /// object[] unpacking the invocation performs, then splats positionally into the real scope.
    /// </remarks>
    internal static Collection<PSObject> InvokeScoped(PSCmdlet host, string scriptText, params object?[] scriptArgs)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        using (ShieldDefaultParameterValues(host))
        using (PropagateActionPreferences(host))
        {
            using ErrorVariableBridge bridge = new ErrorVariableBridge(host);
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
    /// Runs a script - typically a module-scoped hop - and forwards its output through the supplied
    /// callback as each object is produced, rather than buffering it until the script completes.
    /// </summary>
    /// <param name="host">The calling cmdlet.</param>
    /// <param name="onOutput">Receives each success-stream object as it is produced.</param>
    /// <param name="scriptText">The script to run.</param>
    /// <param name="scriptArgs">Arguments splatted positionally into the script.</param>
    /// <remarks>
    /// For hop bodies that emit output before a later record can terminate the run. Buffering the
    /// whole collection would discard everything already produced once the script throws, so output
    /// streams out as it arrives and a terminating error is captured and re-raised only after the
    /// earlier output has left. Warning, verbose, debug, and information records re-emit through the
    /// host's matching streams for -WarningVariable and preference parity; every other object goes to
    /// the callback. The argument array travels as a SINGLE element so null elements survive the
    /// object[] unpacking, then splats positionally into the wrapper's real scope. A terminating
    /// failure is carried out as a marker object so the buffered collection is never the sole record
    /// of it, then re-thrown in the caller's scope to propagate exactly as the script raised it. A
    /// downstream early stop (a consumer taking only the first N objects) is caught, stops the nested
    /// pipeline, and re-throws to the host so upstream side effects halt exactly as they do for the script.
    /// </remarks>
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
            // Pipeline-stop parity: a downstream early stop - e.g. `<command> | Select-Object -First N` -
            // makes the host's WriteObject throw PipelineStoppedException the instant it has enough.
            // Letting that escape the DataAdded handler kills the child process outright, where the
            // script implementation survives. Catch it, BeginStop the nested pipeline (non-blocking - a
            // blocking Stop() from inside the pipeline's own output handler deadlocks) so upstream side
            // effects halt exactly as they do for the script, then re-throw to the host after Invoke.
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
                // Honor the downstream stop on the HOST pipeline - unwinds ProcessRecord exactly as the
                // script implementation's StopUpstreamCommands does.
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

    /// <summary>
    /// Removes the ErrorRecord a nested terminating failure left at the head of the automatic $Error
    /// list, so the caller's own ThrowTerminatingError does not record the same failure twice.
    /// </summary>
    /// <param name="host">The cmdlet whose session state holds $Error.</param>
    /// <param name="record">The terminating record captured from the nested run.</param>
    private static void RemoveCapturedErrorBookkeeping(PSCmdlet host, ErrorRecord record)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        // ThrowTerminatingError will add the final outer record; de-dup is best effort only.
        // The match rule is shared with every hop cmdlet's RemoveHopErrorBookkeeping.
        RemoveDuplicateError(host, record);
    }

    /// <summary>
    /// Invokes a named command over a steppable pipeline, forwarding output as it is produced.
    /// </summary>
    /// <param name="host">The calling cmdlet.</param>
    /// <param name="commandName">A fixed literal command name.</param>
    /// <param name="parameters">Parameters to splat into the command.</param>
    /// <param name="pipelineInput">Input fed to the command one item at a time.</param>
    /// <remarks>
    /// For call sites that piped input to the command at top level, where output must reach the
    /// user's pipeline as it is produced - progress objects, for instance - rather than after the
    /// command completes.
    /// </remarks>
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
    /// Routes one streamed item: warning records go to the host's warning stream, everything else
    /// stays pipeline output.
    /// </summary>
    /// <param name="host">The calling cmdlet.</param>
    /// <param name="item">The item produced by the pipeline.</param>
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
}
