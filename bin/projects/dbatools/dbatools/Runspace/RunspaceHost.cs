using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Sqlcollaborative.Dbatools.Runspace
{
    /// <summary>
    /// Provides hosting for all registered runspaces
    /// </summary>
    public static class RunspaceHost
    {
        /// <summary>
        /// The number of seconds before a Stop command is interrupted and instead the runspace is gracelessly shut down.
        /// </summary>
        public static int StopTimeoutSeconds = 30;

        /// <summary>
        /// The dictionary containing the definitive list of unique Runspace
        /// </summary>
        public static Dictionary<string, RunspaceContainer> Runspaces = new Dictionary<string, RunspaceContainer>();
    }
}
