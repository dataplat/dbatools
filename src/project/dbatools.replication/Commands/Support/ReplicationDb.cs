#nullable enable

using System;
using Dataplat.Dbatools.Message;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Replication;

namespace Dataplat.Dbatools.Commands
{
    /// <summary>
    /// private/functions/Connect-ReplicationDB.ps1 parity: builds an RMO
    /// ReplicationDatabase for a connected server's database, loads its properties, and
    /// returns it regardless of the load outcome - emitting the helper's verbatim Verbose
    /// message only when LoadProperties() returns false. Faithful details: the helper's
    /// Add-ReplicationLibrary call has no runtime equivalent here (this satellite
    /// references the vendored RMO assemblies at build time - same finding as TB-003);
    /// its [switch]$EnableException is declared but never used, so the port takes no
    /// equivalent; member access on null arguments mirrors PS non-strict semantics
    /// (null flows through instead of faulting); LoadProperties() faults (e.g. an
    /// unconnected ConnectionContext) propagate uncaught in both worlds. Sole PS caller:
    /// Get-DbaReplPublication (helper retained at refcount 1). Live success and
    /// properties-not-loaded behavior belong to the lab gate.
    /// </summary>
    public static class ReplicationDb
    {
        /// <summary>
        /// The helper's body: construct, assign Name and ConnectionContext, load
        /// properties, message on false, return the object.
        /// </summary>
        /// <param name="server">The connected SMO server (its ConnectionContext is shared with the RMO object)</param>
        /// <param name="database">The database whose name seeds the ReplicationDatabase</param>
        /// <param name="messageCallback">Optional verbatim-message sink (Write-Message -Level Verbose equivalent)</param>
        public static ReplicationDatabase Connect(Server? server, Microsoft.SqlServer.Management.Smo.Database? database, Action<MessageLevel, string?>? messageCallback)
        {
            ReplicationDatabase repDB = new ReplicationDatabase();
            repDB.Name = database == null ? null : database.Name;
            repDB.ConnectionContext = server == null ? null : server.ConnectionContext;

            if (!repDB.LoadProperties())
            {
                if (messageCallback != null)
                    messageCallback(MessageLevel.Verbose, String.Format("Skipping {0}. Failed to load properties correctly.", database == null ? null : database.Name));
            }

            return repDB;
        }
    }
}
