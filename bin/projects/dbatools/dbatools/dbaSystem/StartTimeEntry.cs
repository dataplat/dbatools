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
        /// Creates a new StartTimeEntry
        /// </summary>
        /// <param name="Action">The action that has been taken</param>
        /// <param name="Timestamp">When was the action taken?</param>
        public StartTimeEntry(string Action, DateTime Timestamp)
        {
            this.Action = Action;
            this.Timestamp = Timestamp;
        }
    }
}
