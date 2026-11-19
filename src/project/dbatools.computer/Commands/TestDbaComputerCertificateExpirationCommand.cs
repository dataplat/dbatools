#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Tests computer certificates for expiration within a threshold. Port of
/// public/Test-DbaComputerCertificateExpiration.ps1; surface pinned by
/// migration/baselines/Test-DbaComputerCertificateExpiration.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaComputerCertificateExpiration")]
[OutputType(typeof(PSObject))]
public sealed class TestDbaComputerCertificateExpirationCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s); defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; } = DefaultComputerName();

    /// <summary>Alternate credential for connecting to the remote computer.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>Certificate store(s) to search.</summary>
    [Parameter(Position = 2)]
    public string[] Store { get; set; } = new[] { "LocalMachine" };

    /// <summary>Certificate folder(s) to search.</summary>
    [Parameter(Position = 3)]
    public string[] Folder { get; set; } = new[] { "My" };

    /// <summary>Service and All check computer certificates; SQL Server checks the instance's network certificate.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    [ValidateSet("All", "Service", "SQL Server")]
    public string Type { get; set; } = "Service";

    /// <summary>Reads a certificate file from this path on the target instead of a store.</summary>
    [Parameter(Position = 5)]
    public string? Path { get; set; }

    /// <summary>Check only certificates with these thumbprints.</summary>
    [Parameter(Position = 6)]
    public string[]? Thumbprint { get; set; }

    /// <summary>Number of days out to warn about expiration.</summary>
    [Parameter(Position = 7)]
    public int Threshold { get; set; } = 30;

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private static readonly string[] DisplaySet = new[] { "ComputerName", "Store", "Folder", "Name", "DnsNameList", "Thumbprint", "NotBefore", "NotAfter", "Subject", "Issuer", "Algorithm", "ExpiredOrExpiring", "Note" };

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
            string computerText = computer.ToString();
            WriteMessage(MessageLevel.Verbose, $"Processing {computerText}");

            // PS: try { nested Get-DbaNetworkCertificate / Get-DbaComputerCertificate with
            // -EnableException:$true } catch { Stop-Function "Failure for $computer" } - no
            // -Continue in the source, but the call sits at the loop-body end with no interrupt
            // test, so the loop (and later pipeline records) kept going: continueLoop is the
            // faithful mapping, and under -EnableException it still throws.
            try
            {
                Collection<PSObject> certs;
                if (string.Equals(Type, "SQL Server", StringComparison.OrdinalIgnoreCase))
                {
                    WriteMessage(MessageLevel.Verbose, "Type is SQL Server, getting network SQL Server-only certificate");
                    Hashtable splatNetworkCert = new Hashtable
                    {
                        { "ComputerName", computer },
                        { "Credential", Credential },
                        { "EnableException", true }
                    };
                    certs = NestedCommand.Invoke(this, "Get-DbaNetworkCertificate", splatNetworkCert);
                }
                else
                {
                    WriteMessage(MessageLevel.Verbose, $"Type is Service, getting all computer certificates on {computerText}");
                    // PS: $parms with Credential/Path/Thumbprint added only when truthy; -Type is
                    // NEVER forwarded, so the nested command uses its own Service default even
                    // when the caller said All (quirk preserved).
                    Hashtable splatComputerCert = new Hashtable
                    {
                        { "ComputerName", computer },
                        { "Store", Store },
                        { "Folder", Folder },
                        { "EnableException", true }
                    };
                    if (Credential is not null)
                    {
                        splatComputerCert["Credential"] = Credential;
                    }
                    if (!string.IsNullOrEmpty(Path))
                    {
                        splatComputerCert["Path"] = Path;
                    }
                    if (Thumbprint is not null && LanguagePrimitives.IsTrue(Thumbprint))
                    {
                        splatComputerCert["Thumbprint"] = Thumbprint;
                    }
                    certs = NestedCommand.Invoke(this, "Get-DbaComputerCertificate", splatComputerCert);
                }

                // PS: "Found $($certs.Name.Count) certificates" - member-enumerated Name count.
                WriteMessage(MessageLevel.Verbose, $"Found {CountMemberValues(certs, "Name")} certificates");

                foreach (PSObject cert in certs)
                {
                    if (cert is null)
                    {
                        continue;
                    }
                    object? nameValue = cert.Properties["Name"]?.Value;
                    WriteMessage(MessageLevel.Verbose, $"Checking {nameValue} cert");

                    // PS: $expiration = $cert.NotAfter.Date.Subtract((Get-Date)).Days
                    DateTime notAfter = LanguagePrimitives.ConvertTo<DateTime>(cert.Properties["NotAfter"]?.Value);
                    int expiration = notAfter.Date.Subtract(DateTime.Now).Days;
                    if (expiration < Threshold)
                    {
                        string note;
                        if (notAfter <= DateTime.Now)
                        {
                            note = "This certificate has expired and is no longer valid";
                        }
                        else
                        {
                            note = $"This certificate expires in {expiration} days";
                        }
                        cert.Properties.Add(new PSNoteProperty("ExpiredOrExpiring", true));
                        cert.Properties.Add(new PSNoteProperty("Note", note));
                        OutputHelper.SetDefaultDisplayPropertySet(cert, DisplaySet);
                        WriteObject(cert);
                    }
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (RuntimeException rex)
            {
                StopFunction($"Failure for {computerText}", errorRecord: rex.ErrorRecord, continueLoop: true);
                continue;
            }
            catch (Exception ex)
            {
                StopFunction($"Failure for {computerText}", exception: ex, continueLoop: true);
                continue;
            }
        }
    }

    // PS: $certs.Name.Count - member enumeration then the Count intrinsic (null -> 0, one -> 1).
    private static int CountMemberValues(Collection<PSObject> items, string name)
    {
        int count = 0;
        foreach (PSObject item in items)
        {
            if (item?.Properties[name] is not null)
            {
                count++;
            }
        }
        return count;
    }

    // PS: [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME
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
