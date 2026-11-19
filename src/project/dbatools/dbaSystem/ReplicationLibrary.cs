using System;
using System.IO;
using System.Reflection;

namespace Dataplat.Dbatools.dbaSystem
{
    /// <summary>
    /// private/functions/Add-ReplicationLibrary.ps1 parity: loads the RMO replication
    /// assemblies from the dbatools.library lib folder, Rmo first then Replication,
    /// exactly like the PS helper's two Add-Type calls (helper lines 10-11 - note the
    /// helper declares $repdll before $rmodll but LOADS Rmo first). Failures propagate
    /// as the load exception - the caller owns the helper's catch semantics, which are
    /// Stop-Function WITHOUT an ErrorRecord and with the verbatim message "Could not
    /// load replication libraries. Replication is very challenging to support. We
    /// recommend running theses commands from a machine that does not have SQL Server
    /// installed." (the "theses" typo is source-verbatim; message changes are surface
    /// decisions). The PS helper resolves its own root via Get-DbatoolsLibraryPath into
    /// $script:libraryroot; the port takes the resolved root as a parameter because
    /// compiled callers own their own resolution context, like DmfLibrary.
    /// </summary>
    public static class ReplicationLibrary
    {
        /// <summary>
        /// Loads Microsoft.SqlServer.Rmo then Microsoft.SqlServer.Replication from
        /// &lt;libraryRoot&gt;\lib. Idempotent: re-invoking with the same assemblies
        /// already loaded returns them without error, like re-running Add-Type -Path.
        /// </summary>
        /// <param name="libraryRoot">The dbatools.library module root (the PS helper's $script:libraryroot)</param>
        public static void Load(string libraryRoot)
        {
            if (String.IsNullOrEmpty(libraryRoot))
                throw new ArgumentNullException("libraryRoot");

            string platformLib = Path.Combine(libraryRoot, "lib");
            // PS load order (helper lines 10-11): Rmo.dll before Replication.dll
            Assembly.LoadFrom(Path.Combine(platformLib, "Microsoft.SqlServer.Rmo.dll"));
            Assembly.LoadFrom(Path.Combine(platformLib, "Microsoft.SqlServer.Replication.dll"));
        }
    }
}
