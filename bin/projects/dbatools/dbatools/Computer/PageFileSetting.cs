using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Sqlcollaborative.Dbatools.Computer
{
    /// <summary>
    /// Data container, listing pagefile settings.
    /// </summary>
    [Serializable]
    public class PageFileSetting
    {
        /// <summary>
        /// The name of the computer
        /// </summary>
        public string ComputerName;

        /// <summary>
        /// Whether Automatic PageFile management is enabled
        /// </summary>
        public bool AutoPageFile;

        /// <summary>
        /// The pagefile name
        /// </summary>
        public string FileName;

        /// <summary>
        /// The pagefile status
        /// </summary>
        public string Status;

        /// <summary>
        /// Whether the pagefile is system managed
        /// </summary>
        public Nullable<Boolean> SystemManaged;

        /// <summary>
        /// When were the settings last changed
        /// </summary>
        public Nullable<DateTime> LastModified;

        /// <summary>
        /// When were the settings last accessed
        /// </summary>
        public Nullable<DateTime> LastAccessed;

        /// <summary>
        /// The base allocated pagefile size in MB
        /// </summary>
        public Nullable<int> AllocatedBaseSize;

        /// <summary>
        /// The initial pagefile size in MB
        /// </summary>
        public Nullable<int> InitialSize;

        /// <summary>
        /// The maximum pagefile size in MB
        /// </summary>
        public Nullable<int> MaximumSize;

        /// <summary>
        /// The maximum percent of the pagefile limit that has been used
        /// </summary>
        public Nullable<int> PeakUsage;

        /// <summary>
        /// The currently used percentage of the pagefile limit that is in use.
        /// </summary>
        public Nullable<int> CurrentUsage;
    }
}
