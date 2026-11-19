using System;
using System.Collections.Concurrent;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Data.SqlClient;
using Microsoft.Identity.Client;

namespace Dataplat.Dbatools.Connection
{
    /// <summary>
    /// Acquires one Microsoft Entra token for a user name and password, given the authority, the scope, the user,
    /// the password and the cancellation the caller allows. The provider's only way to reach Entra; unit tests
    /// replace it so they never need a tenant.
    /// </summary>
    internal delegate Task<SqlAuthenticationToken> EntraPasswordTokenSource(string authority, string scope, string userId, string password, CancellationToken cancellation);

    /// <summary>
    /// The failure SqlClient reports for a refused Microsoft Entra password sign-in. SqlClient shows a provider's
    /// SqlAuthenticationProviderException as "Error code 0x&lt;FailureCode&gt; &lt;Message&gt;", the shape its own
    /// provider gives, and any other exception as "Unknown API violation; provider threw unexpected exception".
    /// </summary>
    internal sealed class EntraPasswordAuthenticationException : SqlAuthenticationProviderException
    {
        internal EntraPasswordAuthenticationException(string failureCode, string message, Exception causedBy)
#pragma warning disable CS0618 // The documented ActiveDirectoryPassword form must keep working; SqlClient marks the member obsolete.
            : base(SqlAuthenticationMethod.ActiveDirectoryPassword, failureCode, false, 0, message, causedBy)
#pragma warning restore CS0618
        {
        }
    }

    /// <summary>
    /// dbatools' SqlClient provider for "Authentication=Active Directory Password". SqlClient 7's own provider signs
    /// in through the Windows account broker even when the broker is not asked for, and the broker has no logon
    /// session to work with in a PowerShell Direct or other non-interactive session (0x80070520), so the documented
    /// ActiveDirectoryPassword form failed there. This provider asks Entra directly, with SqlClient's own first-party
    /// client id and no broker, and calls the username and password flow on every request: it never answers from the
    /// token cache, so a wrong password after a good one is always sent to Entra and refused there.
    /// </summary>
    internal sealed class EntraPasswordAuthenticationProvider : SqlAuthenticationProvider
    {
        /// <summary>SqlClient's own first-party application id, the one its provider uses for this method.</summary>
        internal const string FirstPartyClientId = "2fd908ad-0664-4344-b9be-cd3e8b574c38";

        /// <summary>The scope suffix SqlClient appends to the resource it is given.</summary>
        internal const string DefaultScopeSuffix = "/.default";

        /// <summary>The text SqlClient's own provider puts before Entra's message.</summary>
        internal const string FailurePrefix = "Failed to acquire access token for ActiveDirectoryPassword: ";

        private static readonly ConcurrentDictionary<string, IPublicClientApplication> Clients = new ConcurrentDictionary<string, IPublicClientApplication>(StringComparer.OrdinalIgnoreCase);

        private readonly EntraPasswordTokenSource tokenSource;

        /// <summary>The provider dbatools registers: it signs in through MSAL.</summary>
        internal EntraPasswordAuthenticationProvider()
            : this(AcquireWithMsal)
        {
        }

        /// <summary>A provider that signs in through the given source; for unit tests.</summary>
        internal EntraPasswordAuthenticationProvider(EntraPasswordTokenSource tokenSource)
        {
            if (tokenSource == null)
                throw new ArgumentNullException("tokenSource");
            this.tokenSource = tokenSource;
        }

        /// <summary>The one method SqlClient may call this provider for.</summary>
        internal static SqlAuthenticationMethod PasswordMethod
        {
            get
            {
#pragma warning disable CS0618 // The documented ActiveDirectoryPassword form must keep working; SqlClient marks the member obsolete.
                return SqlAuthenticationMethod.ActiveDirectoryPassword;
#pragma warning restore CS0618
            }
        }

        public override bool IsSupported(SqlAuthenticationMethod authenticationMethod)
        {
            return authenticationMethod == PasswordMethod;
        }

        public override Task<SqlAuthenticationToken> AcquireTokenAsync(SqlAuthenticationParameters parameters)
        {
            if (parameters == null)
                throw new ArgumentNullException("parameters");

            string scope = parameters.Resource.EndsWith(DefaultScopeSuffix, StringComparison.Ordinal) ? parameters.Resource : parameters.Resource + DefaultScopeSuffix;

            // A ConnectionTimeout of 0 is SqlClient's "wait indefinitely", so it gets no cancellation at all; a
            // CancellationTokenSource of zero seconds would cancel before the request leaves.
            CancellationTokenSource timeout = parameters.ConnectionTimeout > 0 ? new CancellationTokenSource(TimeSpan.FromSeconds(parameters.ConnectionTimeout)) : null;
            CancellationToken cancellation = timeout == null ? CancellationToken.None : timeout.Token;
            TaskCompletionSource<SqlAuthenticationToken> completion = new TaskCompletionSource<SqlAuthenticationToken>();

            Task<SqlAuthenticationToken> acquisition;
            try
            {
                acquisition = tokenSource(parameters.Authority, scope, parameters.UserId, parameters.Password, cancellation);
            }
            catch (MsalException exception)
            {
                // A failure before the request starts; reported in the shape SqlClient's own provider gives.
                if (timeout != null)
                    timeout.Dispose();
                completion.SetException(ToProviderException(exception));
                return completion.Task;
            }
            catch
            {
                if (timeout != null)
                    timeout.Dispose();
                throw;
            }

            acquisition.ContinueWith(delegate (Task<SqlAuthenticationToken> finished)
            {
                if (timeout != null)
                    timeout.Dispose();
                if (finished.IsCanceled)
                {
                    completion.SetCanceled();
                }
                else if (finished.IsFaulted)
                {
                    Exception failure = finished.Exception.InnerExceptions.Count == 1 ? finished.Exception.InnerException : finished.Exception;
                    MsalException msalFailure = failure as MsalException;
                    completion.SetException(msalFailure != null ? ToProviderException(msalFailure) : failure);
                }
                else
                {
                    completion.SetResult(finished.Result);
                }
            }, CancellationToken.None, TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
            return completion.Task;
        }

        /// <summary>
        /// MSAL's failure as SqlClient expects it: the MSAL error code as the failure code and SqlClient's own text
        /// before MSAL's message, with the MSAL exception kept as the cause. MSAL's text names the user, never the
        /// password, and nothing here adds either.
        /// </summary>
        internal static EntraPasswordAuthenticationException ToProviderException(MsalException exception)
        {
            return new EntraPasswordAuthenticationException(exception.ErrorCode, FailurePrefix + exception.Message, exception);
        }

        private static IPublicClientApplication CreateClient(string authority)
        {
            // No WithBroker: the Windows account broker is what fails without an interactive logon session.
            return PublicClientApplicationBuilder.Create(FirstPartyClientId).WithAuthority(authority).Build();
        }

        private static Task<SqlAuthenticationToken> AcquireWithMsal(string authority, string scope, string userId, string password, CancellationToken cancellation)
        {
            IPublicClientApplication client = Clients.GetOrAdd(authority, CreateClient);
#pragma warning disable CS0618 // The documented ActiveDirectoryPassword form must keep working; MSAL marks the username and password flow obsolete.
            Task<AuthenticationResult> request = client.AcquireTokenByUsernamePassword(new string[] { scope }, userId, password).ExecuteAsync(cancellation);
#pragma warning restore CS0618
            TaskCompletionSource<SqlAuthenticationToken> completion = new TaskCompletionSource<SqlAuthenticationToken>();
            request.ContinueWith(delegate (Task<AuthenticationResult> finished)
            {
                if (finished.IsCanceled)
                    completion.SetCanceled();
                else if (finished.IsFaulted)
                    completion.SetException(finished.Exception.InnerExceptions);
                else
                    completion.SetResult(new SqlAuthenticationToken(finished.Result.AccessToken, finished.Result.ExpiresOn));
            }, CancellationToken.None, TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
            return completion.Task;
        }
    }

    /// <summary>
    /// Puts dbatools' ActiveDirectoryPassword provider in place once per process, and only over SqlClient's default.
    /// The first ActiveDirectoryPassword connect checks; no later connect checks again, so a provider the caller
    /// registers at any later time is never replaced. The default is recognised as one object of the exact type
    /// ActiveDirectoryAuthenticationProvider that every Entra method with a provider shares. A caller's own provider
    /// type, or a caller's ActiveDirectoryAuthenticationProvider for some methods only, is kept. A caller who
    /// registered one ActiveDirectoryAuthenticationProvider for every Entra method before that first connect cannot be
    /// told from the default, and gets dbatools' provider for ActiveDirectoryPassword only.
    /// </summary>
    internal sealed class EntraPasswordProviderRegistration
    {
        internal const string RegisteredMessage = "Registered the dbatools Microsoft Entra password provider for ActiveDirectoryPassword in this process, in place of SqlClient's default provider";
        internal const string RefusedMessage = "SqlClient did not accept the dbatools Microsoft Entra password provider for ActiveDirectoryPassword; the existing provider is kept";

        /// <summary>The registration that uses SqlClient's process-wide provider table.</summary>
        internal static readonly EntraPasswordProviderRegistration Process = new EntraPasswordProviderRegistration(SqlAuthenticationProvider.GetProvider, SqlAuthenticationProvider.SetProvider, delegate { return new EntraPasswordAuthenticationProvider(); });

        private readonly object gate = new object();
        private readonly Func<SqlAuthenticationMethod, SqlAuthenticationProvider> getProvider;
        private readonly Func<SqlAuthenticationMethod, SqlAuthenticationProvider, bool> setProvider;
        private readonly Func<SqlAuthenticationProvider> createProvider;
        private bool done;

        internal EntraPasswordProviderRegistration(Func<SqlAuthenticationMethod, SqlAuthenticationProvider> getProvider, Func<SqlAuthenticationMethod, SqlAuthenticationProvider, bool> setProvider, Func<SqlAuthenticationProvider> createProvider)
        {
            this.getProvider = getProvider;
            this.setProvider = setProvider;
            this.createProvider = createProvider;
        }

        /// <summary>
        /// Checks once and registers when SqlClient's default is in place. Returns the Verbose line to write, or null
        /// when there is nothing to report. Every call after the first returns null without looking.
        /// </summary>
        internal string EnsureRegistered()
        {
            lock (gate)
            {
                if (done)
                    return null;
                done = true;

                SqlAuthenticationMethod passwordMethod = EntraPasswordAuthenticationProvider.PasswordMethod;
                SqlAuthenticationProvider current = getProvider(passwordMethod);
                if (current == null || current.GetType() != typeof(ActiveDirectoryAuthenticationProvider))
                    return null;

                foreach (SqlAuthenticationMethod method in Enum.GetValues(typeof(SqlAuthenticationMethod)))
                {
                    if (method == passwordMethod || method == SqlAuthenticationMethod.NotSpecified || method == SqlAuthenticationMethod.SqlPassword)
                        continue;
                    SqlAuthenticationProvider other = getProvider(method);
                    if (other != null && !Object.ReferenceEquals(other, current))
                        return null;
                }

                return setProvider(passwordMethod, createProvider()) ? RegisteredMessage : RefusedMessage;
            }
        }
    }
}
