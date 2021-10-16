using System;

namespace Sqlcollaborative.Dbatools.Connection
{
    /// <summary>
    /// The various ways to connect to a windows server fopr management purposes.
    /// </summary>
    [Flags]
    public enum ManagementConnectionType
    {
        /// <summary>
        /// No Connection-Type
        /// </summary>
        None = 0,

        /// <summary>
        /// Cim over a WinRM connection
        /// </summary>
        CimRM = 1,

        /// <summary>
        /// Cim over a DCOM connection
        /// </summary>
        CimDCOM = 2,

        /// <summary>
        /// WMI Connection
        /// </summary>
        Wmi = 4,

        /// <summary>
        /// Connecting with PowerShell remoting and performing WMI queries locally
        /// </summary>
        PowerShellRemoting = 8
    }
}