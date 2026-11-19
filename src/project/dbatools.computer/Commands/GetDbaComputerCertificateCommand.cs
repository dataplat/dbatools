#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves computer certificates that are candidates for SQL Server network encryption.
/// Port of public/Get-DbaComputerCertificate.ps1; surface pinned by
/// migration/baselines/Get-DbaComputerCertificate.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaComputerCertificate")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaComputerCertificateCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s); defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; } = DefaultComputerName();

    /// <summary>Alternate credential for connecting to the remote computer.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>Certificate store(s) to search; All enumerates the target's store locations.</summary>
    [Parameter(Position = 2)]
    public string[] Store { get; set; } = new[] { "LocalMachine" };

    /// <summary>Certificate folder(s) to search; All enumerates the target's store names.</summary>
    [Parameter(Position = 3)]
    public string[] Folder { get; set; } = new[] { "My" };

    /// <summary>Service returns only Server Authentication candidates; All returns everything.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    [ValidateSet("All", "Service")]
    public string Type { get; set; } = "Service";

    /// <summary>Reads a certificate file from this path on the target instead of a store.</summary>
    [Parameter(Position = 5)]
    public string? Path { get; set; }

    /// <summary>Return only certificates with these thumbprints.</summary>
    [Parameter(Position = 6)]
    public string[]? Thumbprint { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // PS begin block, verbatim. The PS scriptblock literal was BOUND to the function scope, so on
    // a LOCALHOST (in-process) run the undeclared $Type resolved to the function's parameter while
    // a REMOTE run got $null (unserialized scope) - the port injects "$Type = ..." for localhost
    // only to reproduce that dynamic-scope split exactly.
    private const string CertificateParamBlock = @"
            param (
                $Thumbprint,
                $Store,
                $Folder,
                $Path
            )
";

    private const string CertificateScript = @"
            if ($Path) {
                $bytes = [System.IO.File]::ReadAllBytes($path)
                $Certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
                $Certificate.Import($bytes, $null, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
                return $Certificate
            }

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

                foreach ($c in $certs) {
                    Add-Member -Force -InputObject $c -NotePropertyName Algorithm -NotePropertyValue $c.SignatureAlgorithm.FriendlyName
                    Add-Member -Force -InputObject $c -NotePropertyName ComputerName -NotePropertyValue $env:ComputerName
                    # had to add Name because remotely, ""FriendlyName"" refused to work. no idea why.
                    Add-Member -Force -InputObject $c -NotePropertyName Name -NotePropertyValue $c.FriendlyName.ToString()
                    Add-Member -Force -InputObject $c -NotePropertyName Store -NotePropertyValue $Store
                    Add-Member -Force -InputObject $c -NotePropertyName Folder -NotePropertyValue $Folder -Passthru
                }
            }

            if ($Thumbprint) {
                try {
                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Verbose ""Searching Cert:\$Store\$Folder""
                    Get-CoreCertificate -Store $Store -Folder $Folder -Thumbprint $Thumbprint
                } catch {
                    # don't care - there's a weird issue with remoting where an exception gets thrown for no apparent reason
                    # here to avoid an empty catch
                    $null = 1
                }
            } else {
                try {
                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Verbose ""Searching Cert:\$Store\$Folder""
                    if ($Type -eq ""Service"") {
                        Get-CoreCertificate -Store $Store -Folder $Folder | Where-Object EnhancedKeyUsageList -match '1\.3\.6\.1\.5\.5\.7\.3\.1'
                    } else {
                        Get-CoreCertificate -Store $Store -Folder $Folder
                    }
                } catch {
                    # still don't care
                    # here to avoid an empty catch
                    $null = 1
                }
            }";

    private const string StoreEnumerationScript = " Get-ChildItem Cert: | Select-Object -ExpandProperty Location ";
    private const string FolderEnumerationScript = " Get-ChildItem Cert: | Select-Object -ExpandProperty StoreNames | Select-Object -ExpandProperty Keys ";

    private static readonly string[] DisplaySet = new[] { "ComputerName", "Store", "Folder", "Name", "DnsNameList", "Thumbprint", "NotBefore", "NotAfter", "Subject", "Issuer", "Algorithm" };

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

        foreach (DbaInstanceParameter rawComputer in ComputerName)
        {
            // PS: `foreach ($computer in $computername)` iterates the array DIRECTLY (not
            // member-enumeration), so a null slot is NOT skipped - PS passes $null to
            // Invoke-Command2, whose [DbaInstanceParameter]$ComputerName cast turns null into the
            // localhost machine name. Mirror that so `-ComputerName @($null)` runs the localhost
            // path (codex parity fix 2026-07-10). Null-array-slot survival proven on the lab.
            DbaInstanceParameter computer = rawComputer ?? new DbaInstanceParameter(Environment.MachineName);

            // PS: if ($Store -eq "All") - array -eq filters, so this means "contains All"; the
            // reassignment replaces the PARAMETER variable, [string[]]-constrained, for all
            // remaining computers too (parameter-variable mutation preserved).
            if (ArrayEqualsAny(Store, "All"))
            {
                try
                {
                    Store = InvokeRawAsStringArray(computer, StoreEnumerationScript);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (RuntimeException rex)
                {
                    StopFunction("Issue connecting to computer", target: computer, errorRecord: rex.ErrorRecord, continueLoop: true);
                    continue;
                }
                catch (Exception ex)
                {
                    StopFunction("Issue connecting to computer", target: computer, exception: ex, continueLoop: true);
                    continue;
                }
            }
            if (ArrayEqualsAny(Folder, "All"))
            {
                try
                {
                    Folder = InvokeRawAsStringArray(computer, FolderEnumerationScript);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (RuntimeException rex)
                {
                    StopFunction("Issue connecting to computer", target: computer, errorRecord: rex.ErrorRecord, continueLoop: true);
                    continue;
                }
                catch (Exception ex)
                {
                    StopFunction("Issue connecting to computer", target: computer, exception: ex, continueLoop: true);
                    continue;
                }
            }

            foreach (string currentStore in Store ?? Array.Empty<string>())
            {
                foreach (string currentFolder in Folder ?? Array.Empty<string>())
                {
                    try
                    {
                        // Localhost runs see the function-scope $Type through the bound
                        // scriptblock; remote runs never did (plain text over the wire). The
                        // injection sits AFTER the param block (param must stay first).
                        string scriptText = computer.IsLocalHost
                            ? CertificateParamBlock + "            $Type = \"" + Type + "\"\n" + CertificateScript
                            : CertificateParamBlock + CertificateScript;

                        RemoteExecutionService.RemoteCommandRequest request = new()
                        {
                            ComputerName = computer,
                            Credential = Credential,
                            ScriptText = scriptText,
                            ArgumentList = new object?[] { Thumbprint, currentStore, currentFolder, Path }!
                        };
                        RemoteExecutionService.RemoteCommandResult result = RemoteExecutionService.InvokeCommand(this, request);

                        // PS: -ErrorAction Stop on the Invoke-Command2 splat - a populated error
                        // bag maps to the catch's Stop-Function, like W5-011.
                        if (result.Errors.Count > 0)
                        {
                            StopFunction("Issue connecting to computer", target: computer, errorRecord: result.Errors[0], continueLoop: true);
                            continue;
                        }

                        // PS: ... | Select-DefaultView -Property ComputerName, Store, Folder, Name,
                        // DnsNameList, Thumbprint, NotBefore, NotAfter, Subject, Issuer, Algorithm
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
                        StopFunction("Issue connecting to computer", target: computer, errorRecord: rex.ErrorRecord, continueLoop: true);
                        continue;
                    }
                    catch (Exception ex)
                    {
                        StopFunction("Issue connecting to computer", target: computer, exception: ex, continueLoop: true);
                        continue;
                    }
                }
            }
        }
    }

    // PS: Invoke-Command2 ... -Raw feeding a [string[]]-constrained parameter variable.
    private string[] InvokeRawAsStringArray(DbaInstanceParameter computer, string scriptText)
    {
        RemoteExecutionService.RemoteCommandRequest request = new()
        {
            ComputerName = computer,
            Credential = Credential,
            ScriptText = scriptText,
            Raw = true
        };
        RemoteExecutionService.RemoteCommandResult result = RemoteExecutionService.InvokeCommand(this, request);
        foreach (ErrorRecord error in result.Errors)
        {
            WriteError(NestedCommand.PreserveErrorIdentity(error));
        }
        List<string> values = new();
        foreach (PSObject item in result.Output)
        {
            if (item is not null)
            {
                values.Add(LanguagePrimitives.ConvertTo<string>(item));
            }
        }
        return values.ToArray();
    }

    // PS array -eq scalar filters the array; in a boolean context that is "any element equals".
    private static bool ArrayEqualsAny(string[]? values, string candidate)
    {
        if (values is null)
        {
            return false;
        }
        foreach (string value in values)
        {
            if (LanguagePrimitives.Equals(value, candidate, ignoreCase: true))
            {
                return true;
            }
        }
        return false;
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
