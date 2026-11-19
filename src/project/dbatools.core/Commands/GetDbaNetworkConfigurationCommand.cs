#nullable enable
#pragma warning disable CA1416 // Windows-only command: WMI, registry, certificate store

using System;
using System.Collections.Generic;
using System.Management;
using System.Management.Automation;
using System.Security.Cryptography.X509Certificates;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Computer;
using Microsoft.SqlServer.Management.Smo.Wmi;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves SQL Server network protocols, TCP/IP settings, and SSL certificate configuration from SQL Server Configuration Manager
/// </summary>
/// <para>
/// Collects comprehensive network configuration details for SQL Server instances, providing the same information visible in SQL Server Configuration Manager but in a scriptable PowerShell format. This function is essential for network connectivity troubleshooting, security audits, and compliance reporting across multiple SQL Server environments.
///
/// The function retrieves protocol status for Shared Memory, Named Pipes, and TCP/IP, along with detailed TCP/IP properties including port configurations, IP address bindings, and dynamic port settings. It also extracts SSL certificate information, encryption settings, and advanced security properties like SPNs and extended protection settings.
///
/// Since the function accesses SQL WMI and Windows registry data, it uses PowerShell remoting to execute on the target machine, requiring appropriate permissions on both the local and remote systems.
///
/// For a detailed explanation of the different properties see the documentation at:
/// https://docs.microsoft.com/en-us/sql/tools/configuration-manager/sql-server-network-configuration
/// </para>
/// <para>
/// PSCustomObject
///
/// Default (-OutputType Full) returns a PSCustomObject with the following properties:
/// - ComputerName: Computer name of the SQL Server instance
/// - InstanceName: SQL Server instance name
/// - SqlInstance: Full SQL Server instance name (computer\instance format)
/// - SharedMemoryEnabled: Boolean indicating if Shared Memory protocol is enabled
/// - NamedPipesEnabled: Boolean indicating if Named Pipes protocol is enabled
/// - TcpIpEnabled: Boolean indicating if TCP/IP protocol is enabled
/// - TcpIpProperties: Nested object containing Enabled, KeepAlive, and ListenAll properties for TCP/IP configuration
/// - TcpIpAddresses: Array of objects representing IP address configurations with properties like Name, Active, Enabled, IpAddress, TcpDynamicPorts, and TcpPort
/// - Certificate: Nested object containing SSL certificate information (FriendlyName, DnsNameList, Thumbprint, Generated, Expires, IssuedTo, IssuedBy, Certificate object)
/// - SuitableCertificate: Array of certificates from the local machine store that are suitable for SQL Server encryption based on key usage, private key (a legacy CSP key with KeySpec AT_KEYEXCHANGE or a Key Storage Provider key), public key, signature algorithm, validity, and DNS names
/// - Advanced: Nested object containing advanced settings (ForceEncryption, HideInstance, AcceptedSPNs, ExtendedProtection)
///
/// When -OutputType ServerProtocols is specified:
/// - ComputerName: Computer name of the SQL Server instance
/// - InstanceName: SQL Server instance name
/// - SqlInstance: Full SQL Server instance name (computer\instance format)
/// - SharedMemoryEnabled: Boolean indicating if Shared Memory protocol is enabled
/// - NamedPipesEnabled: Boolean indicating if Named Pipes protocol is enabled
/// - TcpIpEnabled: Boolean indicating if TCP/IP protocol is enabled
///
/// When -OutputType TcpIpProperties is specified:
/// - ComputerName: Computer name of the SQL Server instance
/// - InstanceName: SQL Server instance name
/// - SqlInstance: Full SQL Server instance name (computer\instance format)
/// - Enabled: Value indicating if TCP/IP protocol is enabled
/// - KeepAlive: TCP KeepAlive timeout setting value
/// - ListenAll: Value indicating if instance listens on all IP addresses
///
/// When -OutputType TcpIpAddresses is specified:
/// If ListenAll is True, returns one object for IPAll:
/// - ComputerName: Computer name of the SQL Server instance
/// - InstanceName: SQL Server instance name
/// - SqlInstance: Full SQL Server instance name (computer\instance format)
/// - Name: IP configuration name (IPAll)
/// - TcpDynamicPorts: Dynamic port configuration (empty or port number)
/// - TcpPort: Static port number configuration
///
/// If ListenAll is False, returns one object per configured IP address:
/// - ComputerName: Computer name of the SQL Server instance
/// - InstanceName: SQL Server instance name
/// - SqlInstance: Full SQL Server instance name (computer\instance format)
/// - Name: IP configuration name (e.g., IP1, IP2, IPV6)
/// - Active: Value indicating if this IP configuration is active
/// - Enabled: Value indicating if this IP configuration is enabled
/// - IpAddress: The IP address (IPv4 or IPv6)
/// - TcpDynamicPorts: Dynamic port configuration (empty or port number)
/// - TcpPort: Static port number configuration
///
/// When -OutputType Certificate is specified:
/// - ComputerName: Computer name of the SQL Server instance
/// - InstanceName: SQL Server instance name
/// - SqlInstance: Full SQL Server instance name (computer\instance format)
/// - VSName: Virtual Server Name (if applicable; omitted if not present)
/// - ServiceAccount: Service account running SQL Server
/// - ForceEncryption: Boolean indicating if encryption is forced for all connections
/// - FriendlyName: Human-readable certificate name
/// - DnsNameList: Array of DNS names in the certificate's Subject Alternative Names
/// - Thumbprint: SHA-1 hash thumbprint of the certificate
/// - Generated: DateTime when the certificate becomes valid (NotBefore)
/// - Expires: DateTime when the certificate expires (NotAfter)
/// - IssuedTo: Certificate subject (who it was issued to)
/// - IssuedBy: Certificate issuer name
/// - Certificate: The full X509Certificate2 object with complete certificate information
/// </para>
/// <example>
/// PS C:\&gt; Get-DbaNetworkConfiguration -SqlInstance sqlserver2014a
///
/// Returns the network configuration for the default instance on sqlserver2014a.
/// </example>
/// <example>
/// PS C:\&gt; Get-DbaNetworkConfiguration -SqlInstance winserver\sqlexpress, sql2016 -OutputType ServerProtocols
///
/// Returns information about the server protocols for the sqlexpress on winserver and the default instance on sql2016.
/// </example>
[Cmdlet(VerbsCommon.Get, "DbaNetworkConfiguration")]
[OutputType(typeof(PSObject))]
public sealed partial class GetDbaNetworkConfigurationCommand : DbaBaseCmdlet
{
    /// <summary>
    /// The target SQL Server instance or instances.
    /// </summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>
    /// Credential object used to connect to the Computer as a different user.
    /// </summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>
    /// Controls which network configuration details are returned from SQL Server Configuration Manager.
    /// Use this to focus on specific troubleshooting areas or reduce output when checking multiple instances.
    /// Valid options: Full, ServerProtocols, TcpIpProperties, TcpIpAddresses, Certificate (defaults to Full).
    ///
    /// Full provides complete network configuration including all protocols, TCP/IP settings, IP bindings, and SSL certificate details.
    /// ServerProtocols shows only whether Shared Memory, Named Pipes, and TCP/IP protocols are enabled.
    /// TcpIpProperties returns TCP/IP protocol settings like KeepAlive timeout and whether the instance listens on all IP addresses.
    /// TcpIpAddresses displays port configurations and IP address bindings for connection troubleshooting.
    /// Certificate outputs SSL certificate information and encryption enforcement settings for security audits.
    /// </summary>
    [Parameter(Position = 2)]
    [PsStringCast]
    [ValidateSet("Full", "ServerProtocols", "TcpIpProperties", "TcpIpAddresses", "Certificate")]
    public string OutputType { get; set; } = "Full";

    /// <summary>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </summary>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            List<HostCertificateStore.Entry>? certificates = null;
            HashSet<X509Certificate2> retained = new();
            X509Certificate2? configuredCertificate = null;
            try
            {
                // mirrors Resolve-DbaComputerName (lab always resolves by short name)
                string computerName = instance.ComputerName;
                // Test-ElevationRequirement and Invoke-Command2 are replaced by direct API access below.

                // As we go remote, ensure the assembly is loaded (ManagedComputer handles this)
                ManagedComputer wmi = BuildManagedComputer(computerName);

                ServerProtocol? wmiSpSm = null, wmiSpNp = null, wmiSpTcp = null;
                foreach (ServerInstance si in wmi.ServerInstances)
                {
                    if (string.Equals(si.Name, instance.InstanceName, StringComparison.OrdinalIgnoreCase))
                    {
                        foreach (ServerProtocol sp in si.ServerProtocols)
                        {
                            if (sp.Name == "Sm") wmiSpSm = sp;
                            else if (sp.Name == "Np") wmiSpNp = sp;
                            else if (sp.Name == "Tcp") wmiSpTcp = sp;
                        }
                        break;
                    }
                }

                // Test if object is filled to test if instance was found on computer
                if (wmiSpSm is null)
                {
                    StopFunction(string.Format("Failed to collect network configuration from {0} for instance {1}. No data was found for this instance, so skipping.", instance.ComputerName, instance.InstanceName), target: instance, continueLoop: true);
                    continue;
                }

                PSObject tcpIpProperties = BuildTcpIpProperties(wmiSpTcp!);
                object[] tcpIpAddresses = BuildTcpIpAddresses(wmiSpTcp!);

                // Gather service account, regRoot, vsname from WMI service AdvancedProperties
                string? serviceAccount = null, regRoot = null, vsname = null;
                foreach (Service svc in wmi.Services)
                {
                    if (string.Equals(svc.DisplayName, string.Format("SQL Server ({0})", instance.InstanceName), StringComparison.OrdinalIgnoreCase))
                    {
                        serviceAccount = svc.ServiceAccount;
                        // AdvancedProperty is internal in the SQL WMI assembly — use dynamic
                        foreach (dynamic ap in svc.AdvancedProperties)
                        {
                            if (ap.Name == "REGROOT") regRoot = ap.Value?.ToString();
                            else if (ap.Name == "VSNAME") vsname = ap.Value?.ToString();
                        }
                        WriteMessage(MessageLevel.Verbose, string.Format("regRoot = '{0}' / vsname = '{1}'", regRoot, vsname));

                        if (string.IsNullOrEmpty(regRoot))
                        {
                            // Fallback: match AdvancedProperty.ToString() which includes Name and Value
                            foreach (dynamic ap in svc.AdvancedProperties)
                            {
                                string apStr = ap.ToString() ?? string.Empty;
                                if (apStr.IndexOf("REGROOT", StringComparison.Ordinal) >= 0)
                                {
                                    string[] parts = apStr.Split(new[] { "Value=" }, StringSplitOptions.None);
                                    if (parts.Length > 1) regRoot = parts[1];
                                }
                                else if (apStr.IndexOf("VSNAME", StringComparison.Ordinal) >= 0)
                                {
                                    string[] parts = apStr.Split(new[] { "Value=" }, StringSplitOptions.None);
                                    if (parts.Length > 1) vsname = parts[1];
                                }
                            }
                            WriteMessage(MessageLevel.Verbose, string.Format("regRoot = '{0}' / vsname = '{1}'", regRoot, vsname));
                            if (!string.IsNullOrEmpty(regRoot))
                                WriteMessage(MessageLevel.Verbose, string.Format("regRoot = '{0}' / vsname = '{1}'", regRoot, vsname));
                            else
                                WriteMessage(MessageLevel.Verbose, "Can't find regRoot");
                        }
                        break;
                    }
                }

                // Read registry data via StdRegProv WMI (avoids dependency on Remote Registry service)
                object outputCertificate;
                object outputAdvanced;
                PSObject[]? suitableCertificate = null;

                if (!string.IsNullOrEmpty(regRoot))
                {
                    string superSocketPath = string.Format(@"{0}\MSSQLServer\SuperSocketNetLib", regRoot);
                    try
                    {
                        using ManagementClass stdReg = GetStdRegProv(computerName);
                        string? acceptedSPNs = GetRegStringValue(stdReg, superSocketPath, "AcceptedSPNs");
                        string? thumbprint = GetRegStringValue(stdReg, superSocketPath, "Certificate");
                        bool? extendedProtection = ConvertDWordToBool(GetRegDWordValue(stdReg, superSocketPath, "ExtendedProtection"));
                        bool? forceEncryption = ConvertDWordToBool(GetRegDWordValue(stdReg, superSocketPath, "ForceEncryption"));
                        bool? hideInstance = ConvertDWordToBool(GetRegDWordValue(stdReg, superSocketPath, "HideInstance"));

                        certificates = ReadCertificates(computerName);
                        X509Certificate2? cert = null;
                        if (!string.IsNullOrEmpty(thumbprint))
                            foreach (HostCertificateStore.Entry entry in certificates)
                                if (string.Equals(entry.Certificate.Thumbprint, thumbprint, StringComparison.OrdinalIgnoreCase))
                                { cert = entry.Certificate; break; }
                        configuredCertificate = cert;

                        PSObject certObj = new();
                        certObj.Properties.Add(new PSNoteProperty("VSName", vsname));
                        certObj.Properties.Add(new PSNoteProperty("ServiceAccount", serviceAccount));
                        certObj.Properties.Add(new PSNoteProperty("ForceEncryption", forceEncryption));
                        certObj.Properties.Add(new PSNoteProperty("FriendlyName", cert?.FriendlyName));
                        certObj.Properties.Add(new PSNoteProperty("DnsNameList", cert is null ? null : GetDnsNamesArray(cert)));
                        certObj.Properties.Add(new PSNoteProperty("Thumbprint", cert?.Thumbprint));
                        certObj.Properties.Add(new PSNoteProperty("Generated", (object?)cert?.NotBefore));
                        certObj.Properties.Add(new PSNoteProperty("Expires", (object?)cert?.NotAfter));
                        certObj.Properties.Add(new PSNoteProperty("IssuedTo", cert?.Subject));
                        certObj.Properties.Add(new PSNoteProperty("IssuedBy", cert?.Issuer));
                        certObj.Properties.Add(new PSNoteProperty("Certificate", cert));
                        outputCertificate = certObj;

                        PSObject advObj = new();
                        advObj.Properties.Add(new PSNoteProperty("ForceEncryption", forceEncryption));
                        advObj.Properties.Add(new PSNoteProperty("HideInstance", hideInstance));
                        advObj.Properties.Add(new PSNoteProperty("AcceptedSPNs", acceptedSPNs));
                        advObj.Properties.Add(new PSNoteProperty("ExtendedProtection", extendedProtection));
                        outputAdvanced = advObj;


                    }
                    catch (Exception ex)
                    {
                        // PS: $outputCertificate = $outputAdvanced = "Failed to get information from registry: $_"
                        outputCertificate = outputAdvanced = string.Format("Failed to get information from registry: {0}", ex);
                    }
                }
                else
                {
                    outputCertificate = outputAdvanced = "Failed to get information from registry: Path not found";
                }

                certificates ??= ReadCertificates(computerName);
                suitableCertificate = GetSuitableCertificates(certificates, vsname);
                if (string.Equals(OutputType, "Full", StringComparison.OrdinalIgnoreCase))
                {
                    if (configuredCertificate is not null) retained.Add(configuredCertificate);
                    if (suitableCertificate is not null)
                        foreach (PSObject suitable in suitableCertificate)
                            retained.Add((X509Certificate2)suitable.BaseObject);
                }
                else if (string.Equals(OutputType, "Certificate", StringComparison.OrdinalIgnoreCase) && configuredCertificate is not null)
                    retained.Add(configuredCertificate);

                // Emit output based on OutputType
                EmitOutput(instance, wmiSpSm!, wmiSpNp!, wmiSpTcp!, tcpIpProperties, tcpIpAddresses,
                    outputCertificate, suitableCertificate, outputAdvanced, vsname, serviceAccount);
            }
            catch (Exception ex)
            {
                StopFunction(string.Format("Failed to collect network configuration from {0} for instance {1}.", instance.ComputerName, instance.InstanceName), target: instance, exception: ex, continueLoop: true);
                continue;
            }
            finally
            {
                if (certificates is not null)
                    foreach (HostCertificateStore.Entry entry in certificates)
                        if (!retained.Contains(entry.Certificate)) entry.Certificate.Dispose();
            }
        }
    }

    private void EmitOutput(
        DbaInstanceParameter instance,
        ServerProtocol wmiSpSm, ServerProtocol wmiSpNp, ServerProtocol wmiSpTcp,
        PSObject tcpIpProperties, object[] tcpIpAddresses,
        object outputCertificate, PSObject[]? suitableCertificate, object outputAdvanced,
        string? vsname, string? serviceAccount)
    {
        string sqlInstance = instance.SqlFullName.TrimStart('[').TrimEnd(']');

        // PS compares $OutputType with -eq (case-insensitive) and ValidateSet accepts any case,
        // so e.g. -OutputType certificate must work. Normalize to the canonical set value once.
        string outputType = OutputType;
        foreach (string canonical in new[] { "Full", "ServerProtocols", "TcpIpProperties", "TcpIpAddresses", "Certificate" })
        {
            if (string.Equals(OutputType, canonical, StringComparison.OrdinalIgnoreCase))
            {
                outputType = canonical;
                break;
            }
        }

        if (outputType == "Full")
        {
            PSObject result = new();
            result.Properties.Add(new PSNoteProperty("ComputerName", instance.ComputerName));
            result.Properties.Add(new PSNoteProperty("InstanceName", instance.InstanceName));
            result.Properties.Add(new PSNoteProperty("SqlInstance", sqlInstance));
            result.Properties.Add(new PSNoteProperty("SharedMemoryEnabled", wmiSpSm.IsEnabled));
            result.Properties.Add(new PSNoteProperty("NamedPipesEnabled", wmiSpNp.IsEnabled));
            result.Properties.Add(new PSNoteProperty("TcpIpEnabled", wmiSpTcp.IsEnabled));
            result.Properties.Add(new PSNoteProperty("TcpIpProperties", tcpIpProperties));
            result.Properties.Add(new PSNoteProperty("TcpIpAddresses", tcpIpAddresses));
            result.Properties.Add(new PSNoteProperty("Certificate", outputCertificate));
            result.Properties.Add(new PSNoteProperty("SuitableCertificate", suitableCertificate?.Length == 1 ? (object)suitableCertificate[0] : suitableCertificate));
            result.Properties.Add(new PSNoteProperty("Advanced", outputAdvanced));
            WriteObject(result);
        }
        else if (outputType == "ServerProtocols")
        {
            PSObject result = new();
            result.Properties.Add(new PSNoteProperty("ComputerName", instance.ComputerName));
            result.Properties.Add(new PSNoteProperty("InstanceName", instance.InstanceName));
            result.Properties.Add(new PSNoteProperty("SqlInstance", sqlInstance));
            result.Properties.Add(new PSNoteProperty("SharedMemoryEnabled", wmiSpSm.IsEnabled));
            result.Properties.Add(new PSNoteProperty("NamedPipesEnabled", wmiSpNp.IsEnabled));
            result.Properties.Add(new PSNoteProperty("TcpIpEnabled", wmiSpTcp.IsEnabled));
            WriteObject(result);
        }
        else if (outputType == "TcpIpProperties")
        {
            PSObject result = new();
            result.Properties.Add(new PSNoteProperty("ComputerName", instance.ComputerName));
            result.Properties.Add(new PSNoteProperty("InstanceName", instance.InstanceName));
            result.Properties.Add(new PSNoteProperty("SqlInstance", sqlInstance));
            result.Properties.Add(new PSNoteProperty("Enabled", tcpIpProperties.Properties["Enabled"]?.Value));
            result.Properties.Add(new PSNoteProperty("KeepAlive", tcpIpProperties.Properties["KeepAlive"]?.Value));
            result.Properties.Add(new PSNoteProperty("ListenAll", tcpIpProperties.Properties["ListenAll"]?.Value));
            WriteObject(result);
        }
        else if (outputType == "TcpIpAddresses")
        {
            bool listenAll = tcpIpProperties.Properties["ListenAll"]?.Value as bool? ?? false;
            if (listenAll)
            {
                // Return only IPAll
                foreach (object addr in tcpIpAddresses)
                {
                    PSObject ip = (PSObject)addr;
                    if (string.Equals(ip.Properties["Name"]?.Value?.ToString(), "IPAll", StringComparison.OrdinalIgnoreCase))
                    {
                        PSObject result = new();
                        result.Properties.Add(new PSNoteProperty("ComputerName", instance.ComputerName));
                        result.Properties.Add(new PSNoteProperty("InstanceName", instance.InstanceName));
                        result.Properties.Add(new PSNoteProperty("SqlInstance", sqlInstance));
                        result.Properties.Add(new PSNoteProperty("Name", ip.Properties["Name"]?.Value));
                        result.Properties.Add(new PSNoteProperty("TcpDynamicPorts", ip.Properties["TcpDynamicPorts"]?.Value));
                        result.Properties.Add(new PSNoteProperty("TcpPort", ip.Properties["TcpPort"]?.Value));
                        WriteObject(result);
                        break;
                    }
                }
            }
            else
            {
                foreach (object addr in tcpIpAddresses)
                {
                    PSObject ip = (PSObject)addr;
                    if (string.Equals(ip.Properties["Name"]?.Value?.ToString(), "IPAll", StringComparison.OrdinalIgnoreCase))
                        continue;
                    PSObject result = new();
                    result.Properties.Add(new PSNoteProperty("ComputerName", instance.ComputerName));
                    result.Properties.Add(new PSNoteProperty("InstanceName", instance.InstanceName));
                    result.Properties.Add(new PSNoteProperty("SqlInstance", sqlInstance));
                    result.Properties.Add(new PSNoteProperty("Name", ip.Properties["Name"]?.Value));
                    result.Properties.Add(new PSNoteProperty("Active", ip.Properties["Active"]?.Value));
                    result.Properties.Add(new PSNoteProperty("Enabled", ip.Properties["Enabled"]?.Value));
                    result.Properties.Add(new PSNoteProperty("IpAddress", ip.Properties["IpAddress"]?.Value));
                    result.Properties.Add(new PSNoteProperty("TcpDynamicPorts", ip.Properties["TcpDynamicPorts"]?.Value));
                    result.Properties.Add(new PSNoteProperty("TcpPort", ip.Properties["TcpPort"]?.Value));
                    WriteObject(result);
                }
            }
        }
        else if (outputType == "Certificate")
        {
            // PS: if ($netConf.Certificate -like 'Failed*')
            if (outputCertificate is string certStr && certStr.StartsWith("Failed", StringComparison.Ordinal))
            {
                StopFunction(string.Format("Failed to collect certificate information from {0} for instance {1}: {2}", instance.ComputerName, instance.InstanceName, certStr), target: instance, continueLoop: true);
                return;
            }
            PSObject? certData = outputCertificate as PSObject;
            PSObject result = new();
            result.Properties.Add(new PSNoteProperty("ComputerName", instance.ComputerName));
            result.Properties.Add(new PSNoteProperty("InstanceName", instance.InstanceName));
            result.Properties.Add(new PSNoteProperty("SqlInstance", sqlInstance));
            result.Properties.Add(new PSNoteProperty("VSName", certData?.Properties["VSName"]?.Value));
            result.Properties.Add(new PSNoteProperty("ServiceAccount", certData?.Properties["ServiceAccount"]?.Value));
            result.Properties.Add(new PSNoteProperty("ForceEncryption", certData?.Properties["ForceEncryption"]?.Value));
            result.Properties.Add(new PSNoteProperty("FriendlyName", certData?.Properties["FriendlyName"]?.Value));
            result.Properties.Add(new PSNoteProperty("DnsNameList", certData?.Properties["DnsNameList"]?.Value));
            result.Properties.Add(new PSNoteProperty("Thumbprint", certData?.Properties["Thumbprint"]?.Value));
            result.Properties.Add(new PSNoteProperty("Generated", certData?.Properties["Generated"]?.Value));
            result.Properties.Add(new PSNoteProperty("Expires", certData?.Properties["Expires"]?.Value));
            result.Properties.Add(new PSNoteProperty("IssuedTo", certData?.Properties["IssuedTo"]?.Value));
            result.Properties.Add(new PSNoteProperty("IssuedBy", certData?.Properties["IssuedBy"]?.Value));
            result.Properties.Add(new PSNoteProperty("Certificate", certData?.Properties["Certificate"]?.Value));

            // PS: Select-DefaultView -Property $defaultView (excludes VSName if empty)
            List<string> defaultView = new() { "ComputerName", "InstanceName", "SqlInstance", "VSName", "ServiceAccount", "ForceEncryption", "FriendlyName", "DnsNameList", "Thumbprint", "Generated", "Expires", "IssuedTo", "IssuedBy" };
            object? vsnameVal = certData?.Properties["VSName"]?.Value;
            if (vsnameVal is null || string.IsNullOrEmpty(vsnameVal.ToString()))
            {
                // PS: $defaultView | Where-Object { $_ -ne 'VSNAME' }  (-ne is case-insensitive)
                defaultView.RemoveAll(s => string.Equals(s, "VSName", StringComparison.OrdinalIgnoreCase));
            }
            Dataplat.Dbatools.Utility.OutputHelper.SetDefaultDisplayPropertySet(result, defaultView.ToArray());
            WriteObject(result);
        }
    }
}
