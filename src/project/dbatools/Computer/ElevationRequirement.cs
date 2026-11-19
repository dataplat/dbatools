using System.Management.Automation;
using System.Security.Principal;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Computer
{
    /// <summary>
    /// Native value of private/functions/flowcontrol/Test-ElevationRequirement.ps1: whether the
    /// console meets the elevation a command needs for the given computer. The caller owns the
    /// Stop-Function side of the helper (its message is <see cref="NotElevatedMessage"/>), so the
    /// attribution, -Continue choice and EnableException handling stay at the command's call site.
    /// </summary>
    public static class ElevationRequirement
    {
        /// <summary>The message Test-ElevationRequirement passes to Stop-Function.</summary>
        public const string NotElevatedMessage = "Console not elevated, but elevation is required to perform some actions on localhost for this command.";

        /// <summary>
        /// False only when the computer is the local host and the console is not elevated;
        /// commands.test-elevationrequirement.disable turns the check off.
        /// </summary>
        /// <param name="computer">The computer the command is about to work on.</param>
        /// <returns>True when the command may proceed.</returns>
        public static bool IsSatisfied(DbaInstanceParameter computer)
        {
            Config config;
            if (ConfigurationHost.Configurations.TryGetValue("commands.test-elevationrequirement.disable", out config) && config != null && config.Value != null && LanguagePrimitives.IsTrue(config.Value))
                return true;

            if (computer == null || !computer.IsLocalHost)
                return true;

#pragma warning disable CA1416 // WindowsPrincipal: the PS helper reads the same Windows identity
            bool isElevated = new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
#pragma warning restore CA1416
            return isElevated;
        }
    }
}
