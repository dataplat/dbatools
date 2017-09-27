using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Sqlcollaborative.Dbatools.dbaSystem
{
    /// <summary>
    /// Provides system-wide static resources regarding the dbatools system runtime in general
    /// </summary>
    public static class SystemHost
    {
        /// <summary>
        /// When this is set to true, functions must assume dbatools is in unattended mode. May not ask for user input of any kind.
        /// </summary>
        public static bool UnattendedMode = false;
    }
}
