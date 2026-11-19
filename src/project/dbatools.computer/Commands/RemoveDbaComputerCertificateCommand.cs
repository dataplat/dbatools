#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes a computer certificate by thumbprint from a certificate store.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaComputerCertificate", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(PSObject))]
public sealed class RemoveDbaComputerCertificateCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s); defaults to the local computer.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; } = DefaultComputerName();

    /// <summary>Alternate credential for connecting to the remote computer.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>The thumbprint(s) of the certificate(s) to remove.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Mandatory = true, Position = 2)]
    public string[]? Thumbprint { get; set; }

    /// <summary>The certificate store location.</summary>
    [Parameter(Position = 3)]
    public string Store { get; set; } = "LocalMachine";

    /// <summary>The certificate folder within the store.</summary>
    [Parameter(Position = 4)]
    public string Folder { get; set; } = "My";

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The Invoke-Command2 scriptblock (cooked), verbatim from the PS source: searches the store
    // for the thumbprint, removes it if found, and emits the status object with the TARGET's own
    // $env:COMPUTERNAME.
    private const string RemoveScript = @"
            param (
                $Thumbprint,
                $Store,
                $Folder
            )
            <# DO NOT use Write-Message as this is inside of a script block #>
            Write-Verbose ""Searching Cert:\$Store\$Folder for thumbprint: $thumbprint""
            function Get-CoreCertStore {
                [CmdletBinding()]
                param (
                    [ValidateSet(""CurrentUser"", ""LocalMachine"")]
                    [string]$Store,
                    [ValidateSet(""AddressBook"", ""AuthRoot, CertificateAuthority"", ""Disallowed"", ""My"", ""Root"", ""TrustedPeople"", ""TrustedPublisher"")]
                    [string]$Folder,
                    [ValidateSet(""ReadOnly"", ""ReadWrite"")]
                    [string]$Flag = ""ReadOnly""
                )

                $storename = [System.Security.Cryptography.X509Certificates.StoreLocation]::$Store
                $foldername = [System.Security.Cryptography.X509Certificates.StoreName]::$Folder
                $flags = [System.Security.Cryptography.X509Certificates.OpenFlags]::$Flag
                $certstore = New-Object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList $foldername, $storename
                $certstore.Open($flags)

                $certstore
            }

            function Get-CoreCertificate {
                [CmdletBinding()]
                param (
                    [ValidateSet(""CurrentUser"", ""LocalMachine"")]
                    [string]$Store,
                    [ValidateSet(""AddressBook"", ""AuthRoot, CertificateAuthority"", ""Disallowed"", ""My"", ""Root"", ""TrustedPeople"", ""TrustedPublisher"")]
                    [string]$Folder,
                    [ValidateSet(""ReadOnly"", ""ReadWrite"")]
                    [string]$Flag = ""ReadOnly"",
                    [string[]]$Thumbprint,
                    [System.Security.Cryptography.X509Certificates.X509Store[]]$InputObject
                )

                if (-not $InputObject) {
                    $InputObject += Get-CoreCertStore -Store $Store -Folder $Folder -Flag $Flag
                }

                $certs = ($InputObject).Certificates

                if ($Thumbprint) {
                    $certs = $certs | Where-Object Thumbprint -in $Thumbprint
                }
                $certs
            }

            if ($Thumbprint) {
                try {
                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Verbose ""Searching Cert:\$Store\$Folder""
                    $cert = Get-CoreCertificate -Store $Store -Folder $Folder -Thumbprint $Thumbprint
                } catch {
                    # don't care - there's a weird issue with remoting where an exception gets thrown for no apparent reason
                    # here to avoid an empty catch
                    $null = 1
                }
            }

            if ($cert) {
                $certstore = Get-CoreCertStore -Store $Store -Folder $Folder -Flag ReadWrite
                $certstore.Remove($cert)
                $status = ""Removed""
            } else {
                $status = ""Certificate not found in Cert:\$Store\$Folder""
            }

            [PSCustomObject]@{
                ComputerName = $env:COMPUTERNAME
                Store        = $Store
                Folder       = $Folder
                Thumbprint   = $thumbprint
                Status       = $status
            }";

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        if (ComputerName is null || Thumbprint is null)
        {
            return;
        }

        // PS: foreach ($computer in $computername) { foreach ($thumb in $Thumbprint) { ... } }
        foreach (DbaInstanceParameter computer in ComputerName)
        {
            if (computer is null)
            {
                continue;
            }
            foreach (string thumb in Thumbprint)
            {
                // PS: if ($PScmdlet.ShouldProcess("local", "Connecting to $computer to remove
                //     cert from Cert:\$Store\$Folder")) - target "local", the exact action text.
                if (!ShouldProcess("local", $"Connecting to {computer} to remove cert from Cert:\\{Store}\\{Folder}"))
                {
                    continue;
                }

                try
                {
                    // PS: Invoke-Command2 ... -ArgumentList $thumb, $Store, $Folder -ScriptBlock
                    //     $scriptBlock -ErrorAction Stop (cooked). -ArgumentList passes ONE thumb.
                    RemoteExecutionService.RemoteCommandRequest request = new()
                    {
                        ComputerName = computer,
                        Credential = Credential,
                        ScriptText = RemoveScript,
                        ArgumentList = new object[] { thumb, Store, Folder }
                    };
                    RemoteExecutionService.RemoteCommandResult result = RemoteExecutionService.InvokeCommand(this, request);
                    // -ErrorAction Stop makes a remote error terminating -> the catch; the compiled
                    // Invoke-Command2 surfaces non-terminating remote errors in .Errors, so map a
                    // populated bag to the same Stop-Function path.
                    if (result.Errors.Count > 0)
                    {
                        StopFunction(result.Errors[0].ToString(), target: computer, errorRecord: result.Errors[0], continueLoop: true);
                        continue;
                    }
                    foreach (PSObject output in result.Output)
                    {
                        if (output is not null)
                        {
                            WriteObject(output);
                        }
                    }
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (RuntimeException rex)
                {
                    StopFunction(rex.ErrorRecord?.ToString() ?? rex.Message, target: computer, errorRecord: rex.ErrorRecord, continueLoop: true);
                    continue;
                }
                catch (Exception ex)
                {
                    StopFunction(ex.Message, target: computer, exception: ex, continueLoop: true);
                    continue;
                }
            }
        }
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
