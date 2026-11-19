using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Connection
{
    /// <summary>
    /// The input to ConnectionService: one property per Connect-DbaInstance parameter, written
    /// fresh from public/Connect-DbaInstance.ps1 (migration/specs/architecture.md section 4).
    /// Unset properties fall back to ConfigurationHost defaults through
    /// ApplyConfigurationDefaults, exactly like the PS parameter defaults did.
    /// </summary>
    public class SmoConnectionRequest
    {
        /// <summary>The target instance in any of the DbaInstanceParameter input shapes.</summary>
        public DbaInstanceParameter Instance;

        /// <summary>
        /// The instance as the caller gave it, when Connect-DbaInstance replaced Instance before resolving (the pinned
        /// service-principal connection string, pinned 569-575). The pinned "Starting loop" message is written before
        /// that replacement, so it names this instance and its type. Null means Instance.
        /// </summary>
        public DbaInstanceParameter LoopInstance;

        /// <summary>Credential for SQL login, Windows credential or Entra authentication.</summary>
        public PSCredential SqlCredential;

        /// <summary>Initial catalog override; empty means the config/default database.</summary>
        public string Database;

        /// <summary>ReadOnly/ReadWrite application intent.</summary>
        public string ApplicationIntent;

        /// <summary>Reject Azure SQL Database targets with the verbatim PS message.</summary>
        public bool AzureUnsupported;

        /// <summary>ConnectionContext.BatchSeparator, applied only when explicitly bound.</summary>
        public string BatchSeparator;

        /// <summary>SqlConnectionInfo.ApplicationName; config default sql.connection.clientname.</summary>
        public string ClientName;

        /// <summary>"Connect Retry Count" in AdditionalParameters, applied only when explicitly bound.</summary>
        public int ConnectRetryCount;

        /// <summary>"Connect Retry Interval" in AdditionalParameters, applied only when explicitly bound.</summary>
        public int ConnectRetryInterval;

        /// <summary>SqlConnectionInfo.ConnectionTimeout; default ConnectionHost.SqlConnectionTimeout.</summary>
        public int ConnectTimeout;

        /// <summary>SqlConnectionInfo.EncryptConnection; config default sql.connection.encrypt.</summary>
        public bool EncryptConnection;

        /// <summary>Appended to AdditionalParameters as FailoverPartner=...;.</summary>
        public string FailoverPartner;

        /// <summary>ConnectionContext.LockTimeout, applied only when explicitly bound.</summary>
        public int LockTimeout;

        /// <summary>SqlConnectionInfo.MaxPoolSize when non-zero.</summary>
        public int MaxPoolSize;

        /// <summary>SqlConnectionInfo.MinPoolSize when non-zero.</summary>
        public int MinPoolSize;

        /// <summary>Reject instances below this major version with the verbatim PS message.</summary>
        public int MinimumVersion;

        /// <summary>ConnectionContext.MultipleActiveResultSets when set.</summary>
        public bool MultipleActiveResultSets;

        /// <summary>Appended to AdditionalParameters as MultiSubnetFailover=True;. Config default sql.connection.multisubnetfailover.</summary>
        public bool MultiSubnetFailover;

        /// <summary>SqlConnectionInfo.ConnectionProtocol; config default sql.connection.protocol.</summary>
        public string NetworkProtocol;

        /// <summary>SqlConnectionInfo.Pooled = false plus ConnectionContext.NonPooledConnection.</summary>
        public bool NonPooledConnection;

        /// <summary>SqlConnectionInfo.PacketSize when non-zero; config default sql.connection.packetsize.</summary>
        public int PacketSize;

        /// <summary>SqlConnectionInfo.PoolConnectionLifeTime when non-zero.</summary>
        public int PooledConnectionLifetime;

        /// <summary>ConnectionContext.SqlExecutionModes, applied only when explicitly bound.</summary>
        public string SqlExecutionModes;

        /// <summary>ConnectionContext.StatementTimeout, always applied on the String path; config default sql.execution.timeout.</summary>
        public int StatementTimeout;

        /// <summary>SqlConnectionInfo.TrustServerCertificate; config default sql.connection.trustcert.</summary>
        public bool TrustServerCertificate;

        /// <summary>Single trusted retry after a certificate validation failure; config default sql.connection.allowtrustcert.</summary>
        public bool AllowTrustServerCertificate;

        /// <summary>SqlConnectionInfo.WorkstationId when non-empty.</summary>
        public string WorkstationId;

        /// <summary>Appends Column Encryption Setting=enabled; to AdditionalParameters.</summary>
        public bool AlwaysEncrypted;

        /// <summary>Raw string appended to SqlConnectionInfo.AdditionalParameters.</summary>
        public string AppendConnectionString;

        /// <summary>Return ConnectionContext.SqlConnectionObject instead of the SMO Server.</summary>
        public bool SqlConnectionOnly;

        /// <summary>The Azure SQL Database domain suffix used for Azure detection.</summary>
        public string AzureDomain = "database.windows.net";

        /// <summary>
        /// Access token input in any of the accepted shapes (New-DbaAzAccessToken renewable
        /// object, Get-AzAccessToken result, SecureString, or string). ResolveInstance unwraps
        /// it in place, mirroring the PS $AccessToken reassignment.
        /// </summary>
        public object AccessToken;

        /// <summary>One of the six Entra ID authentication flows, or empty.</summary>
        public string AuthenticationType;

        /// <summary>Dedicated admin connection: ADMIN: prefix, forced non-pooled, never TEPP-registered.</summary>
        public bool DedicatedAdminConnection;

        /// <summary>
        /// The caller's explicitly bound parameter names (Test-Bound parity). Null means
        /// "internal caller": nothing counts as bound and config defaults fill every unset
        /// field.
        /// </summary>
        public HashSet<string> BoundParameters;

        /// <summary>
        /// Receives the verbatim Write-Message texts of the PS source (level + message).
        /// The Connect-DbaInstance cmdlet wires this to WriteMessage; internal callers leave
        /// it null and connect silently, as compiled consumers always have.
        /// </summary>
        public Action<MessageLevel, string> MessageCallback;

        /// <summary>Test-Bound equivalent over the caller-supplied bound-parameter names.</summary>
        /// <param name="parameterName">The parameter name</param>
        /// <returns>True when the caller explicitly bound the parameter</returns>
        public bool IsBound(string parameterName)
        {
            return BoundParameters != null && BoundParameters.Contains(parameterName);
        }

        /// <summary>Test-Bound over several names: true when ANY of them is bound.</summary>
        /// <param name="parameterNames">The parameter names</param>
        /// <returns>True when at least one is bound</returns>
        public bool IsAnyBound(params string[] parameterNames)
        {
            if (BoundParameters == null)
                return false;
            foreach (string name in parameterNames)
            {
                if (BoundParameters.Contains(name))
                    return true;
            }
            return false;
        }

        /// <summary>
        /// Fills every UNBOUND field that had a Get-DbatoolsConfigValue parameter default in
        /// the PS source (architecture.md section 4.6). Bound fields always win; for internal
        /// callers (BoundParameters null) a field is filled only when still at its type
        /// default, so explicitly assigned request values survive.
        /// </summary>
        public void ApplyConfigurationDefaults()
        {
            // [string]$Database = (Get-DbatoolsConfigValue -FullName 'sql.connection.database')
            if (!IsBound("Database") && String.IsNullOrEmpty(Database))
                Database = ConnectionService.GetConfigString("sql.connection.database", null);

            // [string]$ClientName = (Get-DbatoolsConfigValue -FullName 'sql.connection.clientname')
            if (!IsBound("ClientName") && String.IsNullOrEmpty(ClientName))
                ClientName = ConnectionService.GetConfigString("sql.connection.clientname", null);

            // [int]$ConnectTimeout = ([Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout)
            if (!IsBound("ConnectTimeout") && ConnectTimeout == 0)
                ConnectTimeout = ConnectionHost.SqlConnectionTimeout;

            // [switch]$EncryptConnection = (Get-DbatoolsConfigValue -FullName 'sql.connection.encrypt')
            if (!IsBound("EncryptConnection") && !EncryptConnection)
                EncryptConnection = ConnectionService.GetConfigBool("sql.connection.encrypt");

            // [switch]$MultiSubnetFailover = (Get-DbatoolsConfigValue -FullName 'sql.connection.multisubnetfailover')
            if (!IsBound("MultiSubnetFailover") && !MultiSubnetFailover)
                MultiSubnetFailover = ConnectionService.GetConfigBool("sql.connection.multisubnetfailover");

            // [string]$NetworkProtocol = (Get-DbatoolsConfigValue -FullName 'sql.connection.protocol')
            if (!IsBound("NetworkProtocol") && String.IsNullOrEmpty(NetworkProtocol))
                NetworkProtocol = ConnectionService.GetConfigString("sql.connection.protocol", null);

            // [int]$PacketSize = (Get-DbatoolsConfigValue -FullName 'sql.connection.packetsize')
            if (!IsBound("PacketSize") && PacketSize == 0)
                PacketSize = ConnectionService.GetConfigInt("sql.connection.packetsize", 0);

            // [int]$StatementTimeout = (Get-DbatoolsConfigValue -FullName 'sql.execution.timeout')
            if (!IsBound("StatementTimeout") && StatementTimeout == 0)
                StatementTimeout = ConnectionService.GetConfigInt("sql.execution.timeout", 0);

            // [switch]$TrustServerCertificate = (Get-DbatoolsConfigValue -FullName 'sql.connection.trustcert')
            if (!IsBound("TrustServerCertificate") && !TrustServerCertificate)
                TrustServerCertificate = ConnectionService.GetConfigBool("sql.connection.trustcert");

            // [switch]$AllowTrustServerCertificate = (Get-DbatoolsConfigValue -FullName 'sql.connection.allowtrustcert')
            if (!IsBound("AllowTrustServerCertificate") && !AllowTrustServerCertificate)
                AllowTrustServerCertificate = ConnectionService.GetConfigBool("sql.connection.allowtrustcert");
        }

        /// <summary>
        /// Copy for the re-entrant Server-with-ConnectAsUserName path (input resolution matrix
        /// row 3): the PS source re-invoked Connect-DbaInstance with all bound parameters plus
        /// a replaced SqlInstance/SqlCredential.
        /// </summary>
        /// <returns>A shallow copy with its own BoundParameters set</returns>
        public SmoConnectionRequest Clone()
        {
            SmoConnectionRequest clone = (SmoConnectionRequest)MemberwiseClone();
            if (BoundParameters != null)
                clone.BoundParameters = new HashSet<string>(BoundParameters, StringComparer.OrdinalIgnoreCase);
            return clone;
        }
    }
}
