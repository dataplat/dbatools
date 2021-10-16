using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Sqlcollaborative.Dbatools.Maintenance
{
    /// <summary>
    /// How high the priority of the task. Higher priority tasks take precedence over low priority tasks.
    /// </summary>
    public enum MaintenancePriority
    {
        /// <summary>
        /// This task is completely trivial and can be done whenever there is some spare time for it
        /// </summary>
        Trivial = 1,

        /// <summary>
        /// The task is not very significant, but should be dealt with at some point
        /// </summary>
        Low = 2,

        /// <summary>
        /// Average priority task
        /// </summary>
        Medium = 4,

        /// <summary>
        /// An important task that will take precedence over most other tasks
        /// </summary>
        High = 8,

        /// <summary>
        /// A task so critical, that it should be considered to move it to synchronous execution instead.
        /// </summary>
        Critical = 16
    }
}
