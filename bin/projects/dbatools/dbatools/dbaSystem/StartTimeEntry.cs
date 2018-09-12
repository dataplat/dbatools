using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Sqlcollaborative.Dbatools.dbaSystem
{
    /// <summary>
    /// Entry containing the information of a step during the import sequence
    /// </summary>
    public class StartTimeEntry
    {
        /// <summary>
        /// The action that has been taken
        /// </summary>
        public string Action { get; set; }

        /// <summary>
        /// When was the action taken?
        /// </summary>
        public DateTime Timestamp { get; set; }

        /// <summary>
        /// The runspace the entry was written on
        /// </summary>
        public Guid Runspace;

        /// <summary>
        /// Creates a new StartTimeEntry
        /// </summary>
        /// <param name="Action">The action that has been taken</param>
        /// <param name="Timestamp">When was the action taken?</param>
        /// <param name="Runspace">The runspace the entry was written on</param>
        public StartTimeEntry(string Action, DateTime Timestamp, Guid Runspace)
        {
            this.Action = Action;
            this.Timestamp = Timestamp;
            this.Runspace = Runspace;
        }
    }
}
