using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Sqlcollaborative.Dbatools.Computer
{
    /// <summary>
    /// What kind of drive are you?
    /// </summary>
    public enum DriveType
    {
        /// <summary>
        /// The drive type is not actually known
        /// </summary>
        Unknown = 0,

        /// <summary>
        /// The drive has no root directory
        /// </summary>
        NoRootDirectory = 1,

        /// <summary>
        /// The drive is a removable disk
        /// </summary>
        RemovableDisk = 2,

        /// <summary>
        /// The drive is a local disk
        /// </summary>
        LocalDisk = 3,

        /// <summary>
        /// The drive is a network drive
        /// </summary>
        NetworkDrive = 4,

        /// <summary>
        /// The drive is a compact disk
        /// </summary>
        CompactDisk = 5,

        /// <summary>
        /// The drive is a RAM disk
        /// </summary>
        RAMDisk = 6,
    }
}
