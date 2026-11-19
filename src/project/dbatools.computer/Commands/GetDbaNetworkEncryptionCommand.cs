#nullable enable
using System;
using System.Management.Automation;
using System.Security.Cryptography.X509Certificates;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves the TLS/SSL certificate presented by a SQL Server instance over the network.
/// </summary>
/// <para>
/// Connects directly to a SQL Server instance's TCP port and retrieves the TLS/SSL certificate
/// that the server presents during the TLS handshake. This does not require Windows host access
/// or WinRM - it works purely over the network like a client connecting to SQL Server.
///
/// This complements Get-DbaNetworkCertificate, which reads the configured certificate from the
/// Windows registry (requires WinRM). This command instead shows what certificate is actually
/// being presented to clients over the network, without requiring any host-level access.
///
/// For named instances, the SQL Browser service is queried on UDP port 1434 to determine the
/// TCP port number. For default instances, port 1433 is used unless overridden.
/// </para>
/// <para>
/// Tags: Certificate, Encryption, Security, Network
/// Author: the dbatools team + Claude
///
/// Website: https://dbatools.io
/// Copyright: (c) 2024 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// <para>
/// https://dbatools.io/Get-DbaNetworkEncryption
/// </para>
/// <para>
/// PSCustomObject
///
/// Returns one object per SQL Server instance that successfully presents a TLS certificate.
///
/// Properties:
/// - ComputerName: The hostname of the SQL Server
/// - InstanceName: The SQL Server instance name (MSSQLSERVER for default)
/// - SqlInstance: The full SQL Server instance identifier
/// - Subject: The certificate subject (Common Name)
/// - Issuer: The certificate issuer
/// - Thumbprint: SHA-1 hash thumbprint of the certificate
/// - NotBefore: DateTime when the certificate becomes valid
/// - Expires: DateTime when the certificate expires
/// - DnsNameList: Array of DNS names from the Subject Alternative Names extension
/// - SerialNumber: Certificate serial number
/// - Certificate: The full X509Certificate2 object
/// </para>
/// <example>
/// PS C:\&gt; Get-DbaNetworkEncryption -SqlInstance sql2016
///
/// Retrieves the TLS certificate presented by the default SQL Server instance on sql2016.
/// </example>
/// <example>
/// PS C:\&gt; Get-DbaNetworkEncryption -SqlInstance sql2016\sqlexpress
///
/// Retrieves the TLS certificate presented by the named instance sqlexpress on sql2016.
/// Queries the SQL Browser service to determine the port.
/// </example>
/// <example>
/// PS C:\&gt; Get-DbaNetworkEncryption -SqlInstance sql2016, sql2017, sql2019 | Select-Object SqlInstance, Subject, Expires, Thumbprint
///
/// Retrieves certificates from multiple SQL Server instances and shows key certificate details.
/// </example>
/// <example>
/// PS C:\&gt; $servers | Get-DbaNetworkEncryption | Where-Object { $_.Expires -lt (Get-Date).AddDays(30) }
///
/// Finds SQL Server instances whose TLS certificates expire within the next 30 days.
/// </example>
[Cmdlet(VerbsCommon.Get, "DbaNetworkEncryption")]
[OutputType(typeof(PSObject))]
public sealed partial class GetDbaNetworkEncryptionCommand : DbaBaseCmdlet
{
    /// <summary>
    /// The target SQL Server instance or instances. Accepts pipeline input.
    /// </summary>
    [Parameter(ValueFromPipeline = true, Position = 0, Mandatory = true)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = Array.Empty<DbaInstanceParameter>();

    /// <summary>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </summary>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted) return;
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            try
            {
                string computer = instance.ComputerName;
                string name = instance.InstanceName;
                string tlsName = string.Equals(name, "MSSQLSERVER", StringComparison.OrdinalIgnoreCase) ? "" : name;
                string sqlName = tlsName.Length == 0 ? computer : computer + "\\" + name;
                WriteMessage(MessageLevel.Verbose, string.Format("Using computerName '{0}'", computer));
                WriteMessage(MessageLevel.Verbose, string.Format("Using instanceName '{0}'", name));
                WriteMessage(MessageLevel.Verbose, string.Format("Using tlsInstanceName '{0}'", tlsName));
                WriteMessage(MessageLevel.Verbose, string.Format("Using sqlInstanceName '{0}'", sqlName));
                if (instance.Port > 0) WriteMessage(MessageLevel.Verbose, "Using explicit port " + instance.Port + " for TLS connection");
                X509Certificate2 cert;
                try { cert = ReadCertificate(computer, tlsName, instance.Port); }
                catch (PipelineStoppedException) { throw; }
                catch (Exception failure)
                {
                    StopFunction("Failed to retrieve TLS certificate from " + instance, target: instance, exception: failure, continueLoop: true);
                    continue;
                }
                PSObject output = new();
                output.Properties.Add(new PSNoteProperty("ComputerName", computer));
                output.Properties.Add(new PSNoteProperty("InstanceName", name));
                output.Properties.Add(new PSNoteProperty("SqlInstance", sqlName));
                output.Properties.Add(new PSNoteProperty("Subject", cert.Subject));
                output.Properties.Add(new PSNoteProperty("Issuer", cert.Issuer));
                output.Properties.Add(new PSNoteProperty("Thumbprint", cert.Thumbprint));
                output.Properties.Add(new PSNoteProperty("NotBefore", cert.NotBefore));
                output.Properties.Add(new PSNoteProperty("Expires", cert.NotAfter));
                output.Properties.Add(new PSNoteProperty("DnsNameList", PSObject.AsPSObject(cert).Properties["DnsNameList"]?.Value));
                output.Properties.Add(new PSNoteProperty("SerialNumber", cert.SerialNumber));
                output.Properties.Add(new PSNoteProperty("Certificate", cert));
                WriteObject(output);
            }
            catch (PipelineStoppedException) { throw; }
            catch (Exception failure)
            {
                StopFunction("Failed to retrieve certificate from " + instance, target: instance, exception: failure, continueLoop: true);
            }
        }
    }
}
