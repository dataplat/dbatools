using System;
using System.Collections;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;

namespace Sqlcollaborative.Dbatools.TabExpansion
{
    /// <summary>
    /// Class that handles the static fields supporting the dbatools TabExpansion implementation
    /// </summary>
    public static class TabExpansionHost
    {
        #region State information
        /// <summary>
        /// Field containing the scripts that were registered.
        /// </summary>
        public static ConcurrentDictionary<string, ScriptContainer> Scripts = new ConcurrentDictionary<string, ScriptContainer>();

        /// <summary>
        /// The cache used by scripts utilizing TabExpansionPlusPlus in dbatools
        /// </summary>
        public static Hashtable Cache = new Hashtable();

        /// <summary>
        /// List of instances and when they were last accessed
        /// </summary>
        public static ConcurrentDictionary<string, InstanceAccess> InstanceAccess = new ConcurrentDictionary<string, InstanceAccess>();

        /// <summary>
        /// Scripts that build the cache and are suitable for synchronous execution
        /// </summary>
        public static List<ScriptBlock> TeppGatherScriptsFast = new List<ScriptBlock>();

        /// <summary>
        /// Scripts that build the cache and are not suitable for synchronous execution
        /// </summary>
        public static List<ScriptBlock> TeppGatherScriptsSlow = new List<ScriptBlock>();
        #endregion State information

        #region Utility methods
        /// <summary>
        /// Registers a new instance or updates an already existing one. Should only be called from Connect-SqlInstance and Connect-DbaSqlServer
        /// </summary>
        /// <param name="InstanceName">Name of the instance connected to</param>
        /// <param name="Connection">To connection object containing the relevant information for accessing the instance</param>
        /// <param name="IsSysAdmin">Whether the account connecting to the instnace has SA privileges</param>
        public static void SetInstance(string InstanceName, object Connection, bool IsSysAdmin)
        {
            string tempName = InstanceName.ToLower();

            if (!InstanceAccess.ContainsKey(tempName))
            {
                InstanceAccess tempAccess = new InstanceAccess();
                tempAccess.InstanceName = tempName;
                tempAccess.LastAccess = DateTime.Now;
                tempAccess.ConnectionObject = Connection;
                tempAccess.IsSysAdmin = IsSysAdmin;
                InstanceAccess[tempName] = tempAccess;
            }
            else
            {
                InstanceAccess[tempName].LastAccess = DateTime.Now;

                if (IsSysAdmin & !InstanceAccess[tempName].IsSysAdmin)
                {
                    InstanceAccess[tempName].ConnectionObject = Connection;
                    InstanceAccess[tempName].IsSysAdmin = IsSysAdmin;
                }
            }
        }
        #endregion Utility methods

        #region Configuration
        /// <summary>
        /// Whether TEPP in its entirety is disabled
        /// </summary>
        public static bool TeppDisabled = false;

        /// <summary>
        /// Whether asynchronous TEPP updating should be disabled
        /// </summary>
        public static bool TeppAsyncDisabled = false;

        /// <summary>
        /// Whether synchronous TEPP updating should be disabled
        /// </summary>
        public static bool TeppSyncDisabled = true;

        /// <summary>
        /// The interval in which asynchronous TEPP cache updates are performed
        /// </summary>
        public static TimeSpan TeppUpdateInterval = new TimeSpan(0, 3, 0);

        /// <summary>
        /// After this timespan of no requests to a server, the updates to its cache are disabled.
        /// </summary>
        public static TimeSpan TeppUpdateTimeout = new TimeSpan(0, 0, 30);
        #endregion Configuration
    }
}