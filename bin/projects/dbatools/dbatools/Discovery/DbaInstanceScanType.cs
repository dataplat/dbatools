using System;

namespace Sqlcollaborative.Dbatools.Discovery
{
    /// <summary>
    /// The mechanisms we use to determine, whether a given host contains a legit instance
    /// </summary>
    [Flags]
    public enum DbaInstanceScanType
    {
        /// <summary>
        /// Try connecting to specific ports
        /// </summary>
        TCPPort = 1,

        /// <summary>
        /// Try to connect to discovered instances (improves confidence)
        /// </summary>
        SqlConnect = 2,

        /// <summary>
        /// Check the windows services on the target
        /// </summary>
        SqlService = 4,

        /// <summary>
        /// Try resolving a computername in DNS
        /// </summary>
        DNSResolve = 8,

        /// <summary>
        /// Scan the SPNs for the targeted computer
        /// </summary>
        SPN = 16,

        /// <summary>
        /// Try contacting the local browser service and demand answers
        /// </summary>
        Browser = 32,

        /// <summary>
        /// See whether you can ping the host
        /// </summary>
        Ping = 64,

        /// <summary>
        /// Do EVERYTHING
        /// </summary>
        All = 127,

        /// <summary>
        /// Do all the things we consider sane defaults
        /// </summary>
        Default = 125,
    }
}
