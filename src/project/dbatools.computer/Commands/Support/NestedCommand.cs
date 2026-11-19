#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;

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
/// VERBATIM COPY of project/dbatools.core/Commands/Support/NestedCommand.cs (W5-022): the class is
/// internal per-assembly and the shared dbatools project is pinned to LangVersion 7.3, so promoting
/// it there means an owner LangVersion/style decision - OWNER HAND-BACK, keep the copies in sync.
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
                    // Re-emit through the cmdlet's own error channel so -ErrorVariable capture
                    // and caller-side preference handling see them, as the function world does.
                    host.WriteError(PreserveErrorIdentity(nonTerminating));
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
                        ForwardStreamedItem(host, output);
                }
                foreach (object output in pipeline.End())
                    ForwardStreamedItem(host, output);
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
    private static void ForwardStreamedItem(PSCmdlet host, object? item)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        object? unwrapped = item is PSObject psObject ? psObject.BaseObject : item;
        if (unwrapped is WarningRecord warning)
            host.WriteWarning(warning.Message);
        else if (unwrapped is ErrorRecord nonTerminating)
            // Same channel correction as the item-form branches above.
            host.WriteError(PreserveErrorIdentity(nonTerminating));
        else
            host.WriteObject(item);
    }
}
