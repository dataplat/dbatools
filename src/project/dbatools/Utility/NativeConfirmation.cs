using System;
using System.Management.Automation;

namespace Dataplat.Dbatools.Utility
{
    /// <summary>
    /// Runs a ShouldProcess decision with automatic confirmation temporarily suppressed.
    /// </summary>
    public static class NativeConfirmation
    {
        /// <summary>
        /// Restores the caller's confirmation preference even if ShouldProcess throws.
        /// </summary>
        public static bool WithConfirmationSuppressed(SessionState sessionState, Func<bool> shouldProcess)
        {
            object previousPreference = sessionState.PSVariable.GetValue("ConfirmPreference");
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
}
