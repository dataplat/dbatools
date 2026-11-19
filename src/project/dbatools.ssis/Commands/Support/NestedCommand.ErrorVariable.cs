#nullable enable

using System;
using System.Collections;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

internal static partial class NestedCommand
{
    /// <summary>
    /// DEF-013 residual: Stop-Function's non-EnableException path emits its error records as
    /// `$null = Write-Error ... 2&gt;&amp;1` — bookkeeping-only by design (the dbatools source
    /// comment says the point is that "the error is stored in the $error variable"). Such a
    /// record never rides ANY stream, so the merge-and-forward branches cannot see it; its only
    /// footprint is the engine's error bookkeeping, which in the function world also fed the
    /// caller's -ErrorVariable. The hop boundary severs that link (measured on W2-186
    /// Set-DbaDbSchema: legacy errVar=9, compiled errVar=0, warnings equal). This bridge
    /// restores it: snapshot the shared $Error head before the hop, then reconcile the bound
    /// -ErrorVariable list with the hop-era records afterwards. Records are appended directly —
    /// NOT via WriteError — because the function world never displays or preference-processes
    /// these records either; their only caller-visible effect is variable capture, and $Error
    /// itself is already correct (the hop shares the runspace).
    /// Completion is guaranteed by `using` (Dispose completes if no explicit call ran), so
    /// downstream pipeline stops, iterator disposal, and forwarding exceptions still capture
    /// what the hop bookkept — matching the function world's live capture-before-unwind.
    /// Terminating-path bridging is limited to the marker-based paths, where the terminating
    /// record is known and skippable; the dominant DEF-013 mechanism (Stop-Function -Continue
    /// loops) is nonterminating by construction.
    /// Disclosed bound: a single hop that bookkeeps MORE records than $MaximumErrorCount evicts
    /// its own oldest entries from the capped $Error before completion runs, and those evicted
    /// records cannot be bridged (the function world's variable is uncapped). ArrayList exposes
    /// no change notification, so capture is at-completion by construction; the pre-bridge
    /// behavior for every such record was total loss.
    /// </summary>
    private sealed class ErrorVariableBridge : IDisposable
    {
        private readonly ArrayList? _globalError;
        private readonly object? _baselineHead;
        private readonly ArrayList? _target;
        private readonly int _targetBaseline;
        private bool _completed;

        internal ErrorVariableBridge(PSCmdlet host)
        {
            _globalError = host.SessionState.PSVariable.GetValue("Error") as ArrayList;
            // Identity, not Count: $Error is capped at $MaximumErrorCount, and once full the
            // engine trims the tail as it inserts at the head, leaving Count unchanged. The
            // hop-era region is therefore "entries newer than the pre-hop head entry", found
            // by reference — a Count delta would read 0 on a saturated list.
            _baselineHead = _globalError is { Count: > 0 } ? _globalError[0] : null;
            _target = ResolveBoundErrorVariable(host);
            // With `-ErrorVariable +name` the list already holds PRE-hop captures; only the
            // invocation-era tail past this boundary belongs to this hop's reconciliation.
            _targetBaseline = _target?.Count ?? 0;
        }

        /// <summary>
        /// The pre-hop $error head used to bound this bridge's hop-era region.
        /// </summary>
        internal object? HopEraBaselineHead => _baselineHead;

        public void Dispose()
        {
            Complete(null);
        }

        private static ArrayList? ResolveBoundErrorVariable(PSCmdlet host)
        {
            Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
            if (!host.MyInvocation.BoundParameters.TryGetValue("ErrorVariable", out object? value))
                return null;
            if (value is not string name || name.Length == 0)
                return null;
            // The engine strips exactly ONE leading '+' (the append marker) when it creates
            // the capture list; any further '+' characters are part of the variable name.
            if (name[0] == '+')
                name = name.Substring(1);
            if (name.Length == 0)
                return null;
            return host.SessionState.PSVariable.GetValue(name) as ArrayList;
        }

        internal void Complete(ErrorRecord? terminatingError)
        {
            if (_completed)
                return;
            _completed = true;
            try
            {
                if (_target is null || _globalError is null)
                    return;
                // Aliased target (`-ErrorVariable +Error` style): the list IS the engine's
                // bookkeeping — every hop-era record is already present exactly once, and
                // reconciling would mutate the source under itself. Nothing to bridge.
                if (ReferenceEquals(_target, _globalError))
                    return;
                // $Error is newest-first; hop-era entries run from index 0 down to (but not
                // including) the pre-hop head. A missing head means the hop pushed the entire
                // baseline off the capped list — then everything present is hop-era.
                int added = _globalError.Count;
                if (_baselineHead is not null)
                {
                    for (int i = 0; i < _globalError.Count; i++)
                    {
                        if (ReferenceEquals(_globalError[i], _baselineHead))
                        {
                            added = i;
                            break;
                        }
                    }
                }
                if (added <= 0)
                    return;
                int skipIndex = FindTerminatingIndex(added, terminatingError);
                // Snapshot the hop-era run oldest-first BEFORE mutating the target, so no
                // aliasing shape can pull entries out from under the walk.
                ArrayList hopEra = new ArrayList();
                for (int i = Math.Min(added, _globalError.Count) - 1; i >= 0; i--)
                {
                    if (i == skipIndex)
                        continue;
                    if (Unwrap(_globalError[i]) is ErrorRecord record)
                        hopEra.Add(record);
                }
                // Reconcile the hop-era run as ONE ordered sequence: within this bridge's
                // scope, everything the engine appended past the pre-hop boundary was a
                // stream-forwarded hop record, so that tail — and ONLY that tail — is replaced
                // by the full hop-era run. Pre-hop entries (`+name` append mode) and their
                // multiplicity are untouched, and mixed silent/forwarded emissions keep their
                // emission order in the variable.
                int tailStart = Math.Min(_targetBaseline, _target.Count);
                if (_target.Count > tailStart)
                    _target.RemoveRange(tailStart, _target.Count - tailStart);
                for (int i = 0; i < hopEra.Count; i++)
                    _target.Add(hopEra[i]);
            }
            catch
            {
                // Bridging is bookkeeping parity only; it must never break the invocation.
            }
        }

        /// <summary>
        /// Locates the single hop-era entry standing in for the terminating record — that one
        /// reaches the variable through the engine's own ThrowTerminatingError handling after
        /// the re-throw, so bridging it too would double it. Exactly ONE occurrence is skipped:
        /// a reference match wins; otherwise the newest exception match stands in (the catch
        /// clause bookkept the same record instance it handed to the marker, but a distinct
        /// sibling record legitimately sharing the exception — the Stop-Function catch-time +
        /// `-ErrorRecord` re-write pair — must NOT be swallowed with it).
        /// </summary>
        private int FindTerminatingIndex(int added, ErrorRecord? terminatingError)
        {
            if (terminatingError is null || _globalError is null)
                return -1;
            int exceptionMatch = -1;
            for (int i = 0; i < added && i < _globalError.Count; i++)
            {
                if (Unwrap(_globalError[i]) is not ErrorRecord record)
                    continue;
                if (ReferenceEquals(record, terminatingError))
                    return i;
                if (exceptionMatch < 0 && ReferenceEquals(record.Exception, terminatingError.Exception))
                    exceptionMatch = i;
            }
            return exceptionMatch;
        }

        private static object? Unwrap(object? entry)
        {
            return entry is PSObject wrapped ? wrapped.BaseObject : entry;
        }
    }
}
