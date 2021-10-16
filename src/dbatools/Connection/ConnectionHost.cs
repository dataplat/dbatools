using System;
using System.Collections.Generic;
using System.Management.Automation.Runspaces;

namespace Sqlcollaborative.Dbatools.Connection
{
    /// <summary>
    /// Provides static tools for managing connections
    /// </summary>
    public static class ConnectionHost
    {
        /// <summary>
        /// List of all registered connections.
        /// </summary>
        public static Dictionary<string, ManagementConnection> Connections = new Dictionary<string, ManagementConnection>();

        #region Configuration Computer Management
        /// <summary>
        /// The time interval that must pass, before a connection using a known to not work connection protocol is reattempted
        /// </summary>
        public static TimeSpan BadConnectionTimeout = new TimeSpan(0, 15, 0);

        /// <summary>
        /// Globally disables all caching done by the Computer Management functions.
        /// </summary>
        public static bool DisableCache = false;

        /// <summary>
        /// Disables the caching of bad credentials. dbatools caches bad logon credentials for wmi/cim and will not reuse them.
        /// </summary>
        public static bool DisableBadCredentialCache = false;

        /// <summary>
        /// Disables the automatic registration of working credentials. dbatools will caches the last working credential when connecting using wmi/cim and will use those rather than using known bad credentials
        /// </summary>
        public static bool DisableCredentialAutoRegister = false;

        /// <summary>
        /// Enabling this will force the use of the last credentials known to work, rather than even trying explicit credentials.
        /// </summary>
        public static bool OverrideExplicitCredential = false;

        /// <summary>
        /// Enables automatic failover to working credentials, when passed credentials either are known, or turn out to not work.
        /// </summary>
        public static bool EnableCredentialFailover = false;

        /// <summary>
        /// Globally disables the persistence of Cim sessions used to connect to a target system.
        /// </summary>
        public static bool DisableCimPersistence = false;

        /// <summary>
        /// Whether the CM connection using Cim over WinRM is disabled globally
        /// </summary>
        public static bool DisableConnectionCimRM = false;

        /// <summary>
        /// Whether the CM connection using Cim over DCOM is disabled globally
        /// </summary>
        public static bool DisableConnectionCimDCOM = false;

        /// <summary>
        /// Whether the CM connection using WMI is disabled globally
        /// </summary>
        public static bool DisableConnectionWMI = true;

        /// <summary>
        /// Whether the CM connection using PowerShell Remoting is disabled globally
        /// </summary>
        public static bool DisableConnectionPowerShellRemoting = true;
        #endregion Configuration Computer Management

        #region Configuration Sql Connection
        /// <summary>
        /// The number of seconds before a sql connection attempt times out
        /// </summary>
        public static int SqlConnectionTimeout = 15;
        #endregion Configuration Sql Connection

        #region PowerShell remoting sessions
        /// <summary>
        /// List of all session containers used to maintain a cache
        /// </summary>
        public static Dictionary<Guid, PSSessionContainer> PSSessions = new Dictionary<Guid, PSSessionContainer>();

        #region Public operations
        /// <summary>
        /// Returns a registered session for a given computer on a given runspace. Returns null if nothing is registered.
        /// </summary>
        /// <param name="Runspace">The host runspace that opened the session</param>
        /// <param name="ComputerName">The computer connected to</param>
        /// <returns></returns>
        public static PSSession PSSessionGet(Guid Runspace, string ComputerName)
        {
            if (!PSSessions.ContainsKey(Runspace))
                return null;

            return PSSessions[Runspace].Get(ComputerName.ToLower());
        }

        /// <summary>
        /// Registeres a remote session under the owning runspace in its respective computer name
        /// </summary>
        /// <param name="Runspace">The runspace that owns the session</param>
        /// <param name="ComputerName">The computer the session connects to</param>
        /// <param name="Session">The session object</param>
        public static void PSSessionSet(Guid Runspace, string ComputerName, PSSession Session)
        {
            if (!PSSessionCacheEnabled)
                return;

            if (!PSSessions.ContainsKey(Runspace))
                PSSessions[Runspace] = new PSSessionContainer(Runspace);

            PSSessions[Runspace].Set(ComputerName.ToLower(), Session);
        }

        /// <summary>
        /// Searches the cache for an expired remoting session and purges it. After purging it from the list, it still needs to be closed!
        /// </summary>
        /// <returns>The session purged that then needs to be closed</returns>
        public static PSSession PSSessionPurgeExpired()
        {
            foreach (PSSessionContainer container in PSSessions.Values)
                if (container.CountExpired > 0)
                    return container.PurgeExpiredSession();

            return null;
        }

        /// <summary>
        /// The number of expired sessions 
        /// </summary>
        public static int PSSessionCountExpired
        {
            get
            {
                int num = 0;

                foreach (PSSessionContainer container in PSSessions.Values)
                    num += container.CountExpired;

                return num;
            }
        }
        #endregion Public operations

        #region Configuration
        /// <summary>
        /// The time until established connections will be considered expired (if available)
        /// </summary>
        public static TimeSpan PSSessionTimeout = new TimeSpan(0, 5, 0);

        /// <summary>
        /// Whether sessions should be cached at all
        /// </summary>
        public static bool PSSessionCacheEnabled = true;
        #endregion Configuration
        #endregion PowerShell remoting sessions
    }
}