using System;
using System.Buffers;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Data.SqlClient;
#if NET8_0_OR_GREATER
using System.Net.Security;
#else
using System.Runtime.InteropServices;
#endif

namespace Dataplat.Dbatools.Connection
{
    /// <summary>
    /// Generates SQL Server integrated-authentication tokens from an explicit Windows credential, so Connect-DbaInstance
    /// can sign in with -SqlCredential as a Windows account without impersonation. On .NET it uses NegotiateAuthentication
    /// with its default context requirements, as dbatools.library 56fd1f79 does; on .NET Framework it calls the Windows
    /// SSPI Negotiate package through secur32.dll with the requirements of the impersonation path the pin takes there.
    /// </summary>
    /// <remarks>
    /// SqlClient keeps the provider instance in the connection pool key and drives every handshake of that pool through
    /// it, so a provider belongs to one connection: Connect-DbaInstance creates one per connection, and SMO opens its
    /// physical connections on the calling thread, one handshake at a time. Each handshake starts on an empty incoming
    /// blob (the first round, and SqlClient's retry with the secondary SPN) and ends when the security package reports
    /// completion. The lock serializes single rounds only, so no two threads use a security context at once (Microsoft
    /// Learn, InitializeSecurityContext (Negotiate)); it cannot keep two handshakes apart, because SqlClient's base class
    /// holds per-handshake state on the instance. Two connections opening on one pool at the same time therefore share
    /// one handshake state; a server token that arrives with no context of its own fails the login instead of starting a
    /// new handshake silently.
    /// </remarks>
    public sealed class NetworkCredentialSspiContextProvider : SspiContextProvider, IDisposable
    {
        private readonly NetworkCredential credential;
        private readonly byte[] credentialIdentity;
        private readonly string principal;
        private readonly object sync = new object();
        private string resource;
        private bool disposed;
#if NET8_0_OR_GREATER
        private NegotiateAuthentication authentication;
#else
        private WindowsNegotiateClient authentication;
#endif

        /// <summary>
        /// The case-insensitive Windows principal ("domain\user" or "user") this provider authenticates as. It holds no
        /// password and is safe to use in a cache key.
        /// </summary>
        public string Principal
        {
            get { return principal; }
        }

        /// <summary>
        /// Creates a provider that authenticates with the supplied Windows credential.
        /// </summary>
        /// <param name="credential">The Windows credential used for Negotiate authentication.</param>
        public NetworkCredentialSspiContextProvider(NetworkCredential credential)
        {
            if (credential == null)
                throw new ArgumentNullException(nameof(credential));

            this.credential = new NetworkCredential(credential.UserName, credential.Password, credential.Domain);
            principal = String.IsNullOrEmpty(credential.Domain)
                ? credential.UserName
                : credential.Domain + "\\" + credential.UserName;
            using (SHA256 sha256 = SHA256.Create())
            {
                credentialIdentity = sha256.ComputeHash(Encoding.UTF8.GetBytes(
                    (principal ?? String.Empty).ToUpperInvariant() + "\0" + credential.Password));
            }
        }

        /// <summary>
        /// Compares providers by Windows principal and credential identity.
        /// </summary>
        /// <param name="obj">The object to compare.</param>
        /// <returns>True for a provider of the same principal and password.</returns>
        public override bool Equals(object obj)
        {
            NetworkCredentialSspiContextProvider other = obj as NetworkCredentialSspiContextProvider;
            return other != null && String.Equals(principal, other.principal, StringComparison.OrdinalIgnoreCase) &&
                FixedTimeEquals(credentialIdentity, other.credentialIdentity);
        }

        /// <summary>
        /// Returns the hash of the case-insensitive Windows principal. The credential identity is left out so no
        /// password-derived value is disclosed.
        /// </summary>
        /// <returns>The hash code.</returns>
        public override int GetHashCode()
        {
            return StringComparer.OrdinalIgnoreCase.GetHashCode(principal ?? String.Empty);
        }

        /// <inheritdoc />
        protected override bool GenerateContext(
            ReadOnlySpan<byte> incomingBlob,
            IBufferWriter<byte> outgoingBlobWriter,
            SspiAuthenticationParameters authParams)
        {
            if (outgoingBlobWriter == null)
                throw new ArgumentNullException(nameof(outgoingBlobWriter));
            if (authParams == null)
                throw new ArgumentNullException(nameof(authParams));

            lock (sync)
            {
                if (disposed)
                    throw new ObjectDisposedException(nameof(NetworkCredentialSspiContextProvider));

                // An empty incoming blob opens a handshake: the first round, or SqlClient's retry with the secondary SPN.
                if (incomingBlob.IsEmpty)
                {
                    ResetAuthentication();
                    resource = authParams.Resource;
                    authentication = CreateAuthentication(resource);
                }
                else if (authentication == null || !String.Equals(resource, authParams.Resource, StringComparison.Ordinal))
                {
                    // A server token with no context of its own for this SPN: the handshake already completed or failed,
                    // or another handshake reset it. Refusing makes SqlClient report the SSPI failure.
                    return false;
                }

                try
                {
                    byte[] outgoingBlob;
                    bool completed;
                    if (!NextToken(incomingBlob, out outgoingBlob, out completed))
                    {
                        ResetAuthentication();
                        return false;
                    }

                    if (outgoingBlob != null && outgoingBlob.Length > 0)
                    {
                        Span<byte> destination = outgoingBlobWriter.GetSpan(outgoingBlob.Length);
                        new ReadOnlySpan<byte>(outgoingBlob).CopyTo(destination);
                        outgoingBlobWriter.Advance(outgoingBlob.Length);
                    }

                    if (completed)
                        ResetAuthentication();

                    return true;
                }
                catch
                {
                    ResetAuthentication();
                    throw;
                }
            }
        }

        /// <summary>
        /// Releases the active security context.
        /// </summary>
        public void Dispose()
        {
            lock (sync)
            {
                if (disposed)
                    return;

                disposed = true;
                ResetAuthentication();
            }
        }

        private void ResetAuthentication()
        {
            if (authentication != null)
                authentication.Dispose();
            authentication = null;
            resource = null;
        }

        private static bool FixedTimeEquals(byte[] left, byte[] right)
        {
            if (left == null || right == null || left.Length != right.Length)
                return false;
            int difference = 0;
            for (int i = 0; i < left.Length; i++)
                difference |= left[i] ^ right[i];
            return difference == 0;
        }

#if NET8_0_OR_GREATER
        private NegotiateAuthentication CreateAuthentication(string targetName)
        {
            return new NegotiateAuthentication(new NegotiateAuthenticationClientOptions
            {
                Package = "Negotiate",
                TargetName = targetName,
                Credential = credential
            });
        }

        private bool NextToken(ReadOnlySpan<byte> incomingBlob, out byte[] outgoingBlob, out bool completed)
        {
            NegotiateAuthenticationStatusCode statusCode;
            outgoingBlob = authentication.GetOutgoingBlob(incomingBlob, out statusCode);
            completed = statusCode == NegotiateAuthenticationStatusCode.Completed;
            return completed || statusCode == NegotiateAuthenticationStatusCode.ContinueNeeded;
        }
#else
        private WindowsNegotiateClient CreateAuthentication(string targetName)
        {
            return new WindowsNegotiateClient(credential, targetName);
        }

        private bool NextToken(ReadOnlySpan<byte> incomingBlob, out byte[] outgoingBlob, out bool completed)
        {
            return authentication.Step(incomingBlob.ToArray(), out outgoingBlob, out completed);
        }

        /// <summary>
        /// One client handshake of the Windows Negotiate package: AcquireCredentialsHandle with the explicit credential,
        /// then InitializeSecurityContext once per round. On Windows PowerShell the pin signs a Windows credential in
        /// through SMO impersonation and SqlClient's own SSPI client, which asks for delegation, mutual authentication
        /// and confidentiality besides connection semantics (SqlClient's managed SNI, SNIProxy.GenSspiClientContext,
        /// requested exactly these), so this client asks for the same context: a Kerberos login keeps its double hop.
        /// </summary>
        private sealed class WindowsNegotiateClient : IDisposable
        {
            private const int SecpkgCredOutbound = 2;
            private const int SecWinntAuthIdentityUnicode = 2;
            private const int SecurityNativeDrep = 0x10;
            private const int SecbufferVersion = 0;
            private const int SecbufferToken = 2;
            private const int IscReqDelegate = 0x1;
            private const int IscReqMutualAuth = 0x2;
            private const int IscReqConfidentiality = 0x10;
            private const int IscReqAllocateMemory = 0x100;
            private const int IscReqConnection = 0x800;
            private const int ContextRequirements = IscReqDelegate | IscReqMutualAuth | IscReqConfidentiality | IscReqConnection | IscReqAllocateMemory;
            private const int SecEOk = 0;
            private const int SecIContinueNeeded = 0x00090312;
            private const int SecICompleteNeeded = 0x00090313;
            private const int SecICompleteAndContinue = 0x00090314;

            private readonly string targetName;
            private SecHandle credentialHandle;
            private SecHandle contextHandle;
            private bool hasCredential;

            internal WindowsNegotiateClient(NetworkCredential credential, string targetName)
            {
                this.targetName = String.IsNullOrEmpty(targetName) ? null : targetName;
                // A refused credential leaves hasCredential false, and the first Step reports the refusal to SqlClient.
                AcquireCredentials(credential);
            }

            ~WindowsNegotiateClient()
            {
                Release();
            }

            /// <summary>Runs one round; false when the security package refuses.</summary>
            internal bool Step(byte[] incoming, out byte[] outgoing, out bool completed)
            {
                outgoing = null;
                completed = false;
                if (!hasCredential)
                    return false;

                bool first = !HasContext;
                IntPtr outBufferPtr = IntPtr.Zero;
                IntPtr inBufferPtr = IntPtr.Zero;
                IntPtr inTokenPtr = IntPtr.Zero;
                IntPtr outToken = IntPtr.Zero;
                try
                {
                    int bufferSize = Marshal.SizeOf(typeof(SecBuffer));
                    outBufferPtr = Marshal.AllocHGlobal(bufferSize);
                    Marshal.StructureToPtr(new SecBuffer { cbBuffer = 0, BufferType = SecbufferToken, pvBuffer = IntPtr.Zero }, outBufferPtr, false);
                    SecBufferDesc outDesc = new SecBufferDesc { ulVersion = SecbufferVersion, cBuffers = 1, pBuffers = outBufferPtr };
                    int attributes;
                    long expiry;
                    int status;
                    if (first)
                    {
                        status = InitializeSecurityContextW(ref credentialHandle, IntPtr.Zero, targetName,
                            ContextRequirements, 0, SecurityNativeDrep, IntPtr.Zero, 0,
                            ref contextHandle, ref outDesc, out attributes, out expiry);
                    }
                    else
                    {
                        int length = incoming == null ? 0 : incoming.Length;
                        inTokenPtr = Marshal.AllocHGlobal(Math.Max(length, 1));
                        if (length > 0)
                            Marshal.Copy(incoming, 0, inTokenPtr, length);
                        inBufferPtr = Marshal.AllocHGlobal(bufferSize);
                        Marshal.StructureToPtr(new SecBuffer { cbBuffer = length, BufferType = SecbufferToken, pvBuffer = inTokenPtr }, inBufferPtr, false);
                        SecBufferDesc inDesc = new SecBufferDesc { ulVersion = SecbufferVersion, cBuffers = 1, pBuffers = inBufferPtr };
                        status = InitializeSecurityContextContinue(ref credentialHandle, ref contextHandle, targetName,
                            ContextRequirements, 0, SecurityNativeDrep, ref inDesc, 0,
                            ref contextHandle, ref outDesc, out attributes, out expiry);
                    }

                    SecBuffer produced = (SecBuffer)Marshal.PtrToStructure(outBufferPtr, typeof(SecBuffer));
                    outToken = produced.pvBuffer;
                    if (status == SecICompleteNeeded || status == SecICompleteAndContinue)
                    {
                        int completeStatus = CompleteAuthToken(ref contextHandle, ref outDesc);
                        if (completeStatus < 0)
                            return false;
                        status = status == SecICompleteNeeded ? SecEOk : SecIContinueNeeded;
                        produced = (SecBuffer)Marshal.PtrToStructure(outBufferPtr, typeof(SecBuffer));
                        outToken = produced.pvBuffer;
                    }

                    if (status != SecEOk && status != SecIContinueNeeded)
                        return false;

                    if (produced.cbBuffer > 0 && produced.pvBuffer != IntPtr.Zero)
                    {
                        outgoing = new byte[produced.cbBuffer];
                        Marshal.Copy(produced.pvBuffer, outgoing, 0, produced.cbBuffer);
                    }
                    completed = status == SecEOk;
                    return true;
                }
                finally
                {
                    if (outToken != IntPtr.Zero)
                        FreeContextBuffer(outToken);
                    if (outBufferPtr != IntPtr.Zero)
                        Marshal.FreeHGlobal(outBufferPtr);
                    if (inBufferPtr != IntPtr.Zero)
                        Marshal.FreeHGlobal(inBufferPtr);
                    if (inTokenPtr != IntPtr.Zero)
                        Marshal.FreeHGlobal(inTokenPtr);
                }
            }

            public void Dispose()
            {
                Release();
                GC.SuppressFinalize(this);
            }

            private bool HasContext
            {
                get { return contextHandle.dwLower != IntPtr.Zero || contextHandle.dwUpper != IntPtr.Zero; }
            }

            private void Release()
            {
                if (HasContext)
                {
                    DeleteSecurityContext(ref contextHandle);
                    contextHandle = new SecHandle();
                }
                if (hasCredential)
                {
                    FreeCredentialsHandle(ref credentialHandle);
                    credentialHandle = new SecHandle();
                    hasCredential = false;
                }
            }

            private void AcquireCredentials(NetworkCredential credential)
            {
                string user = credential.UserName ?? String.Empty;
                string domain = credential.Domain ?? String.Empty;
                IntPtr userPtr = IntPtr.Zero;
                IntPtr domainPtr = IntPtr.Zero;
                IntPtr passwordPtr = IntPtr.Zero;
                try
                {
                    userPtr = Marshal.StringToHGlobalUni(user);
                    if (domain.Length > 0)
                        domainPtr = Marshal.StringToHGlobalUni(domain);
                    int passwordLength;
                    // On .NET Framework the getter returns a fresh copy (m_password.Copy()), so it is disposed here.
                    using (System.Security.SecureString password = credential.SecurePassword)
                    {
                        passwordPtr = Marshal.SecureStringToGlobalAllocUnicode(password);
                        passwordLength = password.Length;
                    }
                    SecWinntAuthIdentity identity = new SecWinntAuthIdentity
                    {
                        User = userPtr,
                        UserLength = user.Length,
                        Domain = domainPtr,
                        DomainLength = domain.Length,
                        Password = passwordPtr,
                        PasswordLength = passwordLength,
                        Flags = SecWinntAuthIdentityUnicode
                    };
                    long expiry;
                    int status = AcquireCredentialsHandleW(null, "Negotiate", SecpkgCredOutbound, IntPtr.Zero,
                        ref identity, IntPtr.Zero, IntPtr.Zero, ref credentialHandle, out expiry);
                    hasCredential = status == SecEOk;
                }
                finally
                {
                    if (passwordPtr != IntPtr.Zero)
                        Marshal.ZeroFreeGlobalAllocUnicode(passwordPtr);
                    if (domainPtr != IntPtr.Zero)
                        Marshal.FreeHGlobal(domainPtr);
                    if (userPtr != IntPtr.Zero)
                        Marshal.FreeHGlobal(userPtr);
                }
            }

            [StructLayout(LayoutKind.Sequential)]
            private struct SecHandle
            {
                public IntPtr dwLower;
                public IntPtr dwUpper;
            }

            [StructLayout(LayoutKind.Sequential)]
            private struct SecBuffer
            {
                public int cbBuffer;
                public int BufferType;
                public IntPtr pvBuffer;
            }

            [StructLayout(LayoutKind.Sequential)]
            private struct SecBufferDesc
            {
                public int ulVersion;
                public int cBuffers;
                public IntPtr pBuffers;
            }

            [StructLayout(LayoutKind.Sequential)]
            private struct SecWinntAuthIdentity
            {
                public IntPtr User;
                public int UserLength;
                public IntPtr Domain;
                public int DomainLength;
                public IntPtr Password;
                public int PasswordLength;
                public int Flags;
            }

            [DllImport("secur32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
            private static extern int AcquireCredentialsHandleW(string pszPrincipal, string pszPackage, int fCredentialUse,
                IntPtr pvLogonId, ref SecWinntAuthIdentity pAuthData, IntPtr pGetKeyFn, IntPtr pvGetKeyArgument,
                ref SecHandle phCredential, out long ptsExpiry);

            [DllImport("secur32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
            private static extern int InitializeSecurityContextW(ref SecHandle phCredential, IntPtr phContext,
                string pszTargetName, int fContextReq, int reserved1, int targetDataRep, IntPtr pInput, int reserved2,
                ref SecHandle phNewContext, ref SecBufferDesc pOutput, out int pfContextAttr, out long ptsExpiry);

            [DllImport("secur32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, EntryPoint = "InitializeSecurityContextW")]
            private static extern int InitializeSecurityContextContinue(ref SecHandle phCredential, ref SecHandle phContext,
                string pszTargetName, int fContextReq, int reserved1, int targetDataRep, ref SecBufferDesc pInput, int reserved2,
                ref SecHandle phNewContext, ref SecBufferDesc pOutput, out int pfContextAttr, out long ptsExpiry);

            [DllImport("secur32.dll", ExactSpelling = true)]
            private static extern int CompleteAuthToken(ref SecHandle phContext, ref SecBufferDesc pToken);

            [DllImport("secur32.dll", ExactSpelling = true)]
            private static extern int DeleteSecurityContext(ref SecHandle phContext);

            [DllImport("secur32.dll", ExactSpelling = true)]
            private static extern int FreeCredentialsHandle(ref SecHandle phCredential);

            [DllImport("secur32.dll", ExactSpelling = true)]
            private static extern int FreeContextBuffer(IntPtr pvContextBuffer);
        }
#endif
    }
}
