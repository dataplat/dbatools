#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Tests the network (TLS) certificate configuration of a SQL Server instance - either the
/// configured/available certificates (Way One) or a specific certificate by thumbprint (Way Two).
/// Port of public/Test-DbaNetworkCertificate.ps1; surface pinned by
/// migration/baselines/Test-DbaNetworkCertificate.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaNetworkCertificate")]
[OutputType(typeof(PSObject))]
public sealed class TestDbaNetworkCertificateCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance(s).</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = Array.Empty<DbaInstanceParameter>();

    /// <summary>Alternate Windows credential for the target computer.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>A specific certificate thumbprint to validate (Way Two).</summary>
    [Parameter(Position = 2)]
    public string? Thumbprint { get; set; }

    /// <summary>Minimum days a certificate must remain valid to be considered suitable.</summary>
    [Parameter(Position = 3)]
    public int MinimumValidDays { get; set; } = 0;

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Way-Two validation scriptblock, injected VERBATIM from the PS source (byte-exact).
    private const string ValidationScript = @"
            $instance = $args[0]
            $thumbprint = $args[1]
            $minimumValidDays = $args[2]

            # As we go remote, ensure the assembly is loaded
            [void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SqlWmiManagement')
            $wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
            $null = $wmi.Initialize()
            $wmiService = $wmi.Services | Where-Object { $_.DisplayName -eq ""SQL Server ($($instance.InstanceName))"" }
            $vsname = ($wmiService.AdvancedProperties | Where-Object Name -eq VSNAME).Value
            if ([System.String]::IsNullOrEmpty($vsname)) {
                # Fallback for some WMI versions where direct property access fails (aligned with Get-DbaNetworkConfiguration)
                $vsnameRaw = $wmiService.AdvancedProperties | Where-Object { $_ -match 'VSNAME' }
                if (![System.String]::IsNullOrEmpty($vsnameRaw)) {
                    $vsname = ($vsnameRaw -Split 'Value\=')[1]
                }
            }

            # Determine the network name used for DNS name validation (aligned with Get-DbaNetworkConfiguration)
            $networkName = if ($vsname) { $vsname } else { hostname }

            # Find the certificate by thumbprint in LocalMachine\My
            $cert = Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object Thumbprint -eq $thumbprint

            if ($null -eq $cert) {
                [PSCustomObject]@{
                    ComputerName            = $instance.ComputerName
                    InstanceName            = $instance.InstanceName
                    SqlInstance             = $instance.SqlFullName.Trim('[]')
                    Thumbprint              = $thumbprint
                    IsSuitable              = $false
                    CertificateFound        = $false
                    KeyUsagesValid          = $null
                    DnsNamesValid           = $null
                    PrivateKeyValid         = $null
                    PublicKeyValid          = $null
                    SignatureAlgorithmValid = $null
                    EnhancedKeyUsageValid   = $null
                    ValidityPeriodOk        = $null
                    KeyUsages               = $null
                    DnsNames                = $null
                    PrivateKeyType          = $null
                    PrivateKeyNumber        = $null
                    PublicKeySize           = $null
                    PublicKeyAlgorithm      = $null
                    SignatureAlgorithm      = $null
                    EnhancedKeyUsageList    = $null
                    NotBefore               = $null
                    NotAfter                = $null
                    DaysValid               = $null
                }
                return
            }

            # --- Certificate validation tests, aligned with Get-DbaNetworkConfiguration ---
            $requiredKeyUsages = [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature -bor [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyEncipherment

            try {
                $keyUsageExt = $cert.Extensions | Where-Object { $_ -is [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension] }
                $keyUsages = $keyUsageExt.KeyUsages
                $keyUsagesValid = ($keyUsages -band $requiredKeyUsages) -eq $requiredKeyUsages
            } catch {
                $keyUsages = $null
                $keyUsagesValid = $false
            }

            try {
                $dnsNames = $cert.DnsNameList.Unicode
                if (-not $dnsNames -and $cert.Subject -match 'CN=([^,]+)') { $dnsNames = @( $Matches[1] ) }
                $dnsNamesValid = $dnsNames -contains $networkName -or $dnsNames -contains ""$networkName.$env:USERDNSDOMAIN""
            } catch {
                $dnsNames = $null
                $dnsNamesValid = $false
            }

            try {
                $privateKeyType = if ($null -ne $cert.PrivateKey) { $cert.PrivateKey.GetType().FullName } else { $null }
                $privateKeyNumber = if ($cert.PrivateKey -is [System.Security.Cryptography.RSACryptoServiceProvider]) { $cert.PrivateKey.CspKeyContainerInfo.KeyNumber } else { $null }
                $privateKeyValid = $cert.PrivateKey -is [System.Security.Cryptography.RSACryptoServiceProvider] -and
                $cert.PrivateKey.CspKeyContainerInfo.KeyNumber -eq [System.Security.Cryptography.KeyNumber]::Exchange
            } catch {
                $privateKeyType = $null
                $privateKeyNumber = $null
                $privateKeyValid = $false
            }

            try {
                $publicKeySize = $cert.PublicKey.Key.KeySize
                $publicKeyAlgorithm = $cert.PublicKey.Oid.FriendlyName
                $publicKeyValid = $publicKeySize -ge 2048 -and $publicKeyAlgorithm -match 'RSA'
            } catch {
                $publicKeySize = $null
                $publicKeyAlgorithm = $null
                $publicKeyValid = $false
            }

            try {
                $signatureAlgorithm = $cert.SignatureAlgorithm.FriendlyName
                $signatureAlgorithmValid = $signatureAlgorithm -match 'sha256|sha384|sha512'
            } catch {
                $signatureAlgorithm = $null
                $signatureAlgorithmValid = $false
            }

            try {
                $enhancedKeyUsageList = $cert.EnhancedKeyUsageList.FriendlyName
                $enhancedKeyUsageValid = $enhancedKeyUsageList -contains 'Server Authentication'
            } catch {
                $enhancedKeyUsageList = $null
                $enhancedKeyUsageValid = $false
            }

            $validityPeriodOk = $cert.NotBefore -lt (Get-Date) -and $cert.NotAfter -gt (Get-Date).AddDays($minimumValidDays)
            $daysValid = [int]($cert.NotAfter - (Get-Date)).TotalDays

            $isSuitable = $keyUsagesValid -and $dnsNamesValid -and $privateKeyValid -and $publicKeyValid -and $signatureAlgorithmValid -and $enhancedKeyUsageValid -and $validityPeriodOk

            [PSCustomObject]@{
                ComputerName            = $instance.ComputerName
                InstanceName            = $instance.InstanceName
                SqlInstance             = $instance.SqlFullName.Trim('[]')
                Thumbprint              = $cert.Thumbprint
                IsSuitable              = $isSuitable
                CertificateFound        = $true
                KeyUsagesValid          = $keyUsagesValid
                DnsNamesValid           = $dnsNamesValid
                PrivateKeyValid         = $privateKeyValid
                PublicKeyValid          = $publicKeyValid
                SignatureAlgorithmValid = $signatureAlgorithmValid
                EnhancedKeyUsageValid   = $enhancedKeyUsageValid
                ValidityPeriodOk        = $validityPeriodOk
                KeyUsages               = $keyUsages
                DnsNames                = $dnsNames
                PrivateKeyType          = $privateKeyType
                PrivateKeyNumber        = $privateKeyNumber
                PublicKeySize           = $publicKeySize
                PublicKeyAlgorithm      = $publicKeyAlgorithm
                SignatureAlgorithm      = $signatureAlgorithm
                EnhancedKeyUsageList    = $enhancedKeyUsageList
                NotBefore               = $cert.NotBefore
                NotAfter                = $cert.NotAfter
                DaysValid               = $daysValid
            }
";

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            if (instance is null)
            {
                continue;
            }

            if (TestBound(nameof(Thumbprint)))
            {
                // Way Two: detailed validation of a specific certificate by thumbprint.
                try
                {
                    string computerName = ResolveComputerName(instance);
                    RequireElevation(computerName);

                    RemoteExecutionService.RemoteCommandRequest request = new()
                    {
                        ComputerName = new DbaInstanceParameter(computerName),
                        Credential = Credential,
                        ScriptText = ValidationScript,
                        ArgumentList = new object?[] { instance, Thumbprint, MinimumValidDays }!
                    };
                    RemoteExecutionService.RemoteCommandResult res = RemoteExecutionService.InvokeCommand(this, request);
                    if (res.Errors.Count > 0)
                    {
                        StopFunction($"Failed to test certificate '{Thumbprint}' on {instance.ComputerName} for instance {instance.InstanceName}.", target: instance, errorRecord: res.Errors[0], continueLoop: true);
                        continue;
                    }
                    foreach (PSObject output in res.Output)
                    {
                        if (output is not null) { WriteObject(output); }
                    }
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (RuntimeException rex)
                {
                    StopFunction($"Failed to test certificate '{Thumbprint}' on {instance.ComputerName} for instance {instance.InstanceName}.", target: instance, errorRecord: rex.ErrorRecord, continueLoop: true);
                }
                catch (Exception ex)
                {
                    StopFunction($"Failed to test certificate '{Thumbprint}' on {instance.ComputerName} for instance {instance.InstanceName}.", target: instance, exception: ex, continueLoop: true);
                }
            }
            else
            {
                // Way One: check configured and available certificates via Get-DbaNetworkConfiguration.
                try
                {
                    Hashtable splat = new Hashtable
                    {
                        { "SqlInstance", instance },
                        { "Credential", Credential },
                        { "EnableException", true }
                    };
                    PSObject? netConf = null;
                    foreach (PSObject o in NestedCommand.Invoke(this, "Get-DbaNetworkConfiguration", splat))
                    {
                        if (o is not null) { netConf = o; break; }
                    }

                    object? certValue = netConf?.Properties["Certificate"]?.Value;
                    if (netConf is null)
                    {
                        StopFunction($"Failed to get network configuration from {instance.ComputerName} for instance {instance.InstanceName}.", target: instance, continueLoop: true);
                        continue;
                    }
                    if (Unwrap(certValue) is string certString)
                    {
                        StopFunction($"Failed to collect certificate information from {instance.ComputerName} for instance {instance.InstanceName}: {certString}", target: instance, continueLoop: true);
                        continue;
                    }

                    EmitWayOne(instance, netConf, certValue);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (RuntimeException rex)
                {
                    StopFunction($"Failed to test network certificate for {instance.ComputerName} instance {instance.InstanceName}.", target: instance, errorRecord: rex.ErrorRecord, continueLoop: true);
                }
                catch (Exception ex)
                {
                    StopFunction($"Failed to test network certificate for {instance.ComputerName} instance {instance.InstanceName}.", target: instance, exception: ex, continueLoop: true);
                }
            }
        }
    }

    // PS Way One shaping (lines 315-357).
    private void EmitWayOne(DbaInstanceParameter instance, PSObject netConf, object? certValue)
    {
        PSObject? cert = certValue as PSObject ?? (certValue is null ? null : new PSObject(certValue));
        object? configuredThumbprint = cert?.Properties["Thumbprint"]?.Value;
        object? configuredGenerated = cert?.Properties["Generated"]?.Value;
        object? configuredExpires = cert?.Properties["Expires"]?.Value;
        DateTime currentDate = DateTime.Now;

        object? configuredDaysValid = null;
        if (LanguagePrimitives.IsTrue(configuredThumbprint) && LanguagePrimitives.IsTrue(configuredExpires)
            && TryDate(configuredExpires, out DateTime expiresDt))
        {
            // PS [int] rounds to nearest (banker's); a C# cast truncates toward zero.
            configuredDaysValid = LanguagePrimitives.ConvertTo<int>((expiresDt - currentDate).TotalDays);
        }

        bool configuredCertificateValid = false;
        if (LanguagePrimitives.IsTrue(configuredThumbprint) && LanguagePrimitives.IsTrue(configuredGenerated) && LanguagePrimitives.IsTrue(configuredExpires)
            && TryDate(configuredGenerated, out DateTime generatedDt) && TryDate(configuredExpires, out DateTime expiresDt2))
        {
            configuredCertificateValid = generatedDt < currentDate && expiresDt2 > currentDate.AddDays(MinimumValidDays);
        }

        // PS: $netConf.SuitableCertificate | Where-Object { $_.NotAfter -gt $currentDate.AddDays($MinimumValidDays) }
        List<PSObject> suitableCerts = new();
        foreach (object suit in EnumerateAny(netConf.Properties["SuitableCertificate"]?.Value))
        {
            PSObject sc = suit as PSObject ?? new PSObject(suit);
            if (TryDate(sc.Properties["NotAfter"]?.Value, out DateTime notAfter) && notAfter > currentDate.AddDays(MinimumValidDays))
            {
                suitableCerts.Add(sc);
            }
        }
        int suitableCertCount = suitableCerts.Count;
        List<PSObject> suitableCertObjects = new();
        foreach (PSObject sc in suitableCerts)
        {
            PSObject obj = new();
            obj.Properties.Add(new PSNoteProperty("Thumbprint", sc.Properties["Thumbprint"]?.Value));
            obj.Properties.Add(new PSNoteProperty("FriendlyName", sc.Properties["FriendlyName"]?.Value));
            obj.Properties.Add(new PSNoteProperty("NotBefore", sc.Properties["NotBefore"]?.Value));
            obj.Properties.Add(new PSNoteProperty("NotAfter", sc.Properties["NotAfter"]?.Value));
            object? daysValid = TryDate(sc.Properties["NotAfter"]?.Value, out DateTime na) ? LanguagePrimitives.ConvertTo<int>((na - DateTime.Now).TotalDays) : (object?)null;
            obj.Properties.Add(new PSNoteProperty("DaysValid", daysValid));
            suitableCertObjects.Add(obj);
        }

        PSObject result = new();
        result.Properties.Add(new PSNoteProperty("ComputerName", netConf.Properties["ComputerName"]?.Value));
        result.Properties.Add(new PSNoteProperty("InstanceName", netConf.Properties["InstanceName"]?.Value));
        result.Properties.Add(new PSNoteProperty("SqlInstance", netConf.Properties["SqlInstance"]?.Value));
        result.Properties.Add(new PSNoteProperty("ConfiguredCertificateValid", configuredCertificateValid));
        result.Properties.Add(new PSNoteProperty("ConfiguredCertificateThumbprint", configuredThumbprint));
        result.Properties.Add(new PSNoteProperty("ConfiguredCertificateExpires", configuredExpires));
        result.Properties.Add(new PSNoteProperty("ConfiguredCertificateDaysValid", configuredDaysValid));
        result.Properties.Add(new PSNoteProperty("SuitableCertificateAvailable", suitableCertCount > 0));
        result.Properties.Add(new PSNoteProperty("SuitableCertificateCount", suitableCertCount));
        // PS: $suitableCertObjects = foreach (...) {...} - the assignment shape is null for zero
        // iterations, the scalar object for one, and Object[] for many; never an empty array.
        object? suitableValue = suitableCertObjects.Count == 0
            ? null
            : suitableCertObjects.Count == 1 ? suitableCertObjects[0] : (object)suitableCertObjects.ToArray();
        result.Properties.Add(new PSNoteProperty("SuitableCertificates", suitableValue));
        WriteObject(result);
    }

    // PS: $computerName = Resolve-DbaComputerName -ComputerName $instance.ComputerName -Credential $Credential
    private string ResolveComputerName(DbaInstanceParameter instance)
    {
        Hashtable splat = new Hashtable { { "ComputerName", instance.ComputerName }, { "Credential", Credential } };
        // 3>&1 rides the helper's WarningRecords on the output stream so InvokeModuleScoped can
        // re-emit them through the outer cmdlet (WarningAction/WarningVariable parity with the PS
        // function's direct call); without it they hit the host and bypass both.
        NestedCommand.RequireDbatoolsScriptModule(this);
        Collection<PSObject> res = InvokeModuleScoped(
            "param($__p) $__m = Get-Module dbatools | Where-Object ModuleType -eq \"Script\" | Select-Object -First 1; & $__m { param($p) Resolve-DbaComputerName -ComputerName $p.ComputerName -Credential $p.Credential } $__p 3>&1",
            splat);
        return res.Count > 0 ? res[0]?.ToString() ?? instance.ComputerName : instance.ComputerName;
    }

    // PS: $null = Test-ElevationRequirement -ComputerName $computerName -EnableException $true
    private void RequireElevation(string computerName)
    {
        Hashtable splat = new Hashtable { { "ComputerName", computerName } };
        NestedCommand.RequireDbatoolsScriptModule(this);
        InvokeModuleScoped(
            "param($__p) $__m = Get-Module dbatools | Where-Object ModuleType -eq \"Script\" | Select-Object -First 1; $null = & $__m { param($p) Test-ElevationRequirement -ComputerName $p.ComputerName -EnableException $true } $__p",
            splat);
    }

    private Collection<PSObject> InvokeModuleScoped(string scriptText, object payload)
    {
        object? effective = SessionState.PSVariable.GetValue("PSDefaultParameterValues");
        // Module-internal calls resolve $PSDefaultParameterValues from the MODULE session state,
        // where none is defined - neither caller-LOCAL nor GLOBAL defaults ever reached the retired
        // functions' nested calls, so the faithful shield is an EMPTY table, not the global one.
        bool swapped = effective is not null;
        if (swapped)
        {
            SessionState.PSVariable.Set("PSDefaultParameterValues", new System.Management.Automation.DefaultParameterDictionary());
        }
        try
        {
            Collection<PSObject> raw = InvokeCommand.InvokeScript(false, ScriptBlock.Create(scriptText), null, payload);
            Collection<PSObject> output = new();
            foreach (PSObject item in raw)
            {
                if (item?.BaseObject is WarningRecord warning) { WriteWarning(warning.Message); }
                else if (item is not null) { output.Add(item); }
            }
            return output;
        }
        finally
        {
            if (swapped)
            {
                SessionState.PSVariable.Set("PSDefaultParameterValues", effective);
            }
        }
    }

    private static object? Unwrap(object? value) => value is PSObject p ? p.BaseObject : value;

    private static bool TryDate(object? value, out DateTime result)
    {
        object? v = Unwrap(value);
        if (v is DateTime dt) { result = dt; return true; }
        if (v is not null && DateTime.TryParse(v.ToString(), out result)) { return true; }
        result = default;
        return false;
    }

    private static IEnumerable<object> EnumerateAny(object? value)
    {
        if (value is null) { yield break; }
        object baseObject = value is PSObject wrapped ? wrapped.BaseObject : value;
        if (baseObject is string) { yield return value; yield break; }
        if (baseObject is IEnumerable enumerable)
        {
            foreach (object? item in enumerable) { if (item is not null) { yield return item; } }
            yield break;
        }
        yield return value;
    }
}
