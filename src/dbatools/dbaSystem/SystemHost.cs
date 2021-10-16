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

        /// <summary>
        /// Path where the module was located when imported
        /// </summary>
        public static string ModuleBase
        {
            get { return _ModuleBase; }
            set
            {
                if (String.IsNullOrEmpty(_ModuleBase))
                    _ModuleBase = value;
            }
        }
        private static string _ModuleBase;

        /// <summary>
        /// Flag whether the module has ever been imported in the current process. If that is true, several things (such as importing libraries) is no longer necessary and will be skipped on import.
        /// </summary>
        public static bool ModuleImported;
    }
}
