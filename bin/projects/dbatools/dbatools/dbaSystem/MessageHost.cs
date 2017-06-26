using System;

namespace Sqlcollaborative.Dbatools.dbaSystem
{
    /// <summary>
    /// Provides static resources to the messaging subsystem
    /// </summary>
    public static class MessageHost
    {
        #region Defines
        /// <summary>
        /// The maximum message level to still display to the user directly.
        /// </summary>
        public static int MaximumInformation = 3;

        /// <summary>
        /// The maxium message level where verbose information is still written.
        /// </summary>
        public static int MaximumVerbose = 6;

        /// <summary>
        /// The maximum message level where debug information is still written.
        /// </summary>
        public static int MaximumDebug = 9;

        /// <summary>
        /// The minimum required message level for messages that will be shown to the user.
        /// </summary>
        public static int MinimumInformation = 1;

        /// <summary>
        /// The minimum required message level where verbose information is written.
        /// </summary>
        public static int MinimumVerbose = 4;

        /// <summary>
        /// The minimum required message level where debug information is written.
        /// </summary>
        public static int MinimumDebug = 1;

        /// <summary>
        /// The color stuff gets written to the console in
        /// </summary>
        public static ConsoleColor InfoColor = ConsoleColor.Cyan;

        /// <summary>
        /// The color stuff gets written to the console in, when developer mode is enabled and the message would not have been written after all
        /// </summary>
        public static ConsoleColor DeveloperColor = ConsoleColor.Gray;
        #endregion Defines
    }
}