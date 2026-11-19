using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Security;
using System.Threading;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Connection
{
    /// <summary>The step of a secret read that failed; each maps to one message of the retired Get-DecryptedObject.</summary>
    public enum SecretReadStage
    {
        /// <summary>Reading the machine-encrypted service master key from sys.key_encryptions.</summary>
        ServiceKeyQuery,
        /// <summary>Reading the registry entropy and unprotecting the service master key on its host.</summary>
        Unprotect,
        /// <summary>The unprotected service master key has neither the 3DES nor the AES length.</summary>
        KeySize,
        /// <summary>Reading the encrypted secrets through the dedicated admin connection.</summary>
        SecretQuery
    }

    /// <summary>A secret read failed at a known stage; the inner exception carries the cause.</summary>
    public sealed class SecretReadException : Exception
    {
        private readonly SecretReadStage _stage;

        /// <summary>Creates the failure of one stage.</summary>
        public SecretReadException(SecretReadStage stage, string message, Exception innerException)
            : base(message, innerException)
        {
            _stage = stage;
        }

        /// <summary>The stage that failed.</summary>
        public SecretReadStage Stage { get { return _stage; } }
    }

    /// <summary>One linked server remote login whose password the source stores.</summary>
    public sealed class LinkedServerLoginSecret
    {
        private readonly string _name;
        private readonly string _identity;
        private readonly string _localLogin;
        private readonly SecureString _password;

        internal LinkedServerLoginSecret(string name, string identity, string localLogin, SecureString password)
        {
            _name = name;
            _identity = identity;
            _localLogin = localLogin;
            _password = password;
        }

        /// <summary>The linked server name.</summary>
        public string Name { get { return _name; } }

        /// <summary>The remote user (sys.syslnklgns.name).</summary>
        public string Identity { get { return _identity; } }

        /// <summary>The local login the mapping applies to; empty for the mapping of all local logins, as SMO's LinkedServerLogin.Name.</summary>
        public string LocalLogin { get { return _localLogin; } }

        /// <summary>The decrypted remote password; ownership stays with the reading LinkedServerLoginSecrets.</summary>
        public SecureString Password { get { return _password; } }
    }

    /// <summary>
    /// Owns the decrypted linked server remote-login passwords for one migration operation. The DAC reads,
    /// the registry entropy read and the decryption run here; only the machine-bound DPAPI step goes to
    /// HostProtectedData (watchman a2c84a56: one shared service for the five secret consumers).
    /// </summary>
    public sealed class LinkedServerLoginSecrets : IDisposable
    {
        private const string MachineKeyQuery = "SELECT SUBSTRING(crypt_property, 9, DATALENGTH(crypt_property) - 8) FROM master.sys.key_encryptions WHERE key_id = 102 AND thumbprint = 0x0300000001;";
        private const string LegacyMachineKeyQuery = "SELECT SUBSTRING(crypt_property, 9, DATALENGTH(crypt_property) - 8) FROM master.sys.key_encryptions WHERE key_id = 102 AND thumbprint = 0x03;";
        // sys.syslnklgns is the system base table the DAC exposes; sys.servers.name is the pinned sysservers.srvname.
        // lgnid is sys.linked_logins.local_principal_id (0 for all local logins); the empty name matches SMO's ISNULL(sp.name, '').
        private const string PasswordQuery = @"
SELECT srv.name, lgn.name, lgn.pwdhash, ISNULL(prn.name, N'')
FROM master.sys.syslnklgns AS lgn
INNER JOIN master.sys.servers AS srv ON lgn.srvid = srv.server_id
LEFT JOIN master.sys.server_principals AS prn ON lgn.lgnid = prn.principal_id
WHERE LEN(lgn.pwdhash) > 0;";

        private readonly List<LinkedServerLoginSecret> _logins = new List<LinkedServerLoginSecret>();

        private LinkedServerLoginSecrets() { }

        /// <summary>The logins in catalog order.</summary>
        public ReadOnlyCollection<LinkedServerLoginSecret> Logins
        {
            get { return _logins.AsReadOnly(); }
        }

        /// <summary>Reads and decrypts linked server passwords through the caller's existing DAC.</summary>
        public static LinkedServerLoginSecrets Read(Server server, PSCredential credential, CancellationToken cancellationToken)
        {
            return Read(server, credential, cancellationToken, null);
        }

        /// <summary>Reads linked server passwords while forwarding the retrieval messages to the caller.</summary>
        public static LinkedServerLoginSecrets Read(Server server, PSCredential credential, CancellationToken cancellationToken,
            Action<string> verbose)
        {
            LinkedServerLoginSecrets result = new LinkedServerLoginSecrets();
            byte[] protectedKey = null;
            byte[] entropy = null;
            byte[] serviceKey = null;
            try
            {
                if (verbose != null) verbose("Querying service master key");
                try
                {
                    // key_id 102 is the service master key; thumbprint 3 means encrypted with the machine key.
                    protectedKey = server.ConnectionContext.ExecuteScalar(MachineKeyQuery) as byte[] ??
                        server.ConnectionContext.ExecuteScalar(LegacyMachineKeyQuery) as byte[];
                }
                catch (Exception ex)
                {
                    throw new SecretReadException(SecretReadStage.ServiceKeyQuery, ex.Message, ex);
                }

                if (verbose != null) verbose("Decrypt the service master key");
                try
                {
                    if (protectedKey == null)
                        throw new InvalidOperationException("The machine-encrypted service master key was not found.");
                    string physicalHost = Convert.ToString(server.ConnectionContext.ExecuteScalar(
                        "SELECT CONVERT(nvarchar(128), SERVERPROPERTY('ComputerNamePhysicalNetBIOS'));"), CultureInfo.InvariantCulture);
                    entropy = HostProtectedData.ReadSqlEntropy(physicalHost, server.ServiceInstanceId, credential);
                    serviceKey = HostProtectedData.Unprotect(physicalHost, protectedKey, entropy, credential, cancellationToken);
                }
                catch (OperationCanceledException) { throw; }
                catch (Exception ex)
                {
                    throw new SecretReadException(SecretReadStage.Unprotect, ex.Message, ex);
                }

                if (verbose != null) verbose("Choose the encryption algorithm based on the SMK length - 3DES for 2008, AES for 2012");
                if (serviceKey.Length != 16 && serviceKey.Length != 32)
                    throw new SecretReadException(SecretReadStage.KeySize, "Unknown key size.", null);

                if (verbose != null) verbose("Query password information from the Db.");
                List<object[]> rows = new List<object[]>();
                try
                {
                    SqlConnection connection = server.ConnectionContext.SqlConnectionObject;
                    bool opened = connection.State != ConnectionState.Open;
                    try
                    {
                        if (opened) connection.Open();
                        using (SqlCommand command = connection.CreateCommand())
                        {
                            command.CommandText = PasswordQuery;
                            using (SqlDataReader reader = command.ExecuteReader())
                            {
                                while (reader.Read())
                                {
                                    object[] row = new object[4];
                                    reader.GetValues(row);
                                    rows.Add(row);
                                }
                            }
                        }
                    }
                    finally { if (opened) connection.Close(); }
                }
                catch (Exception ex)
                {
                    foreach (object[] row in rows) ClearRow(row);
                    throw new SecretReadException(SecretReadStage.SecretQuery, ex.Message, ex);
                }

                if (verbose != null) verbose("Go through each row in results");
                try
                {
                    foreach (object[] row in rows)
                    {
                        cancellationToken.ThrowIfCancellationRequested();
                        result._logins.Add(new LinkedServerLoginSecret(AsText(row[0]), AsText(row[1]), AsText(row[3]),
                            SqlCredentialSecrets.Decrypt(serviceKey, (byte[])row[2])));
                    }
                }
                finally
                {
                    foreach (object[] row in rows) ClearRow(row);
                }
                return result;
            }
            catch
            {
                result.Dispose();
                throw;
            }
            finally
            {
                if (serviceKey != null) Array.Clear(serviceKey, 0, serviceKey.Length);
                if (entropy != null) Array.Clear(entropy, 0, entropy.Length);
                if (protectedKey != null) Array.Clear(protectedKey, 0, protectedKey.Length);
            }
        }

        private static string AsText(object value)
        {
            return value == null || value == DBNull.Value ? null : Convert.ToString(value, CultureInfo.InvariantCulture);
        }

        private static void ClearRow(object[] row)
        {
            byte[] bytes = row[2] as byte[];
            if (bytes != null) Array.Clear(bytes, 0, bytes.Length);
        }

        /// <summary>Erases all managed secret buffers held by this operation.</summary>
        public void Dispose()
        {
            foreach (LinkedServerLoginSecret login in _logins)
            {
                if (login.Password != null) login.Password.Dispose();
            }
            _logins.Clear();
        }
    }
}
