#nullable enable

using System;
using System.Collections.Generic;
using System.Text;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Ports the Get-SanExt / GetHexLength helpers shared by the certificate-request commands
/// (New-DbaComputerCertificate, New-DbaComputerCertificateSigningRequest): builds the ASN.1
/// subjectAltName (2.5.29.17) extension as base64, wrapped in 64-char inf-file lines.
/// </summary>
internal static class CertificateSanEncoder
{
    internal static List<string> GetSanExt(string[] hostNames)
    {
        StringBuilder temp = new();
        foreach (string fqdn in hostNames)
        {
            StringBuilder hex = new();
            foreach (char c in fqdn)
            {
                hex.AppendFormat("{0:X2}", (int)c);
            }
            string hexString = hex.ToString();
            string hexLength = GetHexLength(hexString.Length / 2);
            temp.Append("82").Append(hexLength).Append(hexString);
        }
        string tempStr = temp.ToString();
        string totalHexLength = GetHexLength(tempStr.Length / 2);
        tempStr = "30" + totalHexLength + tempStr;

        byte[] bytes = new byte[tempStr.Length / 2];
        for (int i = 0; i < tempStr.Length; i += 2)
        {
            bytes[i / 2] = Convert.ToByte(tempStr.Substring(i, 2), 16);
        }
        string base64 = Convert.ToBase64String(bytes);

        List<string> lines = new();
        for (int i = 0; i < base64.Length; i += 64)
        {
            string line = base64.Substring(i, Math.Min(64, base64.Length - i));
            lines.Add(i == 0 ? $"2.5.29.17={line}" : $"_continue_={line}");
        }
        return lines;
    }

    // PS GetHexLength: hex X2 of strLen; if strLen>127, prefix with X2 of (128 + hex.Length/2).
    internal static string GetHexLength(int strLen)
    {
        string hex = string.Format("{0:X2}", strLen);
        if (strLen > 127)
        {
            return string.Format("{0:X2}", 128 + (hex.Length / 2)) + hex;
        }
        return hex;
    }
}
