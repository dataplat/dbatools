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
/// Runs module-scoped PowerShell compatibility hops through the invoking cmdlet's runspace.
/// The empty PSDefaultParameterValues shield preserves the scope boundary of retired dbatools
/// functions, and merged warnings are re-emitted through the compiled cmdlet's own channel.
/// </summary>
internal static partial class NestedCommand
{
    internal static IDisposable? ShieldDefaultParameterValues(PSCmdlet host)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        object? effective = host.SessionState.PSVariable.GetValue("PSDefaultParameterValues");
        if (effective is null)
            return null;

        host.SessionState.PSVariable.Set(
            "PSDefaultParameterValues",
            new DefaultParameterDictionary());
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

    internal static IEnumerable<PSObject> InvokeScoped(
        PSCmdlet host,
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
            ScriptBlock script = ScriptBlock.Create(
                "param($__nestedCommandArguments, $__nestedTermination, $__nestedTerminationMarker, $__nestedInterruptBeacon)\n" + ModuleRootSeedProlog(host, scriptText, __seedToken) + InterruptBeaconSeedProlog(__seedToken) + "try { & {\n" + scriptText +
                "\n} @__nestedCommandArguments } catch { " +
                "$__nestedTermination.ErrorRecord = $PSItem; " +
                "Write-Output $__nestedTerminationMarker }" + InterruptBeaconSeedEpilog(__seedToken) + ModuleRootSeedEpilog(__seedToken));
            Collection<PSObject> raw = host.InvokeCommand.InvokeScript(
                false,
                script,
                null,
                new object?[] { scriptArgs, termination, terminationMarker, interruptBeacon.State });
            foreach (PSObject item in raw)
            {
                if (string.Equals(item?.BaseObject as string, terminationMarker, StringComparison.Ordinal))
                {
                    if (termination["ErrorRecord"] is not ErrorRecord terminatingError)
                        throw new InvalidOperationException("Nested command terminated without an ErrorRecord.");
                    bridge.Complete(terminatingError);
                    RemoveCapturedErrorBookkeeping(host, terminatingError);
                    host.InvokeCommand.InvokeScript(
                        false,
                        ScriptBlock.Create("param($__record) throw $__record"),
                        null,
                        new object?[] { terminatingError });
                    throw new InvalidOperationException("Nested terminating ErrorRecord unexpectedly returned.");
                }
                else if (item?.BaseObject is WarningRecord warning)
                    host.WriteWarning(warning.Message);
                else if (item?.BaseObject is ErrorRecord nonTerminating)
                    // Re-emit through the cmdlet's own error channel: the engine then applies
                    // -ErrorVariable capture and caller-side preference handling, which the
                    // function world gets for free (measured: -ErrorVariable collected 3 records
                    // from the function and 0 from the hop before this forwarding existed).
                    host.WriteError(PreserveErrorIdentity(nonTerminating));
                else
                    yield return item!;
            }
        }
    }

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
                        // Same forwarding as the non-streaming path: merged nonterminating
                        // errors must ride the cmdlet's error channel, not the output pipeline,
                        // so -ErrorVariable and caller-side handling see them.
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
