using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation.Runspaces;
using System.Text;
using System.Threading.Tasks;

namespace Sqlcollaborative.Dbatools.Connection
{
    /// <summary>
    /// The container that lists all sessions for a given runspace
    /// </summary>
    public class PSSessionContainer
    {
        /// <summary>
        /// The runspace that owns the sessions
        /// </summary>
        public readonly Guid Runspace;

        /// <summary>
        /// The count of expired sessions registered
        /// </summary>
        public int CountExpired { get { return GetExpiredNames().Count; } }

        /// <summary>
        /// List of sessions and their associated computer names
        /// </summary>
        public Dictionary<string, PSSession> Sessions = new Dictionary<string, PSSession>();

        /// <summary>
        /// List of timestamps, when the last command was run against them
        /// </summary>
        public Dictionary<string, DateTime> ConnectionTimestamps = new Dictionary<string, DateTime>();

        /// <summary>
        /// Creates a list of sessions the current runspace is connected to.
        /// </summary>
        /// <param name="Runspace">The Guid of the runspace that is the owner of the registered sessions</param>
        public PSSessionContainer(Guid Runspace)
        {
            this.Runspace = Runspace;
        }

        /// <summary>
        /// Returns the requested session.
        /// </summary>
        /// <param name="ComputerName">The name of the host whose connection to retrieve</param>
        /// <returns>The established connection to the host, null if none exists.</returns>
        public PSSession Get(string ComputerName)
        {
            if (Sessions.ContainsKey(ComputerName.ToLower()))
                return Sessions[ComputerName.ToLower()];
            return null;
        }

        /// <summary>
        /// Sets a session and writes its timestamp to the cache
        /// </summary>
        /// <param name="ComputerName">The hostname it connects to.</param>
        /// <param name="Session">The session that is being registered.</param>
        public void Set(string ComputerName, PSSession Session)
        {
            if (!ConnectionHost.PSSessionCacheEnabled)
                return;
            Sessions[ComputerName.ToLower()] = Session;
            ConnectionTimestamps[ComputerName.ToLower()] = DateTime.Now;
        }

        /// <summary>
        /// Returns the name of hostnames with expired sessions
        /// </summary>
        /// <returns>THe hostnames whose session has expired</returns>
        public List<string> GetExpiredNames()
        {
            List<string> expired = new List<string>();

            foreach (string key in ConnectionTimestamps.Keys)
                if (ConnectionTimestamps[key] + ConnectionHost.PSSessionTimeout < DateTime.Now && Sessions[key] != null && Sessions[key].Availability != RunspaceAvailability.Busy)
                    expired.Add(key);

            return expired;
        }

        /// <summary>
        /// Removes an expired session from the cache, an returns it, so it can be properly closed.
        /// </summary>
        /// <returns>Returns a session to disconnect</returns>
        public PSSession PurgeExpiredSession()
        {
            foreach (string key in ConnectionTimestamps.Keys)
            {
                if (ConnectionTimestamps[key] + ConnectionHost.PSSessionTimeout < DateTime.Now && Sessions[key] != null && Sessions[key].Availability != RunspaceAvailability.Busy)
                {
                    PSSession session = Sessions[key];
                    Sessions.Remove(key);
                    ConnectionTimestamps.Remove(key);
                    return session;
                }
            }
            return null;
        }
    }
}
