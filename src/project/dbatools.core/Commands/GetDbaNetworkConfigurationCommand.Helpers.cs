#nullable enable
#pragma warning disable CA1416 // Windows-only command: WMI, registry, certificate store

using System;
using System.Collections.Generic;
using System.Management;
using System.Management.Automation;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Computer;
using Dataplat.Dbatools.Configuration;
using Microsoft.SqlServer.Management.Smo.Wmi;

namespace Dataplat.Dbatools.Commands;

public sealed partial class GetDbaNetworkConfigurationCommand
{
    private const uint HKEY_LOCAL_MACHINE = 0x80000002u;

    private ManagedComputer BuildManagedComputer(string computerName)
    {
        if (Credential is not null)
        {
            // ManagedComputer requires a plain-text password; this is a necessary
            // exception — the WMI API has no secure-string overload.
            System.Net.NetworkCredential netCred = Credential.GetNetworkCredential();
            string user = string.IsNullOrEmpty(netCred.Domain)
                ? netCred.UserName
                : netCred.Domain + "\\" + netCred.UserName;
            return new ManagedComputer(computerName, user, netCred.Password);
        }
        return new ManagedComputer(computerName);
    }

    private static object? GetProtocolPropertyValue(ServerProtocol sp, string name)
    {
        foreach (ProtocolProperty pp in sp.ProtocolProperties)
        {
            if (string.Equals(pp.Name, name, StringComparison.Ordinal))
                return pp.Value;
        }
        return null;
    }

    private static PSObject BuildTcpIpProperties(ServerProtocol wmiSpTcp)
    {
        PSObject obj = new();
        obj.Properties.Add(new PSNoteProperty("Enabled", GetProtocolPropertyValue(wmiSpTcp, "Enabled")));
        obj.Properties.Add(new PSNoteProperty("KeepAlive", GetProtocolPropertyValue(wmiSpTcp, "KeepAlive")));
        obj.Properties.Add(new PSNoteProperty("ListenAll", GetProtocolPropertyValue(wmiSpTcp, "ListenOnAllIPs")));
        return obj;
    }

    private static object[] BuildTcpIpAddresses(ServerProtocol wmiSpTcp)
    {
        // PS: TcpIpAddresses = $outputTcpIpAddressesIPn + $outputTcpIpAddressesIPAll
        // ServerProtocolIPAddress is internal — use var to iterate without naming the type.
        List<PSObject> result = new();
        PSObject? ipAll = null;

        // ServerProtocolIPAddress / its IPAddressProperties collection are internal types — use dynamic
        foreach (dynamic ipAddr in wmiSpTcp.IPAddresses)
        {
            if (string.Equals((string)ipAddr.Name, "IPAll", StringComparison.OrdinalIgnoreCase))
            {
                // IPAll has only Name, TcpDynamicPorts, TcpPort
                object? tdp = null, tp = null;
                foreach (dynamic prop in ipAddr.IPAddressProperties)
                {
                    if (prop.Name == "TcpDynamicPorts") tdp = prop.Value;
                    else if (prop.Name == "TcpPort") tp = prop.Value;
                }
                ipAll = new PSObject();
                ipAll.Properties.Add(new PSNoteProperty("Name", (string)ipAddr.Name));
                ipAll.Properties.Add(new PSNoteProperty("TcpDynamicPorts", tdp));
                ipAll.Properties.Add(new PSNoteProperty("TcpPort", tp));
            }
            else
            {
                object? active = null, enabled = null, ipAddress = null, tdp = null, tp = null;
                foreach (dynamic prop in ipAddr.IPAddressProperties)
                {
                    if (prop.Name == "Active") active = prop.Value;
                    else if (prop.Name == "Enabled") enabled = prop.Value;
                    else if (prop.Name == "IpAddress") ipAddress = prop.Value;
                    else if (prop.Name == "TcpDynamicPorts") tdp = prop.Value;
                    else if (prop.Name == "TcpPort") tp = prop.Value;
                }
                PSObject ip = new();
                ip.Properties.Add(new PSNoteProperty("Name", (string)ipAddr.Name));
                ip.Properties.Add(new PSNoteProperty("Active", active));
                ip.Properties.Add(new PSNoteProperty("Enabled", enabled));
                ip.Properties.Add(new PSNoteProperty("IpAddress", ipAddress));
                ip.Properties.Add(new PSNoteProperty("TcpDynamicPorts", tdp));
                ip.Properties.Add(new PSNoteProperty("TcpPort", tp));
                result.Add(ip);
            }
        }

        // IPn entries first, then IPAll (matching PS array concatenation order)
        if (ipAll is not null) result.Add(ipAll);
        object[] arr = new object[result.Count];
        for (int i = 0; i < result.Count; i++) arr[i] = result[i];
        return arr;
    }

    private ManagementClass GetStdRegProv(string computerName)
    {
        var opts = new ConnectionOptions();
        if (Credential is not null)
        {
            // WMI ConnectionOptions requires plain text password; no secure-string overload
            System.Net.NetworkCredential netCred = Credential.GetNetworkCredential();
            opts.Username = string.IsNullOrEmpty(netCred.Domain)
                ? netCred.UserName
                : netCred.Domain + "\\" + netCred.UserName;
            opts.Password = netCred.Password;
        }
        var scope = new ManagementScope(@"\\" + computerName + @"\root\cimv2", opts);
        scope.Connect();
        return new ManagementClass(scope, new ManagementPath("StdRegProv"), null);
    }

    private static string? GetRegStringValue(ManagementClass stdReg, string subKey, string valueName)
    {
        using ManagementBaseObject inP = stdReg.GetMethodParameters("GetStringValue");
        inP["hDefKey"] = HKEY_LOCAL_MACHINE;
        inP["sSubKeyName"] = subKey;
        inP["sValueName"] = valueName;
        using ManagementBaseObject outP = stdReg.InvokeMethod("GetStringValue", inP, null);
        return outP?["sValue"]?.ToString();
    }

    private static uint? GetRegDWordValue(ManagementClass stdReg, string subKey, string valueName)
    {
        using ManagementBaseObject inP = stdReg.GetMethodParameters("GetDWORDValue");
        inP["hDefKey"] = HKEY_LOCAL_MACHINE;
        inP["sSubKeyName"] = subKey;
        inP["sValueName"] = valueName;
        using ManagementBaseObject outP = stdReg.InvokeMethod("GetDWORDValue", inP, null);
        return outP?["uValue"] as uint?;
    }

    private List<HostCertificateStore.Entry> ReadCertificates(string computer)
    {
        bool ssl = LanguagePrimitives.IsTrue(RemotingSetting("psremoting.pssession.usessl"));
        int port = ssl ? 5986 : 5985;
        if (LanguagePrimitives.TryConvertTo(RemotingSetting("psremoting.pssession.port"), out int configured) && configured > 0) port = configured;
        string shell = SessionState.PSVariable.GetValue("PSSessionConfigurationName") as string ?? "http://schemas.microsoft.com/powershell/Microsoft.PowerShell";
        return HostCertificateStore.Read(computer, Credential!, ssl, port, shell, CancellationToken);
    }

    private static object? RemotingSetting(string name)
        => ConfigurationHost.Configurations.TryGetValue(name, out Config? value) ? value?.Value : null;

    private PSObject[]? GetSuitableCertificates(List<HostCertificateStore.Entry> entries, string? virtualName)
    {
        List<PSObject> suitable = new();
        X509KeyUsageFlags required = X509KeyUsageFlags.DigitalSignature | X509KeyUsageFlags.KeyEncipherment;
        foreach (HostCertificateStore.Entry entry in entries)
        {
            if (!entry.Personal || entry.Archived) continue;
            X509Certificate2 cert = entry.Certificate;
            if (!string.IsNullOrEmpty(entry.Failure))
                WriteMessage(MessageLevel.Verbose, string.Format("Failed to test certificate '{0}' for suitability: {1}", cert.Thumbprint, entry.Failure));
            if (!entry.PrivateKeyValid) continue;
            try
            {
                bool usage = false, authentication = false;
                foreach (X509Extension extension in cert.Extensions)
                {
                    if (extension is X509KeyUsageExtension keyUsage) usage = (keyUsage.KeyUsages & required) == required;
                    if (extension is X509EnhancedKeyUsageExtension enhanced)
                        foreach (Oid oid in enhanced.EnhancedKeyUsages)
                            if (oid.FriendlyName == "Server Authentication") authentication = true;
                }
                using RSA? rsa = cert.GetRSAPublicKey();
                if (rsa is null || rsa.KeySize < 2048 || cert.PublicKey.Oid.FriendlyName?.IndexOf("RSA", StringComparison.OrdinalIgnoreCase) < 0) continue;
                if (!Regex.IsMatch(cert.SignatureAlgorithm.FriendlyName ?? "", "sha256|sha384|sha512", RegexOptions.IgnoreCase)) continue;
                if (!usage || !authentication || cert.NotBefore >= DateTime.Now || cert.NotAfter <= DateTime.Now) continue;
                string name = string.IsNullOrEmpty(virtualName) ? entry.ComputerName : virtualName!;
                foreach (string dns in GetDnsNames(cert))
                {
                    if (string.Equals(dns, name, StringComparison.OrdinalIgnoreCase) ||
                        string.Equals(dns, name + "." + entry.UserDomain, StringComparison.OrdinalIgnoreCase))
                    {
                        suitable.Add(PSObject.AsPSObject(cert));
                        break;
                    }
                }
            }
            catch (Exception failure)
            {
                WriteMessage(MessageLevel.Verbose, string.Format("Failed to test certificate '{0}' for suitability: {1}", cert.Thumbprint, failure.Message));
            }
        }
        return suitable.Count == 0 ? null : suitable.ToArray();
    }

    private static IEnumerable<string> GetDnsNames(X509Certificate2 cert)
    {
        List<string> names = new();
        foreach (X509Extension extension in cert.Extensions)
        {
            if (extension.Oid?.Value != "2.5.29.17") continue;
            byte[] data = extension.RawData;
            int offset = 0;
            if (data.Length == 0 || data[offset++] != 0x30) break;
            int length = ReadDerLength(data, ref offset);
            if (length > data.Length - offset) throw new CryptographicException("Invalid certificate subject alternative name.");
            int end = offset + length;
            while (offset < end)
            {
                int tag = data[offset++];
                int count = ReadDerLength(data, ref offset);
                if (count > end - offset) throw new CryptographicException("Invalid certificate subject alternative name.");
                if (tag == 0x82)
                {
                    string dnsName = System.Text.Encoding.ASCII.GetString(data, offset, count);
                    string unicodeName;
                    try { unicodeName = new System.Globalization.IdnMapping().GetUnicode(dnsName); }
                    // The certificate provider preserves names that are not valid Punycode.
                    catch (ArgumentException) { unicodeName = dnsName; }
                    names.Add(unicodeName);
                }
                offset += count;
            }
            break;
        }
        if (names.Count == 0)
        {
            Match match = Regex.Match(cert.Subject, "CN=([^,]+)", RegexOptions.IgnoreCase);
            if (match.Success) names.Add(match.Groups[1].Value);
        }
        return names;
    }

    private static int ReadDerLength(byte[] data, ref int offset)
    {
        if (offset >= data.Length) throw new CryptographicException("Invalid certificate subject alternative name.");
        int length = data[offset++];
        if ((length & 0x80) == 0) return length;
        int count = length & 0x7f;
        if (count == 0 || count > 4 || count > data.Length - offset) throw new CryptographicException("Invalid certificate subject alternative name.");
        length = 0;
        for (int i = 0; i < count; i++) length = checked(length * 256 + data[offset++]);
        return length;
    }

    private static object? GetDnsNamesArray(X509Certificate2 cert)
        => PSObject.AsPSObject(cert).Properties["DnsNameList"]?.Value;

    private static bool? ConvertDWordToBool(uint? value)
        => value switch { 0u => false, 1u => true, _ => (bool?)null };
}
