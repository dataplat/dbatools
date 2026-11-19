using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Parameter;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Connection
{
    /// <summary>
    /// The C# resolution of Connect-DbaInstance, written fresh from
    /// public/Connect-DbaInstance.ps1: the full input resolution matrix (live Server
    /// passthrough and context copy, SqlConnection, RegisteredServer, connection string,
    /// String), the full auth matrix including the Entra flows and AccessToken shapes, the
    /// dedicated admin connection rewrite, the verify query with the
    /// AllowTrustServerCertificate and failover-partner retries, MinimumVersion and
    /// AzureUnsupported rejection, PS-exact decoration, TEPP seeding, SetDefaultInitFields
    /// priming, and the ActiveConnections registry (Add-ConnectionHashValue parity).
    /// The Connect-DbaInstance cmdlet drives ResolveInstance directly so every Stop-Function
    /// call site keeps its exact control flow; internal callers use the GetServer facade.
    /// </summary>
    public static partial class ConnectionService
    {
        /// <summary>The Azure SQL Database domain suffix used for Azure detection when a request does not carry its own.</summary>
        public static string AzureDomain = "database.windows.net";

        /// <summary>
        /// Resolves a connection request to a connected SMO Server, per the input resolution
        /// and auth matrices, then runs the new-connection registrations (TEPP seeding,
        /// SetDefaultInitFields, connection hash). Throws on failure;
        /// DbaInstanceCmdlet.ConnectInstance converts failures into the canonical
        /// Stop-Function shape.
        /// </summary>
        /// <param name="request">The connection request</param>
        /// <returns>A connected, decorated SMO Server</returns>
        public static Server GetServer(SmoConnectionRequest request)
        {
            if (request == null)
                throw new ArgumentNullException("request");
            if (request.Instance == null)
                throw new ArgumentException("The request carries no target instance", "request");

            request.ApplyConfigurationDefaults();
            ConnectionResolution resolution = ResolveInstance(request);
            if (resolution.Server == null)
                throw new InvalidOperationException("The request resolved to a bare SqlConnection; use GetSqlConnection for SqlConnectionOnly requests");
            FinalizeConnection(resolution, request);
            return resolution.Server;
        }

        /// <summary>
        /// The -SqlConnectionOnly path: resolves the request and returns
        /// ConnectionContext.SqlConnectionObject, registered in the active-connection registry.
        /// </summary>
        /// <param name="request">The connection request</param>
        /// <returns>The bare SqlConnection</returns>
        public static SqlConnection GetSqlConnection(SmoConnectionRequest request)
        {
            if (request == null)
                throw new ArgumentNullException("request");
            if (request.Instance == null)
                throw new ArgumentException("The request carries no target instance", "request");

            request.SqlConnectionOnly = true;
            request.ApplyConfigurationDefaults();
            ConnectionResolution resolution = ResolveInstance(request);
            return resolution.SqlConnection;
        }

        /// <summary>
        /// Builds the cache key per the frozen shape:
        /// lower(FullSmoName) + "|" + database + "|" + authority + "|" + applicationIntent.
        /// </summary>
        /// <param name="instance">The target instance</param>
        /// <param name="request">The connection request</param>
        /// <returns>The cache key</returns>
        public static string BuildCacheKey(DbaInstanceParameter instance, SmoConnectionRequest request)
        {
            string database = request.Database;
            if (String.IsNullOrEmpty(database))
                database = "";

            string authority = "integrated";
            if (request.SqlCredential != null)
            {
                string userName = NormalizeUserName(request.SqlCredential.UserName);
                if (userName.Contains("\\") || userName.Contains("@"))
                    authority = String.Format("ad|{0}", userName);
                else
                    authority = String.Format("sql|{0}", userName);
            }

            string intent = request.ApplicationIntent;
            if (String.IsNullOrEmpty(intent))
                intent = "";

            return String.Format("{0}|{1}|{2}|{3}", instance.FullSmoName.ToLowerInvariant(), database.ToLowerInvariant(), authority.ToLowerInvariant(), intent.ToLowerInvariant());
        }

        #region String helpers (public for MSTest coverage)
        /// <summary>
        /// private/functions/Convert-ConnectionString.ps1: rewrites the legacy System.Data
        /// keyword spellings onto the Microsoft.Data.SqlClient synonyms.
        /// https://docs.microsoft.com/en-us/sql/connect/ado-net/introduction-microsoft-data-sqlclient-namespace?view=sql-server-ver15#new-connection-string-property-synonyms
        /// </summary>
        /// <param name="connectionString">The raw connection string</param>
        /// <returns>The normalized connection string</returns>
        public static string ConvertConnectionString(string connectionString)
        {
            if (connectionString == null)
                return null;
            string connstring = connectionString;
            connstring = connstring.Replace("Application Intent", "ApplicationIntent");
            connstring = connstring.Replace("Connect Retry Count", "ConnectRetryCount");
            connstring = connstring.Replace("Connect Retry Interval", "ConnectRetryInterval");
            connstring = connstring.Replace("Pool Blocking Period", "PoolBlockingPeriod");
            connstring = connstring.Replace("Multiple Active Result Sets", "MultipleActiveResultSets");
            connstring = connstring.Replace("Multiple Subnet Failover", "MultiSubnetFailover");
            connstring = connstring.Replace("Trust Server Certificate", "TrustServerCertificate");
            return connstring;
        }

        /// <summary>PS: $connectionString -replace "(?i)\bFailoverPartner\s*=", "Failover Partner="</summary>
        /// <param name="connectionString">The connection string</param>
        /// <returns>The connection string with the spaced Failover Partner keyword</returns>
        public static string NormalizeFailoverPartnerKey(string connectionString)
        {
            if (connectionString == null)
                return null;
            return Regex.Replace(connectionString, "(?i)\\bFailoverPartner\\s*=", "Failover Partner=");
        }

        /// <summary>
        /// When a Failover Partner is present without an Initial Catalog/Database, appends
        /// Initial Catalog=master; (the .NET SqlClient pool requires a catalog with mirroring
        /// targets). Mirrors Connect-DbaInstance.ps1 exactly, including the trailing-semicolon
        /// handling.
        /// </summary>
        /// <param name="connectionString">The connection string</param>
        /// <returns>The connection string, possibly with Initial Catalog=master; appended</returns>
        public static string EnsureInitialCatalogForFailoverPartner(string connectionString)
        {
            if (connectionString == null)
                return null;
            string result = connectionString;
            if (Regex.IsMatch(result, "(?i)\\bFailover Partner\\s*=") && !Regex.IsMatch(result, "(?i)\\b(?:Initial Catalog|Database)\\s*="))
            {
                if (Regex.IsMatch(result, ";$"))
                    result += "Initial Catalog=master;";
                else
                    result += ";Initial Catalog=master;";
            }
            return result;
        }

        /// <summary>
        /// Appends Initial Catalog=master; for the failover-partner retry when no catalog is
        /// present (the retry path variant that does not require the Failover Partner keyword,
        /// because the SERVER reported the requirement).
        /// </summary>
        /// <param name="connectionString">The connection string</param>
        /// <returns>The connection string with a catalog guaranteed</returns>
        public static string EnsureInitialCatalogMaster(string connectionString)
        {
            if (connectionString == null)
                return null;
            string result = connectionString;
            if (!Regex.IsMatch(result, "(?i)\\b(?:Initial Catalog|Database)\\s*="))
            {
                if (Regex.IsMatch(result, ";$"))
                    result += "Initial Catalog=master;";
                else
                    result += ";Initial Catalog=master;";
            }
            return result;
        }

        /// <summary>
        /// Whether -AppendConnectionString text names a catalog with a value, the condition under which the port's
        /// -FailoverPartner fix leaves out its Initial Catalog=master. An empty "Database=" names none, so SqlClient
        /// would still refuse the partner without a catalog. Text the builder cannot parse is judged by the keyword,
        /// as before.
        /// </summary>
        /// <param name="additionalParameters">The appended connection string text, or null</param>
        /// <returns>True when the text sets Initial Catalog (or Database) to a non-empty value</returns>
        public static bool AppendedCatalogIsSet(string additionalParameters)
        {
            if (String.IsNullOrEmpty(additionalParameters))
                return false;
            try
            {
                return !String.IsNullOrEmpty(new SqlConnectionStringBuilder(additionalParameters).InitialCatalog);
            }
            catch (ArgumentException)
            {
                return Regex.IsMatch(additionalParameters, "(?i)\\b(?:Initial Catalog|Database)\\s*=");
            }
        }

        /// <summary>PS: $connectionString -replace 'Integrated Security=True;', '' (case-insensitive).</summary>
        /// <param name="connectionString">The connection string</param>
        /// <returns>The connection string without the integrated-security keyword</returns>
        public static string RemoveIntegratedSecurity(string connectionString)
        {
            if (connectionString == null)
                return null;
            return Regex.Replace(connectionString, "Integrated Security=True;", "", RegexOptions.IgnoreCase);
        }

        /// <summary>
        /// The AllowTrustServerCertificate retry edit: flips Trust Server Certificate=False to
        /// True (case-insensitive, like the PS -replace) or appends the keyword when absent.
        /// </summary>
        /// <param name="connectionString">The failing connection string</param>
        /// <returns>The trusted connection string</returns>
        public static string ApplyTrustServerCertificate(string connectionString)
        {
            if (connectionString == null)
                return null;
            string result = Regex.Replace(connectionString, "Trust Server Certificate=False", "Trust Server Certificate=True", RegexOptions.IgnoreCase);
            if (!Regex.IsMatch(result, "Trust Server Certificate", RegexOptions.IgnoreCase))
            {
                if (Regex.IsMatch(result, ";$"))
                    result += "Trust Server Certificate=True;";
                else
                    result += ";Trust Server Certificate=True;";
            }
            return result;
        }

        /// <summary>
        /// Whether a connection string already trusts the server certificate, the condition under which the
        /// AllowTrustServerCertificate retry leaves the context's string alone. Text the builder cannot parse
        /// counts as not trusting, so the retry edits it.
        /// </summary>
        /// <param name="connectionString">The ServerConnection's connection string</param>
        /// <returns>True when TrustServerCertificate is True in the string</returns>
        public static bool ConnectionStringTrustsServerCertificate(string connectionString)
        {
            if (String.IsNullOrEmpty(connectionString))
                return false;
            try
            {
                return new SqlConnectionStringBuilder(connectionString).TrustServerCertificate;
            }
            catch (ArgumentException)
            {
                return false;
            }
        }

        /// <summary>
        /// The String-path username normalization of Connect-DbaInstance.ps1:
        /// a leading backslash is trimmed, and domain\user is rewritten to user@domain when
        /// the environment looks domain-joined (USERDOMAIN differs from COMPUTERNAME).
        /// </summary>
        /// <param name="userName">The credential user name</param>
        /// <param name="userDomain">The USERDOMAIN environment value</param>
        /// <param name="computerName">The COMPUTERNAME environment value</param>
        /// <returns>The normalized user name</returns>
        public static string NormalizeConnectUserName(string userName, string userDomain, string computerName)
        {
            if (userName == null)
                return null;
            string username = userName.TrimStart('\\');
            // support both ad\username and username@ad
            // username@ad works only for domain joined and workgroup
            // nobody remembers why, but username@ad is preferred
            // so we switch ad\username to username@ad only doing a raw guess
            // when USERDOMAIN -ne COMPUTERNAME, we're probably joined to ad
            if (!String.Equals(userDomain, computerName, StringComparison.OrdinalIgnoreCase))
            {
                if (username.Contains("\\"))
                {
                    string[] parts = username.Split('\\');
                    string domain = parts[0];
                    string login;
                    if (parts.Length == 2)
                        login = parts[1];
                    else
                        // PS multiple-assignment parity: $domain, $login = $username.Split("\")
                        // leaves $login as the remaining array, which stringifies space-joined.
                        login = String.Join(" ", parts, 1, parts.Length - 1);
                    username = String.Format("{0}@{1}", login, domain);
                }
            }
            return username;
        }

        /// <summary>
        /// private/functions/utility/Hide-ConnectionString.ps1: masks the password for debug
        /// display, or returns the verbatim failure text when the string cannot be parsed.
        /// </summary>
        /// <param name="connectionString">The connection string to mask</param>
        /// <returns>The masked connection string</returns>
        public static string HideConnectionString(string connectionString)
        {
            try
            {
                SqlConnectionStringBuilder connStringBuilder = new SqlConnectionStringBuilder(connectionString);
                if (!String.IsNullOrEmpty(connStringBuilder.Password))
                    connStringBuilder.Password = "".PadLeft(8, '*');
                return connStringBuilder.ConnectionString;
            }
            catch
            {
                return "Failed to mask the connection string";
            }
        }

        /// <summary>
        /// private/functions/Get-ErrorMessage.ps1: the deepest non-empty exception message
        /// within the first six levels of the chain (the PS walk checks InnerException depth
        /// five first, then shallower, then the exception itself).
        /// </summary>
        /// <param name="exception">The failure</param>
        /// <returns>The deepest meaningful message</returns>
        public static string GetDeepErrorMessage(Exception exception)
        {
            if (exception == null)
                return null;
            string deepest = null;
            Exception current = exception;
            int depth = 0;
            while (current != null && depth <= 5)
            {
                if (!String.IsNullOrEmpty(current.Message))
                    deepest = current.Message;
                current = current.InnerException;
                depth++;
            }
            return deepest;
        }

        /// <summary>
        /// The Azure detection of Connect-DbaInstance.ps1:
        /// $instance.ComputerName -match $AzureDomain -or $instance.InputObject.ComputerName -match $AzureDomain
        /// with the domain regex-escaped in the begin block.
        /// </summary>
        /// <param name="instance">The target instance</param>
        /// <param name="escapedAzureDomainPattern">The Regex.Escape()d azure domain</param>
        /// <returns>Whether the target is Azure</returns>
        public static bool IsAzureInstance(DbaInstanceParameter instance, string escapedAzureDomainPattern)
        {
            if (instance == null)
                return false;
            string computerName = instance.ComputerName;
            if (computerName == null)
                computerName = "";
            if (Regex.IsMatch(computerName, escapedAzureDomainPattern, RegexOptions.IgnoreCase))
                return true;
            object inputComputerName = SmoServerExtensions.GetPSProperty(instance.InputObject, "ComputerName");
            string inputComputerText = inputComputerName == null ? "" : inputComputerName.ToString();
            return Regex.IsMatch(inputComputerText, escapedAzureDomainPattern, RegexOptions.IgnoreCase);
        }
        #endregion String helpers (public for MSTest coverage)

        #region Configuration readers
        /// <summary>Raw ConfigurationHost value for a config key, or null when unset.</summary>
        /// <param name="key">The lowercase config key</param>
        /// <returns>The raw value</returns>
        public static object GetConfigurationValue(string key)
        {
            Config config;
            if (ConfigurationHost.Configurations.TryGetValue(key, out config) && config != null)
                return config.Value;
            return null;
        }

        internal static string GetConfigString(string key, string fallback)
        {
            object raw = GetConfigurationValue(key);
            if (raw == null)
                return fallback;
            return raw.ToString();
        }

        internal static int GetConfigInt(string key, int fallback)
        {
            object raw = GetConfigurationValue(key);
            if (raw == null)
                return fallback;
            try { return Convert.ToInt32(raw); }
            catch { return fallback; }
        }

        internal static bool GetConfigBool(string key)
        {
            object raw = GetConfigurationValue(key);
            if (raw == null)
                return false;
            if (raw is bool)
                return (bool)raw;
            try { return Convert.ToBoolean(raw); }
            catch { return false; }
        }
        #endregion Configuration readers

        #region Internal plumbing
        private static void Msg(SmoConnectionRequest request, Dataplat.Dbatools.Message.MessageLevel level, string message)
        {
            // PipelineStoppedException from the cmdlet's WriteMessage must propagate, so no
            // swallowing here.
            if (request != null && request.MessageCallback != null)
                request.MessageCallback(level, message);
        }

        private static string NormalizeUserName(string userName)
        {
            if (String.IsNullOrEmpty(userName))
                return userName;
            string normalized = userName;
            // A leading backslash is stripped; .\user stays local per the PS normalization.
            if (normalized.StartsWith("\\", StringComparison.Ordinal))
                normalized = normalized.Substring(1);
            return normalized;
        }

        private static void AddNoteProperty(System.Management.Automation.PSObject wrapped, string name, object value)
        {
            // Add-Member -Force semantics: replace when present.
            if (wrapped.Properties[name] != null)
                wrapped.Properties.Remove(name);
            wrapped.Properties.Add(new System.Management.Automation.PSNoteProperty(name, value));
        }

        private static object UnwrapInput(object inputObject)
        {
            System.Management.Automation.PSObject wrapped = inputObject as System.Management.Automation.PSObject;
            if (wrapped != null)
                return wrapped.BaseObject;
            return inputObject;
        }

        private static string CollectMessages(Exception exception)
        {
            // PS triaged $_.Exception.Message; SMO wraps the SqlClient message as the
            // ConnectionFailureException message so the immediate message usually carries the
            // keywords. Matching over the (bounded) message chain keeps the retry triggers
            // robust to wrapper differences between the PS and compiled invocation paths
            // (libmigration rule: match the exception MESSAGE CHAIN, never ToString()).
            List<string> messages = new List<string>();
            Exception current = exception;
            while (current != null && messages.Count < 10)
            {
                messages.Add(current.Message);
                current = current.InnerException;
            }
            return String.Join(" | ", messages.ToArray());
        }
        #endregion Internal plumbing
    }
}
