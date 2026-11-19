using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using System.Security;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Connection
{
    public static partial class ConnectionService
    {
        // Which shape the input resolution matrix classified the instance as; mirrors the
        // $inputObjectType strings of the PS source.
        internal enum ResolveInputType
        {
            Server = 0,
            SqlConnection = 1,
            RegisteredServer = 2,
            ConnectionString = 3,
            String = 4
        }

        // Per-instance working state, so the build/verify phases stay readable without
        // threading a dozen locals through every method.
        private class ResolveState
        {
            public SmoConnectionRequest Request;
            public DbaInstanceParameter Instance;
            public ResolveInputType InputType;
            public bool IsNewConnection;
            public object InputObject;
            public string ServerName;
            public string ConnectionString;
            public bool IsAzure;
            public Server Server;
            // Pinned $usesCredentialSspiProvider, reset per instance (pinned 523-525): only the String path sets it.
            public bool UsesCredentialSspiProvider;
        }

        /// <summary>
        /// Resolves ONE instance through the full Connect-DbaInstance flow: input analysis,
        /// server construction per the input resolution and auth matrices, the verify query
        /// with its sanctioned retries, the AzureUnsupported/MinimumVersion gates, the
        /// SqlConnectionOnly early return, and the PS-exact decoration. Failures throw
        /// ConnectionResolutionException so the cmdlet can replay the exact Stop-Function
        /// call-site semantics; the caller owns emission and the post-emission registrations
        /// (FinalizeConnection or the granular equivalents).
        /// </summary>
        /// <param name="request">The connection request; Instance must be set</param>
        /// <returns>The resolution outcome</returns>
        public static ConnectionResolution ResolveInstance(SmoConnectionRequest request)
        {
            if (request == null)
                throw new ArgumentNullException("request");
            if (request.Instance == null)
                throw new ArgumentException("The request carries no target instance", "request");

            ResolveState state = new ResolveState();
            state.Request = request;
            state.Instance = request.Instance;

            DbaInstanceParameter instance = state.Instance;
            // Pinned 564: the loop message comes before the service-principal replacement, so it names the given instance.
            DbaInstanceParameter loopInstance = request.LoopInstance ?? instance;
            Msg(request, MessageLevel.Verbose, String.Format("Starting loop for '{0}': ComputerName = '{1}', InstanceName = '{2}', IsLocalHost = '{3}', Type = '{4}'", loopInstance, loopInstance.ComputerName, loopInstance.InstanceName, loopInstance.IsLocalHost, loopInstance.Type));

            Msg(request, MessageLevel.Debug, "Immediately checking for Azure");
            // PS begin block: if ($AzureDomain) { $AzureDomain = [regex]::escape($AzureDomain) }
            string azureDomain = request.AzureDomain;
            string azurePattern = String.IsNullOrEmpty(azureDomain) ? "" : Regex.Escape(azureDomain);
            state.IsAzure = IsAzureInstance(instance, azurePattern);
            if (state.IsAzure)
                Msg(request, MessageLevel.Verbose, "Azure detected");

            /*
            Best practice:
            * Create a smo server object by submitting the name of the instance as a string to SqlInstance and additional parameters to configure the connection
            * Reuse the smo server object in all following calls as SqlInstance
            * When reusing the smo server object, only the following additional parameters are allowed with Connect-DbaInstance:
                - Database, ApplicationIntent, NonPooledConnection, StatementTimeout (command clones ConnectionContext and returns new smo server object)
                - AzureUnsupported (command fails if target is Azure)
                - MinimumVersion (command fails if target version is too old)
                - SqlConnectionOnly (command returns only the ConnectionContext.SqlConnectionObject)
            Commands that use these parameters:
            * ApplicationIntent
                - Invoke-DbaQuery
            * NonPooledConnection
                - Install-DbaFirstResponderKit
            * StatementTimeout (sometimes not as a parameter, they should changed to do so)
                - Backup-DbaDatabase
                - Restore-DbaDatabase
                - Get-DbaTopResourceUsage
                - Import-DbaCsv
                - Invoke-DbaDbLogShipping
                - Invoke-DbaDbShrink
                - Invoke-DbaDbUpgrade
                - Set-DbaDbCompression
                - Test-DbaDbCompression
                - Start-DbccCheck
            * AzureUnsupported
                - Backup-DbaDatabase
                - Copy-DbaLogin
                - Get-DbaLogin
                - Set-DbaLogin
                - Get-DbaDefaultPath
                - Get-DbaUserPermission
                - Get-DbaXESession
                - New-DbaCustomError
                - Remove-DbaCustomError
            Additional possibilities as input to SqlInstance:
            * A smo connection object [Microsoft.Data.SqlClient.SqlConnection] (InputObject is used to build smo server object)
            * A smo registered server object [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer] (FullSmoName und InputObject.ConnectionString are used to build smo server object)
            * A connections string [String] (FullSmoName und InputObject are used to build smo server object)
            Limitations of these additional possibilities:
            * All additional parameters are ignored, a warning is displayed if they are used
            * Currently, connection pooling does not work with connections that are build from connection strings
            * All parameters that configure the connection and where they can be set (here just for documentation and future development):
                - AppendConnectionString      SqlConnectionInfo.AdditionalParameters
                - ApplicationIntent           SqlConnectionInfo.ApplicationIntent          SqlConnectionStringBuilder['ApplicationIntent']
                - AuthenticationType          SqlConnectionInfo.Authentication             SqlConnectionStringBuilder['Authentication']
                - BatchSeparator                                                                                                                     ConnectionContext.BatchSeparator
                - ClientName                  SqlConnectionInfo.ApplicationName            SqlConnectionStringBuilder['Application Name']
                - ConnectRetryCount           SqlConnectionInfo.AdditionalParameters       SqlConnectionStringBuilder['Connect Retry Count']
                - ConnectRetryInterval        SqlConnectionInfo.AdditionalParameters       SqlConnectionStringBuilder['Connect Retry Interval']
                - ConnectTimeout              SqlConnectionInfo.ConnectionTimeout          SqlConnectionStringBuilder['Connect Timeout']
                - Database                    SqlConnectionInfo.DatabaseName               SqlConnectionStringBuilder['Initial Catalog']
                - EncryptConnection           SqlConnectionInfo.EncryptConnection          SqlConnectionStringBuilder['Encrypt']
                - FailoverPartner             SqlConnectionInfo.AdditionalParameters       SqlConnectionStringBuilder['Failover Partner']
                - LockTimeout                                                                                                                        ConnectionContext.LockTimeout
                - MaxPoolSize                 SqlConnectionInfo.MaxPoolSize                SqlConnectionStringBuilder['Max Pool Size']
                - MinPoolSize                 SqlConnectionInfo.MinPoolSize                SqlConnectionStringBuilder['Min Pool Size']
                - MultipleActiveResultSets                                                 SqlConnectionStringBuilder['MultipleActiveResultSets']    ConnectionContext.MultipleActiveResultSets
                - MultiSubnetFailover         SqlConnectionInfo.AdditionalParameters       SqlConnectionStringBuilder['MultiSubnetFailover']
                - NetworkProtocol             SqlConnectionInfo.ConnectionProtocol
                - NonPooledConnection         SqlConnectionInfo.Pooled                     SqlConnectionStringBuilder['Pooling']
                - PacketSize                  SqlConnectionInfo.PacketSize                 SqlConnectionStringBuilder['Packet Size']
                - PooledConnectionLifetime    SqlConnectionInfo.PoolConnectionLifeTime     SqlConnectionStringBuilder['Load Balance Timeout']
                - SqlInstance                 SqlConnectionInfo.ServerName                 SqlConnectionStringBuilder['Data Source']
                - SqlCredential               SqlConnectionInfo.SecurePassword             SqlConnectionStringBuilder['Password']
                                            SqlConnectionInfo.UserName                   SqlConnectionStringBuilder['User ID']
                                            SqlConnectionInfo.UseIntegratedSecurity      SqlConnectionStringBuilder['Integrated Security']
                - SqlExecutionModes                                                                                                                  ConnectionContext.SqlExecutionModes
                - StatementTimeout            (SqlConnectionInfo.QueryTimeout?)                                                                      ConnectionContext.StatementTimeout
                - TrustServerCertificate      SqlConnectionInfo.TrustServerCertificate     SqlConnectionStringBuilder['TrustServerCertificate']
                - WorkstationId               SqlConnectionInfo.WorkstationId              SqlConnectionStringBuilder['Workstation Id']

            Some additional tests:
            * Is $AzureUnsupported set? Test for Azure.
            * Is $MinimumVersion set? Test for that.
            * Is $SqlConnectionOnly set? Then return $server.ConnectionContext.SqlConnectionObject.
            * Does the server object have the additional properties? Add them when necessary.

            Some general decisions:
            * We try to treat connections to Azure as normal connections.
            * Not every edge case will be covered at the beginning.
            * We copy as less code from the existing code paths as possible.
            */

            AnalyzeInput(state);
            WarnIgnoredParameters(state);
            ApplyDedicatedAdminRewrite(state);
            BuildServerObject(state);
            return VerifyAndComplete(state);
        }

        // Analyse input object and extract necessary parts
        private static void AnalyzeInput(ResolveState state)
        {
            SmoConnectionRequest request = state.Request;
            DbaInstanceParameter instance = state.Instance;

            if (instance.Type == DbaInstanceInputType.Server)
            {
                Msg(request, MessageLevel.Verbose, "Server object passed in, will do some checks and then return the original object");
                state.InputType = ResolveInputType.Server;
                state.IsNewConnection = false;
                state.InputObject = UnwrapInput(instance.InputObject);
            }
            else if (instance.Type == DbaInstanceInputType.SqlConnection)
            {
                Msg(request, MessageLevel.Verbose, "SqlConnection object passed in, will build server object from instance.InputObject, do some checks and then return the server object");
                state.InputType = ResolveInputType.SqlConnection;
                state.IsNewConnection = false;
                state.InputObject = UnwrapInput(instance.InputObject);
            }
            else if (instance.Type == DbaInstanceInputType.RegisteredServer)
            {
                Msg(request, MessageLevel.Verbose, "RegisteredServer object passed in, will build empty server object, set connection string from instance.InputObject.ConnectionString, do some checks and then return the server object");
                state.InputType = ResolveInputType.RegisteredServer;
                state.IsNewConnection = true;
                state.InputObject = UnwrapInput(instance.InputObject);
                state.ServerName = instance.FullSmoName;
                object registeredConnectionString = SmoServerExtensions.GetPSProperty(instance.InputObject, "ConnectionString");
                state.ConnectionString = registeredConnectionString == null ? null : registeredConnectionString.ToString();
            }
            else if (instance.IsConnectionString)
            {
                Msg(request, MessageLevel.Verbose, "Connection string is passed in, will build empty server object, set connection string from instance.InputObject, do some checks and then return the server object");
                state.InputType = ResolveInputType.ConnectionString;
                state.IsNewConnection = true;
                state.ServerName = instance.FullSmoName;
                state.ConnectionString = ConvertConnectionString(instance.InputObject.ToString());
            }
            else
            {
                Msg(request, MessageLevel.Verbose, "String is passed in, will build server object from instance object and other parameters, do some checks and then return the server object");
                state.InputType = ResolveInputType.String;
                state.IsNewConnection = true;
                state.ServerName = instance.FullSmoName;
            }
        }

        // Check for ignored parameters
        // We do not check for SqlCredential as this parameter is widely used even if a server SMO is passed in and we don't want to output a message for that
        private static readonly string[] IgnoredParameters = new string[] {
            "BatchSeparator", "ClientName", "ConnectRetryCount", "ConnectRetryInterval", "ConnectTimeout", "EncryptConnection", "LockTimeout", "MaxPoolSize", "MinPoolSize", "NetworkProtocol", "PacketSize", "PooledConnectionLifetime", "SqlExecutionModes", "TrustServerCertificate", "AllowTrustServerCertificate", "WorkstationId", "FailoverPartner", "MultipleActiveResultSets", "MultiSubnetFailover", "AppendConnectionString", "AccessToken", "AuthenticationType"
        };

        private static void WarnIgnoredParameters(ResolveState state)
        {
            SmoConnectionRequest request = state.Request;

            if (state.InputType == ResolveInputType.Server)
            {
                if (request.IsAnyBound(IgnoredParameters))
                    Msg(request, MessageLevel.Warning, "Additional parameters are passed in, but they will be ignored");
            }
            else if (state.InputType == ResolveInputType.RegisteredServer || state.InputType == ResolveInputType.ConnectionString)
            {
                // Parameter TrustServerCertificate changes the connection string be allow connections to instances with the default self-signed certificate
                if (request.IsBound("TrustServerCertificate"))
                    Msg(request, MessageLevel.Verbose, "Additional parameter TrustServerCertificate is passed in and will override other settings");
                // Pinned 737-740: every ignored parameter except TrustServerCertificate warns, also beside TrustServerCertificate.
                if (request.IsAnyBound(Array.FindAll(IgnoredParameters, name => name != "TrustServerCertificate")) || request.IsAnyBound("ApplicationIntent", "StatementTimeout"))
                    Msg(request, MessageLevel.Warning, "Additional parameters are passed in, but they will be ignored");
            }
            else if (state.InputType == ResolveInputType.SqlConnection)
            {
                if (request.IsAnyBound(IgnoredParameters) || request.IsAnyBound("ApplicationIntent", "StatementTimeout", "DedicatedAdminConnection"))
                    Msg(request, MessageLevel.Warning, "Additional parameters are passed in, but they will be ignored");
            }
        }

        private static void ApplyDedicatedAdminRewrite(ResolveState state)
        {
            SmoConnectionRequest request = state.Request;
            DbaInstanceParameter instance = state.Instance;

            if (request.DedicatedAdminConnection && !String.IsNullOrEmpty(state.ServerName))
            {
                Msg(request, MessageLevel.Debug, "Parameter DedicatedAdminConnection is used, so serverName will be changed and NonPooledConnection will be set.");
                if (instance.IsLocalHost)
                {
                    // Use localhost to avoid multiple IP resolution on multi-homed servers (issue #10151)
                    if (!String.Equals(instance.InstanceName, "MSSQLSERVER", StringComparison.OrdinalIgnoreCase))
                        state.ServerName = String.Format("ADMIN:localhost\\{0}", instance.InstanceName);
                    else
                        state.ServerName = "ADMIN:localhost";
                    Msg(request, MessageLevel.Debug, String.Format("IsLocalHost is true, using '{0}' for DAC to avoid multi-IP resolution.", state.ServerName));
                    // Trust the server certificate because 'localhost' may not match the certificate CN (e.g., FQDN), issue #10254
                    // NOTE: the PS source mutates the function-scope $TrustServerCertificate here, so the
                    // setting deliberately persists to the remaining instances of the same call.
                    request.TrustServerCertificate = true;
                }
                else
                {
                    state.ServerName = "ADMIN:" + state.ServerName;
                }
                // Same function-scope persistence as $NonPooledConnection = $true in the PS source.
                request.NonPooledConnection = true;
            }
        }

        // Create smo server object
        private static void BuildServerObject(ResolveState state)
        {
            switch (state.InputType)
            {
                case ResolveInputType.Server:
                    ResolveServerInput(state);
                    break;
                case ResolveInputType.SqlConnection:
                    state.Server = new Server(new ServerConnection((SqlConnection)state.InputObject));
                    break;
                case ResolveInputType.RegisteredServer:
                case ResolveInputType.ConnectionString:
                    BuildFromConnectionString(state);
                    break;
                case ResolveInputType.String:
                    BuildFromString(state);
                    break;
            }
        }

        private static void ResolveServerInput(ResolveState state)
        {
            SmoConnectionRequest request = state.Request;
            DbaInstanceParameter instance = state.Instance;
            Server inputServer = (Server)state.InputObject;

            // Test if we have to copy the connection context
            // Currently only if we have a different Database or have to switch to a NonPooledConnection or using a specific StatementTimeout or using ApplicationIntent
            // We do not test for SqlCredential as this would change the behavior compared to the legacy code path
            bool copyContext = false;
            bool createNewConnection = false;
            if (!String.IsNullOrEmpty(request.Database))
            {
                Msg(request, MessageLevel.Debug, String.Format("Database [{0}] provided.", request.Database));
                string inputObjectCurrentDatabase = inputServer.ConnectionContext.CurrentDatabase;
                if (String.IsNullOrEmpty(inputObjectCurrentDatabase))
                {
                    Msg(request, MessageLevel.Debug, "ConnectionContext.CurrentDatabase is empty, so connection will be opened to get the value");
                    // Pinned 776-791 (upstream 6e952f8d8): Connect() keeps a connection checked out until Disconnect(), so
                    // the value is read and the connection handed back at once, unless the caller had opened it before.
                    // The value is kept, because Disconnect() clears CurrentDatabase again.
                    bool inputObjectWasOpen = inputServer.ConnectionContext.IsOpen;
                    inputServer.ConnectionContext.Connect();
                    inputObjectCurrentDatabase = inputServer.ConnectionContext.CurrentDatabase;
                    if (!inputObjectWasOpen)
                        inputServer.ConnectionContext.Disconnect();
                    Msg(request, MessageLevel.Debug, String.Format("ConnectionContext.CurrentDatabase was [{0}]", inputObjectCurrentDatabase));
                }
                if (!String.Equals(inputObjectCurrentDatabase, request.Database, StringComparison.OrdinalIgnoreCase))
                {
                    Msg(request, MessageLevel.Verbose, String.Format("Database [{0}] provided. Does not match ConnectionContext.CurrentDatabase [{1}], copying ConnectionContext and setting the CurrentDatabase", request.Database, inputObjectCurrentDatabase));
                    copyContext = true;
                    if (!String.IsNullOrEmpty(inputServer.ConnectionContext.ConnectAsUserName))
                    {
                        Msg(request, MessageLevel.Debug, String.Format("Using ConnectAsUserName [{0}], so changing database context is not possible without loosing this information. We will create a new connection targeting database [{1}]", inputServer.ConnectionContext.ConnectAsUserName, request.Database));
                        createNewConnection = true;
                    }
                }
            }
            if (!String.IsNullOrEmpty(request.ApplicationIntent) && !String.Equals(inputServer.ConnectionContext.ApplicationIntent, request.ApplicationIntent, StringComparison.OrdinalIgnoreCase))
            {
                Msg(request, MessageLevel.Verbose, "ApplicationIntent provided. Does not match ConnectionContext.ApplicationIntent, copying ConnectionContext and setting the ApplicationIntent");
                copyContext = true;
            }
            if (request.NonPooledConnection && !inputServer.ConnectionContext.NonPooledConnection)
            {
                Msg(request, MessageLevel.Verbose, "NonPooledConnection provided. Does not match ConnectionContext.NonPooledConnection, copying ConnectionContext and setting NonPooledConnection");
                copyContext = true;
            }
            // Pinned 812 reads "Test-Bound -Parameter StatementTimeout -and $inputObject...StatementTimeout -ne $StatementTimeout"
            // in command mode: -and is Test-Bound's -And switch and the comparison never runs, so a bound StatementTimeout
            // copies the context even when the value already matches.
            if (request.IsBound("StatementTimeout"))
            {
                Msg(request, MessageLevel.Verbose, "StatementTimeout provided. Does not match ConnectionContext.StatementTimeout, copying ConnectionContext and setting the StatementTimeout");
                copyContext = true;
            }
            if (request.DedicatedAdminConnection && !Regex.IsMatch(inputServer.ConnectionContext.ServerInstance ?? "", "^ADMIN:", RegexOptions.IgnoreCase))
            {
                Msg(request, MessageLevel.Verbose, "DedicatedAdminConnection provided. Does not match ConnectionContext.ServerInstance, copying ConnectionContext and setting the ServerInstance");
                copyContext = true;
            }

            if (createNewConnection)
            {
                state.IsNewConnection = true;
                // PS: reconstruct the Windows credential from the ConnectionContext and re-invoke
                // Connect-DbaInstance with all bound parameters plus the replaced
                // SqlInstance/SqlCredential (input resolution matrix row 3).
                SecureString secStringPassword = new SecureString();
                string connectAsUserPassword = inputServer.ConnectionContext.ConnectAsUserPassword;
                if (connectAsUserPassword != null)
                {
                    foreach (char passwordChar in connectAsUserPassword)
                        secStringPassword.AppendChar(passwordChar);
                }
                PSCredential serverCredentialFromSMO = new PSCredential(inputServer.ConnectionContext.ConnectAsUserName, secStringPassword);

                SmoConnectionRequest innerRequest = state.Request.Clone();
                innerRequest.Instance = new DbaInstanceParameter(inputServer.Name);
                innerRequest.LoopInstance = null;
                innerRequest.SqlCredential = serverCredentialFromSMO;
                if (innerRequest.BoundParameters != null)
                    innerRequest.BoundParameters.Add("SqlCredential");

                ConnectionResolution inner = ResolveInstance(innerRequest);
                // The PS recursion ran the inner call's TEPP/InitFields/hash registrations
                // before returning (its emitted server was captured, not written to the
                // pipeline). The TeppGatherScriptsFast execution is cmdlet-owned and is
                // skipped here; TabExpansionHost.TeppSyncDisabled defaults to true, so the
                // default path loses nothing.
                FinalizeConnection(inner, innerRequest);

                if (inner.Server != null)
                {
                    state.Server = inner.Server;
                }
                else
                {
                    // PS parity: under -SqlConnectionOnly the recursive call emitted a bare
                    // SqlConnection, and the outer flow then died on the next
                    // ConnectionContext access ("You cannot call a method on a null-valued
                    // expression"), surfacing as the generic connect failure.
                    throw new ConnectionResolutionException(ConnectionResolutionFailure.ConnectFailure, "Failure",
                        new InvalidOperationException("You cannot call a method on a null-valued expression."));
                }
            }
            else if (copyContext)
            {
                state.IsNewConnection = true;
                CopyServerContext(state, inputServer);
            }
            else
            {
                state.Server = inputServer;
            }
        }

        // Database engine editions that refuse USE and need a new connection for another database (pinned 962-971).
        private static readonly string[] NoDatabaseSwitchEditions = new string[] { "SqlDatabase", "SqlDataWarehouse", "SqlOnDemand" };

        /// <summary>
        /// The pinned copy of a passed-in server's ConnectionContext (public/Connect-DbaInstance.ps1 822-1024, upstream
        /// 0ea5fec52): the copy owns a connection of its own from Copy() on, so every path that leaves without building the
        /// server closes it. Settings a context with a fixed connection string refuses go into that string instead, when
        /// the string can still log in; otherwise the connection is refused, or, for -Database on an engine that takes a
        /// USE, the database is switched on the copy's own connection.
        /// </summary>
        private static void CopyServerContext(ResolveState state, Server inputServer)
        {
            SmoConnectionRequest request = state.Request;
            DbaInstanceParameter instance = state.Instance;

            ServerConnection connContext = inputServer.ConnectionContext.Copy();
            bool connContextTransferred = false;
            try
            {
                // A ServerConnection built from a SqlConnection refuses DatabaseName, NonPooledConnection and
                // ServerInstance once its connection string is set; those settings are collected here and put into the
                // connection string below instead. No readable property tells the two kinds of context apart.
                bool databaseNeedsSwitch = false;
                Hashtable connectionStringKeyword = new Hashtable(StringComparer.OrdinalIgnoreCase);
                if (!String.IsNullOrEmpty(request.ApplicationIntent))
                    connContext.ApplicationIntent = request.ApplicationIntent;
                if (request.NonPooledConnection)
                {
                    try
                    {
                        connContext.NonPooledConnection = true;
                    }
                    catch (Exception)
                    {
                        connectionStringKeyword["Pooling"] = false;
                    }
                }
                if (request.IsBound("StatementTimeout"))
                    connContext.StatementTimeout = request.StatementTimeout;
                if (request.DedicatedAdminConnection && !Regex.IsMatch(inputServer.ConnectionContext.ServerInstance ?? "", "^ADMIN:", RegexOptions.IgnoreCase))
                {
                    string dedicatedAdminServerInstance;
                    if (instance.IsLocalHost)
                    {
                        // Use localhost to avoid multiple IP resolution on multi-homed servers (issue #10151)
                        if (!String.Equals(instance.InstanceName, "MSSQLSERVER", StringComparison.OrdinalIgnoreCase))
                            dedicatedAdminServerInstance = String.Format("ADMIN:localhost\\{0}", instance.InstanceName);
                        else
                            dedicatedAdminServerInstance = "ADMIN:localhost";
                        // Trust the server certificate because 'localhost' may not match the certificate CN (e.g., FQDN), issue #10254
                        connContext.TrustServerCertificate = true;
                    }
                    else
                    {
                        dedicatedAdminServerInstance = "ADMIN:" + connContext.ServerInstance;
                    }
                    try
                    {
                        connContext.ServerInstance = dedicatedAdminServerInstance;
                    }
                    catch (Exception)
                    {
                        connectionStringKeyword["Data Source"] = dedicatedAdminServerInstance;
                        // On a fixed connection string the TrustServerCertificate assignment above does not reach the
                        // string, which is what the new connection is built from (#10254).
                        if (instance.IsLocalHost)
                            connectionStringKeyword["Trust Server Certificate"] = true;
                    }
                    try
                    {
                        connContext.NonPooledConnection = true;
                    }
                    catch (Exception)
                    {
                        connectionStringKeyword["Pooling"] = false;
                    }
                }
                if (!String.IsNullOrEmpty(request.Database))
                {
                    // DatabaseName instead of GetDatabaseConnection: the latter opens the copy and returns another
                    // context, whose connection nothing can ever close again.
                    try
                    {
                        connContext.DatabaseName = request.Database;
                    }
                    catch (Exception)
                    {
                        databaseNeedsSwitch = true;
                    }
                }

                // Whatever could not be assigned needs a new connection from a changed connection string, which only a
                // string that still carries the whole login can make.
                SqlConnectionStringBuilder connectionStringBuilder = new SqlConnectionStringBuilder(connContext.ConnectionString);
                if (!String.IsNullOrEmpty(request.ApplicationIntent) && !String.Equals(connectionStringBuilder.ApplicationIntent.ToString(), request.ApplicationIntent, StringComparison.OrdinalIgnoreCase))
                {
                    // SQL Server reads the intent at login; an assignment that never reached a fixed string must go in.
                    connectionStringKeyword["ApplicationIntent"] = request.ApplicationIntent;
                }
                string authenticationMethod = connectionStringBuilder.Authentication.ToString();
                SqlConnection copiedSqlConnection = connContext.SqlConnectionObject;
                bool connectionStringCanLogIn;
                if (connectionStringBuilder.IntegratedSecurity || !String.IsNullOrEmpty(copiedSqlConnection.AccessToken) || copiedSqlConnection.AccessTokenCallback != null)
                {
                    // Windows authentication needs no secret from the string; a token or its callback lives on the
                    // SqlConnection and survives a new connection string.
                    connectionStringCanLogIn = true;
                }
                else if (String.Equals(authenticationMethod, "ActiveDirectoryPassword", StringComparison.OrdinalIgnoreCase) || String.Equals(authenticationMethod, "ActiveDirectoryServicePrincipal", StringComparison.OrdinalIgnoreCase))
                {
                    // The only two Microsoft Entra methods that use a password of their own.
                    connectionStringCanLogIn = !String.IsNullOrEmpty(connectionStringBuilder.Password);
                }
                else if (!String.Equals(authenticationMethod, "NotSpecified", StringComparison.OrdinalIgnoreCase) && !String.Equals(authenticationMethod, "SqlPassword", StringComparison.OrdinalIgnoreCase))
                {
                    // Every other Entra method is passwordless; a client id in User ID is not a SQL Server login.
                    connectionStringCanLogIn = true;
                }
                else
                {
                    // Quality gate 1 (pinned 942): a SQL Server login, unnamed or as Authentication=SqlPassword, needs
                    // both halves in the string; an opened connection without Persist Security Info hides the password.
                    connectionStringCanLogIn = !String.IsNullOrEmpty(connectionStringBuilder.UserID) && !String.IsNullOrEmpty(connectionStringBuilder.Password);
                }

                if (databaseNeedsSwitch)
                {
                    if (connectionStringCanLogIn)
                    {
                        // As Initial Catalog the database is part of the pool key, as DatabaseName is (#9505); the only
                        // way that works on Azure SQL Database.
                        connectionStringKeyword["Initial Catalog"] = request.Database;
                        databaseNeedsSwitch = false;
                    }
                    else if (Array.Exists(NoDatabaseSwitchEditions, edition => String.Equals(edition, inputServer.ConnectionContext.DatabaseEngineEdition.ToString(), StringComparison.OrdinalIgnoreCase)))
                    {
                        // Read from the passed-in server, never the copy: reading it there connects the copy and locks
                        // every property assigned above. Azure SQL Database answers USE with error 40508.
                        throw new ConnectionResolutionException(ConnectionResolutionFailure.CopiedContextRefused,
                            String.Format("Cannot change the database of [{0}] to [{1}]: it needs a new connection, because Azure SQL Database does not support switching the database of an existing one, and the authentication of the connection that was passed in cannot be reproduced from its connection string. Connect with the instance name and -SqlCredential, or with an access token, instead.", instance, request.Database), null);
                    }
                }
                if (connectionStringKeyword.Count > 0)
                {
                    if (!connectionStringCanLogIn)
                    {
                        throw new ConnectionResolutionException(ConnectionResolutionFailure.CopiedContextRefused,
                            String.Format("Cannot apply the requested settings to [{0}]: they need a new connection, and the authentication of the connection that was passed in cannot be reproduced from its connection string. Connect with the instance name and -SqlCredential, or with an access token, instead.", instance), null);
                    }

                    List<string> changedKeywords = new List<string>();
                    foreach (object keyword in connectionStringKeyword.Keys)
                        changedKeywords.Add(keyword.ToString());
                    Msg(request, MessageLevel.Debug, String.Format("Connection context does not accept property assignments, using the connection string for: {0}", String.Join(", ", changedKeywords)));
                    // Setting the connection string of an open connection does not move it. The copy is a session of its
                    // own, so disconnecting it does not touch the caller.
                    connContext.Disconnect();
                    foreach (DictionaryEntry keyword in connectionStringKeyword)
                        connectionStringBuilder[(string)keyword.Key] = keyword.Value;
                    connContext.ConnectionString = connectionStringBuilder.ConnectionString;
                }
                if (databaseNeedsSwitch)
                {
                    // No new connection can be built, but this engine takes a USE, so the copy's own connection switches,
                    // keeping the parts of the login that live on the SqlConnection. The caller keeps its own database.
                    if (connContext.SqlConnectionObject.State != System.Data.ConnectionState.Open)
                        connContext.Connect();
                    connContext.SqlConnectionObject.ChangeDatabase(request.Database);
                }
                state.Server = new Server(connContext);
                connContextTransferred = true;
                if (!String.IsNullOrEmpty(request.Database) && !String.Equals(state.Server.ConnectionContext.CurrentDatabase, request.Database, StringComparison.OrdinalIgnoreCase))
                    Msg(request, MessageLevel.Warning, String.Format("Changing connection context to database {0} was not successful. Current database is {1}. Please open an issue on https://github.com/dataplat/dbatools/issues.", request.Database, state.Server.ConnectionContext.CurrentDatabase));
            }
            finally
            {
                if (!connContextTransferred)
                {
                    // Nothing else can reach this connection any more. Disconnect must not replace the error that
                    // brought us here.
                    try
                    {
                        connContext.Disconnect();
                    }
                    catch (Exception ex)
                    {
                        Msg(request, MessageLevel.Debug, String.Format("Disconnecting the copied connection context after a failed connect failed as well: {0}", ex.Message));
                    }
                }
            }
        }

        private static void BuildFromConnectionString(ResolveState state)
        {
            SmoConnectionRequest request = state.Request;

            // Create the server SMO in the same way as when passing a string (see #8962 for details).
            // Best way to get connection pooling to work is to use SqlConnectionInfo -> ServerConnection -> Server
            SqlConnectionInfo sqlConnectionInfo = new SqlConnectionInfo();

            // Set properties of SqlConnectionInfo based on the used properties of the connection string.
            string connectionString = NormalizeFailoverPartnerKey(state.ConnectionString);
            connectionString = EnsureInitialCatalogForFailoverPartner(connectionString);
            SqlConnectionStringBuilder csb = new SqlConnectionStringBuilder(connectionString);

            // The connection-string form of an Entra password sign-in needs the same provider as -AuthenticationType
            // ActiveDirectoryPassword (BuildFromString): SqlClient's own one signs in through the Windows account broker,
            // which fails without an interactive logon session.
            if (String.Equals(csb.Authentication.ToString(), "ActiveDirectoryPassword", StringComparison.OrdinalIgnoreCase))
            {
                string registration = EntraPasswordProviderRegistration.Process.EnsureRegistered();
                if (registration != null)
                    Msg(request, MessageLevel.Verbose, registration);
            }

            if (csb.ShouldSerialize("Data Source"))
            {
                Msg(request, MessageLevel.Debug, String.Format("ServerName will be set to '{0}'", csb.DataSource));
                sqlConnectionInfo.ServerName = csb.DataSource;
                csb.Remove("Data Source");
            }
            if (csb.ShouldSerialize("User ID"))
            {
                Msg(request, MessageLevel.Debug, String.Format("UserName will be set to '{0}'", csb.UserID));
                sqlConnectionInfo.UserName = csb.UserID;
                csb.Remove("User ID");
            }
            if (csb.ShouldSerialize("Password"))
            {
                Msg(request, MessageLevel.Debug, "Password will be set");
                sqlConnectionInfo.Password = csb.Password;
                csb.Remove("Password");
            }
            // look for 'Initial Catalog' and 'Database' in the connection string
            string specifiedDatabase = Convert.ToString(csb["Database"]);
            if (specifiedDatabase == "")
                specifiedDatabase = Convert.ToString(csb["Initial Catalog"]);
            if (!String.IsNullOrEmpty(request.Database) && !String.Equals(request.Database, specifiedDatabase, StringComparison.OrdinalIgnoreCase))
            {
                Msg(request, MessageLevel.Debug, String.Format("Database specified in connection string '{0}' does not match Database parameter '{1}'. Database parameter will be used.", specifiedDatabase, request.Database));
                // clear both, in order to not be overridden later by setting all AddtionalParameters
                if (csb.ShouldSerialize("Database"))
                    csb.Remove("Database");
                if (csb.ShouldSerialize("Initial Catalog"))
                    csb.Remove("Initial Catalog");
                sqlConnectionInfo.DatabaseName = request.Database;
            }

            // Add all remaining parts of the connection string as additional parameters.
            sqlConnectionInfo.AdditionalParameters = csb.ConnectionString;

            // Set properties based on used parameters.
            if (request.TrustServerCertificate)
            {
                Msg(request, MessageLevel.Debug, String.Format("TrustServerCertificate will be set to '{0}'", true));
                sqlConnectionInfo.TrustServerCertificate = true;
            }

            ServerConnection serverConnection = new ServerConnection(sqlConnectionInfo);
            state.Server = new Server(serverConnection);
        }

        private static void BuildFromString(ResolveState state)
        {
            SmoConnectionRequest request = state.Request;
            DbaInstanceParameter instance = state.Instance;

            // Identify authentication method
            string authType = state.IsAzure ? "azure " : "local ";
            string username = null;
            if (request.SqlCredential != null)
            {
                username = NormalizeConnectUserName(request.SqlCredential.UserName, Environment.GetEnvironmentVariable("USERDOMAIN"), Environment.GetEnvironmentVariable("COMPUTERNAME"));
                if (username.Contains("@") || username.Contains("\\"))
                    authType += "ad";
                else
                    authType += "sql";
            }
            else if (LanguagePrimitives.IsTrue(request.AccessToken))
            {
                // PS: elseif ($AccessToken) - truthiness, so an empty-string token counts as
                // absent (cross-model review 2026-07-07 finding 3).
                authType += "token";
            }
            else
            {
                authType += "integrated";
            }
            Msg(request, MessageLevel.Verbose, String.Format("authentication method is '{0}'", authType));
            // PS: -in is case-insensitive and ValidateSet passes the user's casing through
            // (cross-model review 2026-07-07 finding 1).
            bool authenticationTypeUsesSqlCredential = String.Equals(request.AuthenticationType, "ActiveDirectoryPassword", StringComparison.OrdinalIgnoreCase) || String.Equals(request.AuthenticationType, "ActiveDirectoryServicePrincipal", StringComparison.OrdinalIgnoreCase);

            // Best way to get connection pooling to work is to use SqlConnectionInfo -> ServerConnection -> Server
            SqlConnectionInfo sqlConnectionInfo = new SqlConnectionInfo(state.ServerName);

            // But if we have an AccessToken, we need ConnectionString -> SqlConnection -> ServerConnection -> Server
            // We will get the ConnectionString from the SqlConnectionInfo, so let's move on

            // I will list all properties of SqlConnectionInfo and set them if value is provided

            //AccessToken            Property   Microsoft.SqlServer.Management.Common.IRenewableToken AccessToken {get;set;}
            // This parameter needs an IRenewableToken and we currently support only a non renewable token

            //AdditionalParameters   Property   string AdditionalParameters {get;set;}
            if (!String.IsNullOrEmpty(request.AppendConnectionString))
            {
                Msg(request, MessageLevel.Debug, String.Format("AdditionalParameters will be appended by '{0};'", request.AppendConnectionString));
                sqlConnectionInfo.AdditionalParameters = (sqlConnectionInfo.AdditionalParameters ?? "") + request.AppendConnectionString + ";";
            }
            if (!String.IsNullOrEmpty(request.FailoverPartner))
            {
                Msg(request, MessageLevel.Debug, String.Format("AdditionalParameters will be appended by 'FailoverPartner={0};'", request.FailoverPartner));
                // Quality gate 1: the pin appends "FailoverPartner=<value>;" (pinned 1138), a keyword
                // Microsoft.Data.SqlClient rejects ("Keyword not supported: 'failoverpartner'"), so the
                // documented parameter never connects, and it places the caller's text unescaped. The builder
                // writes the keyword SqlClient knows and quotes the value. SqlClient also refuses a Failover
                // Partner without an Initial Catalog when the ServerConnection is built, before the pinned
                // retry with Initial Catalog=master (pinned 1473) can run, so without a catalog from -Database
                // or AppendConnectionString the port adds that catalog here, as the pin does for a connection
                // string (pinned 1035-1041).
                SqlConnectionStringBuilder failoverPartnerBuilder = new SqlConnectionStringBuilder();
                failoverPartnerBuilder.FailoverPartner = request.FailoverPartner;
                if (String.IsNullOrEmpty(request.Database) && !AppendedCatalogIsSet(sqlConnectionInfo.AdditionalParameters))
                {
                    failoverPartnerBuilder.InitialCatalog = "master";
                }
                sqlConnectionInfo.AdditionalParameters = (sqlConnectionInfo.AdditionalParameters ?? "") + failoverPartnerBuilder.ConnectionString + ";";
            }
            if (request.MultiSubnetFailover)
            {
                Msg(request, MessageLevel.Debug, "AdditionalParameters will be appended by 'MultiSubnetFailover=True;'");
                sqlConnectionInfo.AdditionalParameters = (sqlConnectionInfo.AdditionalParameters ?? "") + "MultiSubnetFailover=True;";
            }
            if (request.AlwaysEncrypted)
            {
                Msg(request, MessageLevel.Debug, "AdditionalParameters will be appended by 'Column Encryption Setting=enabled;'");
                sqlConnectionInfo.AdditionalParameters = (sqlConnectionInfo.AdditionalParameters ?? "") + "Column Encryption Setting=enabled;";
            }
            // Pinned 1148-1167: explicit retry parameters go in through the builder, and an explicit
            // ConnectTimeout wins over a Connect Timeout in AdditionalParameters.
            if (request.IsAnyBound("ConnectRetryCount", "ConnectRetryInterval", "ConnectTimeout"))
            {
                SqlConnectionStringBuilder connectionOptionStringBuilder = String.IsNullOrEmpty(sqlConnectionInfo.AdditionalParameters)
                    ? new SqlConnectionStringBuilder()
                    : new SqlConnectionStringBuilder(sqlConnectionInfo.AdditionalParameters);
                if (request.IsBound("ConnectRetryCount"))
                {
                    Msg(request, MessageLevel.Debug, String.Format("Connect Retry Count will be set to '{0}'", request.ConnectRetryCount));
                    connectionOptionStringBuilder["Connect Retry Count"] = request.ConnectRetryCount;
                }
                if (request.IsBound("ConnectRetryInterval"))
                {
                    Msg(request, MessageLevel.Debug, String.Format("Connect Retry Interval will be set to '{0}'", request.ConnectRetryInterval));
                    connectionOptionStringBuilder["Connect Retry Interval"] = request.ConnectRetryInterval;
                }
                if (request.IsBound("ConnectTimeout"))
                {
                    // ConnectionTimeout is set through SqlConnectionInfo below. Removing a value from
                    // AdditionalParameters makes the explicit parameter win over AppendConnectionString.
                    connectionOptionStringBuilder.Remove("Connect Timeout");
                }
                sqlConnectionInfo.AdditionalParameters = connectionOptionStringBuilder.ConnectionString;
            }

            //ApplicationIntent      Property   string ApplicationIntent {get;set;}
            if (!String.IsNullOrEmpty(request.ApplicationIntent))
            {
                Msg(request, MessageLevel.Debug, String.Format("ApplicationIntent will be set to '{0}'", request.ApplicationIntent));
                sqlConnectionInfo.ApplicationIntent = request.ApplicationIntent;
            }

            //ApplicationName        Property   string ApplicationName {get;set;}
            if (!String.IsNullOrEmpty(request.ClientName))
            {
                Msg(request, MessageLevel.Debug, String.Format("ApplicationName will be set to '{0}'", request.ClientName));
                sqlConnectionInfo.ApplicationName = request.ClientName;
            }

            //Authentication         Property   Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod Authentication {get;set;}
            //[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryIntegrated
            //[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryInteractive
            //[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::ActiveDirectoryPassword
            //[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::NotSpecified
            //[Microsoft.SqlServer.Management.Common.SqlConnectionInfo+AuthenticationMethod]::SqlPassword
            if (!String.IsNullOrEmpty(request.AuthenticationType))
            {
                Msg(request, MessageLevel.Debug, String.Format("Authentication will be set to '{0}' (from AuthenticationType parameter)", request.AuthenticationType));
                // PS: [AuthenticationMethod]::$AuthenticationType - static member access by
                // string is case-insensitive (cross-model review 2026-07-07 finding 1).
                sqlConnectionInfo.Authentication = (SqlConnectionInfo.AuthenticationMethod)Enum.Parse(typeof(SqlConnectionInfo.AuthenticationMethod), request.AuthenticationType, true);
                Msg(request, MessageLevel.Debug, String.Format("UseIntegratedSecurity will be set to '{0}' for {1}", false, request.AuthenticationType));
                sqlConnectionInfo.UseIntegratedSecurity = false;
            }
            else if (String.Equals(authType, "azure integrated", StringComparison.Ordinal))
            {
                // Azure AD integrated security
                // TODO: This is not tested / How can we test that?
                Msg(request, MessageLevel.Debug, "Authentication will be set to 'ActiveDirectoryIntegrated'");
                sqlConnectionInfo.Authentication = SqlConnectionInfo.AuthenticationMethod.ActiveDirectoryIntegrated;
            }
            else if (String.Equals(authType, "azure ad", StringComparison.Ordinal))
            {
                // Azure AD account with password
                Msg(request, MessageLevel.Debug, "Authentication will be set to 'ActiveDirectoryPassword'");
                sqlConnectionInfo.Authentication = SqlConnectionInfo.AuthenticationMethod.ActiveDirectoryPassword;
            }

            // SqlClient's own ActiveDirectoryPassword provider signs in through the Windows account broker, which fails
            // without an interactive logon session; the first such connect in the process puts dbatools' provider in
            // place of SqlClient's default, and only of the default (EntraPasswordProviderRegistration).
            if (sqlConnectionInfo.Authentication == SqlConnectionInfo.AuthenticationMethod.ActiveDirectoryPassword)
            {
                string registration = EntraPasswordProviderRegistration.Process.EnsureRegistered();
                if (registration != null)
                    Msg(request, MessageLevel.Verbose, registration);
            }

            //ConnectionProtocol     Property   Microsoft.SqlServer.Management.Common.NetworkProtocol ConnectionProtocol {get;set;}
            if (!String.IsNullOrEmpty(request.NetworkProtocol))
            {
                Msg(request, MessageLevel.Debug, String.Format("ConnectionProtocol will be set to '{0}'", request.NetworkProtocol));
                // PS enum conversion on assignment is case-insensitive (finding 1).
                sqlConnectionInfo.ConnectionProtocol = (NetworkProtocol)Enum.Parse(typeof(NetworkProtocol), request.NetworkProtocol, true);
            }

            //ConnectionString       Property   string ConnectionString {get;}
            // Only a getter, not a setter - so don't touch

            //ConnectionTimeout      Property   int ConnectionTimeout {get;set;}
            // Pinned 1214: an explicit -ConnectTimeout 0 (wait indefinitely) is applied too.
            if (request.ConnectTimeout != 0 || request.IsBound("ConnectTimeout"))
            {
                Msg(request, MessageLevel.Debug, String.Format("ConnectionTimeout will be set to '{0}'", request.ConnectTimeout));
                sqlConnectionInfo.ConnectionTimeout = request.ConnectTimeout;
            }

            //DatabaseName           Property   string DatabaseName {get;set;}
            if (!String.IsNullOrEmpty(request.Database))
            {
                Msg(request, MessageLevel.Debug, String.Format("Database will be set to '{0}'", request.Database));
                sqlConnectionInfo.DatabaseName = request.Database;
            }

            if (!Regex.IsMatch(instance.ToString(), "localdb", RegexOptions.IgnoreCase))
            {
                //EncryptConnection      Property   bool EncryptConnection {get;set;}
                Msg(request, MessageLevel.Debug, String.Format("EncryptConnection will be set to '{0}'", request.EncryptConnection));
                sqlConnectionInfo.EncryptConnection = request.EncryptConnection;
            }
            else
            {
                Msg(request, MessageLevel.Verbose, "localdb detected, skipping unsupported keyword 'Encryption'");
            }

            //MaxPoolSize            Property   int MaxPoolSize {get;set;}
            if (request.MaxPoolSize != 0)
            {
                Msg(request, MessageLevel.Debug, String.Format("MaxPoolSize will be set to '{0}'", request.MaxPoolSize));
                sqlConnectionInfo.MaxPoolSize = request.MaxPoolSize;
            }

            //MinPoolSize            Property   int MinPoolSize {get;set;}
            if (request.MinPoolSize != 0)
            {
                Msg(request, MessageLevel.Debug, String.Format("MinPoolSize will be set to '{0}'", request.MinPoolSize));
                sqlConnectionInfo.MinPoolSize = request.MinPoolSize;
            }

            //PacketSize             Property   int PacketSize {get;set;}
            if (request.PacketSize != 0)
            {
                Msg(request, MessageLevel.Debug, String.Format("PacketSize will be set to '{0}'", request.PacketSize));
                sqlConnectionInfo.PacketSize = request.PacketSize;
            }

            //Password               Property   string Password {get;set;}
            // We will use SecurePassword

            //PoolConnectionLifeTime Property   int PoolConnectionLifeTime {get;set;}
            if (request.PooledConnectionLifetime != 0)
            {
                Msg(request, MessageLevel.Debug, String.Format("PoolConnectionLifeTime will be set to '{0}'", request.PooledConnectionLifetime));
                sqlConnectionInfo.PoolConnectionLifeTime = request.PooledConnectionLifetime;
            }

            //Pooled                 Property   System.Data.SqlTypes.SqlBoolean Pooled {get;set;}
            // TODO: Do we need or want the else path or is it the default and we better don't touch it?
            if (request.NonPooledConnection)
            {
                Msg(request, MessageLevel.Debug, String.Format("Pooled will be set to '{0}'", false));
                sqlConnectionInfo.Pooled = false;
            }
            else
            {
                Msg(request, MessageLevel.Debug, String.Format("Pooled will be set to '{0}'", true));
                sqlConnectionInfo.Pooled = true;
            }

            //QueryTimeout           Property   int QueryTimeout {get;set;}
            // We use ConnectionContext.StatementTimeout instead

            //SecurePassword         Property   securestring SecurePassword {get;set;}
            if (authenticationTypeUsesSqlCredential || authType == "azure ad" || authType == "azure sql" || authType == "local sql")
            {
                Msg(request, MessageLevel.Debug, "SecurePassword will be set");
                // PS: $SqlCredential.Password on a $null credential yields $null (the Desktop
                // Tenant branch clears SqlCredential after token acquisition) - never throw
                // (cross-model review 2026-07-07 finding 2).
                sqlConnectionInfo.SecurePassword = request.SqlCredential == null ? null : request.SqlCredential.Password;
            }

            //ServerCaseSensitivity  Property   Microsoft.SqlServer.Management.Common.ServerCaseSensitivity ServerCaseSensitivity {get;set;}

            //ServerName             Property   string ServerName {get;set;}
            // Was already set by the constructor.

            //ServerType             Property   Microsoft.SqlServer.Management.Common.ConnectionType ServerType {get;}
            // Only a getter, not a setter - so don't touch

            //ServerVersion          Property   Microsoft.SqlServer.Management.Common.ServerVersion ServerVersion {get;set;}
            // We can set that? No, we don't want to...

            //TrustServerCertificate Property   bool TrustServerCertificate {get;set;}
            Msg(request, MessageLevel.Debug, String.Format("TrustServerCertificate will be set to '{0}'", request.TrustServerCertificate));
            sqlConnectionInfo.TrustServerCertificate = request.TrustServerCertificate;

            //UseIntegratedSecurity  Property   bool UseIntegratedSecurity {get;set;}
            // We rely on the default unless AuthenticationType already set it above or UserName changes it automatically.

            //UserName               Property   string UserName {get;set;}
            if (authenticationTypeUsesSqlCredential || authType == "azure ad" || authType == "azure sql" || authType == "local sql")
            {
                Msg(request, MessageLevel.Debug, String.Format("UserName will be set to '{0}'", username));
                sqlConnectionInfo.UserName = username;
            }

            //WorkstationId          Property   string WorkstationId {get;set;}
            if (!String.IsNullOrEmpty(request.WorkstationId))
            {
                Msg(request, MessageLevel.Debug, String.Format("WorkstationId will be set to '{0}'", request.WorkstationId));
                sqlConnectionInfo.WorkstationId = request.WorkstationId;
            }

            // Pinned 1308-1311: checked before any connection object is built.
            if (authType == "local ad" && String.IsNullOrEmpty(request.AuthenticationType) && Environment.OSVersion.Platform != PlatformID.Win32NT)
            {
                // PS: Stop-Function (no -Continue) followed by return - the cmdlet stops
                // processing the remaining instances, exactly like the PS source did.
                throw new ConnectionResolutionException(ConnectionResolutionFailure.WindowsCredentialOnUnix,
                    "Cannot use Windows credentials to connect when host is Linux or OS X. Use kinit instead. See https://github.com/dataplat/dbatools/issues/7602 for more info.", null);
            }

            ServerConnection serverConnection;
            // If we have an AccessToken, we will build a SqlConnection
            // PS: if ($AccessToken) - truthiness (finding 3)
            if (LanguagePrimitives.IsTrue(request.AccessToken))
            {
                string tokenText = UnwrapAccessToken(state);
                Msg(request, MessageLevel.Debug, "We have an AccessToken and build a SqlConnection with that token");
                Msg(request, MessageLevel.Debug, "But we remove 'Integrated Security=True;'");
                // TODO: How do we get a ConnectionString without this?
                Msg(request, MessageLevel.Debug, "Building SqlConnection from SqlConnectionInfo.ConnectionString");
                string tokenConnectionString = RemoveIntegratedSecurity(sqlConnectionInfo.ConnectionString);
                SqlConnection sqlConnection = new SqlConnection(tokenConnectionString);
                Msg(request, MessageLevel.Debug, "SqlConnection was built");
                sqlConnection.AccessToken = tokenText;
                Msg(request, MessageLevel.Debug, "Building ServerConnection from SqlConnection");
                serverConnection = new ServerConnection(sqlConnection);
                Msg(request, MessageLevel.Debug, "ServerConnection was built");
            }
            else if (authType == "local ad" && String.IsNullOrEmpty(request.AuthenticationType))
            {
                // Pinned 1356-1364 (upstream 343cd853c): the Windows credential authenticates through SqlClient's SSPI
                // provider instead of impersonation. The pin takes this branch whenever the provider type loads; the
                // library carries it on both editions, so it always does.
                Msg(request, MessageLevel.Debug, "Building SqlConnection with explicit Windows credential SSPI provider");
                SqlConnection sqlConnection = new SqlConnection(sqlConnectionInfo.ConnectionString);
                NetworkCredentialSspiContextProvider sspiContextProvider = new NetworkCredentialSspiContextProvider(request.SqlCredential.GetNetworkCredential());
                sqlConnection.SspiContextProvider = sspiContextProvider;
                serverConnection = new ServerConnection(sqlConnection);
                state.UsesCredentialSspiProvider = true;
                Msg(request, MessageLevel.Debug, "ServerConnection was built with explicit Windows credential SSPI provider");
            }
            else
            {
                Msg(request, MessageLevel.Debug, "Building ServerConnection from SqlConnectionInfo");
                serverConnection = new ServerConnection(sqlConnectionInfo);
                Msg(request, MessageLevel.Debug, "ServerConnection was built");
            }

            if (authType == "local ad" && String.IsNullOrEmpty(request.AuthenticationType) && !state.UsesCredentialSspiProvider)
            {
                Msg(request, MessageLevel.Debug, String.Format("ConnectAsUser will be set to '{0}'", true));
                serverConnection.ConnectAsUser = true;

                Msg(request, MessageLevel.Debug, String.Format("ConnectAsUserName will be set to '{0}'", username));
                serverConnection.ConnectAsUserName = username;

                Msg(request, MessageLevel.Debug, "ConnectAsUserPassword will be set");
                // ServerConnection.ConnectAsUserPassword is string-typed; the PS source made the
                // same GetNetworkCredential() unwrap at this boundary (BP-401 exception).
                serverConnection.ConnectAsUserPassword = request.SqlCredential.GetNetworkCredential().Password;
            }

            Msg(request, MessageLevel.Debug, "Building Server from ServerConnection");
            state.Server = new Server(serverConnection);
            Msg(request, MessageLevel.Debug, "Server was built");

            // Set properties of ConnectionContext that are not part of SqlConnectionInfo
            if (request.IsBound("BatchSeparator"))
            {
                Msg(request, MessageLevel.Debug, String.Format("Setting ConnectionContext.BatchSeparator to '{0}'", request.BatchSeparator));
                state.Server.ConnectionContext.BatchSeparator = request.BatchSeparator;
            }
            if (request.IsBound("LockTimeout"))
            {
                Msg(request, MessageLevel.Debug, String.Format("Setting ConnectionContext.LockTimeout to '{0}'", request.LockTimeout));
                state.Server.ConnectionContext.LockTimeout = request.LockTimeout;
            }
            if (request.MultipleActiveResultSets)
            {
                Msg(request, MessageLevel.Debug, "Setting ConnectionContext.MultipleActiveResultSets to 'True'");
                state.Server.ConnectionContext.MultipleActiveResultSets = true;
            }
            if (request.IsBound("SqlExecutionModes"))
            {
                Msg(request, MessageLevel.Debug, String.Format("Setting ConnectionContext.SqlExecutionModes to '{0}'", request.SqlExecutionModes));
                state.Server.ConnectionContext.SqlExecutionModes = (SqlExecutionModes)Enum.Parse(typeof(SqlExecutionModes), request.SqlExecutionModes);
            }
            Msg(request, MessageLevel.Debug, String.Format("Setting ConnectionContext.StatementTimeout to '{0}'", request.StatementTimeout));
            state.Server.ConnectionContext.StatementTimeout = request.StatementTimeout;
            if (request.NonPooledConnection && !state.Server.ConnectionContext.NonPooledConnection)
            {
                Msg(request, MessageLevel.Debug, "Setting ConnectionContext.NonPooledConnection to 'True'");
                state.Server.ConnectionContext.NonPooledConnection = true;
            }
        }

        private static string UnwrapAccessToken(ResolveState state)
        {
            SmoConnectionRequest request = state.Request;

            // Check if token was created by New-DbaAzAccessToken or Get-AzAccessToken
            Msg(request, MessageLevel.Debug, "AccessToken detected, checking for string, SecureString, or PsObjectIRenewableToken");
            object current = request.AccessToken;
            PSObject wrapped = PSObject.AsPSObject(current);
            if (wrapped.Members["GetAccessToken"] != null)
            {
                Msg(request, MessageLevel.Debug, "Token was generated using New-DbaAzAccessToken, executing GetAccessToken()");
                current = wrapped.Methods["GetAccessToken"].Invoke();
                wrapped = PSObject.AsPSObject(current);
            }
            if (wrapped.Members["Token"] != null)
            {
                Msg(request, MessageLevel.Debug, "Token was generated using Get-AzAccessToken, getting .Token");
                object tokenValue = wrapped.Properties["Token"].Value;
                // Check if the Token property is a SecureString (Azure PowerShell v14+)
                SecureString secureToken = UnwrapInput(tokenValue) as SecureString;
                if (secureToken != null)
                {
                    Msg(request, MessageLevel.Debug, "Token is SecureString (Azure PowerShell v14+), converting to plain text");
                    try
                    {
                        current = ConvertFromSecurePass(secureToken);
                        Msg(request, MessageLevel.Debug, "Successfully converted SecureString token to plain text");
                    }
                    catch (Exception ex)
                    {
                        throw new ConnectionResolutionException(ConnectionResolutionFailure.AccessTokenConversion,
                            String.Format("Failed to convert SecureString AccessToken to plain text: {0}", ex.Message), ex);
                    }
                }
                else
                {
                    Msg(request, MessageLevel.Debug, "Token is plain text string (Azure PowerShell v13 and earlier)");
                    current = tokenValue;
                }
            }
            else
            {
                SecureString directSecure = UnwrapInput(current) as SecureString;
                if (directSecure != null)
                {
                    // Handle direct SecureString AccessToken input
                    Msg(request, MessageLevel.Debug, "AccessToken is directly provided as SecureString, converting to plain text");
                    try
                    {
                        current = ConvertFromSecurePass(directSecure);
                        Msg(request, MessageLevel.Debug, "Successfully converted direct SecureString AccessToken to plain text");
                    }
                    catch (Exception ex)
                    {
                        throw new ConnectionResolutionException(ConnectionResolutionFailure.AccessTokenConversion,
                            String.Format("Failed to convert SecureString AccessToken to plain text: {0}", ex.Message), ex);
                    }
                }
            }
            // The PS source reassigned $AccessToken, so the unwrapped token persists for the
            // remaining instances of the same call.
            request.AccessToken = current;
            return current == null ? null : current.ToString();
        }

        private static string ConvertFromSecurePass(SecureString inputObject)
        {
            // private/functions/ConvertFrom-SecurePass.ps1: decrypt on Linux, Windows and OSX.
            // Delegates to the TB-016 parity port (opus TB-016): the previous inline
            // System.Net.NetworkCredential variant returned "" for a null SecureString where
            // the PS helper this comment cites THROWS from the PSCredential ctor (probed both
            // editions) - unreachable here because both call sites null-guard first, but the
            // single compiled counterpart keeps the contracts from drifting.
            return Dataplat.Dbatools.Utility.SecurePass.ToPlainText(inputObject);
        }
    }
}
