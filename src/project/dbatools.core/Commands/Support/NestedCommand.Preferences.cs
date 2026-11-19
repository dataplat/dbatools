#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

internal static partial class NestedCommand
{
    // Action-preference common parameters bound on the cmdlet must govern the hop body the way
    // they govern a function body: the engine translates -WarningAction into a function-local
    // $WarningPreference, but a compiled cmdlet gets engine-level handling only, so the nested
    // scriptblock inherited the AMBIENT preferences instead. Measured divergences (E's
    // W2-161/165/169 suite): -WarningAction SilentlyContinue suppressed a source-internal warning
    // in the function world but not in the hop, and -ErrorAction Stop terminated inside the
    // source's try/catch in the function world but outside it in the hop. Setting the preference
    // variables for the invocation window (same save/restore shape as the shield above) restores
    // function-scope semantics; only EXPLICITLY BOUND preferences propagate - unbound ones keep
    // inheriting the ambient values, exactly like a function call would.
    private static readonly (string ParameterName, string PreferenceVariable)[] ActionPreferenceMap =
    {
        ("ErrorAction", "ErrorActionPreference"),
        // WarningAction is CONVERTING-VALUES-ONLY (see the filter in PropagateActionPreferences):
        // the function world is PATH-DEPENDENT for its non-converting values (measured
        // 2026-07-19: with -WarningAction SilentlyContinue the function world CAPTURES
        // Stop-Function connect warnings on New-DbaDbUser yet SUPPRESSES them on
        // Remove-DbaDbRoleMember - no uniform in-scope preference matches both, and blanket
        // propagation regressed a sealed suite; suppression/display already round-trips through
        // the merge + host re-emission). The Stop value has no such
        // ambiguity: the function-local Warning-to-terminating conversion must fire inside the
        // body for its own try/catch to see it (lane G's control-flow measurement), so those
        // propagate.
        ("WarningAction", "WarningPreference"),
        ("InformationAction", "InformationPreference"),
        ("ProgressAction", "ProgressPreference"),
    };

    internal static IDisposable? PropagateActionPreferences(PSCmdlet host)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        List<(string Name, object? Saved)>? saved = null;
        foreach ((string parameterName, string preferenceVariable) in ActionPreferenceMap)
        {
            if (!host.MyInvocation.BoundParameters.TryGetValue(parameterName, out object? bound) || bound is null)
                continue;
            // Stop is the only propagated WarningAction value: in-body conversion terminates
            // before anything can merge, so it cannot double-fire. Inquire is excluded - an
            // in-body prompt whose Continue answer lets the warning merge out would prompt a
            // SECOND time at the host boundary, unlike the function path; Inquire keeps the
            // pre-existing single host-side prompt instead.
            if (parameterName == "WarningAction" &&
                bound is ActionPreference warningValue &&
                warningValue != ActionPreference.Stop)
                continue;
            saved ??= new List<(string, object?)>();
            saved.Add((preferenceVariable, host.SessionState.PSVariable.GetValue(preferenceVariable)));
            host.SessionState.PSVariable.Set(preferenceVariable, bound);
        }
        return saved is null ? null : new ActionPreferenceRestore(host, saved);
    }

    private sealed class ActionPreferenceRestore : IDisposable
    {
        private readonly PSCmdlet _host;
        private readonly List<(string Name, object? Saved)> _saved;

        internal ActionPreferenceRestore(PSCmdlet host, List<(string Name, object? Saved)> saved)
        {
            _host = host;
            _saved = saved;
        }

        public void Dispose()
        {
            foreach ((string name, object? value) in _saved)
            {
                _host.SessionState.PSVariable.Set(name, value);
            }
        }
    }
}
