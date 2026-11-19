using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.TabExpansion;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Connection
{
    public static partial class ConnectionService
    {
        private static ConnectionResolution VerifyAndComplete(ResolveState state)
        {
            SmoConnectionRequest request = state.Request;
            DbaInstanceParameter instance = state.Instance;
            Server server = state.Server;

            string maskedConnString = HideConnectionString(server.ConnectionContext.ConnectionString);
            Msg(request, MessageLevel.Debug, String.Format("The masked server.ConnectionContext.ConnectionString is {0}", maskedConnString));

            // It doesn't matter which input we have, we pass this line and have a server SMO in $server to work with
            // It might be a brand new one or an already used one.
            // "Pooled connections are always closed directly after an operation" (so .IsOpen does not tell us anything):
            // https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.common.connectionmanager.isopen?view=sql-smo-160#Microsoft_SqlServer_Management_Common_ConnectionManager_IsOpen
            // We could use .ConnectionContext.SqlConnectionObject.Open(), but we would have to check ConnectionContext.IsOpen first because it is not allowed on open connections
            // But ConnectionContext.IsOpen does not tell the truth if the instance was just shut down
            // And we don't use $server.ConnectionContext.Connect() as this would create a non pooled connection
            // Instead we run a real T-SQL command and just SELECT something to be sure we have a valid connection and let the SMO handle the connection
            bool connectionSucceeded = false;
            Exception connectionError = null;
            try
            {
                Msg(request, MessageLevel.Debug, "We connect to the instance by running SELECT 'dbatools is opening a new connection'");
                server.ConnectionContext.ExecuteWithResults("SELECT 'dbatools is opening a new connection'");
                Msg(request, MessageLevel.Debug, "We have a connected server object");
                connectionSucceeded = true;
            }
            catch (Exception initialFailure)
            {
                connectionError = initialFailure;
                string errorMessage = CollectMessages(initialFailure);

                // Check if AllowTrustServerCertificate is enabled and this is a new connection attempt and not already using TrustServerCertificate
                // Also verify this is a certificate validation error
                bool isCertError = Regex.IsMatch(errorMessage, "certificate", RegexOptions.IgnoreCase) || Regex.IsMatch(errorMessage, "SSL", RegexOptions.IgnoreCase) || Regex.IsMatch(errorMessage, "TLS", RegexOptions.IgnoreCase) || Regex.IsMatch(errorMessage, "trust", RegexOptions.IgnoreCase);
                if (request.AllowTrustServerCertificate && state.IsNewConnection && !request.TrustServerCertificate && isCertError && state.InputType == ResolveInputType.String)
                {
                    Msg(request, MessageLevel.Verbose, "Initial connection failed due to certificate validation. Retrying with TrustServerCertificate enabled.");
                    Msg(request, MessageLevel.Debug, String.Format("Original error: {0}", errorMessage));

                    // Recreate the connection with TrustServerCertificate enabled
                    try
                    {
                        // Trust the server certificate. The pin rewrote SqlConnectionObject.ConnectionString, but SMO
                        // resets that string from its own settings before the next command when the ServerConnection was
                        // built from a SqlConnectionInfo (ConnectionSettings.ResetConnectionString), so the retry ran with
                        // the old Trust Server Certificate=False and failed with the same certificate error (probes
                        // failover-trust-20261113 and trust-retry-20261113: pin and port alike, every instance whose
                        // certificate fails validation). Setting ConnectionSettings.TrustServerCertificate changes the
                        // string SMO builds. A ServerConnection built from a SqlConnection (the access-token and SSPI
                        // provider branches) accepts that setter but keeps the string it was given: its
                        // ConnectionString returns that string as is, and SMO copies it into the SqlConnection before it
                        // connects, so an edit of SqlConnectionObject.ConnectionString is undone and the retry validates
                        // again (probes trust-retry-sspi-20261118 and trust-retry-context-20261118, every lab instance
                        // by address, both editions). There the context's own string is edited; SMO copies it into the
                        // same SqlConnection, which keeps its SSPI provider or access token.
                        try
                        {
                            server.ConnectionContext.TrustServerCertificate = true;
                        }
                        catch (PropertyNotAvailableException)
                        {
                            // A context that refuses the setter has its string edited below.
                        }
                        if (!ConnectionStringTrustsServerCertificate(server.ConnectionContext.ConnectionString))
                            server.ConnectionContext.ConnectionString = ApplyTrustServerCertificate(server.ConnectionContext.ConnectionString);

                        // Retry the connection
                        Msg(request, MessageLevel.Debug, "Retrying connection with TrustServerCertificate enabled");
                        server.ConnectionContext.ExecuteWithResults("SELECT 'dbatools is opening a new connection with TrustServerCertificate'");
                        Msg(request, MessageLevel.Verbose, "Connection succeeded with TrustServerCertificate enabled");
                        connectionSucceeded = true;
                    }
                    catch (Exception trustRetryFailure)
                    {
                        Msg(request, MessageLevel.Debug, String.Format("Retry with TrustServerCertificate also failed: {0}", trustRetryFailure.Message));
                        // Keep the latest error details available for any follow-up retry and final reporting
                        connectionError = trustRetryFailure;
                        errorMessage = CollectMessages(trustRetryFailure);
                    }
                }

                // Check if the error is about Failover Partner requiring Initial Catalog.
                // This happens when connecting to a SQL Server instance configured for database mirroring.
                // The .NET SqlClient sends Failover Partner info from the server's TDS handshake to the
                // connection pool, and the pool then requires Initial Catalog to be set in the connection string.
                bool isFailoverPartnerError = Regex.IsMatch(errorMessage, "Failover Partner", RegexOptions.IgnoreCase) && Regex.IsMatch(errorMessage, "Initial Catalog", RegexOptions.IgnoreCase);
                if (state.IsNewConnection && isFailoverPartnerError && !connectionSucceeded && (state.InputType == ResolveInputType.String || state.InputType == ResolveInputType.ConnectionString || state.InputType == ResolveInputType.RegisteredServer))
                {
                    Msg(request, MessageLevel.Verbose, "Connection failed because the server is configured for database mirroring (Failover Partner requires Initial Catalog). Retrying with Initial Catalog=master.");
                    Msg(request, MessageLevel.Debug, String.Format("Original error: {0}", errorMessage));

                    try
                    {
                        // Add Initial Catalog=master to satisfy the Failover Partner connection string requirement
                        string retryConnectionString = NormalizeFailoverPartnerKey(server.ConnectionContext.SqlConnectionObject.ConnectionString);
                        retryConnectionString = EnsureInitialCatalogMaster(retryConnectionString);
                        server.ConnectionContext.SqlConnectionObject.ConnectionString = retryConnectionString;

                        // Retry the connection
                        Msg(request, MessageLevel.Debug, "Retrying connection with Initial Catalog=master for server with database mirroring");
                        server.ConnectionContext.ExecuteWithResults("SELECT 'dbatools is opening a new connection with Initial Catalog'");
                        Msg(request, MessageLevel.Verbose, "Connection succeeded with Initial Catalog=master for server with database mirroring");
                        connectionSucceeded = true;
                    }
                    catch (Exception failoverRetryFailure)
                    {
                        Msg(request, MessageLevel.Debug, String.Format("Retry with Initial Catalog=master also failed: {0}", failoverRetryFailure.Message));
                        // Keep the original error for reporting
                        connectionError = failoverRetryFailure;
                    }
                }

                if (!connectionSucceeded)
                {
                    // PS: Stop-Function -Target $instance -Message "Failure" -Category ConnectionError -ErrorRecord $connectionError -Continue
                    throw new ConnectionResolutionException(ConnectionResolutionFailure.ConnectFailure, "Failure", connectionError);
                }
            }

            if (request.AzureUnsupported && server.DatabaseEngineType == DatabaseEngineType.SqlAzureDatabase)
            {
                if (state.IsNewConnection)
                    server.ConnectionContext.Disconnect();
                throw new ConnectionResolutionException(ConnectionResolutionFailure.AzureUnsupported, "Azure SQL Database not supported", null);
            }

            // dbatools PR 10813 (head d8d01159), Connect-DbaInstance.ps1 after the Azure check: VersionMajor comes from
            // SMO's server information enumerator, which needs SQL Server 2008 and is empty on 2005, so the version
            // falls back to the connection's ServerVersion.Major and then to SERVERPROPERTY('ProductVersion'). It is
            // read for every connection, and both the refusal below and MinimumVersion use it.
            int serverVersionMajor = ReadServerVersionMajor(server, request);

            // PR 10813: SMO 181 declares SQL Server 2008 as the oldest version of every enumerator, so an older
            // instance is refused here, naming the last release that still manages it (operator, 2026-10-29;
            // harness-edits.md, "SQL Server 2005 refusal ported from PR 10813").
            if (serverVersionMajor != 0 && serverVersionMajor < 10)
            {
                if (state.IsNewConnection)
                    server.ConnectionContext.Disconnect();
                throw new ConnectionResolutionException(ConnectionResolutionFailure.UnsupportedVersion, BuildUnsupportedVersionMessage(server, serverVersionMajor), null);
            }

            if (request.MinimumVersion != 0)
            {
                // If none of the sources knows the version, the connection is let through as before.
                if (serverVersionMajor != 0 && serverVersionMajor < request.MinimumVersion)
                {
                    if (state.IsNewConnection)
                        server.ConnectionContext.Disconnect();
                    throw new ConnectionResolutionException(ConnectionResolutionFailure.MinimumVersion, String.Format("SQL Server version {0} required - {1} not supported.", request.MinimumVersion, server), null);
                }
            }

            // Quality gate 1: the pin sets $usesCredentialSspiProvider only when its String path creates the provider
            // (pinned 1366), so a Server or SqlConnection the caller passes back with that provider still on its
            // SqlConnection went into the connection hash (pinned 1555, 1692) under a string that does not name the
            // identity it signed in as. The provider is part of SqlClient's pool key; a later caller with the same
            // string could be handed that identity's connection. The connection itself says whether it carries one.
            if (!state.UsesCredentialSspiProvider && server.ConnectionContext.SqlConnectionObject.SspiContextProvider != null)
                state.UsesCredentialSspiProvider = true;

            ConnectionResolution resolution = new ConnectionResolution();
            resolution.Instance = instance;
            resolution.IsNewConnection = state.IsNewConnection;
            resolution.IsAzure = state.IsAzure;
            resolution.UsesCredentialSspiProvider = state.UsesCredentialSspiProvider;

            if (request.SqlConnectionOnly)
            {
                if (!state.UsesCredentialSspiProvider)
                    RegisterConnection(server.ConnectionContext.ConnectionString, server.ConnectionContext.SqlConnectionObject, request.MessageCallback);
                Msg(request, MessageLevel.Debug, "We return only SqlConnection in server.ConnectionContext.SqlConnectionObject");
                resolution.SqlConnection = server.ConnectionContext.SqlConnectionObject;
                return resolution;
            }

            Decorate(state);
            Msg(request, MessageLevel.Debug, "We return the server object");
            resolution.Server = server;
            return resolution;
        }

        /// <summary>
        /// The refusal of an instance older than SQL Server 2008, word for word as dbatools PR 10813 (head d8d01159)
        /// composes it in Connect-DbaInstance.ps1.
        /// </summary>
        /// <param name="server">The connected server; its ToString() is the "[name]" PowerShell interpolates</param>
        /// <param name="serverVersionMajor">The server's major version, below 10</param>
        /// <returns>The Stop-Function message</returns>
        public static string BuildUnsupportedVersionMessage(object server, int serverVersionMajor)
        {
            string legacyVersionName;
            switch (serverVersionMajor)
            {
                case 9:
                    legacyVersionName = "SQL Server 2005";
                    break;
                case 8:
                    legacyVersionName = "SQL Server 2000";
                    break;
                default:
                    legacyVersionName = String.Format(System.Globalization.CultureInfo.InvariantCulture, "SQL Server version {0}", serverVersionMajor);
                    break;
            }
            string legacyReleaseNote = String.Format("The last release that supports {0} is dbatools 2.8.2 with dbatools.library 2025.12.28", legacyVersionName);
            if (serverVersionMajor < 9)
            {
                // PowerShell 7 cannot log in to SQL Server 2000 at all, see #8425
                legacyReleaseNote += ", run from Windows PowerShell 5.1";
            }
            return String.Format("{0} runs {1}, which dbatools no longer supports: since 2.8.3, dbatools uses SMO 181, which requires SQL Server 2008 or later. {2}. See https://github.com/dataplat/dbatools#sql-server-2000-and-2005", server, legacyVersionName, legacyReleaseNote);
        }

        /// <summary>
        /// The server's major version, as dbatools PR 10813 reads it in Connect-DbaInstance.ps1 (the pin's
        /// MinimumVersion sources, :1520-1543, now read for every connection): SMO's VersionMajor, else
        /// ConnectionContext.ServerVersion.Major, else SERVERPROPERTY('ProductVersion') over the connection's own
        /// T-SQL. Returns 0 when no source knows it; the connection is then let through.
        /// </summary>
        /// <param name="server">The connected server</param>
        /// <param name="request">The request, for its message callback</param>
        /// <returns>The major version, or 0 when unknown</returns>
        private static int ReadServerVersionMajor(Server server, SmoConnectionRequest request)
        {
            int versionMajor = 0;
            try
            {
                versionMajor = server.VersionMajor;
            }
            catch (Exception)
            {
                // PS reads a property whose getter throws as empty, which is what $server.VersionMajor gives on 2005.
                versionMajor = 0;
            }
            if (versionMajor == 0)
            {
                try
                {
                    versionMajor = server.ConnectionContext.ServerVersion.Major;
                    Msg(request, MessageLevel.Debug, String.Format("VersionMajor is not available, using ServerVersion.Major [{0}] from the connection", versionMajor));
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    versionMajor = 0;
                    Msg(request, MessageLevel.Debug, String.Format("Failed to read ServerVersion from the connection: {0}", ex.Message));
                }
            }
            if (versionMajor == 0)
            {
                try
                {
                    object productVersion = server.ConnectionContext.ExecuteScalar("SELECT SERVERPROPERTY('ProductVersion')");
                    string productVersionText = Convert.ToString(productVersion, System.Globalization.CultureInfo.InvariantCulture);
                    versionMajor = Int32.Parse(productVersionText.Split('.')[0], System.Globalization.CultureInfo.InvariantCulture);
                    Msg(request, MessageLevel.Debug, String.Format("ServerVersion is not available, using ProductVersion [{0}] from T-SQL", productVersionText));
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    versionMajor = 0;
                    Msg(request, MessageLevel.Debug, String.Format("Failed to read ProductVersion with T-SQL: {0}", ex.Message));
                }
            }
            return versionMajor;
        }

        private static void Decorate(ResolveState state)
        {
            SmoConnectionRequest request = state.Request;
            DbaInstanceParameter instance = state.Instance;
            Server server = state.Server;

            object existingComputerName = SmoServerExtensions.GetPSProperty(server, "ComputerName");
            bool hasComputerName = existingComputerName != null && !String.IsNullOrEmpty(existingComputerName.ToString());
            if (!hasComputerName)
            {
                // To set the source of ComputerName to something else than the default use this config parameter:
                // Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value 'server.ComputerNamePhysicalNetBIOS'
                // Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value 'instance.ComputerName'
                // If the config parameter is not used, then there a different ways to handle the new property ComputerName
                // Rules in legacy code: Use $server.NetName, but if $server.NetName is empty or we are on Azure or Linux, use $instance.ComputerName
                string computerName = null;
                string computerNameSource = GetConfigString("commands.connect-dbainstance.smo.computername.source", null);
                if (!String.IsNullOrEmpty(computerNameSource))
                {
                    Msg(request, MessageLevel.Debug, String.Format("Setting ComputerName based on {0}", computerNameSource));
                    // PS: $object, $property = $computerNameSource -split '\.'
                    //     $value = (Get-Variable -Name $object).Value.$property
                    string[] sourceParts = computerNameSource.Split('.');
                    object sourceObject = null;
                    if (sourceParts.Length == 2)
                    {
                        if (String.Equals(sourceParts[0], "server", StringComparison.OrdinalIgnoreCase))
                            sourceObject = server;
                        else if (String.Equals(sourceParts[0], "instance", StringComparison.OrdinalIgnoreCase))
                            sourceObject = instance;
                    }
                    object sourceValue = sourceObject == null ? null : SmoServerExtensions.GetPSProperty(sourceObject, sourceParts[1]);
                    if (sourceValue != null && !String.IsNullOrEmpty(sourceValue.ToString()))
                    {
                        computerName = sourceValue.ToString();
                        Msg(request, MessageLevel.Debug, String.Format("ComputerName will be set to {0}", computerName));
                    }
                    else
                    {
                        Msg(request, MessageLevel.Debug, "No value found for ComputerName, so will use the default");
                    }
                }
                if (String.IsNullOrEmpty(computerName))
                {
                    if (server.DatabaseEngineType == DatabaseEngineType.SqlAzureDatabase)
                    {
                        Msg(request, MessageLevel.Debug, "We are on Azure, so server.ComputerName will be set to instance.ComputerName");
                        computerName = instance.ComputerName;
                    }
                    else if (String.Equals(server.HostPlatform, "Linux", StringComparison.OrdinalIgnoreCase))
                    {
                        Msg(request, MessageLevel.Debug, "We are on Linux what is often on docker and the internal name is not useful, so server.ComputerName will be set to instance.ComputerName");
                        computerName = instance.ComputerName;
                    }
                    else if (!String.IsNullOrEmpty(server.NetName))
                    {
                        Msg(request, MessageLevel.Debug, "We will set server.ComputerName to server.NetName");
                        computerName = server.NetName;
                    }
                    else
                    {
                        Msg(request, MessageLevel.Debug, "We will set server.ComputerName to instance.ComputerName as server.NetName is empty");
                        computerName = instance.ComputerName;
                    }
                    Msg(request, MessageLevel.Debug, String.Format("ComputerName will be set to {0}", computerName));
                }
                AddNoteProperty(PSObject.AsPSObject(server), "ComputerName", computerName);
            }

            // PS: if (-not $server.IsAzure) - decoration is skipped only when IsAzure is
            // already present AND true; a false value is refreshed every time (quirk preserved).
            object existingIsAzure = SmoServerExtensions.GetPSProperty(server, "IsAzure");
            bool isAzureAlreadyTrue = existingIsAzure is bool && (bool)existingIsAzure;
            if (!isAzureAlreadyTrue)
            {
                PSObject wrapped = PSObject.AsPSObject(server);
                AddNoteProperty(wrapped, "IsAzure", state.IsAzure);
                AddNoteProperty(wrapped, "DbaInstanceName", instance.InstanceName);
                // Server.DomainInstanceName is adapter-only in SqlManagementObjects 181.x, so
                // it is read through the PSObject view with a composed fallback.
                AddNoteProperty(wrapped, "SqlInstance", SmoServerExtensions.GetDomainInstanceName(server));
                AddNoteProperty(wrapped, "NetPort", instance.Port);
                AddNoteProperty(wrapped, "ConnectedAs", server.ConnectionContext.TrueLogin);
                Msg(request, MessageLevel.Debug, String.Format("We added IsAzure = '{0}', DbaInstanceName = instance.InstanceName = '{1}', SqlInstance = server.DomainInstanceName = '{2}', NetPort = instance.Port = '{3}', ConnectedAs = server.ConnectionContext.TrueLogin = '{4}'", SmoServerExtensions.GetPSProperty(server, "IsAzure"), SmoServerExtensions.GetPSProperty(server, "DbaInstanceName"), SmoServerExtensions.GetPSProperty(server, "SqlInstance"), SmoServerExtensions.GetPSProperty(server, "NetPort"), SmoServerExtensions.GetPSProperty(server, "ConnectedAs")));
            }
        }

        /// <summary>
        /// The post-emission registrations of a resolved connection for callers that do not
        /// interleave TEPP script execution (the GetServer facade and the row-3 re-entry):
        /// TEPP instance seeding and SetDefaultInitFields for new non-DAC connections, then
        /// the connection-hash registration that the PS source ran for every instance.
        /// </summary>
        /// <param name="resolution">The resolution to finalize</param>
        /// <param name="request">The request it was resolved from</param>
        public static void FinalizeConnection(ConnectionResolution resolution, SmoConnectionRequest request)
        {
            if (resolution == null || resolution.Server == null)
                return;
            if (resolution.IsNewConnection && !request.DedicatedAdminConnection)
            {
                if (!resolution.UsesCredentialSspiProvider)
                    RegisterInstanceForTepp(resolution.Instance, resolution.Server);
                ApplyDefaultInitFields(resolution.Server, resolution.IsAzure, request.MessageCallback);
            }
            if (!resolution.UsesCredentialSspiProvider)
                RegisterConnection(resolution.Server.ConnectionContext.ConnectionString, resolution.Server, request.MessageCallback);
        }

        /// <summary>
        /// Registers a new connection with the TEPP updater, exactly like the pinned function (1607-1620): SetInstance
        /// with a disconnected copy of the ConnectionContext and the SysAdmin flag, then the instance-name cache.
        /// </summary>
        /// <param name="instance">The instance that was connected</param>
        /// <param name="server">The connected server</param>
        public static void RegisterInstanceForTepp(DbaInstanceParameter instance, Server server)
        {
            // Register the connected instance, so that the TEPP updater knows it's been connected to and starts building the cache.
            // Copy() clones an open connection as an open one, and the updater keeps the copy for the life of the
            // process, so it gets a disconnected copy: the updater connects when it runs (upstream 0ea5fec52).
            ServerConnection teppConnectionContext = server.ConnectionContext.Copy();
            teppConnectionContext.Disconnect();
            TabExpansionHost.SetInstance(instance.FullSmoName.ToLowerInvariant(), teppConnectionContext, Regex.IsMatch(server.ConnectionContext.FixedServerRoles.ToString(), "SysAdmin", RegexOptions.IgnoreCase));

            // Update cache for instance names
            AddTeppInstanceName(instance.FullSmoName);
        }

        /// <summary>
        /// The pinned private Add-DbaTeppInstanceName (upstream 63a9dee51): rebuilds the tab completion cache of
        /// instance names as an array every time, without empty entries, adding each name trimmed and lower-cased
        /// unless it is already there.
        /// </summary>
        /// <param name="names">The instance names to add; empty entries are ignored</param>
        public static void AddTeppInstanceName(params string[] names)
        {
            lock (TabExpansionHost.Cache)
            {
                // $knownInstances = @(Cache["sqlinstance"] | Where-Object { $PSItem })
                object cacheValue = TabExpansionHost.Cache["sqlinstance"];
                List<object> knownInstances = new List<object>();
                System.Collections.IEnumerable enumerable = LanguagePrimitives.GetEnumerable(cacheValue);
                if (enumerable != null)
                {
                    foreach (object item in enumerable)
                    {
                        if (LanguagePrimitives.IsTrue(item))
                            knownInstances.Add(item);
                    }
                }
                else if (LanguagePrimitives.IsTrue(cacheValue))
                {
                    knownInstances.Add(cacheValue);
                }

                if (names != null)
                {
                    foreach (string item in names)
                    {
                        if (String.IsNullOrEmpty(item))
                            continue;
                        string lower = item.Trim().ToLowerInvariant();
                        // -notcontains: PowerShell's case-insensitive equality against every element
                        if (lower.Length > 0 && !knownInstances.Exists(known => LanguagePrimitives.Equals(known, lower, true)))
                            knownInstances.Add(lower);
                    }
                }
                TabExpansionHost.Cache["sqlinstance"] = knownInstances.ToArray();
            }
        }

        #region SetDefaultInitFields priming
        //'PrimaryFilePath' seems the culprit for slow SMO on databases
        private static readonly string[] Fields2000_Db = new string[] { "Collation", "CompatibilityLevel", "CreateDate", "ID", "IsAccessible", "IsFullTextEnabled", "IsSystemObject", "IsUpdateable", "LastBackupDate", "LastDifferentialBackupDate", "LastLogBackupDate", "Name", "Owner", "ReadOnly", "RecoveryModel", "ReplicationOptions", "Status", "Version" };
        private static readonly string[] Fields200x_Db = new string[] { "Collation", "CompatibilityLevel", "CreateDate", "ID", "IsAccessible", "IsFullTextEnabled", "IsSystemObject", "IsUpdateable", "LastBackupDate", "LastDifferentialBackupDate", "LastLogBackupDate", "Name", "Owner", "ReadOnly", "RecoveryModel", "ReplicationOptions", "Status", "Version", "BrokerEnabled", "DatabaseSnapshotBaseName", "IsMirroringEnabled", "Trustworthy" };
        private static readonly string[] Fields201x_Db = new string[] { "Collation", "CompatibilityLevel", "CreateDate", "ID", "IsAccessible", "IsFullTextEnabled", "IsSystemObject", "IsUpdateable", "LastBackupDate", "LastDifferentialBackupDate", "LastLogBackupDate", "Name", "Owner", "ReadOnly", "RecoveryModel", "ReplicationOptions", "Status", "Version", "BrokerEnabled", "DatabaseSnapshotBaseName", "IsMirroringEnabled", "Trustworthy", "ActiveConnections", "AvailabilityDatabaseSynchronizationState", "AvailabilityGroupName", "ContainmentType", "EncryptionEnabled" };

        private static readonly string[] Fields2000_Login = new string[] { "CreateDate", "DateLastModified", "DefaultDatabase", "DenyWindowsLogin", "IsSystemObject", "Language", "LanguageAlias", "LoginType", "Name", "Sid", "WindowsLoginAccessType" };
        private static readonly string[] Fields200x_Login = new string[] { "CreateDate", "DateLastModified", "DefaultDatabase", "DenyWindowsLogin", "IsSystemObject", "Language", "LanguageAlias", "LoginType", "Name", "Sid", "WindowsLoginAccessType", "AsymmetricKey", "Certificate", "Credential", "ID", "IsDisabled", "IsLocked", "IsPasswordExpired", "MustChangePassword", "PasswordExpirationEnabled", "PasswordPolicyEnforced" };
        private static readonly string[] Fields201x_Login = new string[] { "CreateDate", "DateLastModified", "DefaultDatabase", "DenyWindowsLogin", "IsSystemObject", "Language", "LanguageAlias", "LoginType", "Name", "Sid", "WindowsLoginAccessType", "AsymmetricKey", "Certificate", "Credential", "ID", "IsDisabled", "IsLocked", "IsPasswordExpired", "MustChangePassword", "PasswordExpirationEnabled", "PasswordPolicyEnforced", "PasswordHashAlgorithm" };

        //see #7753
        private static readonly string[] Fields_Job = new string[] { "LastRunOutcome", "CurrentRunStatus", "CurrentRunStep", "CurrentRunRetryAttempt", "NextRunScheduleID", "NextRunDate", "LastRunDate", "JobType", "HasStep", "HasServer", "CurrentRunRetryAttempt", "HasSchedule", "Category", "CategoryID", "CategoryType", "OperatorToEmail", "OperatorToNetSend", "OperatorToPage" };

        private static int _loadedSmoMajorVersion = -1;

        private static int GetLoadedSmoMajorVersion()
        {
            // PS begin block: $loadedSmoVersion from the loaded Microsoft.SqlServer.SMO
            // assembly's location/ProductVersion, later compared -ge 11. The compiled port
            // links the vendored SMO directly (file version 18.x for SqlManagementObjects
            // 181.x), so this resolves once and stays.
            if (_loadedSmoMajorVersion < 0)
            {
                try
                {
                    string location = typeof(Server).Assembly.Location;
                    System.Diagnostics.FileVersionInfo info = System.Diagnostics.FileVersionInfo.GetVersionInfo(location);
                    _loadedSmoMajorVersion = info.ProductMajorPart;
                }
                catch
                {
                    // Single-file or reflection-restricted hosts: the linked SMO is modern.
                    _loadedSmoMajorVersion = 18;
                }
            }
            return _loadedSmoMajorVersion;
        }

        /// <summary>
        /// The SetDefaultInitFields priming of Connect-DbaInstance.ps1, with the exact
        /// per-version field lists (BP-201/BP-202).
        /// </summary>
        /// <param name="server">The connected server</param>
        /// <param name="isAzure">Whether the target is Azure (skips priming)</param>
        /// <param name="messageCallback">Optional verbatim-message sink</param>
        public static void ApplyDefaultInitFields(Server server, bool isAzure, Action<MessageLevel, string> messageCallback)
        {
            // By default, SMO initializes several properties. We push it to the limit and gather a bit more
            // this slows down the connect a smidge but drastically improves overall performance
            // especially when dealing with a multitude of servers
            if (GetLoadedSmoMajorVersion() >= 11 && !isAzure)
            {
                try
                {
                    if (messageCallback != null)
                        messageCallback(MessageLevel.Debug, "SetDefaultInitFields will be used");
                    StringCollection initFieldsDb = new StringCollection();
                    StringCollection initFieldsLogin = new StringCollection();
                    StringCollection initFieldsJob = new StringCollection();
                    if (server.VersionMajor == 8)
                    {
                        // 2000
                        initFieldsDb.AddRange(Fields2000_Db);
                        initFieldsLogin.AddRange(Fields2000_Login);
                    }
                    else if (server.VersionMajor == 9 || server.VersionMajor == 10)
                    {
                        // 2005 and 2008
                        initFieldsDb.AddRange(Fields200x_Db);
                        initFieldsLogin.AddRange(Fields200x_Login);
                    }
                    else if (server.VersionMajor >= 16)
                    {
                        // 2022 and above - exclude ActiveConnections due to performance issue #9282
                        foreach (string field in Fields201x_Db)
                        {
                            if (!String.Equals(field, "ActiveConnections", StringComparison.Ordinal))
                                initFieldsDb.Add(field);
                        }
                        initFieldsLogin.AddRange(Fields201x_Login);
                    }
                    else
                    {
                        // 2012 to 2019
                        initFieldsDb.AddRange(Fields201x_Db);
                        initFieldsLogin.AddRange(Fields201x_Login);
                    }
                    server.SetDefaultInitFields(typeof(Microsoft.SqlServer.Management.Smo.Database), initFieldsDb);
                    server.SetDefaultInitFields(typeof(Microsoft.SqlServer.Management.Smo.Login), initFieldsLogin);
                    //see 7753
                    initFieldsJob.AddRange(Fields_Job);
                    server.SetDefaultInitFields(typeof(Microsoft.SqlServer.Management.Smo.Agent.Job), initFieldsJob);
                }
                catch (Exception ex)
                {
                    if (messageCallback != null)
                        messageCallback(MessageLevel.Debug, String.Format("SetDefaultInitFields failed with {0}", ex.Message));
                    // perhaps a DLL issue, continue going
                }
            }
        }
        #endregion SetDefaultInitFields priming

        /// <summary>
        /// private/functions/Add-ConnectionHashValue.ps1 parity over
        /// ConnectionHost.ActiveConnections: non-pooled connections append to the entry's
        /// list, pooled connections replace it.
        /// </summary>
        /// <param name="key">The connection string key</param>
        /// <param name="value">The Server or SqlConnection to register</param>
        /// <param name="messageCallback">Optional verbatim-message sink</param>
        public static void RegisterConnection(string key, object value, Action<MessageLevel, string> messageCallback)
        {
            if (messageCallback != null)
                messageCallback(MessageLevel.Debug, "Adding to connection hash");
            if (String.IsNullOrEmpty(key) || value == null)
                return;

            // PS: if ($Value.ConnectionContext.NonPooledConnection -or $Value.NonPooledConnection)
            // A Server exposes it through ConnectionContext; a bare SqlConnection has neither,
            // which lands in the pooled/replace branch exactly like the PS member miss did.
            bool nonPooled = false;
            Server serverValue = value as Server;
            if (serverValue != null)
            {
                try { nonPooled = serverValue.ConnectionContext.NonPooledConnection; }
                catch { /* unreadable on some connection shapes; treat as pooled like the PS member miss */ }
            }

            lock (ConnectionHost.ActiveConnections)
            {
                if (nonPooled)
                {
                    List<object> entries;
                    if (!ConnectionHost.ActiveConnections.TryGetValue(key, out entries) || entries == null)
                    {
                        entries = new List<object>();
                        ConnectionHost.ActiveConnections[key] = entries;
                    }
                    entries.Add(value);
                }
                else
                {
                    List<object> single = new List<object>();
                    single.Add(value);
                    ConnectionHost.ActiveConnections[key] = single;
                }
            }
        }
    }
}
