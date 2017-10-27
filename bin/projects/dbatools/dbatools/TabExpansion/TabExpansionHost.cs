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

        /// <summary>
        /// A list of all commands imported into dbatools
        /// </summary>
        public static List<FunctionInfo> DbatoolsCommands = new List<FunctionInfo>();

        /// <summary>
        /// List of completion sets that should be processed into Tepp Assignments. Only populate this list on first import.
        /// </summary>
        public static List<TabCompletionSet> TabCompletionSets = new List<TabCompletionSet>();

        /// <summary>
        /// Maps a TEPP scriptblock to a command and parameter
        /// </summary>
        public static Dictionary<string, Dictionary<string, ScriptContainer>> TeppAssignment = new Dictionary<string, Dictionary<string, ScriptContainer>>();
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

        /// <summary>
        /// Returns the assigned scriptblock for a given parameter
        /// </summary>
        /// <param name="Command">The command that should be completed</param>
        /// <param name="Parameter">The parameter completion is provided for</param>
        /// <returns>Either the relevant script container or null</returns>
        public static ScriptContainer GetTeppScript(string Command, string Parameter)
        {
            if (TeppAssignment.ContainsKey(Command) && TeppAssignment[Command].ContainsKey(Parameter))
                return TeppAssignment[Command][Parameter];
            return null;
        }

        /// <summary>
        /// Assigns a registered script to the parameter of a command
        /// </summary>
        /// <param name="Command">The command for which to complete</param>
        /// <param name="Parameter">The parameter for which to complete</param>
        /// <param name="Script">To name of the script with which to complete</param>
        public static void SetTeppScript(string Command, string Parameter, string Script)
        {
            if (!Scripts.ContainsKey(Script))
                return;

            if (!TeppAssignment.ContainsKey(Command))
                TeppAssignment[Command] = new Dictionary<string, ScriptContainer>();

            TeppAssignment[Command][Parameter] = Scripts[Script];
        }

        /// <summary>
        /// Adds a completion set to the list of items to process
        /// </summary>
        /// <param name="Command">The command to complete for (accepts wildcard matching)</param>
        /// <param name="Parameter">The parameter to complete for (accepts wildcard matching)</param>
        /// <param name="Script">The script to register</param>
        public static void AddTabCompletionSet(string Command, string Parameter, string Script)
        {
            // Only import on the first import
            if (!dbaSystem.SystemHost.ModuleImported)
                TabCompletionSets.Add(new TabCompletionSet(Command, Parameter, Script));
        }

        /// <summary>
        /// Processes the content of TabCompletionSets and Scripts into TappAssignments based on the DbatoolsCommands list.
        /// </summary>
        public static void CalculateTabExpansion()
        {
            foreach (FunctionInfo info in DbatoolsCommands)
                foreach (ParameterMetadata paramInfo in info.Parameters.Values)
                    foreach (TabCompletionSet set in TabCompletionSets)
                        if (set.Applies(info.Name, paramInfo.Name))
                            SetTeppScript(info.Name, paramInfo.Name, set.Script);
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