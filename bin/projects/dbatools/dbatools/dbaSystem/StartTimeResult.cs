using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Sqlcollaborative.Dbatools.dbaSystem
{
    /// <summary>
    /// The processed result how long a given step took
    /// </summary>
    public class StartTimeResult
    {
        /// <summary>
        /// What action was taken?
        /// </summary>
        public string Action { get; set; }

        /// <summary>
        /// How long did things take?
        /// </summary>
        public TimeSpan Duration
        {
            get { return End - Start; }
        }

        /// <summary>
        /// When did this action start?
        /// </summary>
        public DateTime Start { get; set; }

        /// <summary>
        /// When did this action end?
        /// </summary>
        public DateTime End { get; set; }

        /// <summary>
        /// Creates a new StartTimeResult with all values preconfigured
        /// </summary>
        /// <param name="Action">The action that was taken</param>
        /// <param name="Start">When did the action start?</param>
        /// <param name="End">When did the action end?</param>
        public StartTimeResult(string Action, DateTime Start, DateTime End)
        {
            this.Action = Action;
            this.Start = Start;
            this.End = End;
        }
    }
}
