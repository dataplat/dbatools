using System;

namespace Sqlcollaborative.Dbatools.Discovery
{
    /// <summary>
    /// The reply the browser service gave
    /// </summary>
    [Serializable]
    public class DbaBrowserReply
    {
        /// <summary>
        /// The machine name of the computer
        /// </summary>
        public string MachineName { get; set; }

        /// <summary>
        /// the computername of the computer
        /// </summary>
        public string ComputerName { get; set; }

        /// <summary>
        /// The instance running on the computer
        /// </summary>
        public string SqlInstance { get; set; }

        /// <summary>
        /// The name of the instance, running on the computer
        /// </summary>
        public string InstanceName { get; set; }

        /// <summary>
        /// The port number the instance is running under
        /// </summary>
        public int TCPPort { get; set; }

        /// <summary>
        /// The version of the SQL Server
        /// </summary>
        public string Version { get; set; }

        /// <summary>
        /// Whether the instance is part of a cluster or no.
        /// </summary>
        public bool IsClustered { get; set; }

        /// <summary>
        /// Override in order to make it look neater in PowerShell
        /// </summary>
        /// <returns></returns>
        public override string ToString()
        {
            return SqlInstance;
        }
    }
}
