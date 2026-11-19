using Dataplat.Dbatools.Parameter;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Connection
{
    /// <summary>
    /// The outcome of ConnectionService.ResolveInstance for a single instance: the connected
    /// SMO Server (or, on the -SqlConnectionOnly path, the bare SqlConnection), plus the flags
    /// the caller needs for the post-emission steps (TEPP registration, SetDefaultInitFields,
    /// connection-hash registration) that public/Connect-DbaInstance.ps1 ran after emitting
    /// the server object.
    /// </summary>
    public class ConnectionResolution
    {
        /// <summary>The connected, decorated SMO Server. Null on the SqlConnectionOnly path.</summary>
        public Server Server;

        /// <summary>Set ONLY on the -SqlConnectionOnly path: ConnectionContext.SqlConnectionObject.</summary>
        public SqlConnection SqlConnection;

        /// <summary>
        /// Whether this resolution built a new connection (String, ConnectionString,
        /// RegisteredServer inputs, or a copied/re-entered context) as opposed to passing a
        /// live Server or SqlConnection through. Drives the TEPP/InitFields registration and
        /// the disconnect-on-gate-failure behavior, exactly like $isNewConnection in the PS source.
        /// </summary>
        public bool IsNewConnection;

        /// <summary>Whether the target matched the AzureDomain check for this instance.</summary>
        public bool IsAzure;

        /// <summary>The instance that was resolved (after any service-principal rewrite).</summary>
        public DbaInstanceParameter Instance;

        /// <summary>
        /// Whether the connection authenticates a Windows credential through NetworkCredentialSspiContextProvider
        /// (the pin's $usesCredentialSspiProvider). The pin registers such a connection with neither the TEPP
        /// updater nor the connection hash: the provider lives on the SqlConnection, not in its connection string.
        /// </summary>
        public bool UsesCredentialSspiProvider;
    }
}
