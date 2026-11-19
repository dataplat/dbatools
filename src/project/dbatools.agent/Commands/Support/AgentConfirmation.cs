#nullable enable

using System;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

internal static class AgentConfirmation
{
    internal static bool WithConfirmationSuppressed(SessionState sessionState, Func<bool> shouldProcess)
    {
        // Binary cmdlets share the caller's preference scope, unlike advanced functions.
        object? previousPreference = sessionState.PSVariable.GetValue("ConfirmPreference");
        try
        {
            sessionState.PSVariable.Set("ConfirmPreference", ConfirmImpact.None);
            return shouldProcess();
        }
        finally
        {
            sessionState.PSVariable.Set("ConfirmPreference", previousPreference);
        }
    }
}
