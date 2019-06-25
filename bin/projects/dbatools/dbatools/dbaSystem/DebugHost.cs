using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Management.Automation;

namespace Sqlcollaborative.Dbatools.dbaSystem
{
    /// <summary>
    /// Hosts static debugging values and methods
    /// </summary>
    public static class DebugHost
    {
        #region Start Times
        /// <summary>
        /// Lists the duration for the last import of dbatools.
        /// </summary>
        public static List<StartTimeEntry> ImportTimeEntries = new List<StartTimeEntry>();

        /// <summary>
        /// Returns the calculated time each phase took during the last import of dbatool.
        /// </summary>
        public static List<StartTimeResult> ImportTime
        {
            get
            {
                List<StartTimeResult> result = new List<StartTimeResult>();
                int n = 0;
                foreach (StartTimeEntry entry in ImportTimeEntries)
                    if (n++ > 0)
                        result.Add(new StartTimeResult(entry.Action, ImportTimeEntries[n - 2].Timestamp, entry.Timestamp));

                return result;
            }
        }
        #endregion Start Times
    }
}