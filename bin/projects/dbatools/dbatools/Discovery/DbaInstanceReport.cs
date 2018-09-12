using System;

namespace Sqlcollaborative.Dbatools.Discovery
{
    /// <summary>
    /// The report on a discovered instance
    /// </summary>
    [Serializable]
    public class DbaInstanceReport
    {
        /// <summary>
        /// The computername of the underlying machine. Usually equal to the computername, but may differ in case of clusters
        /// </summary>
        public string MachineName { get; set; }

        /// <summary>
        /// The computername of the target
        /// </summary>
        public string ComputerName { get; set; }

        /// <summary>
        /// The name of the instance
        /// </summary>
        public string InstanceName { get; set; }

        /// <summary>
        /// The full server instance name
        /// </summary>
        public string FullName
        {
            get
            {
                if (!String.IsNullOrEmpty(InstanceName) && !Utility.UtilityHost.IsLike(InstanceName, "MSSQLSERVER"))
                    return String.Format(@"{0}\{1}", ComputerName, InstanceName);
                else if ((Port == 1433) || (Utility.UtilityHost.IsLike(InstanceName, "MSSQLSERVER")))
                    return ComputerName;
                else
                    return String.Format(@"{0}:{1}", ComputerName, Port);
            }
            set { }
        }

        /// <summary>
        /// The full name usable to connect via SMO
        /// </summary>
        public string SqlInstance
        {
            get
            {
                if (!String.IsNullOrEmpty(InstanceName) && !Utility.UtilityHost.IsLike(InstanceName, "MSSQLSERVER"))
                    return String.Format(@"{0}\{1}", ComputerName, InstanceName);
                else if ((Port == 1433) || (Utility.UtilityHost.IsLike(InstanceName, "MSSQLSERVER")))
                    return ComputerName;
                else
                    return String.Format(@"{0},{1}", ComputerName, Port);
            }
            set { }
        }

        /// <summary>
        /// The port number the server listens on
        /// </summary>
        public int Port { get; set; }

        /// <summary>
        /// When the scan was concluded
        /// </summary>
        public DateTime Timestamp;

        /// <summary>
        /// Was a TCP connect successful?
        /// </summary>
        public bool TcpConnected { get; set; }

        /// <summary>
        /// Was a connection via SQL successful (even if we got access denied)
        /// </summary>
        public bool SqlConnected { get; set; }
    
        /// <summary>
        /// The DNS Resolution object
        /// </summary>
        public System.Net.IPHostEntry DnsResolution { get; set; }

        /// <summary>
        /// The ping resolution object
        /// </summary>
        public bool Ping { get; set; }

        /// <summary>
        /// The reply received from the browse request
        /// </summary>
        public DbaBrowserReply BrowseReply { get; set; }

        /// <summary>
        /// The windows services for the instance
        /// </summary>
        public object[] Services { get; set; }

        /// <summary>
        /// The SQL Server services that do not belong to that instance alone
        /// </summary>
        public object[] SystemServices { get; set; }

        /// <summary>
        /// Service Principal Names found
        /// </summary>
        public string[] SPNs { get; set; }

        /// <summary>
        /// The ports that have been scanned
        /// </summary>
        public DbaPortReport[] PortsScanned { get; set; }
    

        /// <summary>
        /// What we know about its availability
        /// </summary>
        public DbaInstanceAvailability Availability { get; set; }

        /// <summary>
        /// How confident we are, that this is a real instance
        /// </summary>
        public DbaInstanceConfidenceLevel Confidence { get; set; }

        /// <summary>
        /// What we used to scan the instance
        /// </summary>
        public DbaInstanceScanType ScanTypes { get; set; }
    }
}
