using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Management;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Security.Cryptography;
using System.Threading;
using Microsoft.Win32;

namespace Dataplat.Dbatools.Connection
{
    /// <summary>The machine-bound DPAPI step shared by SQL secret migration services.</summary>
    public static class HostProtectedData
    {
        // StdRegProv can read entropy but cannot call DPAPI. SMO has no unprotect operation.
        // The remote constant performs only the framework load and machine-bound unprotect;
        // caller values never become script text (I2, watchman a2c84a56 and bfd0c231).
        private const string UnprotectScript =
            "param([byte[]]$Encrypted, [byte[]]$Entropy)\n" +
            "Add-Type -AssemblyName System.Security\n" +
            "[System.Security.Cryptography.ProtectedData]::Unprotect($Encrypted, $Entropy, [System.Security.Cryptography.DataProtectionScope]::LocalMachine)";

        private static long _localOperations;
        private static long _remoteOperations;

        /// <summary>Completed local operations; records the exercised path without secret data.</summary>
        public static long LocalOperations { get { return Interlocked.Read(ref _localOperations); } }

        /// <summary>Completed remote operations; records the exercised path without secret data.</summary>
        public static long RemoteOperations { get { return Interlocked.Read(ref _remoteOperations); } }

        /// <summary>Whether the physical SQL host is this Windows machine.</summary>
        public static bool IsLocal(string computerName)
        {
            return String.Equals(computerName, Environment.MachineName, StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>Reads SQL's entropy through the local registry or credentialed remote StdRegProv.</summary>
        public static byte[] ReadSqlEntropy(string computerName, string instanceId, PSCredential credential)
        {
            string path = String.Format(CultureInfo.InvariantCulture,
                @"SOFTWARE\Microsoft\Microsoft SQL Server\{0}\Security", instanceId);
            if (IsLocal(computerName))
            {
                using (RegistryKey root = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                using (RegistryKey key = root.OpenSubKey(path, false))
                {
                    byte[] entropy = key == null ? null : key.GetValue("Entropy") as byte[];
                    if (entropy == null)
                        throw new InvalidOperationException("SQL Server registry entropy was not found.");
                    return entropy;
                }
            }

            ConnectionOptions options = new ConnectionOptions
            {
                Authentication = AuthenticationLevel.PacketPrivacy,
                Impersonation = ImpersonationLevel.Impersonate
            };
            if (credential != null)
            {
                options.Username = credential.UserName;
                options.SecurePassword = credential.Password;
            }
            ManagementScope scope = new ManagementScope(
                String.Format(CultureInfo.InvariantCulture, @"\\{0}\root\default", computerName), options);
            scope.Connect();
            using (ManagementClass registry = new ManagementClass(scope, new ManagementPath("StdRegProv"), null))
            using (ManagementBaseObject input = registry.GetMethodParameters("GetBinaryValue"))
            {
                input["hDefKey"] = (uint)2147483650;
                input["sSubKeyName"] = path;
                input["sValueName"] = "Entropy";
                using (ManagementBaseObject output = registry.InvokeMethod("GetBinaryValue", input, null))
                {
                    uint error = Convert.ToUInt32(output["ReturnValue"], CultureInfo.InvariantCulture);
                    if (error != 0)
                        throw new Win32Exception(unchecked((int)error));
                    byte[] entropy = output["uValue"] as byte[];
                    if (entropy == null)
                        throw new InvalidOperationException("SQL Server registry entropy was not found.");
                    return (byte[])entropy.Clone();
                }
            }
        }

        /// <summary>Unprotects bytes on their Windows host. The caller owns and clears the returned buffer.</summary>
        public static byte[] Unprotect(string computerName, byte[] encrypted, byte[] entropy,
            PSCredential credential, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (IsLocal(computerName))
            {
                byte[] local = ProtectedData.Unprotect(encrypted, entropy, DataProtectionScope.LocalMachine);
                Interlocked.Increment(ref _localOperations);
                return local;
            }

            using (System.Management.Automation.Runspaces.Runspace runspace = RunspaceFactory.CreateRunspace(new WSManConnectionInfo(
                false, computerName, 5985, "wsman", "http://schemas.microsoft.com/powershell/Microsoft.PowerShell", credential)))
            {
                try
                {
                    runspace.Open();
                    using (var ps = PowerShell.Create())
                    {
                        ps.Runspace = runspace;
                        ps.AddScript(UnprotectScript).AddParameter("Encrypted", encrypted).AddParameter("Entropy", entropy);
                        using (cancellationToken.Register(() => ps.Stop()))
                        {
                            Collection<byte> output = ps.Invoke<byte>();
                            if (ps.HadErrors)
                                throw new InvalidOperationException("The source host could not unprotect its service master key.");
                            byte[] result = new byte[output.Count];
                            output.CopyTo(result, 0);
                            // Invoke<T> materializes a second managed copy of the unprotected key.
                            for (int index = 0; index < output.Count; index++)
                                output[index] = 0;
                            Interlocked.Increment(ref _remoteOperations);
                            return result;
                        }
                    }
                }
                finally
                {
                    runspace.Close();
                }
            }
        }
    }
}
