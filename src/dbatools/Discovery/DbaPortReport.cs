using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Sqlcollaborative.Dbatools.Discovery
{
    /// <summary>
    /// We tried to connect to a port, how did it go?
    /// </summary>
    [Serializable]
    public class DbaPortReport
    {
        /// <summary>
        /// The name of the computer connected to
        /// </summary>
        public string ComputerName;

        /// <summary>
        /// The number of the port we tried to connect to.
        /// </summary>
        public int Port;

        /// <summary>
        /// Whether the port was open
        /// </summary>
        public bool IsOpen;

        /// <summary>
        /// Creates an empty report (serialization uses this)
        /// </summary>
        public DbaPortReport()
        {

        }

        /// <summary>
        /// Creates a filled in report
        /// </summary>
        /// <param name="ComputerName">The name of the computer connected to</param>
        /// <param name="Port">The port we tried to connect to</param>
        /// <param name="IsOpen">Whether things worked out</param>
        public DbaPortReport(string ComputerName, int Port, bool IsOpen)
        {
            this.ComputerName = ComputerName;
            this.Port = Port;
            this.IsOpen = IsOpen;
        }

        /// <summary>
        /// Displays port connection reports in a user friendly manner
        /// </summary>
        /// <returns></returns>
        public override string ToString()
        {
            return String.Format("{0}:{1} - {2}", ComputerName, Port, IsOpen);
        }
    }
}
