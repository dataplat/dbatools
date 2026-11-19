using System;
using System.IO;
using System.Reflection;

namespace Dataplat.Dbatools.dbaSystem
{
    /// <summary>
    /// private/functions/Add-PbmLibrary.ps1 parity: loads the Policy-Based Management (DMF)
    /// assemblies from the dbatools.library lib folder, Common first then Dmf, exactly like
    /// the PS helper's two Add-Type calls. Failures propagate as the load exception - the
    /// caller owns the "Could not load DMF libraries" Stop-Function semantics, mirroring the
    /// PS helper's catch block (its callers: the seven public PBM/policy-migration commands).
    /// </summary>
    public static class DmfLibrary
    {
        /// <summary>
        /// Loads Microsoft.SqlServer.Dmf.Common then Microsoft.SqlServer.Dmf from
        /// &lt;libraryRoot&gt;\lib. Idempotent: re-invoking with the same assemblies already
        /// loaded returns them without error, like re-running Add-Type -Path in PS.
        /// </summary>
        /// <param name="libraryRoot">The dbatools.library module root (the PS helper's $script:libraryroot)</param>
        public static void Load(string libraryRoot)
        {
            if (String.IsNullOrEmpty(libraryRoot))
                throw new ArgumentNullException("libraryRoot");

            string platformLib = Path.Combine(libraryRoot, "lib");
            // PS load order (helper lines 9-10): Dmf.Common.DLL before Dmf.dll
            Assembly.LoadFrom(Path.Combine(platformLib, "Microsoft.SqlServer.Dmf.Common.DLL"));
            Assembly.LoadFrom(Path.Combine(platformLib, "Microsoft.SqlServer.Dmf.dll"));
        }
    }
}
