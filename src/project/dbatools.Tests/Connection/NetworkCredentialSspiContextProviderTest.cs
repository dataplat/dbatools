using System;
using System.Buffers;
using System.Net;
using System.Reflection;
using Microsoft.Data.SqlClient;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Dataplat.Dbatools.Connection
{
    /// <summary>
    /// SqlClient 7 compatibility and the explicit-Windows-credential SSPI provider on both frameworks (after
    /// dbatools.library 56fd1f79's SqlClientCompatibilityTest, which covered .NET only). The full handshake against
    /// SQL Server runs in the lab.
    /// </summary>
    [TestClass]
    public class NetworkCredentialSspiContextProviderTest
    {
        private delegate bool GenerateContextCall(ReadOnlySpan<byte> incomingBlob, IBufferWriter<byte> outgoingBlobWriter,
            SspiAuthenticationParameters authParams);

        [TestMethod]
        public void SqlConnectionExposesPluggableSspiProvider()
        {
            Assert.IsNotNull(typeof(SqlConnection).GetProperty("SspiContextProvider"));
        }

        [TestMethod]
        public void EntraAuthenticationProviderIsRegistered()
        {
            // SqlClient 7 finds the Entra providers in Microsoft.Data.SqlClient.Extensions.Azure.
            Assert.IsNotNull(SqlAuthenticationProvider.GetProvider(SqlAuthenticationMethod.ActiveDirectoryIntegrated));
        }

        [TestMethod]
        public void ProviderCanBeAssignedToSqlConnection()
        {
            using (NetworkCredentialSspiContextProvider provider = new NetworkCredentialSspiContextProvider(
                new NetworkCredential("user", "password", "domain")))
            using (SqlConnection connection = new SqlConnection())
            {
                connection.SspiContextProvider = provider;
                Assert.AreSame(provider, connection.SspiContextProvider);
            }
        }

        [TestMethod]
        public void ProviderRejectsNullCredential()
        {
            Assert.ThrowsExactly<ArgumentNullException>(() => new NetworkCredentialSspiContextProvider(null));
        }

        [TestMethod]
        public void ProviderExposesPasswordFreePrincipal()
        {
            using (NetworkCredentialSspiContextProvider domainQualified = new NetworkCredentialSspiContextProvider(
                new NetworkCredential("user", "password", "domain")))
            using (NetworkCredentialSspiContextProvider domainless = new NetworkCredentialSspiContextProvider(
                new NetworkCredential("user", "password", String.Empty)))
            {
                Assert.AreEqual("domain\\user", domainQualified.Principal);
                Assert.AreEqual("user", domainless.Principal);
            }
        }

        [TestMethod]
        public void ProviderHasStableIdentityPerCredential()
        {
            using (NetworkCredentialSspiContextProvider first = new NetworkCredentialSspiContextProvider(
                new NetworkCredential("user", "password", "domain")))
            using (NetworkCredentialSspiContextProvider second = new NetworkCredentialSspiContextProvider(
                new NetworkCredential("USER", "password", "DOMAIN")))
            using (NetworkCredentialSspiContextProvider different = new NetworkCredentialSspiContextProvider(
                new NetworkCredential("other-user", "password", "domain")))
            using (NetworkCredentialSspiContextProvider differentPassword = new NetworkCredentialSspiContextProvider(
                new NetworkCredential("user", "different-password", "domain")))
            {
                Assert.AreEqual(first, second);
                Assert.AreEqual(first.GetHashCode(), second.GetHashCode());
                Assert.AreNotEqual(first, different);
                Assert.AreNotEqual(first, differentPassword);
            }
        }

        [TestMethod]
        [OSCondition(OperatingSystems.Windows)]
        public void FirstRoundWritesANegotiateToken()
        {
            // The first round of a handshake needs no server: the Negotiate package writes its opening token. On .NET
            // Framework this is the secur32 path, so its marshalling runs here. Windows only: elsewhere .NET's Negotiate
            // needs a GSSAPI NTLM mechanism that build hosts do not install.
            using (NetworkCredentialSspiContextProvider provider = new NetworkCredentialSspiContextProvider(
                new NetworkCredential("dbatoolsci", "dbatoolsci", "dbatoolsci.invalid")))
            {
                TestBufferWriter writer = new TestBufferWriter();
                bool generated = Bind(provider)(ReadOnlySpan<byte>.Empty, writer,
                    new SspiAuthenticationParameters("dbatoolsci.invalid", "MSSQLSvc/dbatoolsci.invalid:1433"));
                Assert.IsTrue(generated);
                Assert.IsTrue(writer.Written.Length > 0);
            }
        }

        [TestMethod]
        public void ServerTokenWithoutAHandshakeIsRefused()
        {
            // A server token that reaches a provider with no context of its own (the handshake completed, failed, or was
            // reset by another one) must fail the login, not open a new handshake that drops the token. No security
            // package runs, so this holds on every platform. Only the .NET Framework run tells the two apart: there the
            // secur32 client used to treat the token as a first round and write a new opening token, while on .NET a
            // fresh NegotiateAuthentication also rejects a token it never asked for.
            using (NetworkCredentialSspiContextProvider provider = new NetworkCredentialSspiContextProvider(
                new NetworkCredential("user", "password", "domain")))
            {
                TestBufferWriter writer = new TestBufferWriter();
                bool generated = Bind(provider)(new ReadOnlySpan<byte>(new byte[] { 0x60, 0x01, 0x00 }), writer,
                    new SspiAuthenticationParameters("server", "MSSQLSvc/server:1433"));
                Assert.IsFalse(generated);
                Assert.AreEqual(0, writer.Written.Length);
            }
        }

        [TestMethod]
        public void DisposedProviderRefusesAnotherRound()
        {
            NetworkCredentialSspiContextProvider provider = new NetworkCredentialSspiContextProvider(
                new NetworkCredential("user", "password", "domain"));
            provider.Dispose();
            provider.Dispose();
            GenerateContextCall call = Bind(provider);
            Assert.ThrowsExactly<ObjectDisposedException>(() => call(ReadOnlySpan<byte>.Empty, new TestBufferWriter(),
                new SspiAuthenticationParameters("server", "MSSQLSvc/server:1433")));
        }

        private static GenerateContextCall Bind(NetworkCredentialSspiContextProvider provider)
        {
            MethodInfo method = typeof(NetworkCredentialSspiContextProvider).GetMethod("GenerateContext",
                BindingFlags.Instance | BindingFlags.NonPublic);
            return (GenerateContextCall)Delegate.CreateDelegate(typeof(GenerateContextCall), provider, method);
        }

        private sealed class TestBufferWriter : IBufferWriter<byte>
        {
            private byte[] buffer = new byte[256];
            private int count;

            public byte[] Written
            {
                get
                {
                    byte[] copy = new byte[count];
                    Array.Copy(buffer, copy, count);
                    return copy;
                }
            }

            public void Advance(int written)
            {
                count += written;
            }

            public Memory<byte> GetMemory(int sizeHint)
            {
                Grow(sizeHint);
                return new Memory<byte>(buffer, count, buffer.Length - count);
            }

            public Span<byte> GetSpan(int sizeHint)
            {
                Grow(sizeHint);
                return new Span<byte>(buffer, count, buffer.Length - count);
            }

            private void Grow(int sizeHint)
            {
                int needed = count + Math.Max(sizeHint, 1);
                if (needed > buffer.Length)
                    Array.Resize(ref buffer, Math.Max(needed, buffer.Length * 2));
            }
        }
    }
}
