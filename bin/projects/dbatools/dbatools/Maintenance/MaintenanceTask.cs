using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Text;
using System.Threading.Tasks;

namespace Sqlcollaborative.Dbatools.Maintenance
{
    /// <summary>
    /// An individual task assigned to the maintenance engine
    /// </summary>
    public class MaintenanceTask
    {
        /// <summary>
        /// The name of the task to execute. No duplciates are possible.
        /// </summary>
        public string Name;

        /// <summary>
        /// Whether the task should be done once only
        /// </summary>
        public bool Once;

        /// <summary>
        /// The interval at which the task should be performed
        /// </summary>
        public TimeSpan Interval = new TimeSpan(0);

        /// <summary>
        /// If the task need not be performed right away, it can be delayed, in order to prioritize more important initialization tasks
        /// </summary>
        public TimeSpan Delay = new TimeSpan(0);

        /// <summary>
        /// When was the task first registered. Duplicate registration calls will not increment this value.
        /// </summary>
        public DateTime Registered;

        /// <summary>
        /// When was the task last executed.
        /// </summary>
        public DateTime LastExecution;

        /// <summary>
        /// How important is this task?
        /// </summary>
        public MaintenancePriority Priority;

        /// <summary>
        /// The task code to execute
        /// </summary>
        public ScriptBlock ScriptBlock;

        /// <summary>
        /// Whether the task is due and should be executed
        /// </summary>
        public bool IsDue
        {
            get
            {
                if (Once && (LastExecution > Registered))
                    return false;

                if ((Delay.Ticks > 0) && ((Registered.Add(Delay)) > DateTime.Now))
                    return false;

                if ((LastExecution.Add(Interval)) > DateTime.Now)
                    return false;

                return true;
            }
        }
    }
}
