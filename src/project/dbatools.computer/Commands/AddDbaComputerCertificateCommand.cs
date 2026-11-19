#nullable enable
#pragma warning disable CA1416 // Windows-only command: X509 certificate store import

using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Runtime.InteropServices;
using System.Security;
using System.Security.Cryptography.X509Certificates;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Imports a certificate (or certificate chain from a file) into a computer's certificate store.
/// Port of public/Add-DbaComputerCertificate.ps1; surface pinned by
/// migration/baselines/Add-DbaComputerCertificate.json.
/// </summary>
[Cmdlet(VerbsCommon.Add, "DbaComputerCertificate", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
[OutputType(typeof(PSObject))]
public sealed class AddDbaComputerCertificateCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s); defaults to the local computer.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; } = DefaultComputerName();

    /// <summary>Alternate credential for connecting to the remote computer.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>Password for a password-protected (PFX) certificate.</summary>
    [Parameter(Position = 2)]
    [Alias("Password")]
    public SecureString? SecurePassword { get; set; }

    /// <summary>Certificate object(s) to import, from the pipeline.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public X509Certificate2[]? Certificate { get; set; }

    /// <summary>A certificate file to import (.cer/.pfx, chain preserved).</summary>
    [Parameter(Position = 4)]
    public string? Path { get; set; }

    /// <summary>The certificate store location.</summary>
    [Parameter(Position = 5)]
    public string Store { get; set; } = "LocalMachine";

    /// <summary>The certificate folder within the store.</summary>
    [Parameter(Position = 6)]
    public string Folder { get; set; } = "My";

    /// <summary>Key storage flags controlling how the private key is stored.</summary>
    [Parameter(Position = 7)]
    [ValidateSet("EphemeralKeySet", "Exportable", "PersistKeySet", "UserProtected", "NonExportable")]
    public string[] Flag { get; set; } = new[] { "Exportable", "PersistKeySet" };

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The Invoke-Command2 scriptblock (cooked), verbatim from the PS source: imports the chain
    // into the store on the target and emits the imported certs via Get-ChildItem Cert:\...
    private const string ImportScript = @"
            param (
                $CertificateData,
                [string]$PlainPassword,
                $Store,
                $Folder,
                $flags
            )

            # Use X509Certificate2Collection to import the full certificate chain
            $certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
            Write-Verbose -Message ""Importing certificate chain to $Folder\$Store using flags: $flags""
            $certCollection.Import($CertificateData, $PlainPassword, $flags)

            $tempStore = New-Object System.Security.Cryptography.X509Certificates.X509Store($Folder, $Store)
            $tempStore.Open(""ReadWrite"")

            # Import all certificates in the chain
            $importedCerts = @()
            foreach ($cert in $certCollection) {
                $tempStore.Add($cert)
                $importedCerts += $cert.Thumbprint
                Write-Verbose -Message ""Imported certificate: $($cert.Subject) (Thumbprint: $($cert.Thumbprint))""
            }

            $tempStore.Close()

            Write-Verbose -Message ""Searching Cert:\$Store\$Folder for imported certificates""
            Get-ChildItem ""Cert:\$Store\$Folder"" -Recurse | Where-Object { $_.Thumbprint -in $importedCerts }";

    private static readonly string[] DisplaySet = new[] { "FriendlyName", "DnsNameList", "Thumbprint", "NotBefore", "NotAfter", "Subject", "Issuer" };

    private string _flags = "";
    private bool _isCollection;
    private byte[]? _collectionData;

    protected override void BeginProcessing()
    {
        // PS: if ("NonExportable" -in $Flag) { ... } else { $flags = $Flag -join "," }
        if (ContainsIgnoreCase(Flag, "NonExportable"))
        {
            List<string> kept = new();
            foreach (string f in Flag)
            {
                if (!string.Equals(f, "Exportable", StringComparison.OrdinalIgnoreCase)
                    && !string.Equals(f, "NonExportable", StringComparison.OrdinalIgnoreCase))
                {
                    kept.Add(f);
                }
            }
            _flags = string.Join(",", kept);
            bool localMachine = string.Equals(Store, "LocalMachine", StringComparison.OrdinalIgnoreCase);
            if (string.IsNullOrEmpty(_flags))
            {
                _flags = localMachine ? "MachineKeySet" : "UserKeySet";
            }
            else
            {
                _flags += localMachine ? ",MachineKeySet" : ",UserKeySet";
            }
        }
        else
        {
            _flags = string.Join(",", Flag);
        }

        WriteMessage(MessageLevel.Verbose, $"Flags: {_flags}");

        // PS: if ($Path) { Test-Path; read bytes; import to a collection LOCALLY (Exportable,
        // PersistKeySet); re-export as one PFX with the password; $isCollection=$true }
        if (!string.IsNullOrEmpty(Path))
        {
            if (!System.IO.File.Exists(Path) && !System.IO.Directory.Exists(Path))
            {
                StopFunction($"Path ({Path}) does not exist.", category: ErrorCategory.InvalidArgument);
                return;
            }

            string? plainPassword = SecureToPlain(SecurePassword);
            try
            {
                byte[] fileBytes = System.IO.File.ReadAllBytes(Path!);
                X509Certificate2Collection certCollection = new();
                WriteMessage(MessageLevel.Verbose, $"Importing Path: {Path}");
                certCollection.Import(fileBytes, plainPassword, X509KeyStorageFlags.Exportable | X509KeyStorageFlags.PersistKeySet);
                _collectionData = certCollection.Export(X509ContentType.Pfx, plainPassword);
                _isCollection = true;
                Certificate = ToArray(certCollection);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction("Can't import certificate.", errorRecord: null, exception: ex);
                return;
            }
        }
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

        // PS: if (-not $Certificate) { Stop-Function "You must specify either Certificate or Path" }
        if (Certificate is null || Certificate.Length == 0)
        {
            StopFunction("You must specify either Certificate or Path", category: ErrorCategory.InvalidArgument);
            return;
        }

        string? plainPassword = SecureToPlain(SecurePassword);

        if (_isCollection && _collectionData is not null)
        {
            foreach (DbaInstanceParameter computer in ComputerName)
            {
                if (computer is null)
                {
                    continue;
                }
                if (!ShouldProcess(computer.ToString(), "Attempting to import cert collection"))
                {
                    continue;
                }
                if (ContainsIgnoreCase(Flag, "UserProtected") && !computer.IsLocalHost)
                {
                    StopFunction($"UserProtected flag is only valid for localhost because it causes a prompt, skipping for {computer}", continueLoop: true);
                    continue;
                }
                ImportOnTarget(computer, _collectionData, plainPassword);
            }
        }
        else
        {
            foreach (X509Certificate2 cert in Certificate)
            {
                byte[]? certData = null;
                try
                {
                    certData = cert.Export(X509ContentType.Pfx, plainPassword);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    StopFunction("Can't export certificate", exception: ex, continueLoop: true);
                }
                if (certData is null)
                {
                    continue;
                }

                foreach (DbaInstanceParameter computer in ComputerName)
                {
                    if (computer is null)
                    {
                        continue;
                    }
                    if (!ShouldProcess(computer.ToString(), "Attempting to import cert"))
                    {
                        continue;
                    }
                    if (ContainsIgnoreCase(Flag, "UserProtected") && !computer.IsLocalHost)
                    {
                        StopFunction($"UserProtected flag is only valid for localhost because it causes a prompt, skipping for {computer}", continueLoop: true);
                        continue;
                    }
                    ImportOnTarget(computer, certData, plainPassword);
                }
            }
        }
    }

    // PS: Invoke-Command2 ... -ArgumentList $data, $plainPassword, $Store, $Folder, $flags
    //     -ScriptBlock $scriptBlock -ErrorAction Stop | Select-DefaultView -Property <7>
    private void ImportOnTarget(DbaInstanceParameter computer, byte[] certData, string? plainPassword)
    {
        try
        {
            RemoteExecutionService.RemoteCommandRequest request = new()
            {
                ComputerName = computer,
                Credential = Credential,
                ScriptText = ImportScript,
                ArgumentList = new object?[] { certData, plainPassword, Store, Folder, _flags }!
            };
            RemoteExecutionService.RemoteCommandResult result = RemoteExecutionService.InvokeCommand(this, request);
            if (result.Errors.Count > 0)
            {
                StopFunction("Failure", target: computer, errorRecord: result.Errors[0], continueLoop: true);
                return;
            }
            foreach (PSObject output in result.Output)
            {
                if (output is null)
                {
                    continue;
                }
                OutputHelper.SetDefaultDisplayPropertySet(output, DisplaySet);
                WriteObject(output);
            }
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (RuntimeException rex)
        {
            StopFunction("Failure", target: computer, errorRecord: rex.ErrorRecord, continueLoop: true);
        }
        catch (Exception ex)
        {
            StopFunction("Failure", target: computer, exception: ex, continueLoop: true);
        }
    }

    private static bool ContainsIgnoreCase(string[]? values, string candidate)
    {
        if (values is null)
        {
            return false;
        }
        foreach (string v in values)
        {
            if (string.Equals(v, candidate, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }

    private static string? SecureToPlain(SecureString? secure)
    {
        if (secure is null)
        {
            return null;
        }
        IntPtr ptr = IntPtr.Zero;
        try
        {
            ptr = Marshal.SecureStringToGlobalAllocUnicode(secure);
            return Marshal.PtrToStringUni(ptr);
        }
        finally
        {
            if (ptr != IntPtr.Zero)
            {
                Marshal.ZeroFreeGlobalAllocUnicode(ptr);
            }
        }
    }

    private static X509Certificate2[] ToArray(X509Certificate2Collection collection)
    {
        List<X509Certificate2> list = new();
        foreach (X509Certificate2 cert in collection)
        {
            list.Add(cert);
        }
        return list.ToArray();
    }

    // PS: [DbaInstance[]]$ComputerName = $env:COMPUTERNAME
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
