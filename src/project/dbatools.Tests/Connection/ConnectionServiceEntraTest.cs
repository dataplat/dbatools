using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Reflection;
using System.Security;
using System.Threading;
using System.Threading.Tasks;
using Dataplat.Dbatools.Commands;
using Dataplat.Dbatools.Connection;
using Microsoft.Data.SqlClient;
using Microsoft.Identity.Client;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Connection.Test
{
    /// <summary>
    /// Coverage for the Entra ID half of the auth matrix now that it lives in the service
    /// layer: the accepted flows, which of them cannot proceed without a credential, the
    /// tenant-plus-client-id service-principal trigger, and the per-framework split between
    /// minting an access token and building an Active Directory Service Principal connection
    /// string. All of it is connection-string construction, so none of it needs a cloud - the
    /// built string is asserted by parsing it with the driver's own builder.
    /// </summary>
    [TestClass]
    public class ConnectionServiceEntraTest
    {
        private const string ClientId = "21f5633f-6776-4bab-b878-bbd5e3e5ed72";
        private const string Secret = "s3cr3t";

        private static PSCredential MakeCredential(string userName, string password)
        {
            SecureString secure = new SecureString();
            foreach (char c in password)
                secure.AppendChar(c);
            secure.MakeReadOnly();
            return new PSCredential(userName, secure);
        }

        [TestMethod]
        public void EntraAuthentication_ListsTheSixFlowsInParameterOrder()
        {
            string[] expected = new string[]
            {
                "ActiveDirectoryIntegrated",
                "ActiveDirectoryInteractive",
                "ActiveDirectoryPassword",
                "ActiveDirectoryServicePrincipal",
                "ActiveDirectoryManagedIdentity",
                "ActiveDirectoryDeviceCodeFlow"
            };
            CollectionAssert.AreEqual(expected, ConnectionService.EntraAuthentication.All);
        }

        [TestMethod]
        public void AuthenticationTypeValidateSet_IsGeneratedFromTheServiceDefinition()
        {
            // The point of the consolidation: the parameter surface and the connection logic
            // cannot drift because they read the same constants.
            PropertyInfo property = typeof(ConnectDbaInstanceCommand).GetProperty("AuthenticationType");
            Assert.IsNotNull(property, "Connect-DbaInstance no longer exposes AuthenticationType");
            ValidateSetAttribute validateSet = (ValidateSetAttribute)Attribute.GetCustomAttribute(property, typeof(ValidateSetAttribute));
            Assert.IsNotNull(validateSet, "AuthenticationType carries no ValidateSet");

            string[] declared = new string[validateSet.ValidValues.Count];
            validateSet.ValidValues.CopyTo(declared, 0);
            CollectionAssert.AreEqual(ConnectionService.EntraAuthentication.All, declared);
        }

        [TestMethod]
        public void RequiresSqlCredential_CoversOnlyThePasswordAndServicePrincipalFlows()
        {
            Assert.IsTrue(ConnectionService.RequiresSqlCredential(ConnectionService.EntraAuthentication.Password));
            Assert.IsTrue(ConnectionService.RequiresSqlCredential(ConnectionService.EntraAuthentication.ServicePrincipal));

            Assert.IsFalse(ConnectionService.RequiresSqlCredential(ConnectionService.EntraAuthentication.Integrated));
            Assert.IsFalse(ConnectionService.RequiresSqlCredential(ConnectionService.EntraAuthentication.Interactive));
            Assert.IsFalse(ConnectionService.RequiresSqlCredential(ConnectionService.EntraAuthentication.ManagedIdentity));
            Assert.IsFalse(ConnectionService.RequiresSqlCredential(ConnectionService.EntraAuthentication.DeviceCodeFlow));
            Assert.IsFalse(ConnectionService.RequiresSqlCredential(null));
            Assert.IsFalse(ConnectionService.RequiresSqlCredential(""));
        }

        [TestMethod]
        public void RequiresSqlCredential_IgnoresCasingLikeTheParameterBinder()
        {
            // ValidateSet passes the caller's casing straight through, so the check that
            // rejects a missing credential has to be case-insensitive or it silently lets an
            // uncredentialed connection attempt through.
            Assert.IsTrue(ConnectionService.RequiresSqlCredential("activedirectorypassword"));
            Assert.IsTrue(ConnectionService.RequiresSqlCredential("ACTIVEDIRECTORYSERVICEPRINCIPAL"));
        }

        [TestMethod]
        public void IsClientIdUserName_AcceptsOnlyGuidShapedNames()
        {
            Assert.IsTrue(ConnectionService.IsClientIdUserName(ClientId));
            Assert.IsTrue(ConnectionService.IsClientIdUserName(ClientId.ToUpperInvariant()));
            Assert.IsFalse(ConnectionService.IsClientIdUserName("appuser@contoso.com"));
            Assert.IsFalse(ConnectionService.IsClientIdUserName(ClientId.Substring(1)));
            Assert.IsFalse(ConnectionService.IsClientIdUserName("prefix-" + ClientId));
            Assert.IsFalse(ConnectionService.IsClientIdUserName(""));
            Assert.IsFalse(ConnectionService.IsClientIdUserName(null));
        }

        [TestMethod]
        public void IsServicePrincipalTenantFlow_NeedsTenantClientIdAndNoToken()
        {
            PSCredential clientCredential = MakeCredential(ClientId, Secret);

            Assert.IsTrue(ConnectionService.IsServicePrincipalTenantFlow("contoso.onmicrosoft.com", null, clientCredential));

            Assert.IsFalse(ConnectionService.IsServicePrincipalTenantFlow(null, null, clientCredential), "no tenant");
            Assert.IsFalse(ConnectionService.IsServicePrincipalTenantFlow("", null, clientCredential), "empty tenant");
            Assert.IsFalse(ConnectionService.IsServicePrincipalTenantFlow("contoso.onmicrosoft.com", null, null), "no credential");
            Assert.IsFalse(ConnectionService.IsServicePrincipalTenantFlow("contoso.onmicrosoft.com", null, MakeCredential("appuser@contoso.com", Secret)), "not a client id");
            Assert.IsFalse(ConnectionService.IsServicePrincipalTenantFlow("contoso.onmicrosoft.com", "already-a-token", clientCredential), "token supplied");
        }

        [TestMethod]
        public void IsServicePrincipalTenantFlow_TreatsAnEmptyTokenAsAbsent()
        {
            // The source tested truthiness, not null: an empty-string token must NOT suppress
            // the service-principal flow.
            PSCredential clientCredential = MakeCredential(ClientId, Secret);
            Assert.IsTrue(ConnectionService.IsServicePrincipalTenantFlow("contoso.onmicrosoft.com", "", clientCredential));
            Assert.IsTrue(ConnectionService.IsServicePrincipalTenantFlow("contoso.onmicrosoft.com", false, clientCredential));
        }

        [TestMethod]
        public void PlanServicePrincipalConnection_ReturnsNullWhenTheFlowDoesNotApply()
        {
            Assert.IsNull(ConnectionService.PlanServicePrincipalConnection(null, null, MakeCredential(ClientId, Secret)));
            Assert.IsNull(ConnectionService.PlanServicePrincipalConnection("contoso.onmicrosoft.com", null, null));
        }

        [TestMethod]
        public void PlanServicePrincipalConnection_TakesTheStrategyThisFrameworkSupports()
        {
            ServicePrincipalPlan plan = ConnectionService.PlanServicePrincipalConnection(
                "contoso.onmicrosoft.com", null, MakeCredential(ClientId, Secret));
            Assert.IsNotNull(plan);
            Assert.AreEqual(ConnectionService.RuntimeServicePrincipalStrategy, plan.Strategy);

#if NETFRAMEWORK
            // .NET Framework can mint a renewable service-principal token.
            Assert.AreEqual(ServicePrincipalStrategy.AccessTokenAcquisition, plan.Strategy);
            Assert.AreEqual(ConnectionService.ServicePrincipalTokenMessage, plan.VerboseMessage);
#else
            // .NET cannot, and expresses the same intent as a connection string instead.
            Assert.AreEqual(ServicePrincipalStrategy.ConnectionStringRewrite, plan.Strategy);
            Assert.AreEqual(ConnectionService.ServicePrincipalRewriteMessage, plan.VerboseMessage);
#endif
        }

        [TestMethod]
        public void NewServicePrincipalToken_IsTheRenewableAzureSqlDbToken()
        {
            PsObjectIRenewableToken token = ConnectionService.NewServicePrincipalToken(
                "contoso.onmicrosoft.com", MakeCredential(ClientId, Secret));
            Assert.AreEqual("https://database.windows.net/", token.Resource);
            Assert.AreEqual("contoso.onmicrosoft.com", token.Tenant);
            Assert.AreEqual(ClientId, token.UserId);
            Assert.AreEqual(Secret, token.ClientSecret);
        }

        [TestMethod]
        public void BuildServicePrincipalConnectionString_CarriesTheAuthTokensThroughTheDriverBuilder()
        {
            string built = ConnectionService.BuildServicePrincipalConnectionString(
                "myserver.database.windows.net", "AdventureWorks", ClientId, Secret);

            SqlConnectionStringBuilder builder = new SqlConnectionStringBuilder(built);
            Assert.AreEqual(SqlAuthenticationMethod.ActiveDirectoryServicePrincipal, builder.Authentication);
            Assert.AreEqual("myserver.database.windows.net", builder.DataSource);
            Assert.AreEqual("AdventureWorks", builder.InitialCatalog);
            Assert.AreEqual(ClientId, builder.UserID);
            Assert.AreEqual(Secret, builder.Password);
        }

        [TestMethod]
        public void BuildServicePrincipalConnectionString_OmitsTheDatabaseWhenNoneWasRequested()
        {
            string built = ConnectionService.BuildServicePrincipalConnectionString(
                "myserver.database.windows.net", null, ClientId, Secret);
            Assert.IsFalse(built.Contains("Database=") || built.Contains("Initial Catalog="),
                "a database segment appeared for a request that named no database");

            SqlConnectionStringBuilder builder = new SqlConnectionStringBuilder(built);
            Assert.AreEqual(SqlAuthenticationMethod.ActiveDirectoryServicePrincipal, builder.Authentication);
            Assert.AreEqual("", builder.InitialCatalog);
            Assert.AreEqual(ClientId, builder.UserID);

            string emptyDatabase = ConnectionService.BuildServicePrincipalConnectionString(
                "myserver.database.windows.net", "", ClientId, Secret);
            Assert.AreEqual(built, emptyDatabase, "an empty database must be treated as none, like the request default");
        }

        /// <summary>
        /// A client secret is arbitrary text: it can hold the very characters a connection
        /// string uses as syntax. A semicolon is the one that used to be fatal - it ended the
        /// Password segment early and the whole string stopped parsing, with an error naming
        /// only a character index. Every one of these secrets must arrive at the driver
        /// byte-identical to what the caller supplied.
        /// </summary>
        [TestMethod]
        public void BuildServicePrincipalConnectionString_CarriesASecretHoldingConnectionStringSyntax()
        {
            string[] awkwardSecrets = new string[]
            {
                "ab;cd",            // the keyword separator - unparseable before this was escaped
                "ab=cd",            // the key/value separator
                "ab'cd",            // single quote
                "ab\"cd",           // double quote
                "a;b='c\"d;",       // all of them at once, with a trailing separator
                "Ab8Q~xY.z-K_1",    // the shape Azure actually mints
            };

            foreach (string secret in awkwardSecrets)
            {
                string built = ConnectionService.BuildServicePrincipalConnectionString(
                    "myserver.database.windows.net", "AdventureWorks", ClientId, secret);

                SqlConnectionStringBuilder builder = new SqlConnectionStringBuilder(built);
                Assert.AreEqual(secret, builder.Password, "the secret did not survive the round trip: " + secret);
                Assert.AreEqual(ClientId, builder.UserID, "the user id was disturbed by the secret: " + secret);
                Assert.AreEqual("AdventureWorks", builder.InitialCatalog, "the database was disturbed by the secret: " + secret);
                Assert.AreEqual("myserver.database.windows.net", builder.DataSource, "the server was disturbed by the secret: " + secret);
                Assert.AreEqual(SqlAuthenticationMethod.ActiveDirectoryServicePrincipal, builder.Authentication,
                    "the authentication method was disturbed by the secret: " + secret);
            }
        }

        /// <summary>
        /// The same escaping has to hold for the other three values. They are hostname-, GUID-
        /// and identifier-shaped in this flow, so this is a guard against the concatenation
        /// coming back rather than a bug seen in the field.
        /// </summary>
        [TestMethod]
        public void BuildServicePrincipalConnectionString_CarriesAServerDatabaseAndUserIdHoldingSeparators()
        {
            string built = ConnectionService.BuildServicePrincipalConnectionString(
                "my;server", "Adventure;Works", "client;id", Secret);

            SqlConnectionStringBuilder builder = new SqlConnectionStringBuilder(built);
            Assert.AreEqual("my;server", builder.DataSource);
            Assert.AreEqual("Adventure;Works", builder.InitialCatalog);
            Assert.AreEqual("client;id", builder.UserID);
            Assert.AreEqual(Secret, builder.Password);
        }
    }

    /// <summary>
    /// dbatools' ActiveDirectoryPassword provider and its once-per-process registration. The provider is driven
    /// through a recording token source, so no tenant is needed; the registration is driven through a private
    /// provider table, so SqlClient's process-wide table is never touched by these tests.
    /// </summary>
    [TestClass]
    public class EntraPasswordAuthenticationProviderTest
    {
        private const string GoodPassword = "g00d-Pa55";
        private const string WrongPassword = "wr0ng-Pa55";
        private const string UserName = "user@contoso.com";
        private const string Authority = "https://login.microsoftonline.com/contoso.onmicrosoft.com/";

        private sealed class RecordingSource
        {
            public readonly List<string> Passwords = new List<string>();
            public readonly List<CancellationToken> Cancellations = new List<CancellationToken>();
            public readonly List<string> Scopes = new List<string>();
            public readonly List<string> Authorities = new List<string>();
            public readonly List<string> Users = new List<string>();
            public Exception Failure;
            public bool Cancel;

            public Task<SqlAuthenticationToken> Acquire(string authority, string scope, string userId, string password, CancellationToken cancellation)
            {
                Passwords.Add(password);
                Cancellations.Add(cancellation);
                Scopes.Add(scope);
                Authorities.Add(authority);
                Users.Add(userId);
                TaskCompletionSource<SqlAuthenticationToken> completion = new TaskCompletionSource<SqlAuthenticationToken>();
                if (Cancel)
                    completion.SetCanceled();
                else if (Failure != null)
                    completion.SetException(Failure);
                else if (password == GoodPassword)
                    completion.SetResult(new SqlAuthenticationToken("token-for-" + userId, DateTimeOffset.UtcNow.AddHours(1)));
                else
                    completion.SetException(new MsalServiceException("invalid_grant", "AADSTS50126: Error validating credentials due to invalid username or password."));
                return completion.Task;
            }
        }

        private sealed class CallerProvider : SqlAuthenticationProvider
        {
            public override Task<SqlAuthenticationToken> AcquireTokenAsync(SqlAuthenticationParameters parameters)
            {
                throw new NotSupportedException("never called by these tests");
            }

            public override bool IsSupported(SqlAuthenticationMethod authenticationMethod)
            {
                return true;
            }
        }

        private sealed class ProviderTable
        {
            public readonly Dictionary<SqlAuthenticationMethod, SqlAuthenticationProvider> Providers = new Dictionary<SqlAuthenticationMethod, SqlAuthenticationProvider>();
            public int SetCalls;
            public bool Accept = true;

            public SqlAuthenticationProvider Get(SqlAuthenticationMethod method)
            {
                lock (Providers)
                {
                    SqlAuthenticationProvider provider;
                    return Providers.TryGetValue(method, out provider) ? provider : null;
                }
            }

            public bool Set(SqlAuthenticationMethod method, SqlAuthenticationProvider provider)
            {
                Interlocked.Increment(ref SetCalls);
                if (!Accept)
                    return false;
                lock (Providers)
                    Providers[method] = provider;
                return true;
            }

            public EntraPasswordProviderRegistration Registration()
            {
                return new EntraPasswordProviderRegistration(Get, Set, delegate { return new EntraPasswordAuthenticationProvider(); });
            }

            /// <summary>What SqlClient's default looks like: one provider object for every Entra method.</summary>
            public static ProviderTable WithSqlClientDefault(out SqlAuthenticationProvider shared)
            {
                ProviderTable table = new ProviderTable();
                shared = new ActiveDirectoryAuthenticationProvider();
                foreach (SqlAuthenticationMethod method in Enum.GetValues(typeof(SqlAuthenticationMethod)))
                {
                    if (method != SqlAuthenticationMethod.NotSpecified && method != SqlAuthenticationMethod.SqlPassword)
                        table.Providers[method] = shared;
                }
                return table;
            }
        }

        private static SqlAuthenticationParameters Parameters(string resource, string password, int connectionTimeout)
        {
            return new SqlAuthenticationParameters(EntraPasswordAuthenticationProvider.PasswordMethod, "sqlwhale22", "master", resource, Authority, UserName, password, Guid.NewGuid(), connectionTimeout);
        }

        [TestMethod]
        public void Provider_WrongPasswordAfterASuccess_IsSentToEntraAndRefused()
        {
            // Watchman condition 1: no silent path, so a token from a good sign-in is never handed to a wrong password.
            RecordingSource source = new RecordingSource();
            EntraPasswordAuthenticationProvider provider = new EntraPasswordAuthenticationProvider(source.Acquire);

            SqlAuthenticationToken token = provider.AcquireTokenAsync(Parameters("https://database.windows.net", GoodPassword, 30)).GetAwaiter().GetResult();
            Assert.AreEqual("token-for-" + UserName, token.AccessToken);

            EntraPasswordAuthenticationException refused = null;
            try
            {
                provider.AcquireTokenAsync(Parameters("https://database.windows.net", WrongPassword, 30)).GetAwaiter().GetResult();
            }
            catch (EntraPasswordAuthenticationException exception)
            {
                refused = exception;
            }

            Assert.IsNotNull(refused, "a wrong password after a good sign-in was not refused");
            CollectionAssert.AreEqual(new string[] { GoodPassword, WrongPassword }, source.Passwords, "the wrong password did not go to the username and password flow");
            Assert.IsInstanceOfType(refused, typeof(SqlAuthenticationProviderException));
            Assert.AreEqual("invalid_grant", refused.FailureCode);
            Assert.AreEqual(EntraPasswordAuthenticationProvider.PasswordMethod, refused.Method);
            Assert.IsFalse(refused.ShouldRetry);
            Assert.AreEqual(EntraPasswordAuthenticationProvider.FailurePrefix + "AADSTS50126: Error validating credentials due to invalid username or password.", refused.Message);
            Assert.IsInstanceOfType(refused.InnerException, typeof(MsalServiceException));
            // Watchman condition 3: no password in the failure.
            Assert.IsFalse(refused.ToString().Contains(WrongPassword));
            Assert.IsFalse(refused.ToString().Contains(GoodPassword));
        }

        [TestMethod]
        public void Provider_ConnectionTimeoutZero_HasNoLimit()
        {
            // Watchman condition 2: 0 is "wait indefinitely", never an already-cancelled token.
            RecordingSource source = new RecordingSource();
            EntraPasswordAuthenticationProvider provider = new EntraPasswordAuthenticationProvider(source.Acquire);

            SqlAuthenticationToken token = provider.AcquireTokenAsync(Parameters("https://database.windows.net", GoodPassword, 0)).GetAwaiter().GetResult();

            Assert.IsNotNull(token);
            Assert.AreEqual(1, source.Cancellations.Count);
            Assert.IsFalse(source.Cancellations[0].CanBeCanceled);
            Assert.IsFalse(source.Cancellations[0].IsCancellationRequested);
        }

        [TestMethod]
        public void Provider_ConnectionTimeoutAboveZero_IsALiveLimit()
        {
            RecordingSource source = new RecordingSource();
            EntraPasswordAuthenticationProvider provider = new EntraPasswordAuthenticationProvider(source.Acquire);

            provider.AcquireTokenAsync(Parameters("https://database.windows.net", GoodPassword, 30)).GetAwaiter().GetResult();

            Assert.IsTrue(source.Cancellations[0].CanBeCanceled);
            Assert.IsFalse(source.Cancellations[0].IsCancellationRequested);
        }

        [TestMethod]
        public void Provider_ForwardsAuthorityAndUser_AndAddsTheDefaultScopeOnce()
        {
            RecordingSource source = new RecordingSource();
            EntraPasswordAuthenticationProvider provider = new EntraPasswordAuthenticationProvider(source.Acquire);

            provider.AcquireTokenAsync(Parameters("https://database.windows.net", GoodPassword, 30)).GetAwaiter().GetResult();
            provider.AcquireTokenAsync(Parameters("https://database.windows.net/.default", GoodPassword, 30)).GetAwaiter().GetResult();

            CollectionAssert.AreEqual(new string[] { "https://database.windows.net/.default", "https://database.windows.net/.default" }, source.Scopes);
            CollectionAssert.AreEqual(new string[] { Authority, Authority }, source.Authorities);
            CollectionAssert.AreEqual(new string[] { UserName, UserName }, source.Users);
        }

        [TestMethod]
        public void Provider_SupportsActiveDirectoryPasswordOnly()
        {
            EntraPasswordAuthenticationProvider provider = new EntraPasswordAuthenticationProvider(new RecordingSource().Acquire);
            foreach (SqlAuthenticationMethod method in Enum.GetValues(typeof(SqlAuthenticationMethod)))
                Assert.AreEqual(method == EntraPasswordAuthenticationProvider.PasswordMethod, provider.IsSupported(method), method.ToString());
        }

        [TestMethod]
        public void Provider_OtherFailures_PassThroughUnchanged()
        {
            RecordingSource source = new RecordingSource();
            InvalidOperationException failure = new InvalidOperationException("not an MSAL failure");
            source.Failure = failure;
            EntraPasswordAuthenticationProvider provider = new EntraPasswordAuthenticationProvider(source.Acquire);

            Exception thrown = null;
            try
            {
                provider.AcquireTokenAsync(Parameters("https://database.windows.net", GoodPassword, 30)).GetAwaiter().GetResult();
            }
            catch (Exception exception)
            {
                thrown = exception;
            }

            Assert.AreSame(failure, thrown);
        }

        [TestMethod]
        public void Provider_CancelledAcquisition_StaysCancelled()
        {
            RecordingSource source = new RecordingSource();
            source.Cancel = true;
            EntraPasswordAuthenticationProvider provider = new EntraPasswordAuthenticationProvider(source.Acquire);

            Task<SqlAuthenticationToken> acquisition = provider.AcquireTokenAsync(Parameters("https://database.windows.net", GoodPassword, 30));
            try
            {
                acquisition.Wait();
            }
            catch (AggregateException)
            {
                // The cancelled task is the assertion below; Wait reports it as an AggregateException.
            }

            Assert.IsTrue(acquisition.IsCanceled);
        }

        [TestMethod]
        public void Provider_SynchronousMsalFailure_IsReportedAsSqlClientExpects()
        {
            EntraPasswordAuthenticationProvider provider = new EntraPasswordAuthenticationProvider(delegate (string authority, string scope, string userId, string password, CancellationToken cancellation)
            {
                throw new MsalClientException("invalid_authority", "The authority is not valid.");
            });

            Task<SqlAuthenticationToken> acquisition = provider.AcquireTokenAsync(Parameters("https://database.windows.net", GoodPassword, 30));

            Assert.IsTrue(acquisition.IsFaulted);
            EntraPasswordAuthenticationException refused = acquisition.Exception.InnerException as EntraPasswordAuthenticationException;
            Assert.IsNotNull(refused);
            Assert.AreEqual("invalid_authority", refused.FailureCode);
            Assert.AreEqual(EntraPasswordAuthenticationProvider.FailurePrefix + "The authority is not valid.", refused.Message);
        }

        [TestMethod]
        public void Registration_ReplacesSqlClientsDefault_ForActiveDirectoryPasswordOnly()
        {
            SqlAuthenticationProvider shared;
            ProviderTable table = ProviderTable.WithSqlClientDefault(out shared);

            string message = table.Registration().EnsureRegistered();

            Assert.AreEqual(EntraPasswordProviderRegistration.RegisteredMessage, message);
            Assert.IsInstanceOfType(table.Get(EntraPasswordAuthenticationProvider.PasswordMethod), typeof(EntraPasswordAuthenticationProvider));
            foreach (KeyValuePair<SqlAuthenticationMethod, SqlAuthenticationProvider> entry in table.Providers)
            {
                if (entry.Key != EntraPasswordAuthenticationProvider.PasswordMethod)
                    Assert.AreSame(shared, entry.Value, entry.Key.ToString());
            }
        }

        [TestMethod]
        public void Registration_KeepsACallersOwnProviderType()
        {
            ProviderTable table = new ProviderTable();
            CallerProvider caller = new CallerProvider();
            foreach (SqlAuthenticationMethod method in Enum.GetValues(typeof(SqlAuthenticationMethod)))
            {
                if (method != SqlAuthenticationMethod.NotSpecified && method != SqlAuthenticationMethod.SqlPassword)
                    table.Providers[method] = caller;
            }

            Assert.IsNull(table.Registration().EnsureRegistered());
            Assert.AreSame(caller, table.Get(EntraPasswordAuthenticationProvider.PasswordMethod));
            Assert.AreEqual(0, table.SetCalls);
        }

        [TestMethod]
        public void Registration_KeepsACallersPerMethodActiveDirectoryAuthenticationProvider()
        {
            SqlAuthenticationProvider shared;
            ProviderTable table = ProviderTable.WithSqlClientDefault(out shared);
            ActiveDirectoryAuthenticationProvider caller = new ActiveDirectoryAuthenticationProvider();
            table.Providers[EntraPasswordAuthenticationProvider.PasswordMethod] = caller;

            Assert.IsNull(table.Registration().EnsureRegistered());
            Assert.AreSame(caller, table.Get(EntraPasswordAuthenticationProvider.PasswordMethod));
            Assert.AreEqual(0, table.SetCalls);
        }

        [TestMethod]
        public void Registration_KeepsWhatIsThereWhenNoProviderIsRegistered()
        {
            ProviderTable table = new ProviderTable();

            Assert.IsNull(table.Registration().EnsureRegistered());
            Assert.IsNull(table.Get(EntraPasswordAuthenticationProvider.PasswordMethod));
            Assert.AreEqual(0, table.SetCalls);
        }

        [TestMethod]
        public void Registration_NeverOverwritesALaterCallerRegistration()
        {
            SqlAuthenticationProvider shared;
            ProviderTable table = ProviderTable.WithSqlClientDefault(out shared);
            EntraPasswordProviderRegistration registration = table.Registration();

            Assert.AreEqual(EntraPasswordProviderRegistration.RegisteredMessage, registration.EnsureRegistered());
            // The caller puts SqlClient's own provider back after dbatools' first ActiveDirectoryPassword connect.
            table.Providers[EntraPasswordAuthenticationProvider.PasswordMethod] = shared;

            Assert.IsNull(registration.EnsureRegistered());
            Assert.AreSame(shared, table.Get(EntraPasswordAuthenticationProvider.PasswordMethod));
            Assert.AreEqual(1, table.SetCalls);
        }

        [TestMethod]
        public void Registration_HappensAtMostOnce_AcrossThreads()
        {
            SqlAuthenticationProvider shared;
            ProviderTable table = ProviderTable.WithSqlClientDefault(out shared);
            EntraPasswordProviderRegistration registration = table.Registration();
            int registered = 0;

            Parallel.For(0, 64, delegate (int index)
            {
                if (registration.EnsureRegistered() != null)
                    Interlocked.Increment(ref registered);
            });

            Assert.AreEqual(1, registered);
            Assert.AreEqual(1, table.SetCalls);
        }

        [TestMethod]
        public void Registration_RefusedSetProvider_KeepsTheExistingProvider()
        {
            SqlAuthenticationProvider shared;
            ProviderTable table = ProviderTable.WithSqlClientDefault(out shared);
            table.Accept = false;

            Assert.AreEqual(EntraPasswordProviderRegistration.RefusedMessage, table.Registration().EnsureRegistered());
            Assert.AreSame(shared, table.Get(EntraPasswordAuthenticationProvider.PasswordMethod));
            Assert.AreEqual(1, table.SetCalls);
        }
    }
}
