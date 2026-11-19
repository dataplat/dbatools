#nullable enable

using System;
using System.Reflection;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// C1 condition of the prompt-state transplant adjudication (coordinator 2026-07-17
/// 00:20, B concurred): the transplant used by the W3-081/082/090 hop scripts rides the
/// NON-PUBLIC engine field MshCommandRuntime.lastShouldProcessContinueStatus. B proved
/// the silent-rename hazard is real one field away, so the field's resolvability is
/// asserted LOUDLY at first use of every carrying cmdlet - a PS servicing train that
/// renames the field turns into an immediate, attributable failure instead of a silent
/// loss of Yes-to-All/No-to-All persistence.
/// </summary>
internal static class PromptStateTransplant
{
    private static readonly FieldInfo? ResolvedField =
        typeof(PSCmdlet).Assembly
            .GetType("System.Management.Automation.MshCommandRuntime")?
            .GetField("lastShouldProcessContinueStatus", BindingFlags.NonPublic | BindingFlags.Instance);

    /// <summary>Throws loudly when the engine field the transplant depends on cannot be
    /// resolved on this PowerShell engine. Call from BeginProcessing of every carrying
    /// cmdlet so the failure surfaces before any record is processed.</summary>
    internal static void AssertResolvable(string commandName)
    {
        if (ResolvedField is null)
        {
            throw new InvalidOperationException(
                commandName + ": the ShouldProcess prompt-state transplant requires the engine field " +
                "MshCommandRuntime.lastShouldProcessContinueStatus, which could not be resolved on this " +
                "PowerShell engine (" + typeof(PSCmdlet).Assembly.GetName().Version + "). The engine has " +
                "changed; the W3-081/082/090 transplant mechanism must be revalidated before this command " +
                "can run. See migration DEF ledger / coordinator.md 2026-07-17 00:20 (C1).");
        }
    }
}
