using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Threading;

namespace Dataplat.Dbatools.Computer
{
    /// <summary>Public certificate snapshots with private-key usability measured on their Windows host.</summary>
    public static class HostCertificateStore
    {
        // CIM and the remote registry expose public certificates, but cannot open a host's private key.
        // I2 "Remote host work": only this host-bound store/key read runs remotely; selection stays in C#.
        private const string ReadCertificatesScript = @"
$ErrorActionPreference = 'Stop'
foreach ($cert in Get-ChildItem Cert:\LocalMachine -Recurse -Force -ErrorAction SilentlyContinue) {
    if ($cert -isnot [System.Security.Cryptography.X509Certificates.X509Certificate2]) { continue }
    $personal = $cert.PSParentPath -match '\\My$'
    $valid = $false
    $failure = $null
    $rsa = $null
    try {
        if ($personal -and -not $cert.Archived) {
            try { $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert) }
            catch { $rsa = $cert.PrivateKey }
            if ($rsa -is [System.Security.Cryptography.RSACng]) {
                $valid = ($rsa.Key.KeyUsage -band [System.Security.Cryptography.CngKeyUsages]::Decryption) -ne 0
            } elseif ($rsa -is [System.Security.Cryptography.RSACryptoServiceProvider]) {
                $valid = $rsa.CspKeyContainerInfo.KeyNumber -eq [System.Security.Cryptography.KeyNumber]::Exchange
            }
        }
    } catch { $failure = $_.Exception.Message }
    finally { if ($rsa) { $rsa.Dispose() } }
    [pscustomobject]@{ RawData = $cert.RawData; FriendlyName = $cert.FriendlyName; Personal = $personal; Archived = $cert.Archived; PrivateKeyValid = $valid; Failure = $failure; ComputerName = [System.Net.Dns]::GetHostName(); UserDomain = $env:USERDNSDOMAIN }
    $cert.Dispose()
}";

        /// <summary>One store entry. No private key leaves the host.</summary>
        public sealed class Entry
        {
            public X509Certificate2 Certificate { get; internal set; }
            public bool Personal { get; internal set; }
            public bool Archived { get; internal set; }
            public bool PrivateKeyValid { get; internal set; }
            public string Failure { get; internal set; }
            public string ComputerName { get; internal set; }
            public string UserDomain { get; internal set; }
        }

        private delegate bool StoreCallback(IntPtr store, uint flags, IntPtr info, IntPtr reserved, IntPtr argument);
        [DllImport("crypt32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CertEnumSystemStore(uint flags, IntPtr location, IntPtr argument, StoreCallback callback);

        /// <summary>Reads local stores directly, or uses the caller's identity in a remote host runspace.</summary>
        public static List<Entry> Read(string computer, PSCredential credential, bool ssl, int port,
            string configuration, CancellationToken cancellation)
        {
            cancellation.ThrowIfCancellationRequested();
            if (String.Equals(computer, Environment.MachineName, StringComparison.OrdinalIgnoreCase) &&
                (credential == null || credential == PSCredential.Empty)) return ReadLocal(cancellation);
            using (System.Management.Automation.Runspaces.Runspace runspace = RunspaceFactory.CreateRunspace(new WSManConnectionInfo(
                ssl, computer, port, "wsman", configuration, credential)))
            {
                runspace.Open();
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    shell.AddScript(ReadCertificatesScript);
                    using (cancellation.Register(() => shell.Stop()))
                    {
                        var values = shell.Invoke();
                        if (shell.HadErrors) throw new RuntimeException(shell.Streams.Error[0].ToString(), shell.Streams.Error[0].Exception);
                        List<Entry> entries = new List<Entry>();
                        foreach (PSObject value in values)
                        {
                            X509Certificate2 cert = new X509Certificate2(LanguagePrimitives.ConvertTo<byte[]>(value.Properties["RawData"].Value));
                            cert.FriendlyName = LanguagePrimitives.ConvertTo<string>(value.Properties["FriendlyName"].Value);
                            entries.Add(new Entry { Certificate = cert,
                                Personal = LanguagePrimitives.IsTrue(value.Properties["Personal"].Value),
                                Archived = LanguagePrimitives.IsTrue(value.Properties["Archived"].Value),
                                PrivateKeyValid = LanguagePrimitives.IsTrue(value.Properties["PrivateKeyValid"].Value),
                                Failure = LanguagePrimitives.ConvertTo<string>(value.Properties["Failure"].Value),
                                ComputerName = LanguagePrimitives.ConvertTo<string>(value.Properties["ComputerName"].Value),
                                UserDomain = LanguagePrimitives.ConvertTo<string>(value.Properties["UserDomain"].Value) });
                        }
                        return entries;
                    }
                }
            }
        }

        private static List<Entry> ReadLocal(CancellationToken cancellation)
        {
            List<string> names = new List<string>();
            StoreCallback callback = (store, flags, info, reserved, argument) => { names.Add(Marshal.PtrToStringUni(store)); return true; };
            if (!CertEnumSystemStore(0x00020000, IntPtr.Zero, IntPtr.Zero, callback)) throw new Win32Exception(Marshal.GetLastWin32Error());
            GC.KeepAlive(callback);
            List<Entry> entries = new List<Entry>();
            foreach (string name in names)
            {
                cancellation.ThrowIfCancellationRequested();
                using (X509Store store = new X509Store(name, StoreLocation.LocalMachine))
                {
                    // The pin silently ignores stores its certificate provider cannot open.
                    try { store.Open(OpenFlags.ReadOnly | OpenFlags.OpenExistingOnly | OpenFlags.IncludeArchived); }
                    catch (CryptographicException) { continue; }
                    foreach (X509Certificate2 cert in store.Certificates)
                    {
                        Entry entry = new Entry { Certificate = cert, Personal = String.Equals(name, "My", StringComparison.OrdinalIgnoreCase),
                            Archived = cert.Archived, ComputerName = System.Net.Dns.GetHostName(), UserDomain = Environment.GetEnvironmentVariable("USERDNSDOMAIN") };
                        if (entry.Personal && !entry.Archived)
                        {
                            RSA rsa = null;
                            try
                            {
                                try { rsa = cert.GetRSAPrivateKey(); }
                                catch { rsa = cert.PrivateKey as RSA; }
                                RSACng cng = rsa as RSACng;
                                RSACryptoServiceProvider csp = rsa as RSACryptoServiceProvider;
                                entry.PrivateKeyValid = cng != null ? (cng.Key.KeyUsage & CngKeyUsages.Decryption) != 0
                                    : csp != null && csp.CspKeyContainerInfo.KeyNumber == KeyNumber.Exchange;
                            }
                            catch (Exception failure) { entry.Failure = failure.Message; }
                            finally { if (rsa != null) rsa.Dispose(); }
                        }
                        entries.Add(entry);
                    }
                }
            }
            return entries;
        }
    }
}
