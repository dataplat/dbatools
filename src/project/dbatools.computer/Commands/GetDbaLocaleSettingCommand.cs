#nullable enable
#pragma warning disable CA1416 // Windows-only command: WMI registry (StdRegProv) over System.Management

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves Windows locale settings from the HKEY_CURRENT_USER\Control Panel\International
/// registry key on one or more computers. Port of public/Get-DbaLocaleSetting.ps1; surface
/// pinned by migration/baselines/Get-DbaLocaleSetting.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaLocaleSetting")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaLocaleSettingCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s); a SQL Server instance name is accepted but only the computer portion is used. Defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    [Alias("cn", "host", "Server")]
    public string[] ComputerName { get; set; } = DefaultComputerName();

    /// <summary>Credential object used to connect to the computer as a different user.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared. Get-DbaLocaleSetting
    // only ever Write-Message's warnings (never Stop-Function), so EnableException changes nothing
    // about its behavior - preserved exactly by never calling StopFunction here.

    // PS begin-block constants.
    private const uint CIMHiveCU = 2147483649u;          // [UInt32]$CIMHiveCU = 2147483649 -> HKEY_CURRENT_USER (0x80000001)
    private const string KeyName = @"Control Panel\International";  // $keyname = "Control Panel\International"

    protected override void BeginProcessing()
    {
        base.BeginProcessing();
        // PS begin: $ComputerName = $ComputerName | ForEach-Object { $_.split("\")[0] } | Select-Object -Unique
        // A ValueFromPipeline parameter is rebound per pipeline item before ProcessRecord, so this
        // normalization only reaches direct (-ComputerName a,b,c) invocation - piped items pass
        // through raw, exactly as the PS begin/process split does (begin runs against the default,
        // process re-binds each piped value).
        ComputerName = NormalizeComputerNames(ComputerName);
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

        foreach (string computer in ComputerName)
        {
            // PS: $props = @{ "ComputerName" = $computer }. A PowerShell hashtable literal is a
            // case-insensitive System.Collections.Hashtable, and [PSCustomObject]$props enumerates
            // it in bucket order (ComputerName is inserted first but does NOT come out first).
            // Reproduce with the same comparer and insertion order: on net472 the deterministic
            // hashing yields the byte-identical property order; on net8.0 the runtime randomizes
            // string hashing per process, so the PS function's OWN order already varies run to run
            // (verified) and the port matches that same non-determinism plus an identical property
            // set. StringComparer.CurrentCultureIgnoreCase reproduces the @{} order (verified;
            // ordinal and ordinal-ignore-case do not).
            Hashtable props = new Hashtable(StringComparer.CurrentCultureIgnoreCase);
            props["ComputerName"] = computer;

            // PS: $Server = Resolve-DbaNetworkName -ComputerName $Computer -Credential $credential
            NetworkResolutionService.NetworkResolutionResult? resolution = null;
            try
            {
                resolution = NetworkResolutionService.Resolve(this, new DbaInstanceParameter(computer), Credential, turbo: false);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch
            {
                // Resolve-DbaNetworkName runs without -EnableException here: a failure is its own
                // warning plus a null result. The function does not add a DNS message of its own -
                // it only tests FullComputerName below and warns "Can't connect".
                resolution = null;
            }

            // PS: if ($Server.FullComputerName) { ... } else { "Can't connect to $computer" }.
            // The else branch runs before $computer is reassigned, so it uses the original name.
            string? fullComputerName = resolution?.FullComputerName;
            if (string.IsNullOrEmpty(fullComputerName))
            {
                WriteMessage(MessageLevel.Warning, $"Can't connect to {computer}");
                continue;
            }

            // PS: $Computer = $server.FullComputerName - the CIM connection and the "Can't create
            // CIMSession" warning below both use the resolved full name.
            string resolvedComputer = fullComputerName!;

            // PS: New-CimSession over WSMan, then DCom on failure. The compiled port takes the
            // established StdRegProv transport (System.Management ManagementScope over root\cimv2,
            // as in Get-DbaNetworkConfiguration) - one connection instead of the WSMan->DCom pair,
            // output-identical because it invokes the same StdRegProv EnumValues/GetStringValue
            // methods against the same hive. The WSMan/DCom-specific verbose lines are elided with
            // the transport swap.
            ManagementClass? stdReg = TryConnectStdRegProv(resolvedComputer);
            if (stdReg is null)
            {
                WriteMessage(MessageLevel.Warning, $"Can't create CIMSession on {resolvedComputer}");
                continue;
            }

            using (stdReg)
            {
                WriteMessage(MessageLevel.Verbose, "Getting properties from Registry Key");

                // PS: $PropNames = Invoke-CimMethod ... enumvalues ... | Select -ExpandProperty snames
                string[] propNames = EnumRegValueNames(stdReg, KeyName);

                foreach (string name in propNames)
                {
                    // PS: $sValue = Invoke-CimMethod ... GetSTRINGvalue ... | Select -ExpandProperty svalue
                    // Every value is read as a string (all Control Panel\International values are
                    // REG_SZ); a null read lands as a $null-valued property, matching $props.add.
                    string? value = GetRegStringValue(stdReg, KeyName, name);
                    // PS: $props.add($Name, $sValue) - a duplicate key raises a NON-terminating
                    // MethodInvocationException, keeps the first value, and the loop continues to
                    // still emit the object. Hashtable.Add throws ArgumentException; catch it and
                    // WriteError so the cmdlet does not terminate (codex parity fix 2026-07-10).
                    try
                    {
                        props.Add(name, value);
                    }
                    catch (ArgumentException ex)
                    {
                        WriteError(new ErrorRecord(ex, "dbatools_Get-DbaLocaleSetting", ErrorCategory.NotSpecified, name));
                    }
                }

                // PS: [PSCustomObject]$props
                WriteObject(BuildOutput(props));
            }
        }
    }

    // PS: New-CimSession -ComputerName $Computer (WSMan) then -SessionOption DCom on failure, both
    // -ErrorAction SilentlyContinue. The compiled equivalent is a single System.Management scope
    // connect; a failure returns null so the caller warns "Can't create CIMSession".
    private ManagementClass? TryConnectStdRegProv(string computerName)
    {
        try
        {
            ConnectionOptions opts = new ConnectionOptions();
            if (Credential is not null)
            {
                // WMI ConnectionOptions requires a plain-text password; no secure-string overload.
                System.Net.NetworkCredential netCred = Credential.GetNetworkCredential();
                opts.Username = string.IsNullOrEmpty(netCred.Domain)
                    ? netCred.UserName
                    : $"{netCred.Domain}\\{netCred.UserName}";
                opts.Password = netCred.Password;
            }
            ManagementScope scope = new ManagementScope($@"\\{computerName}\root\cimv2", opts);
            scope.Connect();
            return new ManagementClass(scope, new ManagementPath("StdRegProv"), null);
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch
        {
            return null;
        }
    }

    // PS: Invoke-CimMethod -MethodName enumvalues -Arguments @{ hDefKey = $CIMHiveCU; sSubKeyName =
    // $keyname } | Select-Object -ExpandProperty snames. A failed enumeration (non-zero return or a
    // WMI error) yields no names, so the emitted object carries only ComputerName - matching the PS
    // foreach over a $null PropNames.
    private static string[] EnumRegValueNames(ManagementClass stdReg, string subKey)
    {
        try
        {
            using ManagementBaseObject inParams = stdReg.GetMethodParameters("EnumValues");
            inParams["hDefKey"] = CIMHiveCU;
            inParams["sSubKeyName"] = subKey;
            using ManagementBaseObject outParams = stdReg.InvokeMethod("EnumValues", inParams, null);
            return outParams?["sNames"] as string[] ?? Array.Empty<string>();
        }
        catch
        {
            return Array.Empty<string>();
        }
    }

    // PS: Invoke-CimMethod -MethodName GetSTRINGvalue -Arguments @{ hDefKey = $CIMHiveCU;
    // sSubKeyName = $keyname; sValueName = $Name } | Select-Object -ExpandProperty svalue. The PS
    // calls carry no -ErrorAction, so a per-value read failure surfaces on the error stream and the
    // pipeline yields nothing ($null); the port returns null on any read failure to match the
    // $props.add($Name, $null) that leaves.
    private static string? GetRegStringValue(ManagementClass stdReg, string subKey, string valueName)
    {
        try
        {
            using ManagementBaseObject inParams = stdReg.GetMethodParameters("GetStringValue");
            inParams["hDefKey"] = CIMHiveCU;
            inParams["sSubKeyName"] = subKey;
            inParams["sValueName"] = valueName;
            using ManagementBaseObject outParams = stdReg.InvokeMethod("GetStringValue", inParams, null);
            return outParams?["sValue"]?.ToString();
        }
        catch
        {
            return null;
        }
    }

    // [PSCustomObject]$props parity: enumerate the Hashtable in its native (bucket) order and add
    // one PSNoteProperty per entry, so the property order equals PowerShell's own Hashtable ->
    // PSCustomObject cast on the same runtime (byte-identical on net472; the same per-process
    // ordering the function produces on net8.0).
    private static PSObject BuildOutput(Hashtable props)
    {
        PSObject output = new PSObject();
        foreach (DictionaryEntry entry in props)
        {
            output.Properties.Add(new PSNoteProperty((string)entry.Key, entry.Value));
        }
        return output;
    }

    // PS begin: $_.split("\")[0] then Select-Object -Unique. Select-Object -Unique is
    // CASE-SENSITIVE (lab-proven both editions: 'SQL1','sql1' -> both kept), so use an ordinal
    // (case-sensitive) set, first occurrence kept (codex parity fix 2026-07-10).
    private static string[] NormalizeComputerNames(string[]? names)
    {
        if (names is null)
        {
            return Array.Empty<string>();
        }
        List<string> ordered = new List<string>();
        HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (string raw in names)
        {
            string head = (raw ?? string.Empty).Split('\\')[0];
            if (seen.Add(head))
            {
                ordered.Add(head);
            }
        }
        return ordered.ToArray();
    }

    // PS: [string[]]$ComputerName = $env:COMPUTERNAME
    private static string[] DefaultComputerName()
    {
        string? machine = Environment.GetEnvironmentVariable("COMPUTERNAME");
        return string.IsNullOrEmpty(machine) ? Array.Empty<string>() : new[] { machine };
    }
}
