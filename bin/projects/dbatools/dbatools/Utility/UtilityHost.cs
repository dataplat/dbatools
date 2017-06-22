using System;

namespace Sqlcollaborative.Dbatools
{
    namespace Utility
    {
        /// <summary>
        /// Provides static resources to utility-namespaced stuff
        /// </summary>
        public static class UtilityHost
        {
            /// <summary>
            /// Restores all DateTime objects to their default display behavior
            /// </summary>
            public static bool DisableCustomDateTime = false;

            /// <summary>
            /// Restores all timespan objects to their default display behavior.
            /// </summary>
            public static bool DisableCustomTimeSpan = false;

            /// <summary>
            /// Formating string for date-style datetime objects.
            /// </summary>
            public static string FormatDate = "dd MMM yyyy";

            /// <summary>
            /// Formating string for datetime-style datetime objects
            /// </summary>
            public static string FormatDateTime = "yyyy-MM-dd HH:mm:ss.fff";

            /// <summary>
            /// Formating string for time-style datetime objects
            /// </summary>
            public static string FormatTime = "HH:mm:ss";

            /// <summary>
            /// The Version of the dbatools Library. Used to compare with import script to determine out-of-date libraries
            /// </summary>
            public readonly static Version LibraryVersion = new Version(0, 6, 0, 13);
        }
    }
}