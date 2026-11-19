using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Security;
using System.Security.Cryptography;
using System.Threading;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Connection
{
    /// <summary>Owns decrypted SQL credential secrets for one migration operation.</summary>
    public sealed class SqlCredentialSecrets : IDisposable
    {
        private readonly Dictionary<string, SecureString> _secrets = new Dictionary<string, SecureString>(StringComparer.Ordinal);

        private SqlCredentialSecrets() { }

        /// <summary>Gets the secret for the exact catalog name; ownership stays with this object.</summary>
        public SecureString GetSecret(string name) { return _secrets[name]; }

        /// <summary>Reads and decrypts credentials through the caller's existing DAC.</summary>
        public static SqlCredentialSecrets Read(Server server, PSCredential credential, CancellationToken cancellationToken)
        {
            return Read(server, credential, cancellationToken, null);
        }

        /// <summary>Reads credentials while forwarding the pinned retrieval messages to the caller.</summary>
        public static SqlCredentialSecrets Read(Server server, PSCredential credential, CancellationToken cancellationToken,
            Action<string> verbose)
        {
            SqlCredentialSecrets result = new SqlCredentialSecrets();
            byte[] protectedKey = null;
            byte[] entropy = null;
            byte[] serviceKey = null;
            try
            {
                if (verbose != null) verbose("Querying service master key");
                protectedKey = server.ConnectionContext.ExecuteScalar(@"
SELECT TOP (1) SUBSTRING(crypt_property, 9, DATALENGTH(crypt_property) - 8)
FROM master.sys.key_encryptions
WHERE key_id = 102 AND thumbprint IN (0x0300000001, 0x03)
ORDER BY DATALENGTH(thumbprint) DESC;") as byte[];
                if (protectedKey == null)
                    throw new InvalidOperationException("The machine-encrypted service master key was not found.");
                string physicalHost = Convert.ToString(server.ConnectionContext.ExecuteScalar(
                    "SELECT CONVERT(nvarchar(128), SERVERPROPERTY('ComputerNamePhysicalNetBIOS'));"), CultureInfo.InvariantCulture);
                if (verbose != null) verbose("Decrypt the service master key");
                entropy = HostProtectedData.ReadSqlEntropy(physicalHost, server.ServiceInstanceId, credential);
                serviceKey = HostProtectedData.Unprotect(physicalHost, protectedKey, entropy, credential, cancellationToken);
                if (verbose != null) verbose("Choose the encryption algorithm based on the SMK length - 3DES for 2008, AES for 2012");
                if (serviceKey.Length != 16 && serviceKey.Length != 32)
                    throw new InvalidOperationException(String.Format(CultureInfo.InvariantCulture,
                        "Unknown key size. Do you have administrative access to the Windows registry on {0}? Otherwise, we're out of ideas.", server.Name));

                if (verbose != null) verbose("Query password information from the Db.");
                SqlConnection connection = server.ConnectionContext.SqlConnectionObject;
                bool opened = connection.State != ConnectionState.Open;
                try
                {
                    if (opened) connection.Open();
                    using (SqlCommand command = connection.CreateCommand())
                    {
                        command.CommandText = @"
SELECT cred.name, obj.imageval
FROM master.sys.credentials AS cred
INNER JOIN master.sys.sysobjvalues AS obj ON cred.credential_id = obj.objid
WHERE obj.valclass = 28 AND obj.valnum = 2;";
                        using (SqlDataReader reader = command.ExecuteReader())
                        {
                            if (verbose != null) verbose("Go through each row in results");
                            while (reader.Read())
                            {
                                cancellationToken.ThrowIfCancellationRequested();
                                byte[] encrypted = (byte[])reader.GetValue(1);
                                try { result._secrets.Add(reader.GetString(0), Decrypt(serviceKey, encrypted)); }
                                finally { Array.Clear(encrypted, 0, encrypted.Length); }
                            }
                        }
                    }
                }
                finally { if (opened) connection.Close(); }
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

        /// <summary>Decrypts one SMK-encrypted secret blob (header, IV, ciphertext); also used for linked server passwords.</summary>
        internal static SecureString Decrypt(byte[] serviceKey, byte[] encrypted)
        {
            using (SymmetricAlgorithm algorithm = serviceKey.Length == 32 ? (SymmetricAlgorithm)Aes.Create() : TripleDES.Create())
            {
                algorithm.Mode = CipherMode.CBC;
                algorithm.Padding = PaddingMode.None;
                int ivLength = algorithm.BlockSize / 8;
                byte[] iv = new byte[ivLength];
                byte[] plain = null;
                try
                {
                    Array.Copy(encrypted, 4, iv, 0, ivLength);
                    using (ICryptoTransform transform = algorithm.CreateDecryptor(serviceKey, iv))
                        plain = transform.TransformFinalBlock(encrypted, 4 + ivLength, encrypted.Length - 4 - ivLength);
                    // SQL's byte length preserves UTF-16 secrets that the pinned adjacent-nonzero
                    // heuristic truncates. Header verified on SQL Server 2017, 2019 and 2022.
                    if (plain.Length < 8 || BitConverter.ToUInt32(plain, 0) != 0xBAADF00D)
                        throw new CryptographicException("Unrecognized SQL credential secret header.");
                    int offset = 8 + BitConverter.ToUInt16(plain, 4);
                    int length = BitConverter.ToUInt16(plain, 6);
                    if ((length & 1) != 0 || offset > plain.Length || length > plain.Length - offset)
                        throw new CryptographicException("Invalid SQL credential secret length.");
                    SecureString secret = new SecureString();
                    try
                    {
                        for (int index = offset; index < offset + length; index += 2)
                            secret.AppendChar((char)(plain[index] | (plain[index + 1] << 8)));
                        secret.MakeReadOnly();
                        return secret;
                    }
                    catch
                    {
                        secret.Dispose();
                        throw;
                    }
                }
                finally
                {
                    if (plain != null) Array.Clear(plain, 0, plain.Length);
                    Array.Clear(iv, 0, iv.Length);
                }
            }
        }

        /// <summary>Checks the provider as data, including names containing SQL punctuation.</summary>
        public static bool HasEnabledProvider(Server server, string providerName)
        {
            SqlConnection connection = server.ConnectionContext.SqlConnectionObject;
            bool opened = connection.State != ConnectionState.Open;
            try
            {
                if (opened) connection.Open();
                using (SqlCommand command = connection.CreateCommand())
                {
                    command.CommandText = "SELECT is_enabled FROM sys.cryptographic_providers WHERE name = @name;";
                    command.Parameters.Add("@name", SqlDbType.NVarChar, 128).Value = providerName;
                    object enabled = command.ExecuteScalar();
                    return enabled != null && enabled != DBNull.Value && Convert.ToBoolean(enabled, CultureInfo.InvariantCulture);
                }
            }
            finally { if (opened) connection.Close(); }
        }

        /// <summary>Erases all managed secret buffers held by this operation.</summary>
        public void Dispose()
        {
            foreach (SecureString secret in _secrets.Values) secret.Dispose();
            _secrets.Clear();
        }
    }
}
