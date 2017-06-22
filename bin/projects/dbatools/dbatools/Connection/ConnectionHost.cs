using System;
using System.Collections.Generic;

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

        #region Configuration
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
        #endregion Configuration
    }
}