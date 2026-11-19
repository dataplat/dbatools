#nullable enable
#pragma warning disable CA1416 // Windows-only command: X509 certificate export

using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Security;
using System.Security.Cryptography.X509Certificates;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports certificate objects piped from Get-DbaComputerCertificate to files. Port of
/// public/Backup-DbaComputerCertificate.ps1; surface pinned by
/// migration/baselines/Backup-DbaComputerCertificate.json.
/// </summary>
[Cmdlet(VerbsData.Backup, "DbaComputerCertificate")]
[OutputType(typeof(System.IO.FileInfo))]
public sealed class BackupDbaComputerCertificateCommand : DbaBaseCmdlet
{
    /// <summary>Secures the certificate export, when the export type supports a password.</summary>
    [Parameter(Position = 0)]
    [Alias("Password")]
    public SecureString? SecurePassword { get; set; }

    /// <summary>The certificate object(s) to back up, piped from Get-DbaComputerCertificate.</summary>
    [Parameter(ValueFromPipeline = true, Mandatory = true, Position = 1)]
    public object[]? InputObject { get; set; }

    /// <summary>The directory to export to; defaults to the current location.</summary>
    [Parameter(Position = 2)]
    public string? Path { get; set; }

    /// <summary>The full export file path; overrides the computed name.</summary>
    [Parameter(Position = 3)]
    public string? FilePath { get; set; }

    /// <summary>The certificate export content type.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    [ValidateSet("Authenticode", "Cert", "Pfx", "Pkcs12", "Pkcs7", "SerializedCert")]
    public string Type { get; set; } = "Cert";

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private string? _effectiveFilePath;

    protected override void BeginProcessing()
    {
        // PS: [string]$Path = $pwd - the default binds the CURRENT LOCATION at invocation.
        if (!TestBound("Path"))
        {
            Path = SessionState.Path.CurrentLocation.Path;
        }
        _effectiveFilePath = FilePath;
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        if (InputObject is null)
        {
            return;
        }

        foreach (object certInput in InputObject)
        {
            if (certInput is null)
            {
                continue;
            }
            PSObject cert = PSObject.AsPSObject(certInput);

            // PS: if ((Test-Bound -Parameter FilePath -Not)) { $FilePath = "$Path\$($cert.ComputerName)-$($cert.Thumbprint).cer" }
            if (!TestBound("FilePath"))
            {
                object? computerName = cert.Properties["ComputerName"]?.Value;
                object? thumbprint = cert.Properties["Thumbprint"]?.Value;
                _effectiveFilePath = $"{Path}\\{computerName}-{thumbprint}.cer";
            }

            // PS: $certfromraw = New-Object X509Certificate2($cert.RawData, $SecurePassword);
            //     [io.file]::WriteAllBytes($FilePath, $certfromraw.Export($Type)) - each statement
            // fails independently (statement-terminating) and the next still runs, like PS.
            X509Certificate2? certFromRaw = null;
            try
            {
                byte[] rawData = LanguagePrimitives.ConvertTo<byte[]>(cert.Properties["RawData"]?.Value);
                certFromRaw = new X509Certificate2(rawData, SecurePassword);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                WriteError(new ErrorRecord(ex, "dbatools_Backup-DbaComputerCertificate", ErrorCategory.NotSpecified, certInput));
            }

            try
            {
                if (certFromRaw is not null)
                {
                    X509ContentType contentType = LanguagePrimitives.ConvertTo<X509ContentType>(Type);
                    System.IO.File.WriteAllBytes(_effectiveFilePath!, certFromRaw.Export(contentType));
                }
                else
                {
                    // PS: $certfromraw.Export(...) on a null variable is its own statement error.
                    throw new RuntimeException("You cannot call a method on a null-valued expression.");
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                WriteError(new ErrorRecord(ex, "dbatools_Backup-DbaComputerCertificate", ErrorCategory.NotSpecified, certInput));
            }

            // PS: Get-ChildItem $FilePath - the engine cmdlet emits the FileInfo (or its own
            // error when the export never landed).
            using PowerShell shell = PowerShell.Create(RunspaceMode.CurrentRunspace);
            shell.AddCommand("Get-ChildItem").AddParameter("Path", _effectiveFilePath);
            try
            {
                Collection<PSObject> items = shell.Invoke();
                foreach (ErrorRecord error in shell.Streams.Error)
                {
                    WriteError(NestedCommand.PreserveErrorIdentity(error));
                }
                foreach (PSObject item in items)
                {
                    WriteObject(item);
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (RuntimeException rex)
            {
                WriteError(NestedCommand.PreserveErrorIdentity(rex.ErrorRecord));
            }
        }
    }
}
