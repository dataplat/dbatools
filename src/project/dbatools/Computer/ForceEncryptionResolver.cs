#pragma warning disable CA1416 // Windows-only: SQL WMI ManagedComputer, WindowsPrincipal

using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;
using System.Management;
using System.Management.Automation;
using System.Security.Principal;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo.Wmi;

namespace Dataplat.Dbatools.Commands
{

/// <summary>
/// Shared native SQL service identity and network registry access.
/// Command callers retain their own messages, confirmation and output contracts.
/// </summary>
public static class ForceEncryptionResolver
{
    public sealed class Resolution
    {
        public string RegRoot = "";
        public string Vsname;
        public string InstanceName;
        public string ServiceAccount;
    }

    /// <summary>The failure kinds the callers map to their own Stop-Function messages.</summary>
    public enum Outcome
    {
        Ok,
        AccessFailed,
        InstanceNotFound
    }

    // PS: $null = Test-ElevationRequirement -ComputerName $instance -Continue.
    public static bool RequireElevationSatisfied(DbaInstanceParameter instance)
    {
        if (GetConfigTruthy("commands.test-elevationrequirement.disable"))
        {
            return true;
        }
        bool isElevated = new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
        // Only a localhost target without an elevated console fails; a remote target passes through.
        return !(instance.IsLocalHost && !isElevated);
    }

    // PS: $sqlwmi = new ManagedComputer(full).Services | Where DisplayName -eq "SQL Server (inst)"
    //     then REGROOT/VSNAME direct read + the -match/-Split "Value=" fallback.
    public static Outcome Resolve(string fullComputerName, DbaInstanceParameter instance, PSCredentialWrap credential, out Resolution resolution, out Exception accessException)
    {
        resolution = new Resolution();
        accessException = null;

        Service sqlwmi = null;
        try
        {
            ManagedComputer wmi = BuildManagedComputer(fullComputerName, credential);
            string wantDisplay = String.Format("SQL Server ({0})", instance.InstanceName);
            foreach (Service svc in wmi.Services)
            {
                if (string.Equals(svc.DisplayName, wantDisplay, StringComparison.OrdinalIgnoreCase))
                {
                    sqlwmi = svc;
                    break;
                }
            }
        }
        catch (Exception ex)
        {
            accessException = ex;
            return Outcome.AccessFailed;
        }

        string regRoot = null, vsname = null, instanceName = null, serviceAccount = null;
        if (sqlwmi != null)
        {
            foreach (dynamic ap in sqlwmi.AdvancedProperties)
            {
                if (string.Equals((string)ap.Name, "REGROOT", StringComparison.OrdinalIgnoreCase))
                    regRoot = ap.Value?.ToString();
                else if (string.Equals((string)ap.Name, "VSNAME", StringComparison.OrdinalIgnoreCase))
                    vsname = ap.Value?.ToString();
            }
            try
            {
                instanceName = sqlwmi.DisplayName.Replace("SQL Server (", "").Replace(")", "");
            }
            catch
            {
                // instance name aliased / absent - PS empty-catch
            }
            serviceAccount = sqlwmi.ServiceAccount;
        }

        if (string.IsNullOrEmpty(regRoot))
        {
            string regRootMatch = null, vsnameMatch = null;
            if (sqlwmi != null)
            {
                foreach (dynamic ap in sqlwmi.AdvancedProperties)
                {
                    string apStr = ap.ToString() ?? string.Empty;
                    if (apStr.IndexOf("REGROOT", StringComparison.OrdinalIgnoreCase) >= 0)
                        regRootMatch = apStr;
                    if (apStr.IndexOf("VSNAME", StringComparison.OrdinalIgnoreCase) >= 0)
                        vsnameMatch = apStr;
                }
            }
            if (!string.IsNullOrEmpty(regRootMatch))
            {
                regRoot = SplitAfterValue(regRootMatch);
                vsname = SplitAfterValue(vsnameMatch);
            }
            else
            {
                resolution.Vsname = vsname;
                return Outcome.InstanceNotFound;
            }
        }

        resolution.RegRoot = regRoot ?? "";
        resolution.Vsname = vsname;
        resolution.InstanceName = instanceName;
        resolution.ServiceAccount = serviceAccount;
        return Outcome.Ok;
    }


    /// <summary>Native values read after changing one SQL service network flag.</summary>
    public sealed class NetworkFlagResult
    {
        public object ComputerName;
        public uint Value;
        public string Certificate;
    }

    /// <summary>Write and read back a network DWORD, optionally reading the configured certificate first.</summary>
    public static NetworkFlagResult SetNetworkFlag(string computerName, string regRoot,
        string flagName, uint flagValue, PSCredential credential, bool readCertificate)
    {
        ConnectionOptions options = new ConnectionOptions
        {
            Authentication = AuthenticationLevel.PacketPrivacy,
            Impersonation = ImpersonationLevel.Impersonate
        };
        if (credential != null && !Dataplat.Dbatools.Utility.Validation.IsLocalhost(computerName))
        {
            options.Username = credential.UserName;
            options.SecurePassword = credential.Password;
        }
        ManagementScope scope = new ManagementScope(String.Format(@"\\{0}\root\default", computerName), options);
        scope.Connect();
        using (ManagementClass registry = new ManagementClass(scope, new ManagementPath("StdRegProv"), null))
        {
            string key = regRoot + @"\MSSQLServer\SuperSocketNetLib";
            NetworkFlagResult result = new NetworkFlagResult();
            if (readCertificate)
            {
                using (ManagementBaseObject certificate = RegistryValue(registry, "GetStringValue", key, "Certificate", null))
                    result.Certificate = certificate["sValue"]?.ToString();
            }
            using (ManagementBaseObject changed = RegistryValue(registry, "SetDWORDValue", key, flagName, flagValue))
            {
                // RegistryValue checks the provider's return code before returning.
            }
            using (ManagementBaseObject readback = RegistryValue(registry, "GetDWORDValue", key, flagName, null))
                result.Value = Convert.ToUInt32(readback["uValue"], CultureInfo.InvariantCulture);
            using (ManagementBaseObject machine = RegistryValue(registry, "GetStringValue",
                @"SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName", "ComputerName", null))
                result.ComputerName = machine["sValue"];
            return result;
        }
    }

    /// <summary>The SuperSocketNetLib values Get-DbaForceNetworkEncryption reports, typed as Get-ItemProperty returns them.</summary>
    public sealed class NetworkValues
    {
        /// <summary>The target's active computer name, as $env:COMPUTERNAME reads it there.</summary>
        public object ComputerName;

        /// <summary>The raw Certificate value.</summary>
        public object Certificate;

        /// <summary>The raw ForceEncryption value.</summary>
        public object ForceEncryption;
    }

    /// <summary>
    /// Reads Certificate, then ForceEncryption, under HKLM\&lt;regRoot&gt;\MSSQLServer\SuperSocketNetLib, and the target's
    /// active computer name. A missing value throws, as Get-ItemProperty -Name does under -ErrorAction Stop.
    /// </summary>
    /// <param name="computerName">The computer to read.</param>
    /// <param name="regRoot">The instance registry root from the SQL service's REGROOT property.</param>
    /// <param name="credential">A Windows credential for a remote computer; ignored for the local computer.</param>
    /// <returns>The values read.</returns>
    public static NetworkValues ReadNetworkValues(string computerName, string regRoot, PSCredential credential)
    {
        using (ManagementClass registry = OpenRegistry(computerName, credential))
        {
            string key = regRoot + @"\MSSQLServer\SuperSocketNetLib";
            Dictionary<string, int> kinds = ValueKinds(registry, key);
            NetworkValues values = new NetworkValues();
            values.Certificate = TypedValue(registry, key, kinds, "Certificate");
            values.ForceEncryption = TypedValue(registry, key, kinds, "ForceEncryption");
            using (ManagementBaseObject machine = RegistryValue(registry, "GetStringValue",
                @"SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName", "ComputerName", null))
                values.ComputerName = machine["sValue"];
            return values;
        }
    }

    // WMI refuses explicit credentials for a local connection; the pinned local Invoke-Command ignores them too.
    private static ManagementClass OpenRegistry(string computerName, PSCredential credential)
    {
        ConnectionOptions options = new ConnectionOptions();
        options.Authentication = AuthenticationLevel.PacketPrivacy;
        options.Impersonation = ImpersonationLevel.Impersonate;
        if (credential != null && !Dataplat.Dbatools.Utility.Validation.IsLocalhost(computerName))
        {
            options.Username = credential.UserName;
            options.SecurePassword = credential.Password;
        }
        ManagementScope scope = new ManagementScope(String.Format(@"\\{0}\root\default", computerName), options);
        scope.Connect();
        return new ManagementClass(scope, new ManagementPath("StdRegProv"), null);
    }

    /// <summary>One SuperSocketNetLib value, typed as Get-ItemProperty returns it, and the target's active computer name.</summary>
    public sealed class NetworkValue
    {
        /// <summary>The target's active computer name, as $env:COMPUTERNAME reads it there.</summary>
        public object ComputerName;

        /// <summary>The raw value.</summary>
        public object Value;
    }

    /// <summary>
    /// Reads one named value under HKLM\&lt;regRoot&gt;\MSSQLServer\SuperSocketNetLib, then the target's active computer name.
    /// A missing value throws, as Get-ItemProperty -Name does under -ErrorAction Stop.
    /// </summary>
    /// <param name="computerName">The computer to read.</param>
    /// <param name="regRoot">The instance registry root from the SQL service's REGROOT property.</param>
    /// <param name="valueName">The value to read, such as HideInstance.</param>
    /// <param name="credential">A Windows credential for a remote computer; ignored for the local computer.</param>
    /// <returns>The value read.</returns>
    public static NetworkValue ReadNetworkValue(string computerName, string regRoot, string valueName, PSCredential credential)
    {
        using (ManagementClass registry = OpenRegistry(computerName, credential))
        {
            string key = regRoot + @"\MSSQLServer\SuperSocketNetLib";
            NetworkValue read = new NetworkValue();
            read.Value = TypedValue(registry, key, ValueKinds(registry, key), valueName);
            using (ManagementBaseObject machine = RegistryValue(registry, "GetStringValue",
                @"SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName", "ComputerName", null))
                read.ComputerName = machine["sValue"];
            return read;
        }
    }

    // The key's value names and registry kinds; a value name lookup is case-insensitive, as the registry is.
    // Access denied (ERROR_ACCESS_DENIED, 5) is the SecurityException the registry provider behind Get-ItemProperty reports.
    private static Dictionary<string, int> ValueKinds(ManagementClass registry, string key)
    {
        Dictionary<string, int> kinds = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        using (ManagementBaseObject input = registry.GetMethodParameters("EnumValues"))
        {
            input["hDefKey"] = 0x80000002u;
            input["sSubKeyName"] = key;
            using (ManagementBaseObject output = registry.InvokeMethod("EnumValues", input, null))
            {
                uint result = Convert.ToUInt32(output["ReturnValue"], CultureInfo.InvariantCulture);
                if (result == 5)
                    throw new System.Security.SecurityException("Requested registry access is not allowed.");
                if (result != 0)
                    throw new Win32Exception(unchecked((int)result));
                string[] names = output["sNames"] as string[];
                int[] types = output["Types"] as int[];
                for (int index = 0; names != null && types != null && index < names.Length && index < types.Length; index++)
                    kinds[names[index]] = types[index];
            }
        }
        return kinds;
    }

    // PS: (Get-ItemProperty -Path $regPath -Name <name>).<name>: REG_DWORD as Int32, REG_QWORD as Int64, REG_SZ and
    // REG_EXPAND_SZ (expanded) as String, REG_MULTI_SZ as String[], anything else as Byte[].
    private static object TypedValue(ManagementClass registry, string key, Dictionary<string, int> kinds, string name)
    {
        int kind;
        if (!kinds.TryGetValue(name, out kind))
            throw new PSArgumentException(String.Format(CultureInfo.InvariantCulture, @"Property {0} does not exist at path HKEY_LOCAL_MACHINE\{1}.", name, key));
        string method = "GetBinaryValue";
        string field = "uValue";
        if (kind == 1 || kind == 2 || kind == 7)
        {
            method = kind == 1 ? "GetStringValue" : kind == 2 ? "GetExpandedStringValue" : "GetMultiStringValue";
            field = "sValue";
        }
        else if (kind == 4 || kind == 11)
        {
            method = kind == 4 ? "GetDWORDValue" : "GetQWORDValue";
        }
        object raw;
        using (ManagementBaseObject output = RegistryValue(registry, method, key, name, null))
            raw = output[field];
        if (raw != null && kind == 4)
            return unchecked((int)Convert.ToUInt32(raw, CultureInfo.InvariantCulture));
        if (raw != null && kind == 11)
            return unchecked((long)Convert.ToUInt64(raw, CultureInfo.InvariantCulture));
        return raw;
    }

    private static ManagementBaseObject RegistryValue(ManagementClass registry, string method, string key, string name, uint? value)
    {
        using (ManagementBaseObject input = registry.GetMethodParameters(method))
        {
            input["hDefKey"] = 0x80000002u;
            input["sSubKeyName"] = key;
            input["sValueName"] = name;
            if (value.HasValue)
                input["uValue"] = value.Value;
            ManagementBaseObject output = registry.InvokeMethod(method, input, null);
            uint result = Convert.ToUInt32(output["ReturnValue"], CultureInfo.InvariantCulture);
            if (result != 0)
            {
                output.Dispose();
                throw new Win32Exception(unchecked((int)result));
            }
            return output;
        }
    }

    private static ManagedComputer BuildManagedComputer(string computerName, PSCredentialWrap credential)
    {
        if (credential.HasValue && !Dataplat.Dbatools.Utility.Validation.IsLocalhost(computerName))
        {
            System.Net.NetworkCredential netCred = credential.GetNetworkCredential();
            string user = string.IsNullOrEmpty(netCred.Domain) ? netCred.UserName : String.Format(@"{0}\{1}", netCred.Domain, netCred.UserName);
            return new ManagedComputer(computerName, user, netCred.Password);
        }
        return new ManagedComputer(computerName);
    }

    private static string SplitAfterValue(string value)
    {
        if (value == null)
        {
            return null;
        }
        // PS: ($x -Split 'Value\=')[1] - the -Split OPERATOR is case-insensitive (SMO emits
        // "Value=" with a capital V in practice, so this is non-physical, but match PS exactly).
        string[] parts = System.Text.RegularExpressions.Regex.Split(value, "Value=", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        return parts.Length > 1 ? parts[1] : null;
    }

    private static bool GetConfigTruthy(string name)
    {
        if (ConfigurationHost.Configurations.TryGetValue(name, out Config config) && config != null && config.Value != null)
        {
            try
            {
                return System.Management.Automation.LanguagePrimitives.IsTrue(config.Value);
            }
            catch
            {
                // malformed config falls back to false
            }
        }
        return false;
    }
}

/// <summary>Tiny wrapper so the resolver stays free of a direct PSCredential null-check idiom.</summary>
public readonly struct PSCredentialWrap
{
    private readonly System.Management.Automation.PSCredential _credential;
    public PSCredentialWrap(System.Management.Automation.PSCredential credential) { _credential = credential; }
    public bool HasValue => _credential != null;
    public System.Net.NetworkCredential GetNetworkCredential() => _credential.GetNetworkCredential();
}
}
