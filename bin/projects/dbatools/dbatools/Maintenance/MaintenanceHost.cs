using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Sqlcollaborative.Dbatools.Maintenance
{
    /// <summary>
    /// Host class providing access to resources need to perform dbatools maintenance
    /// </summary>
    public static class MaintenanceHost
    {
        /// <summary>
        /// The register of available tasks.
        /// </summary>
        public static Dictionary<string, MaintenanceTask> Tasks = new Dictionary<string, MaintenanceTask>();

        /// <summary>
        /// Whether there are any due tasks
        /// </summary>
        public static bool HasDueTasks
        {
            get
            {
                foreach (MaintenanceTask task in Tasks.Values)
                    if (task.IsDue)
                        return true;

                return false;
            }
        }

        /// <summary>
        /// Returns the next task to perform. Returns null when there are no more tasks to perform
        /// </summary>
        /// <param name="Exclusions">List of tasks not to return, even if they are ready to execute again. This avoids one misconfigured task starving all lower priority tasks</param>
        /// <returns>The next task to perform.</returns>
        public static MaintenanceTask GetNextTask(string[] Exclusions)
        {
            MaintenanceTask tempTask = null;

            foreach (MaintenanceTask task in Tasks.Values)
                if (task.IsDue && (!Exclusions.Contains(task.Name)) && ((tempTask == null) || (task.Priority > tempTask.Priority)))
                    tempTask = task;

            return tempTask;
        }
    }
}
