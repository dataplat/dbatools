#nullable enable
#pragma warning disable CA1416 // Windows-only: WMI StdRegProv

using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;
using System.Management;
using System.Management.Automation;
using System.Security;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Reads the SQL Server SuperSocketNetLib values that Get-DbaExtendedProtection and Set-DbaExtendedProtection
/// report, through the WMI registry provider (StdRegProv) on the target computer. Values come back with the types
/// PowerShell's Get-ItemProperty gives them: REG_DWORD as Int32, REG_QWORD as Int64, REG_SZ and REG_EXPAND_SZ
/// (expanded) as String, REG_MULTI_SZ as String[] and REG_BINARY as Byte[]; an absent value is null.
/// </summary>
public static class ExtendedProtectionRegistry
{
    private const uint LocalMachine = 0x80000002u;
    private const string ActiveComputerNameKey = @"SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName";

    /// <summary>The values one read returns.</summary>
    public sealed class Settings
    {
        /// <summary>The target's active computer name, as $env:COMPUTERNAME reads it there.</summary>
        public object? ComputerName { get; set; }

        /// <summary>The raw ExtendedProtection value, or null when the value is absent.</summary>
        public object? ExtendedProtection { get; set; }

        /// <summary>The raw AcceptedSPNs value, or null when the value is absent.</summary>
        public object? AcceptedSpns { get; set; }
    }

    /// <summary>
    /// Reads ExtendedProtection and AcceptedSPNs under HKLM\&lt;regRoot&gt;\MSSQLServer\SuperSocketNetLib.
    /// A missing key throws, as Get-ItemProperty does under -ErrorAction Stop.
    /// </summary>
    /// <param name="computerName">The computer to read.</param>
    /// <param name="regRoot">The instance registry root from the SQL service's REGROOT property.</param>
    /// <param name="credential">A Windows credential for a remote computer; ignored for the local computer.</param>
    /// <returns>The values read.</returns>
    public static Settings Read(string computerName, string regRoot, PSCredential? credential)
    {
        using (ManagementClass provider = Connect(computerName, credential))
        {
            return ReadSettings(provider, NetworkKey(regRoot));
        }
    }

    /// <summary>
    /// Writes ExtendedProtection and AcceptedSPNs as Set-ItemProperty writes them, then reads both back.
    /// An existing value keeps its registry kind; a new one takes the kind of its .NET type (Int32 as REG_DWORD,
    /// String[] as REG_MULTI_SZ, Byte[] as REG_BINARY, anything else as its REG_SZ text).
    /// </summary>
    /// <param name="computerName">The computer to change.</param>
    /// <param name="regRoot">The instance registry root from the SQL service's REGROOT property.</param>
    /// <param name="credential">A Windows credential for a remote computer; ignored for the local computer.</param>
    /// <param name="setProtection">Whether ExtendedProtection is written.</param>
    /// <param name="protection">The ExtendedProtection value to write.</param>
    /// <param name="setSpns">Whether AcceptedSPNs is written.</param>
    /// <param name="spns">The AcceptedSPNs value to write.</param>
    /// <returns>The values read back after writing.</returns>
    public static Settings Write(string computerName, string regRoot, PSCredential? credential,
        bool setProtection, object? protection, bool setSpns, string spns)
    {
        using (ManagementClass provider = Connect(computerName, credential))
        {
            string networkKey = NetworkKey(regRoot);
            if (setProtection)
            {
                WriteValue(provider, networkKey, "ExtendedProtection", protection);
            }
            if (setSpns)
            {
                WriteValue(provider, networkKey, "AcceptedSPNs", spns);
            }
            return ReadSettings(provider, networkKey);
        }
    }

    private static string NetworkKey(string regRoot)
    {
        return regRoot + @"\MSSQLServer\SuperSocketNetLib";
    }

    private static Settings ReadSettings(ManagementClass provider, string networkKey)
    {
        Dictionary<string, int> kinds = ValueKinds(provider, networkKey);
        Settings settings = new Settings();
        settings.ExtendedProtection = ReadValue(provider, networkKey, kinds, "ExtendedProtection");
        settings.AcceptedSpns = ReadValue(provider, networkKey, kinds, "AcceptedSPNs");
        settings.ComputerName = ReadTyped(provider, ActiveComputerNameKey, "ComputerName", 1);
        return settings;
    }

    // PS: Set-ItemProperty -Path $regPath -Name <name> -Value <value>. The registry provider keeps an existing
    // value's kind and converts the new value to it; a missing value takes the kind RegistryKey.SetValue infers.
    private static void WriteValue(ManagementClass provider, string key, string name, object? value)
    {
        object? raw = value is PSObject wrapped ? wrapped.BaseObject : value;
        int kind;
        if (!ValueKinds(provider, key).TryGetValue(name, out kind))
        {
            kind = raw is int ? 4 : raw is string[] ? 7 : raw is byte[] ? 3 : 1;
        }
        switch (kind)
        {
            case 1:
                Store(provider, "SetStringValue", key, name, "sValue", AsText(raw));
                break;
            case 2:
                Store(provider, "SetExpandedStringValue", key, name, "sValue", AsText(raw));
                break;
            case 4:
                Store(provider, "SetDWORDValue", key, name, "uValue", unchecked((uint)AsDword(raw)));
                break;
            case 7:
                Store(provider, "SetMultiStringValue", key, name, "sValue",
                    (raw is null ? null : LanguagePrimitives.ConvertTo<string[]>(raw)) ?? new string[0]);
                break;
            case 11:
                Store(provider, "SetQWORDValue", key, name, "uValue", unchecked((ulong)AsQword(raw)));
                break;
            default:
                Store(provider, "SetBinaryValue", key, name, "uValue",
                    (raw is null ? null : LanguagePrimitives.ConvertTo<byte[]>(raw)) ?? new byte[0]);
                break;
        }
    }

    private static string AsText(object? raw)
    {
        return raw is null ? String.Empty : LanguagePrimitives.ConvertTo<string>(raw) ?? String.Empty;
    }

    // The provider converts to Int32 and falls back to UInt32 for values above Int32.MaxValue.
    private static int AsDword(object? raw)
    {
        if (raw is null)
        {
            return 0;
        }
        try
        {
            return LanguagePrimitives.ConvertTo<int>(raw);
        }
        catch (PSInvalidCastException)
        {
            return unchecked((int)LanguagePrimitives.ConvertTo<uint>(raw));
        }
    }

    // The provider converts to Int64 and falls back to UInt64 for values above Int64.MaxValue.
    private static long AsQword(object? raw)
    {
        if (raw is null)
        {
            return 0;
        }
        try
        {
            return LanguagePrimitives.ConvertTo<long>(raw);
        }
        catch (PSInvalidCastException)
        {
            return unchecked((long)LanguagePrimitives.ConvertTo<ulong>(raw));
        }
    }

    private static void Store(ManagementClass provider, string method, string key, string name, string field, object data)
    {
        using (ManagementBaseObject arguments = provider.GetMethodParameters(method))
        {
            arguments["hDefKey"] = LocalMachine;
            arguments["sSubKeyName"] = key;
            arguments["sValueName"] = name;
            arguments[field] = data;
            using (ManagementBaseObject reply = provider.InvokeMethod(method, arguments, null))
            {
                uint code = Convert.ToUInt32(reply["ReturnValue"], CultureInfo.InvariantCulture);
                if (code != 0)
                {
                    throw RegistryFailure(code);
                }
            }
        }
    }

    // A nonzero StdRegProv ReturnValue as the error the registry gave. Access denied (ERROR_ACCESS_DENIED, 5) is the
    // SecurityException the registry provider behind Get-ItemProperty and Set-ItemProperty reports for a key the caller
    // may not open, "Requested registry access is not allowed.", with no inner exception, as RegistryKey throws it: the warning
    // text is the innermost message, so an inner Win32Exception would show "Access is denied" instead (result 20261105T0001273695815Z).
    private static Exception RegistryFailure(uint code)
    {
        if (code == 5)
        {
            return new SecurityException("Requested registry access is not allowed.");
        }
        return new Win32Exception(unchecked((int)code));
    }

    private static ManagementClass Connect(string computerName, PSCredential? credential)
    {
        ConnectionOptions connection = new ConnectionOptions();
        connection.Impersonation = ImpersonationLevel.Impersonate;
        connection.Authentication = AuthenticationLevel.PacketPrivacy;
        // WMI refuses explicit credentials for a local connection; the pinned local Invoke-Command ignores them too.
        bool remote = !Dataplat.Dbatools.Utility.Validation.IsLocalhost(computerName);
        if (remote && credential != null)
        {
            connection.Username = credential.UserName;
            connection.SecurePassword = credential.Password;
        }
        ManagementScope registryScope = new ManagementScope(String.Format(@"\\{0}\root\default", computerName), connection);
        registryScope.Connect();
        return new ManagementClass(registryScope, new ManagementPath("StdRegProv"), null);
    }

    // Value names and their registry kinds; a value name lookup is case-insensitive, as the registry is.
    private static Dictionary<string, int> ValueKinds(ManagementClass provider, string key)
    {
        Dictionary<string, int> kinds = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        using (ManagementBaseObject listing = Call(provider, "EnumValues", key, null))
        {
            string[]? names = listing["sNames"] as string[];
            int[]? types = listing["Types"] as int[];
            if (names == null || types == null)
            {
                return kinds;
            }
            for (int index = 0; index < names.Length && index < types.Length; index++)
            {
                kinds[names[index]] = types[index];
            }
        }
        return kinds;
    }

    private static object? ReadValue(ManagementClass provider, string key, Dictionary<string, int> kinds, string name)
    {
        int kind;
        if (!kinds.TryGetValue(name, out kind))
        {
            return null;
        }
        return ReadTyped(provider, key, name, kind);
    }

    private static object? ReadTyped(ManagementClass provider, string key, string name, int kind)
    {
        switch (kind)
        {
            case 1: // REG_SZ
                return Fetch(provider, "GetStringValue", key, name, "sValue");
            case 2: // REG_EXPAND_SZ, expanded on the target as Get-ItemProperty expands it
                return Fetch(provider, "GetExpandedStringValue", key, name, "sValue");
            case 4: // REG_DWORD: Get-ItemProperty returns the signed Int32
                object? dword = Fetch(provider, "GetDWORDValue", key, name, "uValue");
                return dword == null ? null : (object)unchecked((int)Convert.ToUInt32(dword, CultureInfo.InvariantCulture));
            case 7: // REG_MULTI_SZ
                return Fetch(provider, "GetMultiStringValue", key, name, "sValue");
            case 11: // REG_QWORD: Get-ItemProperty returns the signed Int64
                object? qword = Fetch(provider, "GetQWORDValue", key, name, "uValue");
                return qword == null ? null : (object)unchecked((long)Convert.ToUInt64(qword, CultureInfo.InvariantCulture));
            default: // REG_BINARY and other kinds come back as bytes
                return Fetch(provider, "GetBinaryValue", key, name, "uValue");
        }
    }

    private static object? Fetch(ManagementClass provider, string method, string key, string name, string output)
    {
        using (ManagementBaseObject result = Call(provider, method, key, name))
        {
            return result[output];
        }
    }

    // Calls one StdRegProv method on HKLM; a nonzero ReturnValue is the Win32 error the registry gave.
    private static ManagementBaseObject Call(ManagementClass provider, string method, string key, string? name)
    {
        using (ManagementBaseObject arguments = provider.GetMethodParameters(method))
        {
            arguments["hDefKey"] = LocalMachine;
            arguments["sSubKeyName"] = key;
            if (name != null)
            {
                arguments["sValueName"] = name;
            }
            ManagementBaseObject reply = provider.InvokeMethod(method, arguments, null);
            uint code = Convert.ToUInt32(reply["ReturnValue"], CultureInfo.InvariantCulture);
            if (code == 0)
            {
                return reply;
            }
            reply.Dispose();
            throw RegistryFailure(code);
        }
    }
}
