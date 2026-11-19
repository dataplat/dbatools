#nullable enable
#pragma warning disable CA1416 // Windows-only command: certreq, WindowsPrincipal

using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Security.Principal;
using System.Text;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Generates a certificate signing request (.inf config + .csr) for a computer using certreq.
/// Port of public/New-DbaComputerCertificateSigningRequest.ps1; surface pinned by
/// migration/baselines/New-DbaComputerCertificateSigningRequest.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaComputerCertificateSigningRequest", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
[OutputType(typeof(System.IO.FileInfo))]
public sealed class NewDbaComputerCertificateSigningRequestCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s); defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; } = DefaultComputerName();

    /// <summary>Alternate credential for connecting to the remote computer.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>The cluster (virtual) instance name to request the certificate for.</summary>
    [Parameter(Position = 2)]
    public string? ClusterInstanceName { get; set; }

    /// <summary>The directory to write the request files to.</summary>
    [Parameter(Position = 3)]
    public string? Path { get; set; }

    /// <summary>The certificate friendly name.</summary>
    [Parameter(Position = 4)]
    public string FriendlyName { get; set; } = "SQL Server";

    /// <summary>The RSA key length.</summary>
    [Parameter(Position = 5)]
    public int KeyLength { get; set; } = 1024;

    /// <summary>Subject alternative DNS names; defaults to the short name and FQDN.</summary>
    [Parameter(Position = 6)]
    public string[]? Dns { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private static readonly int[] EnglishCodes = { 9, 1033, 2057, 3081, 4105, 5129, 6153, 7177, 8201, 9225 };
    private string[]? _dnsEffective;

    protected override void BeginProcessing()
    {
        // PS: [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport')
        if (!TestBound(nameof(Path)))
        {
            Path = GetConfigString("path.dbatoolsexport") ?? "";
        }

        // PS: if ($englishCodes -notcontains (Get-DbaCmObject Win32_OperatingSystem).OSLanguage) {
        //     Stop-Function "... only supported in English OS locales ..."; return }
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
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch
        {
            // a locale probe failure is not the PS Stop-Function path; let the process block proceed
        }

        _dnsEffective = Dns;
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // PS: if (-not (Test-ElevationRequirement -ComputerName $env:COMPUTERNAME)) { return }
        if (!ElevationSatisfied())
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

            // PS: fqdn = ClusterInstanceName (dotted or +USERDNSDOMAIN) OR Resolve-DbaNetworkName.fqdn
            string fqdn;
            if (!string.IsNullOrEmpty(ClusterInstanceName))
            {
                fqdn = ClusterInstanceName!.Contains(".")
                    ? ClusterInstanceName!
                    : $"{ClusterInstanceName}.{Environment.GetEnvironmentVariable("USERDNSDOMAIN")}";
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

            string certDir = $"{Path}\\{fqdn}";
            string certCfg = $"{certDir}\\request.inf";
            string certCsr = $"{certDir}\\{fqdn}.csr";

            try
            {
                if (System.IO.Directory.Exists(certDir))
                {
                    foreach (string f in System.IO.Directory.GetFiles(certDir))
                    {
                        System.IO.File.Delete(f);
                    }
                }
                else
                {
                    System.IO.Directory.CreateDirectory(certDir);
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                WriteError(new ErrorRecord(ex, "dbatools_New-DbaComputerCertificateSigningRequest", ErrorCategory.WriteError, certDir));
                continue;
            }

            string shortName = fqdn.Split('.')[0];
            // PS: if (-not $dns) { $dns = $shortName, $fqdn } - accumulates across computers.
            if (_dnsEffective is null || _dnsEffective.Length == 0)
            {
                _dnsEffective = new[] { shortName, fqdn };
            }

            List<string> san = GetSanExt(_dnsEffective);

            // Write config file (verbatim line set; RequestType is always PKCS10 - the PS $SelfSigned
            // variable is never declared, so it is $null/false).
            StringBuilder cfg = new();
            cfg.Append("[Version]\r\n");
            cfg.Append("Signature=\"$Windows NT$\"\r\n");
            cfg.Append("[NewRequest]\r\n");
            cfg.Append($"Subject = \"CN={fqdn}\"\r\n");
            cfg.Append("KeySpec = 1\r\n");
            cfg.Append($"KeyLength = {KeyLength}\r\n");
            cfg.Append("Exportable = TRUE\r\n");
            cfg.Append("MachineKeySet = TRUE\r\n");
            cfg.Append($"FriendlyName=\"{FriendlyName}\"\r\n");
            cfg.Append("SMIME = False\r\n");
            cfg.Append("PrivateKeyArchive = FALSE\r\n");
            cfg.Append("UserProtected = FALSE\r\n");
            cfg.Append("UseExistingKeySet = FALSE\r\n");
            cfg.Append("ProviderName = \"Microsoft RSA SChannel Cryptographic Provider\"\r\n");
            cfg.Append("ProviderType = 12\r\n");
            cfg.Append("RequestType = PKCS10\r\n");
            cfg.Append("KeyUsage = 0xa0\r\n");
            cfg.Append("[EnhancedKeyUsageExtension]\r\n");
            cfg.Append("OID=1.3.6.1.5.5.7.3.1\r\n");
            cfg.Append("[Extensions]\r\n");
            foreach (string line in san)
            {
                cfg.Append(line).Append("\r\n");
            }
            cfg.Append("Critical=2.5.29.17\r\n");

            try
            {
                System.IO.File.WriteAllText(certCfg, cfg.ToString());
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                WriteError(new ErrorRecord(ex, "dbatools_New-DbaComputerCertificateSigningRequest", ErrorCategory.WriteError, certCfg));
                continue;
            }

            // PS: if ($PScmdlet.ShouldProcess("local", "Creating certificate for $computer")) {
            //     certreq -new $certCfg $certCsr }
            if (ShouldProcess("local", $"Creating certificate for {computer}"))
            {
                RunCertReq(certCfg, certCsr);
            }

            // PS: Get-ChildItem $certCfg, $certCsr - emits the FileInfo for each existing path.
            foreach (PSObject item in GetChildItems(certCfg, certCsr))
            {
                WriteObject(item);
            }
        }
    }

    // certreq -new <cfg> <csr>; output discarded ($null =). certreq is a local Windows exe.
    private void RunCertReq(string certCfg, string certCsr)
    {
        try
        {
            // net472 has no ProcessStartInfo.ArgumentList; build a quoted Arguments string.
            System.Diagnostics.ProcessStartInfo psi = new("certreq")
            {
                Arguments = $"-new \"{certCfg}\" \"{certCsr}\"",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            using System.Diagnostics.Process? proc = System.Diagnostics.Process.Start(psi);
            proc?.StandardOutput.ReadToEnd();
            proc?.StandardError.ReadToEnd();
            proc?.WaitForExit();
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            WriteError(new ErrorRecord(ex, "dbatools_New-DbaComputerCertificateSigningRequest", ErrorCategory.NotSpecified, certCsr));
        }
    }

    private IEnumerable<PSObject> GetChildItems(params string[] paths)
    {
        using PowerShell shell = PowerShell.Create(RunspaceMode.CurrentRunspace);
        shell.AddCommand("Get-ChildItem").AddParameter("Path", paths);
        Collection<PSObject> items;
        try { items = shell.Invoke(); }
        catch (RuntimeException) { yield break; }
        foreach (ErrorRecord error in shell.Streams.Error)
        {
            WriteError(NestedCommand.PreserveErrorIdentity(error));
        }
        foreach (PSObject item in items)
        {
            yield return item;
        }
    }

    // PS Get-SanExt + GetHexLength: build the ASN.1 subjectAltName extension (2.5.29.17) as base64,
    // wrapped in 64-char lines (first "2.5.29.17=", rest "_continue_=").
    private static List<string> GetSanExt(string[] hostNames)
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
    private static string GetHexLength(int strLen)
    {
        string hex = string.Format("{0:X2}", strLen);
        if (strLen > 127)
        {
            return string.Format("{0:X2}", 128 + (hex.Length / 2)) + hex;
        }
        return hex;
    }

    private object? QueryOsLanguage()
    {
        CimService.CmObjectRequest request = new()
        {
            ComputerName = new DbaInstanceParameter(Environment.MachineName).ComputerName,
            ClassName = "Win32_OperatingSystem"
        };
        CimService.CmObjectResult result = CimService.GetCmObject(this, request);
        foreach (PSObject instance in result.Instances)
        {
            return instance.Properties["OSLanguage"]?.Value;
        }
        return null;
    }

    // PS: Test-ElevationRequirement -ComputerName $env:COMPUTERNAME (localhost) - returns false
    // (and warns) when the console is not elevated.
    private bool ElevationSatisfied()
    {
        if (GetConfigTruthy("commands.test-elevationrequirement.disable"))
        {
            return true;
        }
        bool isElevated = new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
        if (!isElevated)
        {
            WriteMessage(MessageLevel.Warning, "Console not elevated, but elevation is required to perform some actions on localhost for this command.");
            return false;
        }
        return true;
    }

    private static string? GetConfigString(string key)
    {
        if (ConfigurationHost.Configurations.TryGetValue(key, out Config? config) && config != null && config.Value != null)
        {
            return config.Value.ToString();
        }
        return null;
    }

    private static bool GetConfigTruthy(string key)
    {
        if (ConfigurationHost.Configurations.TryGetValue(key, out Config? config) && config != null && config.Value != null)
        {
            try { return LanguagePrimitives.IsTrue(config.Value); }
            catch { return false; }
        }
        return false;
    }

    private static DbaInstanceParameter[]? DefaultComputerName()
    {
        string? machine = Environment.GetEnvironmentVariable("COMPUTERNAME");
        if (string.IsNullOrEmpty(machine))
        {
            return null;
        }
        return new[] { new DbaInstanceParameter(machine) };
    }
}
