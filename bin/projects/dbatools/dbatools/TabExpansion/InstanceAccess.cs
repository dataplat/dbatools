using System;

namespace Sqlcollaborative.Dbatools.TabExpansion
{
    /// <summary>
    /// Contains information on access to an instance
    /// </summary>
    public class InstanceAccess
    {
        /// <summary>
        /// The name of the instance to access
        /// </summary>
        public string InstanceName;

        /// <summary>
        /// Whether the account had sysadmin privileges. On multiple user usage, the cache will prefer sysadmin accounts.
        /// </summary>
        public bool IsSysAdmin;

        /// <summary>
        /// The actual connection object to connect with to the server
        /// </summary>
        public object ConnectionObject;

        /// <summary>
        /// When was the instance last accessed using dbatools
        /// </summary>
        public DateTime LastAccess;

        /// <summary>
        /// When was the instance's TEPP cache last updated
        /// </summary>
        public DateTime LastUpdate = new DateTime(1, 1, 1, 0, 0, 0);
    }
}