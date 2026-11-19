#nullable enable
#pragma warning disable CA1416 // Windows-only command: certreq, cert store, WindowsPrincipal

using System;
using System.Collections;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Management.Automation;
using System.Security.Principal;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>The remote-import path and native helpers for New-DbaComputerCertificate - split
/// from the main class file per the repository 400-line limit (codex r2), which the DEF-008
/// cluster create-once fix pushed it past.</summary>
public sealed partial class NewDbaComputerCertificateCommand
{
    private void RemoteImport(DbaInstanceParameter computer)
    {
        // PS :479-489. Each step carries the SAME ShouldProcess gate the source uses, and they are
        // SEPARATE gates - collapsing them (codex r2 HIGH) meant -WhatIf still exported the pfx and
        // deleted the local certificate before declining the import. Note the latch itself is NOT
        // gated in the source: under -WhatIf a cluster run still latches, so later nodes still skip
        // creation. Reproduced exactly, including that asymmetry.
        if (!_secondaryNode)
        {
            if (ShouldProcess("local", "Generating pfx and reading from disk"))
            {
                NestedCommand.RequireDbatoolsScriptModule(this);
                _certData = InvokeCertScript(
                    @"param($p)
                $m = Get-Module dbatools | Where-Object ModuleType -eq 'Script' | Select-Object -First 1
                & $m {
                    param($p)
                    @{ Data = $p.Cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::PFX, $p.Password) }
                } $p 3>&1",
                    new Hashtable { { "Cert", _storedCert }, { "Password", SecurePassword } });
            }

            if (ShouldProcess("local", "Removing cert from disk but keeping it in memory"))
            {
                NestedCommand.RequireDbatoolsScriptModule(this);
                InvokeCertScript(
                    @"param($p)
                $m = Get-Module dbatools | Where-Object ModuleType -eq 'Script' | Select-Object -First 1
                & $m {
                    param($p)
                    $p.Cert | Remove-Item -ErrorAction SilentlyContinue
                } $p 3>&1",
                    new Hashtable { { "Cert", _storedCert } });
            }

            // PS :489 - cluster only, so the non-cluster path keeps creating a cert per node.
            if (!string.IsNullOrEmpty(ClusterInstanceName))
            {
                _secondaryNode = true;
            }
        }

        // PS :510 - the import gate, with the UserProtected rejection INSIDE it (:511).
        if (!ShouldProcess(computer.ComputerName, "Attempting to import new cert"))
        {
            return;
        }

        if (ContainsIgnoreCase(Flag, "UserProtected"))
        {
            StopFunction($"UserProtected flag is only valid for localhost because it causes a prompt, skipping for {computer}", continueLoop: true);
            return;
        }

        // Delegated to the engine to keep the import and Get-DbaComputerCertificate surface
        // faithful; unreachable in the localhost test path. $p.Data is the CARRIED pfx - on a
        // cluster's later nodes it is the first node's certificate.
        Hashtable splat = new()
        {
            { "Computer", computer.ComputerName },
            { "Data", _certData },
            { "Password", SecurePassword },
            { "Store", Store },
            { "Folder", Folder },
            { "Flags", string.Join(",", Flag) }
        };
        NestedCommand.RequireDbatoolsScriptModule(this);
        Collection<PSObject> imported = InvokeCommand.InvokeScript(
            false,
            ScriptBlock.Create(@"param($p)
                $m = Get-Module dbatools | Where-Object ModuleType -eq 'Script' | Select-Object -First 1
                & $m {
                    param($p)
                    $sb = {
                        param($CertificateData, [SecureString]$SecurePassword, $Store, $Folder, $flags)
                        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertificateData, $SecurePassword, $flags)
                        $certstore = New-Object System.Security.Cryptography.X509Certificates.X509Store($Folder, $Store)
                        $certstore.Open('ReadWrite'); $certstore.Add($cert); $certstore.Close()
                        Get-ChildItem ""Cert:\$($Store)\$($Folder)"" -Recurse | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
                    }
                    $tp = (Invoke-Command2 -ComputerName $p.Computer -ArgumentList $p.Data, $p.Password, $p.Store, $p.Folder, $p.Flags -ScriptBlock $sb -ErrorAction Stop).Thumbprint
                    Get-DbaComputerCertificate -ComputerName $p.Computer -Thumbprint $tp
                } $p 3>&1"),
            null,
            splat);
        foreach (PSObject item in imported)
        {
            if (item?.BaseObject is WarningRecord w) { WriteWarning(w.Message); }
            else if (item is not null) { WriteObject(item); }
        }
    }

    // Runs one of the small cert scriptblocks and returns the Data entry of a returned Hashtable,
    // or null. The Hashtable wrapper is load-bearing: InvokeScript ENUMERATES a returned byte[]
    // (measured - a 5-byte pfx arrives as 5 Byte PSObjects), and a comma wrap does not stop it, so
    // an unwrapped return would hand the import a single byte instead of the certificate.
    private object? InvokeCertScript(string script, Hashtable args)
    {
        object? payload = null;
        Collection<PSObject> results = InvokeCommand.InvokeScript(false, ScriptBlock.Create(script), null, args);
        foreach (PSObject item in results)
        {
            if (item?.BaseObject is WarningRecord w) { WriteWarning(w.Message); }
            else if (item?.BaseObject is Hashtable bag && bag.ContainsKey("Data")) { payload = bag["Data"]; }
        }
        return payload;
    }

    private string RunCertReq(string arguments)
    {
        try
        {
            System.Diagnostics.ProcessStartInfo psi = new("certreq")
            {
                Arguments = arguments,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            using System.Diagnostics.Process? proc = System.Diagnostics.Process.Start(psi);
            string stdout = proc?.StandardOutput.ReadToEnd() ?? "";
            proc?.StandardError.ReadToEnd();
            proc?.WaitForExit();
            return stdout;
        }
        catch (PipelineStoppedException) { throw; }
        catch (Exception ex)
        {
            WriteError(new ErrorRecord(ex, "dbatools_New-DbaComputerCertificate", ErrorCategory.NotSpecified, null));
            return "";
        }
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

    private bool ElevationSatisfied()
    {
        if (GetConfigTruthy("commands.test-elevationrequirement.disable"))
        {
            return true;
        }
        return new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
    }

    private static bool ContainsIgnoreCase(string[]? values, string candidate)
    {
        if (values is null) { return false; }
        foreach (string v in values)
        {
            if (string.Equals(v, candidate, StringComparison.OrdinalIgnoreCase)) { return true; }
        }
        return false;
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
        if (string.IsNullOrEmpty(machine)) { return null; }
        return new[] { new DbaInstanceParameter(machine) };
    }
}
