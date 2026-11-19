#nullable enable

using System;
using System.Management.Automation;
using System.Reflection;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Reproduces Stop-Function -Continue for call sites where the PS `continue` had NO
/// enclosing loop inside the function itself: PowerShell's dynamically scoped continue
/// crosses the function boundary and continues the CALLER's nearest loop (or silently ends
/// a loop-less calling script). A compiled cmdlet reproduces that by throwing the engine's
/// own ContinueException, which the pipeline machinery propagates as flow control instead
/// of wrapping it as a cmdlet error. Lab-proven on both editions (2026-07-12 probe-az2 P6:
/// a test cmdlet throwing the reflected exception makes the calling foreach skip the rest
/// of its iteration, byte-identical to the function path; the InvokeScript("continue")
/// fallback behaves the same).
/// </summary>
internal static class CallerFlow
{
    /// <summary>Throws the engine's flow-control 'continue' toward the caller's nearest loop. Never returns.</summary>
    internal static void Continue(PSCmdlet host)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        Type? continueType = typeof(PSCmdlet).Assembly.GetType("System.Management.Automation.ContinueException");
        if (continueType != null)
        {
            foreach (ConstructorInfo ctor in continueType.GetConstructors(BindingFlags.NonPublic | BindingFlags.Public | BindingFlags.Instance))
            {
                ParameterInfo[] ctorParams = ctor.GetParameters();
                if (ctorParams.Length == 0)
                    throw (Exception)ctor.Invoke(null);
                if (ctorParams.Length == 1 && ctorParams[0].ParameterType == typeof(string))
                    throw (Exception)ctor.Invoke(new object[] { "" });
            }
        }

        // Fallback when the engine type or a usable constructor is missing: a nested
        // script-level `continue` propagates identically (lab-proven both editions).
        host.InvokeCommand.InvokeScript("continue");
    }
}
