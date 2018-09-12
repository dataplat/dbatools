using System;

namespace Sqlcollaborative.Dbatools.Discovery
{
    /// <summary>
    /// What discovery mechanisms to use
    /// </summary>
    [Flags]
    public enum DbaInstanceDiscoveryType
    {
        /// <summary>
        /// We shall sweep the network for instances, by targeting every IP within a range.
        /// </summary>
        IPRange = 1,

        /// <summary>
        /// We shall search for SQL SPNs in active directory
        /// </summary>
        Domain = 2,

        /// <summary>
        /// We shall use the SSMS Data Sizrce Enumeration mechanism and hope for the best
        /// </summary>
        DataSourceEnumeration = 4,

        /// <summary>
        /// We shall use all tools in our control to find stuff
        /// </summary>
        All = 7
    }
}
