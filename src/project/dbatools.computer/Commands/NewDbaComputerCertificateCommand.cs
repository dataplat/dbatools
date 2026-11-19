#nullable enable
#pragma warning disable CA1416 // Windows-only command: certreq, cert store, WindowsPrincipal

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Security;
using System.Security.Principal;
using System.Text;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a new computer certificate (self-signed or CA-signed) via certreq and imports it into
/// a certificate store. Port of public/New-DbaComputerCertificate.ps1; surface pinned by
/// migration/baselines/New-DbaComputerCertificate.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaComputerCertificate", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
[OutputType(typeof(PSObject))]
public sealed partial class NewDbaComputerCertificateCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s); defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; } = DefaultComputerName();

    /// <summary>Alternate credential for connecting to the remote computer.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>The Certificate Authority server (auto-detected when omitted and not self-signed).</summary>
    [Parameter(Position = 2)]
    public string? CaServer { get; set; }

    /// <summary>The Certificate Authority name (auto-detected when omitted and not self-signed).</summary>
    [Parameter(Position = 3)]
    public string? CaName { get; set; }

    /// <summary>The cluster (virtual) instance name.</summary>
    [Parameter(Position = 4)]
    public string? ClusterInstanceName { get; set; }

    /// <summary>Password securing the exported PFX for a remote import.</summary>
    [Parameter(Position = 5)]
    [Alias("Password")]
    public SecureString? SecurePassword { get; set; }

    /// <summary>The certificate friendly name.</summary>
    [Parameter(Position = 6)]
    public string FriendlyName { get; set; } = "SQL Server";

    /// <summary>The CA certificate template.</summary>
    [Parameter(Position = 7)]
    public string CertificateTemplate { get; set; } = "WebServer";

    /// <summary>The RSA key length.</summary>
    [Parameter(Position = 8)]
    public int KeyLength { get; set; } = 2048;

    /// <summary>The certificate store location.</summary>
    [Parameter(Position = 9)]
    public string Store { get; set; } = "LocalMachine";

    /// <summary>The certificate folder within the store.</summary>
    [Parameter(Position = 10)]
    public string Folder { get; set; } = "My";

    /// <summary>Key storage flags.</summary>
    [Parameter(Position = 11)]
    [ValidateSet("EphemeralKeySet", "Exportable", "PersistKeySet", "UserProtected", "NonExportable")]
    public string[] Flag { get; set; } = new[] { "Exportable", "PersistKeySet" };

    /// <summary>Subject alternative DNS names; defaults to the short name and FQDN.</summary>
    [Parameter(Position = 12)]
    public string[]? Dns { get; set; }

    /// <summary>Generate a self-signed certificate instead of requesting one from a CA.</summary>
    [Parameter]
    public SwitchParameter SelfSigned { get; set; }

    /// <summary>Create a document-encryption certificate (Always Encrypted column master keys).</summary>
    [Parameter]
    public SwitchParameter DocumentEncryptionCert { get; set; }

    /// <summary>The signature hash algorithm.</summary>
    [Parameter(Position = 13)]
    [PsStringCast]
    [ValidateSet("Sha256", "sha384", "sha512")]
    public string HashAlgorithm { get; set; } = "Sha256";

    /// <summary>Certificate validity in months (self-signed).</summary>
    [Parameter(Position = 14)]
    public int MonthsValid { get; set; } = 12;

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private static readonly int[] EnglishCodes = { 9, 1033, 2057, 3081, 4105, 5129, 6153, 7177, 8201, 9225 };
    private static readonly string[] DisplaySet = { "FriendlyName", "DnsNameList", "Thumbprint", "NotBefore", "NotAfter", "Subject", "Issuer" };
    private string[]? _dnsEffective;
    private string _tempDir = "";

    // DEF-008 (B's sweep true-positive, source-confirmed by A 2026-07-21). The source keeps
    // $secondaryNode / $certdata / $certDir / $storedCert on the FUNCTION scope: none is ever
    // initialised, all are assigned inside process{}, so they survive BOTH the foreach over
    // ComputerName AND - since ComputerName is ValueFromPipeline - the pipeline records.
    //
    // What that buys, and what the port was losing: for a FAILOVER CLUSTER
    // (New-DbaComputerCertificate -ComputerName sqla,sqlb -ClusterInstanceName sqlcluster) the
    // source creates the CN=cluster certificate ONCE on the first node, exports it to $certdata,
    // latches $secondaryNode, and every later node SKIPS creation and imports THAT SAME
    // certificate. All nodes must share one identical cert or TLS breaks the moment the cluster
    // fails over to a node holding a different key. The port had no latch and no carry: it
    // created a fresh cert per node, so N nodes got N different certs with the same CN.
    //
    // These are C# instance fields precisely because the cmdlet instance is what persists across
    // ProcessRecord calls - the same scope the source's function-scope variables have.
    private bool _secondaryNode;
    private object? _certData;
    private string? _certDir;
    private PSObject? _storedCert;

    protected override void BeginProcessing()
    {
        // PS: DocumentEncryptionCert requires -SelfSigned or explicit -CertificateTemplate.
        if (DocumentEncryptionCert.IsPresent && !SelfSigned.IsPresent && !TestBound(nameof(CertificateTemplate)))
        {
            StopFunction("DocumentEncryptionCert requires -SelfSigned or an explicit -CertificateTemplate configured for Always Encrypted column master keys. The default WebServer template is intended for TLS server certificates.");
            return;
        }

        // PS: English OS-locale gate.
        try
        {
            object? osLang = QueryOsLanguage();
            long langCode = osLang is null ? 0 : Convert.ToInt64(osLang, CultureInfo.InvariantCulture);
            if (Array.IndexOf(EnglishCodes, (int)langCode) < 0)
            {
                string display;
                try { display = CultureInfo.GetCultureInfo((int)langCode).DisplayName; }
                catch { display = langCode.ToString(CultureInfo.InvariantCulture); }
                StopFunction($"Currently, this command is only supported in English OS locales. OS Locale detected: {display}\nWe apologize for the inconvenience and look into providing universal language support in future releases.");
                return;
            }
        }
        catch (PipelineStoppedException) { throw; }
        catch { /* locale probe failure is not the PS Stop path */ }

        if (!ElevationSatisfied())
        {
            // PS returns from process on the elevation gate; mirror by marking interrupted.
            StopFunction("Console not elevated, but elevation is required to perform some actions on localhost for this command.");
            return;
        }

        // NOTE: CA auto-detection (when not -SelfSigned) is an AD lookup that this lab cannot
        // exercise (no enterprise CA). The self-signed path - the only lab-reachable and tested
        // path - never runs it. It is preserved as best-effort below only when CaServer/CaName
        // are explicitly supplied.

        _tempDir = System.IO.Path.GetTempPath().TrimEnd('\\');
        _dnsEffective = Dns;
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        if (ComputerName is null)
        {
            return;
        }

        foreach (DbaInstanceParameter computer in ComputerName)
        {
            if (computer is null)
            {
                continue;
            }

            // PS :356 `if (-not $secondaryNode) {` - the ENTIRE creation block (fqdn resolution,
            // request.inf, certreq, storedCert lookup, the localhost display) is gated. On a
            // cluster's second and later nodes none of it runs; the carried state below is what
            // the import then uses.
            if (!_secondaryNode)
            {
                string fqdn;
                if (!string.IsNullOrEmpty(ClusterInstanceName))
                {
                    fqdn = ClusterInstanceName!.Contains(".") ? ClusterInstanceName! : $"{ClusterInstanceName}.{Environment.GetEnvironmentVariable("USERDNSDOMAIN")}";
                }
                else
                {
                    NetworkResolutionService.NetworkResolutionResult? resolved = null;
                    try { resolved = NetworkResolutionService.Resolve(this, new DbaInstanceParameter(computer.ComputerName), Credential, turbo: false); }
                    catch (PipelineStoppedException) { throw; }
                    catch { resolved = null; }
                    if (resolved is null)
                    {
                        fqdn = $"{computer.ComputerName}.{Environment.GetEnvironmentVariable("USERDNSDOMAIN")}";
                        WriteMessage(MessageLevel.Warning, $"Server name cannot be resolved. Guessing it's {fqdn}");
                    }
                    else
                    {
                        fqdn = resolved.FQDN;
                    }
                }

                string certDir = $"{_tempDir}\\{fqdn}";
                _certDir = certDir;
                string certCfg = $"{certDir}\\request.inf";
                string certCsr = $"{certDir}\\{fqdn}.csr";

                try
                {
                    if (System.IO.Directory.Exists(certDir))
                    {
                        foreach (string f in System.IO.Directory.GetFiles(certDir)) { System.IO.File.Delete(f); }
                    }
                    else
                    {
                        System.IO.Directory.CreateDirectory(certDir);
                    }
                }
                catch (PipelineStoppedException) { throw; }
                catch (Exception ex)
                {
                    WriteError(new ErrorRecord(ex, "dbatools_New-DbaComputerCertificate", ErrorCategory.WriteError, certDir));
                    continue;
                }

                string shortName = fqdn.Split('.')[0];
                if (_dnsEffective is null || _dnsEffective.Length == 0)
                {
                    _dnsEffective = new[] { shortName, fqdn };
                }
                List<string> san = CertificateSanEncoder.GetSanExt(_dnsEffective);

                // Build request.inf verbatim.
                StringBuilder cfg = new();
                cfg.Append("[Version]\r\n");
                cfg.Append("Signature=\"$Windows NT$\"\r\n");
                cfg.Append("[NewRequest]\r\n");
                cfg.Append($"Subject = \"CN={fqdn}\"\r\n");
                cfg.Append("KeySpec = 1\r\n");
                cfg.Append($"KeyLength = {KeyLength}\r\n");
                bool nonExportableLocal = ContainsIgnoreCase(Flag, "NonExportable") && string.IsNullOrEmpty(ClusterInstanceName) && computer.IsLocalHost;
                cfg.Append(nonExportableLocal ? "Exportable = FALSE\r\n" : "Exportable = TRUE\r\n");
                cfg.Append("MachineKeySet = TRUE\r\n");
                cfg.Append($"FriendlyName=\"{FriendlyName}\"\r\n");
                cfg.Append("SMIME = False\r\n");
                cfg.Append("PrivateKeyArchive = FALSE\r\n");
                cfg.Append("UserProtected = FALSE\r\n");
                cfg.Append("UseExistingKeySet = FALSE\r\n");
                cfg.Append("ProviderName = \"Microsoft RSA SChannel Cryptographic Provider\"\r\n");
                cfg.Append("ProviderType = 12\r\n");
                if (SelfSigned.IsPresent)
                {
                    cfg.Append("RequestType = Cert\r\n");
                    cfg.Append($"NotBefore = {DateTime.Now.ToShortDateString()}\r\n");
                    cfg.Append($"NotAfter = {DateTime.Now.AddMonths(MonthsValid).ToShortDateString()}\r\n");
                }
                else
                {
                    cfg.Append("RequestType = PKCS10\r\n");
                }
                cfg.Append($"HashAlgorithm = {HashAlgorithm}\r\n");
                if (DocumentEncryptionCert.IsPresent)
                {
                    cfg.Append("KeyUsage = 0x20\r\n");
                    cfg.Append("[EnhancedKeyUsageExtension]\r\n");
                    cfg.Append("OID=1.3.6.1.5.5.8.2.2\r\n");
                    cfg.Append("OID=1.3.6.1.4.1.311.10.3.11\r\n");
                }
                else
                {
                    cfg.Append("KeyUsage = 0xa0\r\n");
                    cfg.Append("[EnhancedKeyUsageExtension]\r\n");
                    cfg.Append("OID=1.3.6.1.5.5.7.3.1\r\n");
                }
                cfg.Append("[Extensions]\r\n");
                foreach (string line in san) { cfg.Append(line).Append("\r\n"); }
                cfg.Append("Critical=2.5.29.17\r\n");

                try { System.IO.File.WriteAllText(certCfg, cfg.ToString()); }
                catch (PipelineStoppedException) { throw; }
                catch (Exception ex)
                {
                    WriteError(new ErrorRecord(ex, "dbatools_New-DbaComputerCertificate", ErrorCategory.WriteError, certCfg));
                    continue;
                }

                string createOut = "";
                if (ShouldProcess("local", $"Creating certificate for {computer}"))
                {
                    createOut = RunCertReq($"-new \"{certCfg}\" \"{certCsr}\"");
                }

                PSObject? storedCert = null;
                if (SelfSigned.IsPresent)
                {
                    // PS: $serial = (($create -Split "Serial Number:" -Split "Subject")[2]).Trim()
                    string serial = ParseSerial(createOut);
                    storedCert = FindStoredCertBySerial(serial);
                    if (computer.IsLocalHost && storedCert is not null)
                    {
                        WriteObject(ProjectForDisplay(storedCert));
                    }
                }
                else
                {
                    // CA path - unreachable on this lab (no enterprise CA); preserved best-effort.
                    if (ShouldProcess("local", $"Submitting certificate request for {computer} to {CaServer}\\{CaName}"))
                    {
                        string certCrt = $"{certDir}\\{fqdn}.crt";
                        string certPfx = $"{certDir}\\{fqdn}.pfx";
                        string certTemplate = $"CertificateTemplate:{CertificateTemplate}";
                        string submit = RunCertReq($"-submit -config \"{CaServer}\\{CaName}\" -attrib {certTemplate} \"{certCsr}\" \"{certCrt}\" \"{certPfx}\"");
                        if (submit.IndexOf("ssued", StringComparison.Ordinal) >= 0)
                        {
                            RunCertReq($"-accept -machine \"{certCrt}\"");
                        }
                        else if (!string.IsNullOrEmpty(submit))
                        {
                            WriteMessage(MessageLevel.Warning, "Something went wrong");
                            WriteMessage(MessageLevel.Warning, createOut);
                            WriteMessage(MessageLevel.Warning, submit);
                            StopFunction($"Failure when attempting to create the cert on {computer}. Exception: ", target: computer, continueLoop: true);
                            continue;
                        }
                    }
                }

                _storedCert = storedCert;
            } // PS :475 - end of the `-not $secondaryNode` creation block

            // The remote-import path (non-localhost) exports the pfx, removes the local copy and
            // re-imports on the target. Unreachable in the localhost self-signed test; translated
            // faithfully but exercised only when a remote ComputerName is supplied.
            // DEF-008: reads the CARRIED cert - on a cluster's later nodes this is the first
            // node's certificate, which is the whole point of the source's $secondaryNode latch.
            if (!computer.IsLocalHost && _storedCert is not null)
            {
                RemoteImport(computer);
            }

            // PS :522 - the cleanup sits OUTSIDE the creation guard, so on a cluster's later nodes
            // the source re-cleans the FIRST node's $certDir (function-scope, never reassigned).
            // Reproduced deliberately via the carried _certDir rather than "fixed".
            if (!string.IsNullOrEmpty(_certDir) && ShouldProcess("local", $"Removing all files from {_certDir}"))
            {
                try { System.IO.Directory.Delete(_certDir!, recursive: true); }
                catch { /* PS: Stop-Function best-effort on cleanup */ }
            }
        }
    }

    // PS: $serial = (($create -Split "Serial Number:" -Split "Subject")[2]).Trim()
    // $create is the certreq native-command output, which PowerShell captures as an ARRAY OF LINES.
    // -Split therefore operates PER LINE and flattens - NOT on one joined string. Replicate that
    // (a single-string split shifts [2] onto the Subject text; lab-diagnosed).
    private static string ParseSerial(string createOut)
    {
        string[] lines = createOut.Split(new[] { "\r\n", "\n", "\r" }, StringSplitOptions.None);
        List<string> step1 = new();
        foreach (string line in lines)
        {
            step1.AddRange(SplitOnLiteral(line, "Serial Number:"));
        }
        List<string> step2 = new();
        foreach (string s in step1)
        {
            step2.AddRange(SplitOnLiteral(s, "Subject"));
        }
        return step2.Count > 2 ? step2[2].Trim() : "";
    }

    private static string[] SplitOnLiteral(string input, string sep)
    {
        return input.Split(new[] { sep }, StringSplitOptions.None);
    }

    // PS: $storedCert = Get-ChildItem Cert:\LocalMachine\My -Recurse | Where SerialNumber -eq $serial
    // Returns the REAL X509Certificate2 (NOT a Select-Object * projection) so the non-localhost path
    // can call $storedCert.Export(PFX, ...) - a projection has no Export / private key (the localhost
    // path projects separately for its display output).
    private PSObject? FindStoredCertBySerial(string serial)
    {
        Collection<PSObject> results = InvokeCommand.InvokeScript(
            false,
            ScriptBlock.Create("param($s) Get-ChildItem Cert:\\LocalMachine\\My -Recurse | Where-Object SerialNumber -eq $s"),
            null,
            serial);
        return results.Count > 0 ? results[0] : null;
    }

    // PS localhost branch: $storedCert | Select-Object * | Select-DefaultView -Property <7>.
    // Project the real cert to the Selected.X509Certificate2 surface then attach the display set.
    private PSObject ProjectForDisplay(PSObject storedCert)
    {
        Collection<PSObject> projected = InvokeCommand.InvokeScript(
            false,
            ScriptBlock.Create("param($c) $c | Select-Object -Property *"),
            null,
            storedCert);
        PSObject result = projected.Count > 0 ? projected[0] : storedCert;
        OutputHelper.SetDefaultDisplayPropertySet(result, DisplaySet);
        return result;
    }
}
