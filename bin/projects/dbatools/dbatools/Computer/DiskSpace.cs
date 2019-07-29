using Sqlcollaborative.Dbatools.Utility;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Sqlcollaborative.Dbatools.Computer
{
    /// <summary>
    /// Data Container for the output of Get-DbaDiskSpace
    /// </summary>
    public class DiskSpace
    {
        /// <summary>
        /// The computer that was scanned
        /// </summary>
        public string ComputerName { get; set; }

        /// <summary>
        /// Name of the disk
        /// </summary>
        public string Name { get; set; }

        /// <summary>
        /// Label of the disk
        /// </summary>
        public string Label { get; set; }

        /// <summary>
        /// What's the total capacity of the disk?
        /// </summary>
        public Size Capacity { get; set; }

        /// <summary>
        /// How much is still free?
        /// </summary>
        public Size Free { get; set; }

        /// <summary>
        /// How much is still free
        /// </summary>
        public double PercentFree
        {
            get
            {
                return Math.Round((double)((double)Free.Byte / (double)Capacity.Byte * 100), 2);
            }
        }

        /// <summary>
        /// What blocksize is the object set to
        /// </summary>
        public int BlockSize { get; set; }

        /// <summary>
        /// What filesystem is installed on the system
        /// </summary>
        public string FileSystem { get; set; }

        /// <summary>
        /// What kind of drive is it?
        /// </summary>
        public DriveType Type { get; set; }

        /// <summary>
        /// Whether the drive is a sql disk. Nullable, because it is an optional property and may not always be included, thus a third state is necessary.
        /// </summary>
        public Nullable<bool> IsSqlDisk { get; set; }

        #region Legacy Properties
        /// <summary>
        /// The computer that was scanned. Legacy-Name
        /// </summary>
        public string Server
        {
            get { return ComputerName; }
        }

        /// <summary>
        /// The type of drive this is in the legacy string notation
        /// </summary>
        public string DriveType
        {
            get
            {
                switch (Type)
                {
                    case Computer.DriveType.Unknown:
                        return "Unknown";
                    case Computer.DriveType.NoRootDirectory:
                        return "No Root Directory";
                    case Computer.DriveType.RemovableDisk:
                        return "Removable Disk";
                    case Computer.DriveType.LocalDisk:
                        return "Local Disk";
                    case Computer.DriveType.NetworkDrive:
                        return "Network Drive";
                    case Computer.DriveType.CompactDisk:
                        return "Compact Disk";
                    case Computer.DriveType.RAMDisk:
                        return "RAM Disk";
                    default:
                        return "Unknown";
                }
            }
        }

        /// <summary>
        /// The total capacity in Bytes
        /// </summary>
        public double SizeInBytes
        {
            get
            {
                return Capacity.Byte;
            }
        }

        /// <summary>
        /// The free space in Bytes
        /// </summary>
        public double FreeInBytes
        {
            get
            {
                return Free.Byte;
            }
        }

        /// <summary>
        /// The total capacity in KB
        /// </summary>
        public double SizeInKB
        {
            get
            {
                return Math.Round(Capacity.Kilobyte, 2);
            }
        }

        /// <summary>
        /// The free space in KB
        /// </summary>
        public double FreeInKB
        {
            get
            {
                return Math.Round(Free.Kilobyte, 2);
            }
        }

        /// <summary>
        /// The total capacity in MB
        /// </summary>
        public double SizeInMB
        {
            get
            {
                return Math.Round(Capacity.Megabyte, 2);
            }
        }

        /// <summary>
        /// The free space in MB
        /// </summary>
        public double FreeInMB
        {
            get
            {
                return Math.Round(Free.Megabyte, 2);
            }
        }

        /// <summary>
        /// The total capacity in GB
        /// </summary>
        public double SizeInGB
        {
            get
            {
                return Math.Round(Capacity.Gigabyte, 2);
            }
        }

        /// <summary>
        /// The free space in GB
        /// </summary>
        public double FreeInGB
        {
            get
            {
                return Math.Round(Free.Gigabyte, 2);
            }
        }

        /// <summary>
        /// The total capacity in TB
        /// </summary>
        public double SizeInTB
        {
            get
            {
                return Math.Round(Capacity.Terabyte, 2);
            }
        }

        /// <summary>
        /// The free space in TB
        /// </summary>
        public double FreeInTB
        {
            get
            {
                return Math.Round(Free.Terabyte, 2);
            }
        }

        /// <summary>
        /// The total capacity in PB
        /// </summary>
        public double SizeInPB
        {
            get
            {
                return Math.Round(Capacity.Terabyte / 1024, 2);
            }
        }

        /// <summary>
        /// The free space in PB
        /// </summary>
        public double FreeInPB
        {
            get
            {
                return Math.Round(Free.Terabyte / 1024, 2);
            }
        }
        #endregion Legacy Properties
    }
}
